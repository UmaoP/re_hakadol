import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'screens/news_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();

  // 環境変数またはプレースホルダーから設定を読み込みます
  // 実行時（ビルド時）に --dart-define=SUPABASE_URL=xxx --dart-define=SUPABASE_ANON_KEY=xxx を指定するか、
  // 下記の値を直接書き換えて使用します。
  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wybgkuqyvrybufwgxyoc.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind5YmdrdXF5dnJ5YnVmd2d4eW9jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQwODg2NzUsImV4cCI6MjA5OTY2NDY3NX0.-0LVf3-7Hn35bWK1J91DoA5e0-CSEZROuuSUEiNdHhE',
  );

  // Supabaseの初期化
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ハッカドール：Re',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: const Color(0xFF00CC99),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00CC99),
          brightness: Brightness.light,
          primary: const Color(0xFF00CC99),
          secondary: const Color(0xFF009973),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.grey[50],
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00CC99),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00CC99),
          brightness: Brightness.dark,
          primary: const Color(0xFF00CC99),
          secondary: const Color(0xFF009973),
          surface: const Color(0xFF1E1E2E),
        ),
        scaffoldBackgroundColor: const Color(0xFF12121A),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E2E),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      themeMode: ThemeMode.system, // システムのダークモード設定に自動連動
      home: const NewsListScreen(),
    );
  }
}
