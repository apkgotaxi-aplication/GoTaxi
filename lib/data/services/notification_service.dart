import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final appId = dotenv.env['ONESIGNAL_APP_ID'];
    if (appId == null || appId.isEmpty) {
      return;
    }

    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.Debug.setAlertLevel(OSLogLevel.none);

    OneSignal.Notifications.addClickListener(_handleNotificationTap);
    OneSignal.Notifications.addForegroundWillDisplayListener(
      _handleForegroundNotification,
    );

    OneSignal.initialize(appId);

    _isInitialized = true;
  }

  void _handleForegroundNotification(OSNotificationWillDisplayEvent event) {
    event.preventDefault();
    event.notification.display();
  }

  void _handleNotificationTap(OSNotificationClickEvent event) {
    final additionalData = event.notification.additionalData;
    if (additionalData != null) {
      final viajeId = additionalData['viaje_id'] as String?;
      if (viajeId != null) {
        _navigateToRide(viajeId);
      }
    }
  }

  void _navigateToRide(String viajeId) {}

  Future<void> login(String userId) async {
    if (!_isInitialized) return;
    OneSignal.login(userId);
    await savePlayerId(userId);
  }

  Future<void> logout() async {
    if (!_isInitialized) return;
    OneSignal.logout();
  }

  Future<void> savePlayerId(String userId) async {
    final playerId = OneSignal.User.pushSubscription.id;
    if (playerId == null) return;

    await Supabase.instance.client.from('user_onesignal_players').upsert({
      'user_id': userId,
      'onesignal_player_id': playerId,
    }, onConflict: 'user_id');
  }

  Future<String?> getPlayerId() async {
    return OneSignal.User.pushSubscription.id;
  }
}
