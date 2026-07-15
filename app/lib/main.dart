import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/news_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      title: 'ハッカドール再現',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF00CC99),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00CC99),
          primary: const Color(0xFF00CC99),
          secondary: const Color(0xFF00CC99),
        ),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const NewsListScreen(),
    );
  }
}
