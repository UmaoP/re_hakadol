import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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

  Future<void> _openArticle(Map<String, dynamic> article) async {
    final url = Uri.parse(article['link']);
    
    // 閲覧ログの送信（非同期）
    _supabaseService.logArticleView(article['id']);
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.inAppBrowserView, // アプリ内Webビュー（Chrome Custom Tabs / SafariViewController）で表示
        );
        // 戻ってきたときにおすすめ情報を再読み込みして推薦をアップデートする
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

  Widget _buildArticleList(List<Map<String, dynamic>> articles, bool isLoading, VoidCallback onRefresh) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00CC99)));
    }
    
    if (articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('記事がありません', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF00CC99),
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: articles.length,
        itemBuilder: (context, index) {
          final article = articles[index];
          final hasImage = article['image_url'] != null && article['image_url'].toString().isNotEmpty;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openArticle(article),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                key: ValueKey(article['id']),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 画像サムネイル
                    if (hasImage)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.network(
                          article['image_url'],
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 90,
                              height: 90,
                              color: Colors.grey[200],
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
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: const Icon(Icons.newspaper, color: Colors.grey, size: 36),
                      ),
                    const SizedBox(width: 12),
                    // 記事テキスト情報
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
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                height: 1.3,
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.between,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE5F9F4),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    article['source_name'] ?? '',
                                    style: const TextStyle(
                                      color: Color(0xFF009973),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDate(article['published_at'] ?? ''),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 11,
                                  ),
                                ),
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // ハッカドール風の配色・アイコン
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFF00CC99),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            const Text(
              'ハッカドール再現',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF00CC99),
          unselectedLabelColor: Colors.grey,
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
        color: Colors.grey[50],
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildArticleList(_allArticles, _isLoadingAll, _loadAllArticles),
            _buildArticleList(_recommendedArticles, _isLoadingRecommended, _loadRecommendedArticles),
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
