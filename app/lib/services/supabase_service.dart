import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  /// 匿名サインインを実行し、Userを返します。既存のセッションがあれば再利用します。
  Future<User?> signInAnonymously() async {
    try {
      final currentUser = client.auth.currentUser;
      if (currentUser != null) {
        print('既存のログインセッションを再利用します: ${currentUser.id}');
        return currentUser;
      }
      
      final response = await client.auth.signInAnonymously();
      print('新規に匿名サインインしました: ${response.user?.id}');
      return response.user;
    } catch (e) {
      print('匿名認証エラー: $e');
      return null;
    }
  }

  /// 現在のユーザーIDを取得します。
  String? get currentUserId => client.auth.currentUser?.id;

  /// 通常の新着記事一覧を取得します。
  Future<List<Map<String, dynamic>>> fetchArticles({int limit = 50}) async {
    try {
      final response = await client
          .from('articles')
          .select()
          .order('published_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('記事取得エラー: $e');
      return [];
    }
  }

  /// 閲覧履歴に基づいた推薦記事一覧を取得します。
  Future<List<Map<String, dynamic>>> fetchRecommendedArticles({int limit = 50}) async {
    final userId = currentUserId;
    if (userId == null) {
      // ユーザーが認証されていない場合は通常の新着記事をフォールバック
      return fetchArticles(limit: limit);
    }

    try {
      final response = await client.rpc(
        'get_recommended_articles',
        params: {
          'user_uuid': userId,
          'match_limit': limit,
        },
      );
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('推薦記事取得エラー: $e');
      // エラー時は新着記事をフォールバックとして返す
      return fetchArticles(limit: limit);
    }
  }

  /// 記事の閲覧履歴を登録します。すでに登録済みの場合は重複を避けるため登録しません。
  Future<void> logArticleView(String articleId) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      // 既に履歴が存在するか確認
      final existing = await client
          .from('user_history')
          .select()
          .eq('user_id', userId)
          .eq('article_id', articleId)
          .limit(1)
          .maybeSingle();

      if (existing != null) return; // 既にread/like等が存在すればスキップ

      await client.from('user_history').insert({
        'user_id': userId,
        'article_id': articleId,
        'action_type': 'read',
      });
    } catch (e) {
      print('履歴保存エラー: $e');
    }
  }

  /// お気に入りのトグル（すでにお気に入りされていれば削除、されていなければ追加）
  Future<bool> toggleLikeArticle(String articleId) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final existing = await client
          .from('user_history')
          .select()
          .eq('user_id', userId)
          .eq('article_id', articleId)
          .eq('action_type', 'like')
          .maybeSingle();

      if (existing != null) {
        // お気に入り解除
        await client
            .from('user_history')
            .delete()
            .eq('id', existing['id']);
        return false; // お気に入り解除された
      } else {
        // お気に入り登録
        await client.from('user_history').insert({
          'user_id': userId,
          'article_id': articleId,
          'action_type': 'like',
        });
        return true; // お気に入り登録された
      }
    } catch (e) {
      print('お気に入りトグルエラー: $e');
      return false;
    }
  }

  /// 興味なし（dislike）に登録します（既存の閲覧履歴があれば削除）
  Future<void> dislikeArticle(String articleId) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      // 既存の閲覧・お気に入り履歴があれば削除
      await client
          .from('user_history')
          .delete()
          .eq('user_id', userId)
          .eq('article_id', articleId);

      // 新しく「興味なし」アクションを挿入
      await client.from('user_history').insert({
        'user_id': userId,
        'article_id': articleId,
        'action_type': 'dislike',
      });
    } catch (e) {
      print('興味なし登録エラー: $e');
    }
  }

  /// ユーザーがお気に入りした記事のIDセットを取得します。
  Future<Set<String>> fetchLikedArticleIds() async {
    final userId = currentUserId;
    if (userId == null) return {};

    try {
      final response = await client
          .from('user_history')
          .select('article_id')
          .eq('user_id', userId)
          .eq('action_type', 'like');
      
      final ids = List<Map<String, dynamic>>.from(response)
          .map((row) => row['article_id'].toString())
          .toSet();
      return ids;
    } catch (e) {
      print('お気に入り一覧取得エラー: $e');
      return {};
    }
  }
}
