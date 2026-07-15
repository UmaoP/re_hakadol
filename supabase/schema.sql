-- pgvector 拡張を有効化
create extension if not exists vector;

-- ニュース記事テーブル
create table if not exists articles (
  id uuid default gen_random_uuid() primary key,
  title text not null,
  link text not null unique,
  image_url text,
  source_name text not null,      -- 例: 'ファミ通', '電撃オンライン'
  published_at timestamp with time zone not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  embedding vector(384)           -- multilingual-e5-small の 384次元 に合わせて設定
);

-- 高速なベクトル検索のためのインデックス作成（コサイン類似度用）
create index if not exists articles_embedding_hnsw_idx 
on articles using hnsw (embedding vector_cosine_ops);

-- ユーザーの閲覧履歴テーブル
create table if not exists user_history (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  article_id uuid references articles(id) on delete cascade not null,
  action_type text not null,      -- 'read'（閲覧）, 'like'（お気に入り）
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 閲覧履歴に基づく推薦関数
create or replace function get_recommended_articles(user_uuid uuid, match_limit int)
returns table (
  id uuid,
  title text,
  link text,
  image_url text,
  source_name text,
  published_at timestamp with time zone,
  similarity_score double precision -- 類似度スコア (0.0 〜 1.0)
) as $$
declare
  user_profile_vector vector(384);
  user_dislike_vector vector(384);
begin
  -- 1. 直近30件の『好ましい』履歴（read または like）から平均ベクトルを算出
  -- 'like' は 3倍の重みで計算するため、UNION ALL で like のレコードを3回複製して平均を取る
  select avg(a.embedding)::vector(384) into user_profile_vector
  from (
    select article_id, action_type, created_at
    from user_history 
    where user_id = user_uuid and action_type in ('read', 'like')
    order by created_at desc 
    limit 30
  ) h
  join articles a on h.article_id = a.id
  -- 重み付けのためのクロスジョイン（likeは3行、readは1行にする）
  cross join lateral (
    select 1 as w union all
    select 2 as w where h.action_type = 'like' union all
    select 3 as w where h.action_type = 'like'
  ) w;

  -- 2. 直近30件の『嫌い（dislike）』な履歴から平均ベクトルを算出
  select avg(a.embedding)::vector(384) into user_dislike_vector
  from (
    select article_id 
    from user_history 
    where user_id = user_uuid and action_type = 'dislike'
    order by created_at desc 
    limit 30
  ) h
  join articles a on h.article_id = a.id;

  -- 3. 履歴が空（新規ユーザー）の場合は、新着順で降順表示（類似度は0.0とする）
  if user_profile_vector is null then
    return query
    select a.id, a.title, a.link, a.image_url, a.source_name, a.published_at, 0.0::double precision as similarity_score
    from articles a
    order by a.published_at desc
    limit match_limit;
  else
    -- 4. 既読記事・非表示（dislike）記事を除外し、好みのベクトルに近い順に推薦
    -- dislike ベクトルがある場合は、そのベクトルとのコサイン類似度が高いほどペナルティ（減算）を科す
    return query
    select 
      a.id, 
      a.title, 
      a.link, 
      a.image_url, 
      a.source_name, 
      a.published_at,
      (
        -- コサイン類似度 (1 - distance)
        (1.0 - (a.embedding <=> user_profile_vector)) 
        -- dislikeペナルティ (dislikeベクトルとの類似度 x 0.3 を減算)
        - coalesce((1.0 - (a.embedding <=> user_dislike_vector)) * 0.3, 0.0)
      )::double precision as similarity_score
    from articles a
    where a.id not in (
      select article_id from user_history where user_id = user_uuid
    )
    order by 
      (a.embedding <=> user_profile_vector) 
      + coalesce((a.embedding <=> user_dislike_vector) * -0.3, 0.0) asc -- ペナルティを加味したコサイン距離の昇順
    limit match_limit;
  end if;
end;
$$ language plpgsql stable;

-- Row Level Security (RLS) の有効化
alter table articles enable row level security;
alter table user_history enable row level security;

-- 既存ポリシーの削除（再実行時のエラー回避用）
drop policy if exists "Allow public read access to articles" on articles;
drop policy if exists "Allow users to insert their own history" on user_history;
drop policy if exists "Allow users to select their own history" on user_history;
drop policy if exists "Allow users to delete their own history" on user_history;

-- articles テーブル用ポリシー：誰でも閲覧可能（書き込みはクローラーの service_role のみ許可）
create policy "Allow public read access to articles"
on articles for select
using (true);

-- user_history テーブル用ポリシー：自分の履歴のみ作成・閲覧・削除可能
create policy "Allow users to insert their own history"
on user_history for insert
with check (auth.uid() = user_id);

create policy "Allow users to select their own history"
on user_history for select
using (auth.uid() = user_id);

create policy "Allow users to delete their own history"
on user_history for delete
using (auth.uid() = user_id);
