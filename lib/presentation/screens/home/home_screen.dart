import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gotaxi/presentation/screens/home/tabs/driver_dashboard_tab.dart';
import 'package:gotaxi/presentation/screens/home/tabs/map_tab.dart';
import 'package:gotaxi/presentation/screens/home/tabs/profile_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;

  int _currentIndex = 0;
  bool _loadingRole = true;
  bool _isTaxista = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isTaxista = false;
          _loadingRole = false;
        });
        return;
      }

      final response = await _supabase
          .from('usuarios')
          .select('rol')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _isTaxista = response != null && response['rol'] == 'taxista';
        _loadingRole = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isTaxista = false;
        _loadingRole = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tabs = _isTaxista
        ? const [DriverDashboardTab(), ProfileTab()]
        : const [MapTab(), ProfileTab()];

    return Scaffold(
      resizeToAvoidBottomInset: _currentIndex != 0,
      body: tabs[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: Icon(
              _isTaxista ? Icons.dashboard_outlined : Icons.map_outlined,
            ),
            selectedIcon: Icon(_isTaxista ? Icons.dashboard : Icons.map),
            label: _isTaxista ? 'Panel' : 'Mapa',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
