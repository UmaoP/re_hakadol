import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
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
  Set<String> _readArticleIds = {};
  
  bool _isLoadingAll = true;
  bool _isLoadingRecommended = true;
  String? _authError;

  // 広告用キャッシュと状態管理
  final Map<int, NativeAd> _adCache = {};

  // Amazonアソシエイト関連商品の定義 (game, tech, animeの3大ジャンル)
  final List<Map<String, dynamic>> _affiliateAds = [
    {
      'id': 'aff-1',
      'title': '【最新モデル】PlayStation 5 (CFI-2000A01) 大ヒットゲーム同梱限定セット [PR]',
      'link': 'https://www.amazon.co.jp/dp/B0CL5N529B?tag=hakadollre-22', // AmazonアソシエイトURL (プレースホルダーID)
      'image_url': 'https://images.unsplash.com/photo-1606813907291-d86efa9b94db?w=200', 
      'source_name': 'Amazon.co.jp',
      'published_at': DateTime.now().toIso8601String(),
      'category': 'game',
      'price': '￥59,980',
    },
    {
      'id': 'aff-2',
      'title': '【プログラミング効率向上】ロジクール MX KEYS mini ワイヤレス イルミネイテッド キーボード [PR]',
      'link': 'https://www.amazon.co.jp/dp/B09J8S2C69?tag=hakadollre-22', 
      'image_url': 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=200', 
      'source_name': 'Amazon.co.jp',
      'published_at': DateTime.now().toIso8601String(),
      'category': 'tech',
      'price': '￥15,900',
    },
    {
      'id': 'aff-3',
      'title': '【コミック全巻セット】チェンソーマン コミックス 1-16巻セット（最新刊まで一気読み） [PR]',
      'link': 'https://www.amazon.co.jp/dp/B0CJR7MX8Z?tag=hakadollre-22', 
      'image_url': 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=200', 
      'source_name': 'Amazon.co.jp',
      'published_at': DateTime.now().toIso8601String(),
      'category': 'anime',
      'price': '￥8,200',
    },
  ];

  // ユーザーのおすすめ記事から最も興味のあるジャンルを分析し、最適なアフィリエイトを返す
  Map<String, dynamic> _getBestAffiliate() {
    if (_recommendedArticles.isEmpty) return _affiliateAds[0];

    int gameCount = 0;
    int techCount = 0;
    int animeCount = 0;

    for (var article in _recommendedArticles) {
      final title = (article['title'] ?? '').toString().toLowerCase();
      if (title.contains('ゲーム') || title.contains('game') || title.contains('switch') || title.contains('ps5') || title.contains('steam')) {
        gameCount++;
      } else if (title.contains('ai') || title.contains('開発') || title.contains('プログラミング') || title.contains('テック') || title.contains('エンジニア')) {
        techCount++;
      } else if (title.contains('マンガ') || title.contains('アニメ') || title.contains('コミック') || title.contains('声優') || title.contains('劇場版')) {
        animeCount++;
      }
    }

    if (techCount >= gameCount && techCount >= animeCount) {
      return _affiliateAds[1]; // テック系アフィリエイト (キーボード)
    } else if (animeCount >= gameCount && animeCount >= techCount) {
      return _affiliateAds[2]; // アニメ系アフィリエイト (コミックセット)
    } else {
      return _affiliateAds[0]; // ゲーム系アフィリエイト (PS5) (デフォルト)
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      final user = await _supabaseService.signInAnonymously();
      if (user == null) {
        setState(() {
          _authError = '認証に失敗しました。SupabaseのAnonymous Authが有効か確認してください。';
          _isLoadingAll = false;
          _isLoadingRecommended = false;
        });
        return;
      }
      
      await Future.wait([
        _loadAllArticles(),
        _loadRecommendedArticles(),
        _loadLikedArticles(),
        _loadReadArticles(),
      ]);
    } catch (e) {
      setState(() {
        _authError = 'アプリ起動エラー: $e';
        _isLoadingAll = false;
        _isLoadingRecommended = false;
      });
    }
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
    
    // クライアント側で記事リストを「マッチ度（%）」の降順で明示的にソート
    // これにより、履歴がある場合も初期状態（ダミーマッチ度）の場合も、常にマッチ率の高い順に上から並ぶことを保証します
    articles.sort((a, b) {
      final aRaw = double.tryParse(a['similarity_score']?.toString() ?? '') ?? 0.0;
      final bRaw = double.tryParse(b['similarity_score']?.toString() ?? '') ?? 0.0;
      
      int aMatch = 0;
      int bMatch = 0;

      // 1. similarity_score に基づくマッチ率算出
      if (aRaw > 0) {
        final double norm = (aRaw - 0.55) / 0.25;
        aMatch = ((norm * 38) + 60).clamp(60, 98).toInt();
      } else {
        // 初期ダミーマッチ度の算出 (IDハッシュから一意)
        aMatch = 65 + (a['id'].toString().hashCode.abs() % 14);
      }

      if (bRaw > 0) {
        final double norm = (bRaw - 0.55) / 0.25;
        bMatch = ((norm * 38) + 60).clamp(60, 98).toInt();
      } else {
        bMatch = 65 + (b['id'].toString().hashCode.abs() % 14);
      }

      return bMatch.compareTo(aMatch); // 降順ソート
    });

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

  Future<void> _loadReadArticles() async {
    final readIds = await _supabaseService.fetchReadArticleIds();
    setState(() {
      _readArticleIds = readIds;
    });
  }

  // 特定インデックス用のインフィード広告をロード・キャッシュ
  void _loadAdForIndex(int index) {
    if (_adCache.containsKey(index)) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final ad = NativeAd(
      adUnitId: 'ca-app-pub-3940256099942544/2247696110', 
      factoryId: null, 
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        cornerRadius: 16.0,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFF00CC99),
          style: NativeTemplateFontStyle.bold,
          size: 12,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: isDark ? Colors.white : Colors.black87,
          style: NativeTemplateFontStyle.bold,
          size: 13,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.grey[500],
          size: 11,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _adCache[index] = ad as NativeAd;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          print('広告のロードに失敗しました (index: $index): $error');
          ad.dispose();
        },
      ),
      request: const AdRequest(),
    );

    ad.load();
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

    final articleId = article['id'].toString();
    
    // アフィリエイト(IDがaff-)以外の場合のみ既読処理・ログ送信を行う
    if (!articleId.startsWith('aff-')) {
      setState(() {
        _readArticleIds.add(articleId);
      });
      _supabaseService.logArticleView(articleId);
    }
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.inAppBrowserView, 
        );
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('リンクを開けませんでした。')),
        );
      }
    }
  }

  Future<void> _toggleLike(String articleId) async {
    setState(() {
      if (_likedArticleIds.contains(articleId)) {
        _likedArticleIds.remove(articleId);
      } else {
        _likedArticleIds.add(articleId);
      }
    });
    await _supabaseService.toggleLikeArticle(articleId);
  }

  Future<void> _dislikeArticle(String articleId) async {
    setState(() {
      _allArticles.removeWhere((a) => a['id'] == articleId);
      _recommendedArticles.removeWhere((a) => a['id'] == articleId);
    });
    await _supabaseService.dislikeArticle(articleId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('この記事を非表示にしました。'),
          duration: Duration(seconds: 2),
        ),
      );
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

  // 広告表示用のインフィード広告ウィジェット
  Widget _buildAdCard(int index) {
    final ad = _adCache[index];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (ad != null) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          height: 106, 
          child: AdWidget(ad: ad),
        ),
      );
    }

    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF2D2D3D) : Colors.grey[300]!,
      highlightColor: isDark ? const Color(0xFF3D3D4D) : Colors.grey[100]!,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        child: Container(
          height: 106,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  // 溶け込みアフィリエイト案件の構築 (おすすめタブ用 - Amazonアソシエイト関連商品)
  Widget _buildAffiliateCard(int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final affiliate = _getBestAffiliate();
    final hasImage = affiliate['image_url'] != null;

    // アフィリエイトはユーザーの関心にマッチするため、高いマッチ率をバッジに表示
    final hash = index.hashCode.abs();
    final matchPercent = 90 + (hash % 9); // 90% 〜 98% マッチ

    return Card(
      key: ValueKey('aff_card_$index'),
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openArticle(affiliate),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  if (hasImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        affiliate['image_url'],
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5A5F), // 広告・PR用でおすすめと区別しやすい赤/ピンク
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$matchPercent% マッチ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        affiliate['title'] ?? '',
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
                                  color: isDark ? const Color(0xFF1F3D5A) : const Color(0xFFE6F2FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  affiliate['source_name'] ?? '',
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF3399FF) : const Color(0xFF0066CC),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                affiliate['price'] ?? '',
                                style: const TextStyle(
                                  color: Color(0xFFD32F2F),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          // Amazonアソシエイト用の特別な誘導ボタン (オレンジカラー)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9900), // Amazon オレンジ
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.shopping_cart, color: Colors.white, size: 10),
                                SizedBox(width: 4),
                                Text(
                                  'Amazonで見る',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
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
  }

  Widget _buildArticleList(List<Map<String, dynamic>> articles, bool isLoading, VoidCallback onRefresh, {bool isRecommended = false}) {
    if (_authError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_authError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _initApp, child: const Text('再試行')),
            ],
          ),
        ),
      );
    }

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

    // 10記事ごとに広告またはアフィリエイトを差し込むための計算
    const adInterval = 10; 
    final totalItems = articles.length + (articles.length ~/ adInterval);

    return RefreshIndicator(
      color: const Color(0xFF00CC99),
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        key: PageStorageKey(isRecommended ? 'rec_list_key' : 'all_list_key'),
        padding: const EdgeInsets.all(8.0),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          // 10記事ごとの差し込み位置
          if (index % (adInterval + 1) == adInterval) {
            if (isRecommended) {
              return _buildAffiliateCard(index);
            } else {
              _loadAdForIndex(index);
              return _buildAdCard(index);
            }
          }

          // 差し込みによる記事インデックスの調整
          final articleIndex = index - (index ~/ (adInterval + 1));
          
          if (articleIndex >= articles.length) {
            return const SizedBox.shrink();
          }

          final article = articles[articleIndex];
          final articleId = article['id'].toString();
          final hasImage = article['image_url'] != null && article['image_url'].toString().isNotEmpty;
          final isLiked = _likedArticleIds.contains(articleId);

          final rawScore = double.tryParse(article['similarity_score']?.toString() ?? '') ?? 0.0;
          final double normalized = (rawScore - 0.55) / 0.25;
          int matchPercent = rawScore > 0
              ? ((normalized * 38) + 60).clamp(60, 98).toInt()
              : 0;

          // おすすめタブで、履歴がない等の理由で similarity_score が 0.0 の場合でも、
          // ユーザーにマッチ度をアピールするため初期ダミーマッチ度 (65%〜78%) を記事IDに基づいて一意に算出して表示
          if (isRecommended && matchPercent == 0) {
            final hash = articleId.hashCode.abs();
            matchPercent = 65 + (hash % 14); // 65% 〜 78% の範囲で固定的にマッピング
          }

          final isRead = _readArticleIds.contains(articleId);

          return Card(
            key: ValueKey('card_$articleId'),
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openArticle(article),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                '$matchPercent% マッチ',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
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
                                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                color: isRead
                                    ? (isDark ? Colors.grey[600] : Colors.grey[500])
                                    : (isDark ? Colors.white : Colors.black87),
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
                                Row(
                                  children: [
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
      body: Container(
        color: isDark ? const Color(0xFF12121A) : Colors.grey[50],
        child: NestedScrollView(
          // スクロール時に AppBar を自動で折りたたんで隠し、タブを上部に固定する構造
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return <Widget>[
              SliverAppBar(
                expandedHeight: 96.0, // ロゴの縦幅を十分に確保
                floating: true,       // スクロールダウンで隠れ、少しのスクロールアップで再出現
                pinned: true,         // タブバー（bottom）は画面上部に固定
                snap: true,           // スナップイン動作
                elevation: 0,
                backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  titlePadding: const EdgeInsets.only(bottom: 48), // タブの上にロゴが重ならないように調整
                  title: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 44), // 高さを30→44に引き上げてロゴを大幅拡大
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
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
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildArticleList(_allArticles, _isLoadingAll, _loadAllArticles),
              _buildArticleList(_recommendedArticles, _isLoadingRecommended, _loadRecommendedArticles, isRecommended: true),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _adCache.values.forEach((ad) => ad.dispose());
    super.dispose();
  }
}
