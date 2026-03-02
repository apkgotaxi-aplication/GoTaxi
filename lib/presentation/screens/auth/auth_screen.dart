import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gotaxi/presentation/screens/home/home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nombreController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _dniController = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;

  /// Valida un DNI/NIE español.
  /// Formato DNI: 8 dígitos + 1 letra.
  /// Formato NIE: X/Y/Z + 7 dígitos + 1 letra.
  bool _validarDni(String dni) {
    final dniUpper = dni.toUpperCase().trim();
    final dniRegex = RegExp(r'^[0-9]{8}[A-Z]$');
    final nieRegex = RegExp(r'^[XYZ][0-9]{7}[A-Z]$');

    if (!dniRegex.hasMatch(dniUpper) && !nieRegex.hasMatch(dniUpper)) {
      return false;
    }

    const letras = 'TRWAGMYFPDXBNJZSQVHLCKE';
    String numStr = dniUpper;

    // Reemplazar letra inicial del NIE por su número equivalente
    if (dniUpper.startsWith('X')) {
      numStr = '0${dniUpper.substring(1)}';
    } else if (dniUpper.startsWith('Y')) {
      numStr = '1${dniUpper.substring(1)}';
    } else if (dniUpper.startsWith('Z')) {
      numStr = '2${dniUpper.substring(1)}';
    }

    final numero = int.tryParse(numStr.substring(0, numStr.length - 1));
    if (numero == null) return false;

    final letraEsperada = letras[numero % 23];
    final letraIntroducida = dniUpper[dniUpper.length - 1];

    return letraEsperada == letraIntroducida;
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

    if (!_isLogin && !_validarDni(_dniController.text)) {
      _showError('El DNI introducido no es correcto');
      return;
    }
    setState(() => _loading = true);

    try {
      if (_isLogin) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await Supabase.instance.client.auth.signUp(
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
          // Navegar a la pantalla principal tras login
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
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
    );
  }

  @override
  void dispose() {
    // Liberar los controladores para liberar memoria
    _emailController.dispose();
    _passwordController.dispose();
    _nombreController.dispose();
    _apellidosController.dispose();
    _telefonoController.dispose();
    _dniController.dispose();
    super.dispose();
  }
}
