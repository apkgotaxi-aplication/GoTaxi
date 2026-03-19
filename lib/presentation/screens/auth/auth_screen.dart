import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gotaxi/data/services/auth_service.dart';
import 'package:gotaxi/domain/validators/dni_validator.dart';
import 'package:gotaxi/presentation/screens/home/home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.authService,
    this.homeBuilder,
  });

  final AuthService? authService;
  final WidgetBuilder? homeBuilder;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nombreController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _dniController = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  late final AnimationController _beamsController;
  late final AuthService _authService;
  late final WidgetBuilder _homeBuilder;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? SupabaseAuthService();
    _homeBuilder = widget.homeBuilder ?? (_) => const HomeScreen();
    _beamsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  Future<void> _submit() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('Por favor, rellena todos los campos');
      return;
    }

    if (!_isLogin &&
        (_nombreController.text.isEmpty || _apellidosController.text.isEmpty)) {
      _showError('Nombre y apellidos son obligatorios para el registro');
      return;
    }

    if (!_isLogin && _dniController.text.trim().isEmpty) {
      _showError('El DNI es obligatorio para el registro');
      return;
    }

    if (!_isLogin && !validarDniNie(_dniController.text)) {
      _showError('El DNI introducido no es correcto');
      return;
    }
    setState(() => _loading = true);

    try {
      if (_isLogin) {
        await _authService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await _authService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          data: {
            'nombre': _nombreController.text.trim(),
            'apellidos': _apellidosController.text.trim(),
            'telefono': _telefonoController.text.trim(),
            'dni': _dniController.text.trim().toUpperCase(),
          },
        );
      }

      if (mounted) {
        if (_isLogin) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: _homeBuilder),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registro correcto. Ahora inicia sesión.'),
            ),
          );
          setState(() => _isLogin = true);
        }
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Error inesperado');
    }

    setState(() => _loading = false);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _beamsController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _BeamsPainter(progress: _beamsController.value),
                );
              },
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                color: Colors.black.withValues(alpha: 0.68),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isLogin ? 'Iniciar Sesión' : 'Crear Cuenta',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!_isLogin) ...[
                        TextField(
                          controller: _nombreController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _apellidosController,
                          decoration: const InputDecoration(
                            labelText: 'Apellidos',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _telefonoController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono',
                            prefixIcon: Icon(Icons.phone),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _dniController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'DNI / NIE *',
                            prefixIcon: Icon(Icons.badge),
                            hintText: '12345678A',
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: Icon(Icons.lock),
                        ),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const CircularProgressIndicator()
                              : Text(_isLogin ? 'Entrar' : 'Registrarse'),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextButton(
                        onPressed: () => setState(() => _isLogin = !_isLogin),
                        child: Text(
                          _isLogin
                              ? '¿No tienes cuenta? Regístrate'
                              : '¿Ya tienes cuenta? Inicia sesión',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _beamsController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nombreController.dispose();
    _apellidosController.dispose();
    _telefonoController.dispose();
    _dniController.dispose();
    super.dispose();
  }
}

class _BeamsPainter extends CustomPainter {
  _BeamsPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFF030303);
    canvas.drawRect(Offset.zero & size, background);

    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(30 * math.pi / 180);
    canvas.translate(-center.dx, -center.dy);

    const beamCount = 20;
    const beamWidth = 3.0;
    final beamHeight = size.height * 0.42;
    final spacing = size.width / beamCount;
    final speed = size.height * 0.55;

    for (var index = 0; index < beamCount; index++) {
      final x = spacing * index + (spacing - beamWidth) / 2;
      final waveOffset = math.sin((index * 0.7) + (progress * math.pi * 2));
      final y =
          ((progress * speed * 2) + (index * 36) + waveOffset * 18) %
              (size.height + beamHeight * 2) -
          beamHeight;

      final rect = Rect.fromLTWH(x, y, beamWidth, beamHeight);
      final gradient = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00FFF200),
            Color(0x88FFF200),
            Color(0xCCFFF200),
            Color(0x00FFF200),
          ],
          stops: [0.0, 0.25, 0.75, 1.0],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        gradient,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BeamsPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
