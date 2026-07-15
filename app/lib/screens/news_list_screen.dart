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

      if (aRaw > 0) {
        final double norm = (aRaw - 0.55) / 0.25;
        aMatch = ((norm * 38) + 60).clamp(60, 98).toInt();
      } else {
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

  Future<void> _likedArticlesLoad() async {
    final likedIds = await _supabaseService.fetchLikedArticleIds();
    setState(() {
      _likedArticleIds = likedIds;
    });
  }

  Future<void> _loadLikedArticles() async {
    await _likedArticlesLoad();
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

  // セリフや無効なフレーズをフィルタリングする処理
  bool _isValidKeyword(String text) {
    if (text.length < 2 || text.length > 20) return false;
    
    // セリフ、口語表現、予約などのアクション単体フレーズを除外
    final invalidPatterns = RegExp(
      r'(です|ます|だっ|ください|予約開始|発売開始|決定|発表|スタート|登場|開催|コラボ|特集|情報|速報|！|？|w|www|お勧め|おすすめ|一覧|まとめ)$'
    );
    if (invalidPatterns.hasMatch(text)) return false;
    
    // 助詞を含む長文フレーズの除外
    if (text.contains('が') || text.contains('は') || text.contains('の') || text.contains('で') || text.contains('を')) {
      return false;
    }
    
    return true;
  }

  // タイトルから複数のアフィリエイトキーワード候補を抽出するロジック
  List<String> _extractCandidateKeywords(String title) {
    final List<String> candidates = [];
    
    // 1. カギカッコ 「」 や 『』 の中身を抽出
    final bracketRegExp = RegExp(r'[「『]([^」』]{2,20})[」』]');
    final matches = bracketRegExp.allMatches(title);
    for (var m in matches) {
      final text = m.group(1)!.trim();
      if (_isValidKeyword(text)) {
        candidates.add(text);
      }
    }

    // 2. 【】 や [ ] で囲まれた宣伝用ヘッダーから抽出
    final headerRegExp = RegExp(r'[【\[]([^】\]]{2,20})[】\]]');
    final hMatches = headerRegExp.allMatches(title);
    for (var m in hMatches) {
      final text = m.group(1)!.trim();
      if (_isValidKeyword(text)) {
        candidates.add(text);
      }
    }

    // 3. 区切り記号で分割された3〜15文字のフレーズ
    final cleanTitle = title.replaceAll(RegExp(r'[「『【\[].*?[」』】\]]'), ' ');
    final parts = cleanTitle.split(RegExp(r'[|：\-－／/,\s]'));
    for (var part in parts) {
      final p = part.trim();
      if (p.length >= 3 && p.length <= 15 && _isValidKeyword(p)) {
        candidates.add(p);
      }
    }

    return candidates.toSet().toList(); // 重複排除
  }

  // ユーザーの興味（_recommendedArticles）に最も関連性の高いキーワードを選択
  String _selectBestKeyword(List<String> candidates, String fallbackKeyword) {
    if (candidates.isEmpty) return fallbackKeyword;
    if (candidates.length == 1) return candidates.first;

    String bestKeyword = candidates.first;
    int highestScore = -1;

    for (var candidate in candidates) {
      int score = 0;
      final lowerCandidate = candidate.toLowerCase();
      
      for (var article in _recommendedArticles) {
        final recTitle = (article['title'] ?? '').toString().toLowerCase();
        // 過去の関心に近いおすすめ記事タイトルとの部分一致を評価
        if (recTitle.contains(lowerCandidate)) {
          score += 5;
        }
      }
      
      // キーワードの長さ（適度な4〜10文字）へのバイアス評価
      if (candidate.length >= 4 && candidate.length <= 10) {
        score += 1;
      }

      if (score > highestScore) {
        highestScore = score;
        bestKeyword = candidate;
      }
    }

    return bestKeyword;
  }

  // 手前10件のコンテキスト記事全体から、最も好みにマッチしたキーワードと対応する画像を抽出するロジック
  Map<String, dynamic> _getBestAffiliateFromContext(int index, List<Map<String, dynamic>> articles) {
    final List<Map<String, dynamic>> contextArticles = [];
    
    // 現在差し込みを行っている直前の記事インデックスを逆算
    const adInterval = 10; 
    final currentArticleIndex = index - (index ~/ (adInterval + 1));
    
    // 手前10件の記事を収集
    for (int i = 1; i <= 10; i++) {
      final targetIndex = currentArticleIndex - i;
      if (targetIndex >= 0 && targetIndex < articles.length) {
        contextArticles.add(articles[targetIndex]);
      }
    }

    // デフォルト値 (手前記事が取得できないなどのフォールバック)
    var bestKeyword = 'ゲーム ガジェット';
    var imageUrl = 'https://images.unsplash.com/photo-1606813907291-d86efa9b94db?w=200';
    var link = 'https://www.amazon.co.jp/s?k=ゲーム+ガジェット&tag=umaop_hackadollre-22';
    var priceText = '最新価格をチェック';

    if (contextArticles.isEmpty) {
      return {
        'title': '【Amazon】注目の最新ゲーム・ガジェット関連商品 [PR]',
        'link': link,
        'image_url': imageUrl,
        'priceText': priceText,
      };
    }

    // 10件の記事タイトルすべてからキーワード候補を抽出
    // 同時に、どのキーワードがどの画像URLから抽出されたかをマッピング保持（画像のシンクロ化）
    final Map<String, String> keywordToImageUrl = {};
    final List<String> allCandidates = [];

    for (var article in contextArticles) {
      final prevTitle = article['title'] ?? '';
      final candidates = _extractCandidateKeywords(prevTitle);
      
      final artImgUrl = (article['image_url'] ?? '').toString();
      
      for (var cand in candidates) {
        allCandidates.add(cand);
        if (artImgUrl.isNotEmpty && !keywordToImageUrl.containsKey(cand)) {
          keywordToImageUrl[cand] = artImgUrl;
        }
      }
    }

    // 10件分のキーワード候補の中から、ユーザーの好みに最も適合するものを選択
    if (allCandidates.isNotEmpty) {
      // デフォルトフォールバックは直前1件目の最初のキーワード
      final firstArticleTitle = contextArticles.first['title'] ?? '';
      final firstArticleCandidates = _extractCandidateKeywords(firstArticleTitle);
      final defaultKeyword = firstArticleCandidates.isNotEmpty 
          ? firstArticleCandidates.first 
          : firstArticleTitle.substring(0, firstArticleTitle.length > 8 ? 8 : firstArticleTitle.length);
      
      bestKeyword = _selectBestKeyword(allCandidates, defaultKeyword);
      link = 'https://www.amazon.co.jp/s?k=${Uri.encodeComponent(bestKeyword)}&tag=umaop_hackadollre-22';
      
      // 画像は選択されたキーワードに紐づく記事画像をそのまま使用（完全一致ビジュアル）
      if (keywordToImageUrl.containsKey(bestKeyword)) {
        imageUrl = keywordToImageUrl[bestKeyword]!;
      } else if (contextArticles.first['image_url'] != null) {
        imageUrl = contextArticles.first['image_url'];
      }
      priceText = 'Amazonポイント還元あり';
    }

    return {
      'title': '【Amazon】「$bestKeyword」の関連商品・最安値を今すぐチェック！ [PR]',
      'link': link,
      'image_url': imageUrl,
      'priceText': priceText,
    };
  }

  // 溶け込みアフィリエイト案件の構築 (おすすめタブ用 - 直前10件のコンテキストとユーザーの好みの両方に最適化したアソシエイト)
  Widget _buildAffiliateCard(int index, List<Map<String, dynamic>> articles) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // コンテキスト分析エンジンから最適なアフィリエイト情報を動的生成
    final affiliate = _getBestAffiliateFromContext(index, articles);
    final link = affiliate['link'] ?? '';
    final imageUrl = affiliate['image_url'] ?? '';
    final title = affiliate['title'] ?? '';
    final priceText = affiliate['priceText'] ?? '最新価格を表示';
    final sourceName = 'Amazon.co.jp';

    final hash = index.hashCode.abs();
    final matchPercent = 90 + (hash % 9); // 90% 〜 98% マッチ

    return Card(
      key: ValueKey('aff_card_$index'),
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openArticle({'link': link, 'id': 'aff-$index'}),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrl,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 90,
                          height: 90,
                          color: isDark ? const Color(0xFF2D2D3D) : Colors.grey[200],
                          child: const Icon(Icons.shopping_bag, color: Colors.grey),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5A5F), 
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
                        title,
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
                                  sourceName,
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF3399FF) : const Color(0xFF0066CC),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                priceText,
                                style: const TextStyle(
                                  color: Color(0xFFD32F2F),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          // Amazonアソシエイト用オレンジボタン
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9900), 
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
              return _buildAffiliateCard(index, articles);
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
                floating: true,       
                pinned: true,         
                snap: true,           
                elevation: 0,
                backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                title: Image.asset(
                  'assets/images/logo.png',
                  height: 42,
                  fit: BoxFit.contain,
                ),
                centerTitle: true,
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
