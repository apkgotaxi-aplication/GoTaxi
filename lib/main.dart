import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './presentation/screens/auth/auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase credentials
  await Supabase.initialize(
    url: 'https://vkewprpynejnmobgpbiu.supabase.co',
    anonKey: 'sb_publishable_0wl332igFmJN2iRCAJFqTg_KecNU5-b',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Supabase Auth',
      theme: ThemeData.dark(),
      home: const AuthScreen(),
    );
  }
}