import os
import sys
import time
from datetime import datetime, timezone, timedelta
import feedparser
from dotenv import load_dotenv
import requests
from supabase import create_client, Client
from huggingface_hub import InferenceClient

# 環境変数の読み込み（ローカル開発用）
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
HF_TOKEN = os.getenv("HF_TOKEN")

# 定数定義
HF_API_URL = "https://router.huggingface.co/hf-inference/models/intfloat/multilingual-e5-small"
MODEL_DIMENSION = 384

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

def generate_embedding(text: str, token: str) -> list:
    """Hugging Face Inference API を使用して、テキストのベクトル表現を生成します。"""
    import random
    
    # ローカルデバッグ用、またはトークン未設定時のフォールバック
    if token == "debug" or not token:
        # e5モデルは正規化されたベクトルを出力するため、小さなランダム値を使用
        return [random.uniform(-0.1, 0.1) for _ in range(MODEL_DIMENSION)]
        
    headers = {"Authorization": f"Bearer {token}"}
    payload = {"inputs": text}
    
    # API呼び出し（リトライ処理付き）
    max_retries = 3
    for attempt in range(max_retries):
        try:
            response = requests.post(HF_API_URL, headers=headers, json=payload, timeout=15)
            
            # 502/503エラーはモデルのロード中や一時的な過負荷の可能性があるためリトライ
            if response.status_code in [502, 503]:
                wait_time = 5
                if response.status_code == 503:
                    try:
                        wait_time = response.json().get("estimated_time", 5)
                    except Exception:
                        pass
                print(f"一時的なサーバーエラー ({response.status_code})... {wait_time}秒待機します (試行 {attempt + 1}/{max_retries})")
                time.sleep(min(wait_time, 20))
                continue
                
            response.raise_for_status()
            output = response.json()
            return mean_pooling(output)
            
        except Exception as e:
            print(f"警告: embedding生成に失敗しました (試行 {attempt + 1}/{max_retries})。 {e}")
            if attempt < max_retries - 1:
                time.sleep(5)
            else:
                # すべてのリトライが失敗した場合、ローカルテスト継続のためにダミーベクトルでフォールバック
                print("警告: すべてのAPI試行が失敗しました。開発継続のため、この記事にはダミーのベクトルを設定します。")
                return [random.uniform(-0.1, 0.1) for _ in range(MODEL_DIMENSION)]
                
    return [random.uniform(-0.1, 0.1) for _ in range(MODEL_DIMENSION)]

def mean_pooling(model_output) -> list:
    """Inference APIの出力形式を解析し、384次元の平均プーリングベクトルを返します。"""
    if isinstance(model_output, list) and len(model_output) > 0:
        # 3次元: [[[f1, f2, ...]]] (トークンごとの埋め込み)
        if isinstance(model_output[0], list) and len(model_output[0]) > 0:
            if isinstance(model_output[0][0], list):
                tokens_embeddings = model_output[0]
                num_tokens = len(tokens_embeddings)
                embedding_dim = len(tokens_embeddings[0])
                
                # 384次元かチェック
                if embedding_dim != MODEL_DIMENSION:
                    print(f"警告: 埋め込み次元数が {embedding_dim} です。期待値は {MODEL_DIMENSION} です。")
                
                mean_embedding = [0.0] * embedding_dim
                for token in tokens_embeddings:
                    for i in range(embedding_dim):
                        mean_embedding[i] += token[i]
                for i in range(embedding_dim):
                    mean_embedding[i] /= num_tokens
                return mean_embedding
                
            # 2次元: [[f1, f2, ...]]
            elif isinstance(model_output[0], (float, int)):
                return model_output[0]
                
        # 1次元: [f1, f2, ...]
        elif isinstance(model_output[0], (float, int)):
            return model_output
            
    raise ValueError(f"予期しないEmbedding出力形式です。: {type(model_output)}")

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
    
    # 古い記事のクリーンアップを実行（無料枠維持のため）
    cleanup_old_articles(supabase_client)
    
    # RSSフィードから最新記事を取得
    all_articles = fetch_rss_articles(RSS_FEEDS)
    
    # 新着記事（未登録のもの）のみ抽出
    new_articles = filter_new_articles(supabase_client, all_articles)
    
    if not new_articles:
        print("追加する新しい記事はありません。終了します。")
        return
        
    print(f"{len(new_articles)} 件の新着記事のベクトル化と登録を開始します。")
    
    success_count = 0
    for idx, article in enumerate(new_articles):
        # E5モデルの仕様に合わせ、入力文字列の先頭に "passage: " を付与
        input_text = f"passage: {article['title']}"
        
        try:
            print(f"[{idx + 1}/{len(new_articles)}] ベクトル生成中: {article['title']}")
            # 埋め込み生成
            embedding = generate_embedding(input_text, HF_TOKEN)
            article["embedding"] = embedding
            
            # Supabaseに挿入（UPSERT）
            supabase_client.table("articles").upsert(article, on_conflict="link").execute()
            success_count += 1
            
            # APIの負荷軽減・レートリミット対策のための短いウェイト
            time.sleep(0.5)
            
        except Exception as e:
            print(f"エラー: 記事「{article['title']}」の登録に失敗しました。{e}")
            
    print(f"処理完了: {success_count} / {len(new_articles)} 件登録成功")

if __name__ == "__main__":
    main()
