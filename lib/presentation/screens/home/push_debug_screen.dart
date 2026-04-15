import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushDebugScreen extends StatefulWidget {
  const PushDebugScreen({super.key});

  @override
  State<PushDebugScreen> createState() => _PushDebugScreenState();
}

class _PushDebugScreenState extends State<PushDebugScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _subscriptionId;
  String? _dbSubscriptionId;
  String? _currentUserId;
  String? _currentJwt;
  String _jwtHeader = 'Sin decodificar';
  String _jwtPayloadSummary = 'Sin decodificar';
  bool _permission = false;
  bool _loading = true;
  bool _sending = false;
  bool _refreshingSession = false;
  String _lastOpenedPayload = 'Sin eventos';
  String _functionResult = 'Sin probar';
  String _lastRequestPayload = 'Sin enviar';

  late final OnNotificationClickListener _clickListener = _handleClick;
  late final OnPushSubscriptionChangeObserver _pushObserver =
      _handlePushSubscriptionChanged;

  @override
  void initState() {
    super.initState();
    OneSignal.Notifications.addClickListener(_clickListener);
    OneSignal.User.pushSubscription.addObserver(_pushObserver);
    _initDebug();
  }

  @override
  void dispose() {
    OneSignal.Notifications.removeClickListener(_clickListener);
    OneSignal.User.pushSubscription.removeObserver(_pushObserver);
    super.dispose();
  }

  Future<void> _initDebug() async {
    final currentUser = _supabase.auth.currentUser;
    final row = currentUser == null
        ? null
        : await _supabase
              .from('user_onesignal_players')
              .select('onesignal_player_id')
              .eq('user_id', currentUser.id)
              .maybeSingle();

    if (!mounted) return;

    setState(() {
      _permission = OneSignal.Notifications.permission;
      _subscriptionId = OneSignal.User.pushSubscription.id;
      _dbSubscriptionId = row?['onesignal_player_id'] as String?;
      _currentUserId = _supabase.auth.currentUser?.id;
      _currentJwt = _supabase.auth.currentSession?.accessToken;
      _jwtHeader = _decodeJwtSection(_currentJwt, 0);
      _jwtPayloadSummary = _describeJwtPayload(_currentJwt);
      _loading = false;
    });
  }

  String _decodeJwtSection(String? token, int index) {
    if (token == null || token.isEmpty) return 'null';

    final parts = token.split('.');
    if (parts.length <= index) return 'JWT invalido';

    try {
      final normalized = base64Url.normalize(parts[index]);
      return utf8.decode(base64Url.decode(normalized));
    } catch (_) {
      return 'No se pudo decodificar';
    }
  }

  String _describeJwtPayload(String? token) {
    final payload = _decodeJwtSection(token, 1);
    if (payload == 'null' ||
        payload == 'JWT invalido' ||
        payload == 'No se pudo decodificar') {
      return payload;
    }

    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      return jsonEncode({
        'iss': json['iss'],
        'sub': json['sub'],
        'role': json['role'],
        'aud': json['aud'],
        'exp': json['exp'],
      });
    } catch (_) {
      return payload;
    }
  }

  void _handleClick(OSNotificationClickEvent event) {
    if (!mounted) return;
    setState(() {
      _lastOpenedPayload = event.notification.additionalData.toString();
    });
  }

  void _handlePushSubscriptionChanged(OSPushSubscriptionChangedState state) {
    if (!mounted) return;
    setState(() {
      _subscriptionId = state.current.id;
    });
  }

  Future<void> _requestPermission() async {
    final accepted = await OneSignal.Notifications.requestPermission(true);
    if (!mounted) return;

    setState(() {
      _permission = accepted;
    });

    await _initDebug();
  }

  Future<void> _refreshSession() async {
    setState(() {
      _refreshingSession = true;
      _functionResult = 'Refrescando sesion...';
    });

    try {
      await _supabase.auth.refreshSession();
      await _initDebug();
      if (!mounted) return;
      setState(() {
        _functionResult = 'Sesion refrescada correctamente';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _functionResult = 'Error refrescando sesion: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _refreshingSession = false;
        });
      }
    }
  }

  Future<void> _sendTestPush() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;

    final requestBody = {
      'user_id': currentUser.id,
      'title': 'Push test GoTaxi',
      'body': 'Si ves esto, OneSignal funciona',
      'data': {'tipo': 'debug_push'},
    };

    print('USER => ${_supabase.auth.currentUser?.id}');
    print('JWT => ${_supabase.auth.currentSession?.accessToken}');
    print('REQUEST BODY => $requestBody');

    setState(() {
      _sending = true;
      _functionResult = 'Enviando...';
      _lastRequestPayload = requestBody.toString();
    });

    try {
      final result = await _supabase.functions.invoke(
        'send-notification',
        body: requestBody,
      );

      if (!mounted) return;
      setState(() {
        _functionResult = result.data.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _functionResult = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Push Debug')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _DebugCard(
                  title: 'Estado actual',
                  children: [
                    Text('Subscription ID local: ${_subscriptionId ?? 'null'}'),
                    const SizedBox(height: 8),
                    Text(
                      'Subscription ID en BD: ${_dbSubscriptionId ?? 'null'}',
                    ),
                    const SizedBox(height: 8),
                    Text('Permiso de notificaciones: $_permission'),
                    const SizedBox(height: 8),
                    SelectableText('USER => ${_currentUserId ?? 'null'}'),
                    const SizedBox(height: 8),
                    SelectableText('JWT => ${_currentJwt ?? 'null'}'),
                    const SizedBox(height: 8),
                    SelectableText('JWT header => $_jwtHeader'),
                    const SizedBox(height: 8),
                    SelectableText('JWT payload => $_jwtPayloadSummary'),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _requestPermission,
                  child: const Text('Solicitar permiso'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _refreshingSession ? null : _refreshSession,
                  child: Text(
                    _refreshingSession
                        ? 'Refrescando sesion...'
                        : 'Refrescar sesion',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _sending ? null : _sendTestPush,
                  child: Text(
                    _sending ? 'Enviando push...' : 'Enviarme push de prueba',
                  ),
                ),
                const SizedBox(height: 24),
                Text('Payload enviado', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(_lastRequestPayload),
                const SizedBox(height: 24),
                Text('Ultimo payload abierto', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(_lastOpenedPayload),
                const SizedBox(height: 24),
                Text('Resultado Edge Function', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(_functionResult),
              ],
            ),
    );
  }
}

class _DebugCard extends StatelessWidget {
  const _DebugCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
