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
returns setof articles as $$
declare
  user_profile_vector vector(384);
begin
  -- 1. ユーザーの閲覧履歴から、直近30件のアクションの平均ベクトルを算出
  select avg(a.embedding)::vector(384) into user_profile_vector
  from (
    select article_id 
    from user_history 
    where user_id = user_uuid 
    order by created_at desc 
    limit 30
  ) h
  join articles a on h.article_id = a.id;

  -- 2. 履歴が空（新規ユーザー）の場合は、新着順で降順表示
  if user_profile_vector is null then
    return query
    select * from articles
    order by published_at desc
    limit match_limit;
  else
    -- 3. 既読記事を除外し、ユーザープロファイルベクトルと近い順に記事を推薦
    return query
    select a.*
    from articles a
    where a.id not in (
      select article_id from user_history where user_id = user_uuid
    )
    order by a.embedding <=> user_profile_vector -- コサイン距離が近い順
    limit match_limit;
  end if;
end;
$$ language plpgsql stable;

-- Row Level Security (RLS) の有効化
alter table articles enable row level security;
alter table user_history enable row level security;

-- articles テーブル用ポリシー：誰でも閲覧可能（書き込みはクローラーの service_role のみ許可）
create policy "Allow public read access to articles"
on articles for select
using (true);

-- user_history テーブル用ポリシー：自分の履歴のみ作成・閲覧可能
create policy "Allow users to insert their own history"
on user_history for insert
with check (auth.uid() = user_id);

create policy "Allow users to select their own history"
on user_history for select
using (auth.uid() = user_id);
