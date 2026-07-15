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

  /// 記事の閲覧履歴を登録します。
  Future<void> logArticleView(String articleId) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      await client.from('user_history').insert({
        'user_id': userId,
        'article_id': articleId,
        'action_type': 'read',
      });
    } catch (e) {
      print('履歴保存エラー: $e');
    }
  }
}
