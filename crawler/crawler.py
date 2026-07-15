import os
import sys
import time
from datetime import datetime, timezone, timedelta
import feedparser
from dotenv import load_dotenv
import requests
from supabase import create_client, Client
from sentence_transformers import SentenceTransformer

# 環境変数の読み込み（ローカル開発用）
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

# 定数定義
MODEL_DIMENSION = 384

# ローカルで利用する埋め込みモデルの初期化（初回起動時に自動ダウンロード）
print("ローカル埋め込みモデル（intfloat/multilingual-e5-small）を読み込んでいます...")
EMBEDDING_MODEL = SentenceTransformer("intfloat/multilingual-e5-small")

# RSSフィードの配信元リスト
RSS_FEEDS = [
    {
        "name": "ファミ通.com",
        "url": "https://www.famitsu.com/rss/x/news.xml"
    },
    {
        "name": "電撃オンライン",
        "url": "https://dengekionline.com/rss.xml"
    },
    {
        "name": "4Gamer.net",
        "url": "https://www.4gamer.net/rss/index.xml"
    },
    {
        "name": "インサイド",
        "url": "https://www.inside-games.jp/rss/index.rdf"
    },
    {
        "name": "アニメ！アニメ！",
        "url": "https://animeanime.jp/rss/index.rdf"
    },
    {
        "name": "GAME Watch",
        "url": "https://game.watch.impress.co.jp/data/rss/link/gw.xml"
    },
    {
        "name": "ねとらぼ",
        "url": "https://rss.itmedia.co.jp/rss/2.0/netlab.xml"
    },
    {
        "name": "GIGAZINE",
        "url": "https://gigazine.net/news/rss_2.0/"
    },
    {
        "name": "KAI-YOU.net",
        "url": "http://kai-you.net/contents/feed.rss"
    },
    {
        "name": "Togetter",
        "url": "https://togetter.com/rss/hot"
    },
    {
        "name": "HOBBY Watch",
        "url": "https://hobby.watch.impress.co.jp/data/rss/link/hbw.xml"
    },
    {
        "name": "電撃ホビーウェブ",
        "url": "https://hobby.dengeki.com/feed/"
    },
    {
        "name": "AUTOMATON",
        "url": "https://automaton-media.com/feed/"
    }
]

def init_supabase() -> Client:
    """Supabase クライアントを初期化します。"""
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("エラー: SUPABASE_URL または SUPABASE_KEY が設定されていません。")
        sys.exit(1)
    return create_client(SUPABASE_URL, SUPABASE_KEY)

def get_image_url(entry) -> str:
    """エントリーから画像URLを抽出します。"""
    # media:thumbnail
    if 'media_thumbnail' in entry and len(entry.media_thumbnail) > 0:
        return entry.media_thumbnail[0].get('url')
    # media:content
    if 'media_content' in entry and len(entry.media_content) > 0:
        return entry.media_content[0].get('url')
    # enclosure (添付ファイル)
    if 'links' in entry:
        for link in entry.links:
            if link.get('rel') == 'enclosure' or 'image' in link.get('type', ''):
                return link.get('href')
    return None

def parse_published_time(entry) -> datetime:
    """エントリーの公開日時をパースし、UTCのdatetimeオブジェクトを返します。"""
    if hasattr(entry, 'published_parsed') and entry.published_parsed:
        try:
            return datetime.fromtimestamp(time.mktime(entry.published_parsed), tz=timezone.utc)
        except Exception:
            pass
    return datetime.now(timezone.utc)

def fetch_rss_articles(feeds) -> list:
    """RSSフィードから記事の一覧を取得します。"""
    articles = []
    for feed in feeds:
        print(f"RSS取得中: {feed['name']} ({feed['url']})")
        try:
            parsed = feedparser.parse(feed['url'])
            for entry in parsed.entries:
                published_at = parse_published_time(entry)
                image_url = get_image_url(entry)
                
                articles.append({
                    "title": entry.title,
                    "link": entry.link,
                    "image_url": image_url,
                    "source_name": feed['name'],
                    "published_at": published_at.isoformat()
                })
        except Exception as e:
            print(f"警告: フィード {feed['name']} の取得に失敗しました。{e}")
    return articles

def filter_new_articles(supabase_client: Client, articles: list) -> list:
    """すでにデータベースに登録されている記事を除外します。"""
    if not articles:
        return []
    
    links = [a["link"] for a in articles]
    
    # チャンクに分けて確認（リンク数が多すぎる場合のクエリ制限対策）
    existing_links = set()
    chunk_size = 100
    for i in range(0, len(links), chunk_size):
        chunk = links[i:i + chunk_size]
        try:
            response = supabase_client.table("articles").select("link").in_("link", chunk).execute()
            if response.data:
                for row in response.data:
                    existing_links.add(row["link"])
        except Exception as e:
            print(f"警告: 既存記事の確認中にエラーが発生しました。{e}")
            
    new_articles = [a for a in articles if a["link"] not in existing_links]
    print(f"取得した記事数: {len(articles)} 件, 新着記事数: {len(new_articles)} 件")
    return new_articles

def generate_embeddings_batch(articles: list) -> list:
    """ローカルの sentence-transformers を使用して、記事リストのタイトルを一括でベクトル表現に変換します。"""
    if not articles:
        return []
        
    titles = [f"passage: {a['title']}" for a in articles]
    print(f"記事タイトルの一括ベクトル化（バッチ処理）を開始します... (対象: {len(titles)} 件)")
    
    try:
        # 一括エンコードを実行（確実に numpy 配列で取得）
        embeddings = EMBEDDING_MODEL.encode(titles, convert_to_numpy=True, show_progress_bar=False)
        for idx, embedding in enumerate(embeddings):
            # ndarray から標準の Python list[float] に変換してシリアライズエラーを防ぐ
            articles[idx]["embedding"] = embedding.tolist()
    except Exception as e:
        print(f"エラー: 一括ベクトル化に失敗しました。フォールバックとしてダミーベクトルを使用します。 {e}")
        import random
        for article in articles:
            article["embedding"] = [random.uniform(-0.1, 0.1) for _ in range(MODEL_DIMENSION)]
            
    return articles

def cleanup_old_articles(supabase_client: Client, days: int = 14):
    """指定された日数より前の古い記事を削除して、データベースの容量を節約します。"""
    print(f"古い記事のクリーンアップを開始します (基準: {days}日前)...")
    try:
        cutoff_date = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
        # articlesテーブルから published_at < cutoff_date のものを削除
        # user_historyテーブルは on delete cascade により自動的に削除されます
        response = supabase_client.table("articles").delete().lt("published_at", cutoff_date).execute()
        deleted_count = len(response.data) if response.data else 0
        print(f"クリーンアップ完了: {deleted_count} 件の古い記事を削除しました。")
    except Exception as e:
        print(f"警告: クリーンアップ処理中にエラーが発生しました。{e}")

def main():
    print(f"--- クローラー起動: {datetime.now(timezone.utc).isoformat()} ---")
    
    # 接続初期化
    supabase_client = init_supabase()
    
    # 古い記事のクリーンアップを実行（無料枠維持のため、負荷軽減として約10%の確率で実行）
    import random
    if random.random() < 0.1:
        cleanup_old_articles(supabase_client)
    else:
        print("今回の起動ではクリーンアップ処理をスキップします（データベース負荷削減のため）。")
    
    # RSSフィードから最新記事を取得
    all_articles = fetch_rss_articles(RSS_FEEDS)
    
    # 新着記事（未登録のもの）のみ抽出
    new_articles = filter_new_articles(supabase_client, all_articles)
    
    if not new_articles:
        print("追加する新しい記事はありません。終了します。")
        return
        
    # ベクトル化を一括実行
    new_articles = generate_embeddings_batch(new_articles)
    
    print(f"{len(new_articles)} 件の新着記事を Supabase に登録します。")
    
    success_count = 0
    for idx, article in enumerate(new_articles):
        try:
            # Supabaseに挿入（UPSERT）
            supabase_client.table("articles").upsert(article, on_conflict="link").execute()
            success_count += 1
        except Exception as e:
            print(f"エラー: 記事「{article['title']}」の登録に失敗しました。{e}")
            
    print(f"処理完了: {success_count} / {len(new_articles)} 件登録成功")

if __name__ == "__main__":
    main()
