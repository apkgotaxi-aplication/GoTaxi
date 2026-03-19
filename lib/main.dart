import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './presentation/screens/auth/auth_screen.dart';
import './presentation/screens/home/home_screen.dart';

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
      title: 'GoTaxi',
      theme: ThemeData.dark(),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final hasSession = Supabase.instance.client.auth.currentSession != null;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => hasSession ? const HomeScreen() : const AuthScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.local_taxi, size: 84),
            SizedBox(height: 16),
            Text(
              'GoTaxi',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
