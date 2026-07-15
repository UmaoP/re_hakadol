import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import '../services/supabase_service.dart';

class NewsListScreen extends StatefulWidget {
  const NewsListScreen({super.key});

  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseService _supabaseService = SupabaseService();
  
  List<Map<String, dynamic>> _allArticles = [];
  List<Map<String, dynamic>> _recommendedArticles = [];
  Set<String> _likedArticleIds = {};
  
  bool _isLoadingAll = true;
  bool _isLoadingRecommended = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // 匿名サインインを実行後、データを取得
    _initApp();
  }

  Future<void> _initApp() async {
    await _supabaseService.signInAnonymously();
    _loadAllArticles();
    _loadRecommendedArticles();
    _loadLikedArticles();
  }

  Future<void> _loadAllArticles() async {
    setState(() => _isLoadingAll = true);
    final articles = await _supabaseService.fetchArticles();
    setState(() {
      _allArticles = articles;
      _isLoadingAll = false;
    });
  }

  Future<void> _loadRecommendedArticles() async {
    setState(() => _isLoadingRecommended = true);
    final articles = await _supabaseService.fetchRecommendedArticles();
    setState(() {
      _recommendedArticles = articles;
      _isLoadingRecommended = false;
    });
  }

  Future<void> _loadLikedArticles() async {
    final likedIds = await _supabaseService.fetchLikedArticleIds();
    setState(() {
      _likedArticleIds = likedIds;
    });
  }

  Future<void> _openArticle(Map<String, dynamic> article) async {
    final urlString = article['link'] ?? '';
    if (urlString.isEmpty) return;

    final url = Uri.tryParse(urlString);
    if (url == null || !(url.scheme == 'http' || url.scheme == 'https')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無効なURLリンクです。')),
        );
      }
      return;
    }
    
    // 閲覧ログの送信（非同期）
    _supabaseService.logArticleView(article['id']);
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.inAppBrowserView, // アプリ内ブラウザ（Chrome Custom Tabs / SafariViewController）で表示
        );
        // 戻ってきたときにおすすめ情報を再読み込みして推薦をアップデート
        _loadRecommendedArticles();
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('記事を開けませんでした。')),
        );
      }
    }
  }

  Future<void> _toggleLike(String articleId) async {
    final isLiked = await _supabaseService.toggleLikeArticle(articleId);
    setState(() {
      if (isLiked) {
        _likedArticleIds.add(articleId);
      } else {
        _likedArticleIds.remove(articleId);
      }
    });
    // お気に入り状況が変わったので、おすすめリストも再読み込みして推薦モデルに学習させる
    _loadRecommendedArticles();
  }

  Future<void> _dislikeArticle(String articleId) async {
    // 楽観的UI更新：リストから即座に非表示にしてレスポンスを改善
    setState(() {
      _allArticles.removeWhere((a) => a['id'] == articleId);
      _recommendedArticles.removeWhere((a) => a['id'] == articleId);
    });

    // バックグラウンドで「興味なし」登録（他の推薦でもこの系統が排除されるようになる）
    await _supabaseService.dislikeArticle(articleId);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('この記事を非表示にしました。好みを学習します。'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    _loadRecommendedArticles();
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}分前';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}時間前';
      } else {
        return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {
      return '';
    }
  }

  Widget _buildShimmerList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: isDark ? const Color(0xFF2D2D3D) : Colors.grey[300]!,
          highlightColor: isDark ? const Color(0xFF3D3D4D) : Colors.grey[100]!,
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: double.infinity, height: 16, color: Colors.white),
                        const SizedBox(height: 8),
                        Container(width: 150, height: 12, color: Colors.white),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(width: 60, height: 16, color: Colors.white),
                            Container(width: 50, height: 12, color: Colors.white),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildArticleList(List<Map<String, dynamic>> articles, bool isLoading, VoidCallback onRefresh, {bool isRecommended = false}) {
    if (isLoading) {
      return _buildShimmerList();
    }
    
    if (articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '記事がありません',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      color: const Color(0xFF00CC99),
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: articles.length,
        itemBuilder: (context, index) {
          final article = articles[index];
          final articleId = article['id'].toString();
          final hasImage = article['image_url'] != null && article['image_url'].toString().isNotEmpty;
          final isLiked = _likedArticleIds.contains(articleId);

          // コサイン類似度のスコア（0.0 〜 1.0）を % に変換（E5モデルのスコア範囲に応じたスケーリング）
          // スコアが 0.7 以下の場合は底上げし、リアルで見栄えの良いマッチ度を算出します
          final rawScore = article['similarity_score'] as double? ?? 0.0;
          final int matchPercent = rawScore > 0
              ? (((rawScore - 0.5) / 0.5 * 100).clamp(50, 99)).toInt()
              : 0;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openArticle(article),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                key: ValueKey(articleId),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 画像サムネイル
                    Stack(
                      children: [
                        if (hasImage)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              article['image_url'],
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 90,
                                  height: 90,
                                  color: isDark ? const Color(0xFF2D2D3D) : Colors.grey[200],
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                );
                              },
                            ),
                          )
                        else
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2D2D3D) : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.newspaper, color: Colors.grey, size: 36),
                          ),
                        // おすすめタブでの「マッチ度（%）」表示バッジ
                        if (isRecommended && matchPercent > 0)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00CC99),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$matchPercent%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // 記事テキストとアクション
                    Expanded(
                      child: SizedBox(
                        height: 90,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              article['title'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                                height: 1.3,
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF154030) : const Color(0xFFE5F9F4),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        article['source_name'] ?? '',
                                        style: TextStyle(
                                          color: isDark ? const Color(0xFF00FFCC) : const Color(0xFF009973),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatDate(article['published_at'] ?? ''),
                                      style: TextStyle(
                                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                                // アクションボタン（お気に入り＆興味なし）
                                Row(
                                  children: [
                                    // お気に入り（ハート）
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        isLiked ? Icons.favorite : Icons.favorite_border,
                                        color: isLiked ? Colors.pink : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                        size: 20,
                                      ),
                                      onPressed: () => _toggleLike(articleId),
                                    ),
                                    const SizedBox(width: 10),
                                    // 興味なし（非表示）
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        Icons.visibility_off_outlined,
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        size: 20,
                                      ),
                                      onPressed: () => _dislikeArticle(articleId),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFF00CC99),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            Text(
              'ハッカドール：Re',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF00CC99),
          unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey,
          indicatorColor: const Color(0xFF00CC99),
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          tabs: const [
            Tab(text: 'すべて'),
            Tab(text: 'おすすめ'),
          ],
        ),
      ),
      body: Container(
        color: isDark ? const Color(0xFF12121A) : Colors.grey[50],
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildArticleList(_allArticles, _isLoadingAll, _loadAllArticles),
            _buildArticleList(_recommendedArticles, _isLoadingRecommended, _loadRecommendedArticles, isRecommended: true),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
