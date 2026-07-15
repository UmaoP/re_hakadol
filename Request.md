# 📋 ハッカドール再現プロジェクト 開発指示書【完全無料・高精度版】

## 1. プロジェクト概要

かつて存在したオタク向けニュースアプリ「ハッカドール」のメイン機能（ニュースの自動収集 ➔ ユーザーの好みを学習 ➔ おすすめ配信）を、「初期・運用コスト完全無料（月額0円）」で再現します。

コストを極限まで抑えつつ高い推薦精度を維持するため、Supabase（ベクトル検索拡張）**と**Hugging Faceの無料API（Serverless Inference API）を組み合わせたモダンなサーバーレス構成を採用します。

---

## 2. システムアーキテクチャ＆技術スタック

| レイヤー | 採用技術 | 役割・選定理由 |
| --- | --- | --- |
| **フロントエンド** | **Flutter** (Dart) | iOS/Androidの両OSに対応。サクサクしたニュースリスト表示と閲覧履歴の送信処理を担当。 |
| **データベース** | **Supabase** (PostgreSQL) | 無料枠（DB容量 500MB / ユーザー 5万人）を活用。ベクトル検索拡張 `pgvector` により、好みの推薦計算をDB側で高速処理。 |
| **クローラー** | **Python** + **GitHub Actions** | 1時間ごとに自動起動（無料枠2000分内）。RSS巡回、Embedding生成、Supabaseへのデータ格納を全自動化。 |
| **AI (Embedding)** | **Hugging Face Inference API**<br>

<br>(モデル: `intfloat/multilingual-e5-small`) | **完全無料**で利用可能な埋め込みベクトル生成API。日本語のセマンティック（意味）検索に非常に強い軽量モデルを採用（出力: **384次元**）。 |

---

## 3. データベース設計（Supabase Schema）

Hugging Faceの `multilingual-e5-small` の出力次元数である **384次元** に合わせて、`articles` テーブルのベクトル型を定義します。

### 3.1. `articles` テーブル（ニュースデータ）

```sql
-- pgvector 拡張を有効化（初回のみ）
create extension if not exists vector;

create table articles (
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
create index on articles using hnsw (embedding vector_cosine_ops);

```

### 3.2. `user_history` テーブル（ユーザーの閲覧履歴）

```sql
create table user_history (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  article_id uuid references articles(id) on delete cascade not null,
  action_type text not null,      -- 'read'（閲覧）, 'like'（お気に入り）
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

```

---

## 4. 推薦ロジック（Supabase RPC）

ユーザーの閲覧履歴に基づき、まだ読んでいない記事をおすすめ順（コサイン類似度順）に並び替えて返すSQL関数（RPC）をSupabaseに定義します。

```sql
create or replace function get_recommended_articles(user_uuid uuid, match_limit int)
returns setof articles as $$
declare
  user_profile_vector vector(384);
begin
  -- 1. ユーザーの閲覧履歴から、最近のアクション（例: 直近100件）の平均ベクトルを算出
  select avg(a.embedding)::vector(384) into user_profile_vector
  from user_history h
  join articles a on h.article_id = a.id
  where h.user_id = user_uuid;

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

```

---

## 5. 開発ロードマップ（全4フェーズ）

* **Phase 1: ニュース自動収集（クローラー）と無料ベクトル化の実装**
* Pythonで各種オタク系RSSを取得。
* Hugging Faceの `InferenceClient` を使い、タイトルを `multilingual-e5-small` で384次元ベクトル化（※E5モデルの特性上、入力文字列の先頭に `"query: "` または `"passage: "` を付与するルールを適用）。
* データをSupabaseへUPSERTするスクリプトを構築し、GitHub Actionsに組み込んで定期実行（Cron）を設定。


* **Phase 2: Supabase推薦関数の実装**
* SupabaseのSQLエディタで、上記「4. 推薦ロジック」のSQLを実行し、関数（RPC）を定義する。


* **Phase 3: Flutterアプリ開発（UIと閲覧履歴の連携）**
* FlutterにSupabase SDKを導入し、匿名認証（Anonymous Auth）またはメール認証を実装。
* ニュース一覧画面（通常タブと「おすすめ」タブ）を構築。
* 記事タップ時にアプリ内Webビューで開き、同時にSupabaseの `user_history` に閲覧ログを送信。


* **Phase 4: 不要データの自動クリーンアップ（無料枠維持のため）**
* Supabaseの無料枠（500MB）を永久に守るため、30日以上前の古い記事データを自動削除するSQL（pg_cron等）またはクローラー側でのクリーンアップ処理を実装。
