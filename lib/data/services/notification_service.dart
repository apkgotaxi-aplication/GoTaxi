import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _isInitialized = false;
  String? _currentUserId;
  bool _isSyncingSubscription = false;

  late final OnPushSubscriptionChangeObserver _pushObserver =
      _handlePushSubscriptionChange;
  late final OnNotificationPermissionChangeObserver _permissionObserver =
      _handlePermissionChange;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final appId = dotenv.env['ONESIGNAL_APP_ID'];
    if (appId == null || appId.isEmpty) {
      return;
    }

    OneSignal.Debug.setLogLevel(
      kDebugMode ? OSLogLevel.verbose : OSLogLevel.none,
    );
    OneSignal.Debug.setAlertLevel(OSLogLevel.none);

    await OneSignal.initialize(appId);

    OneSignal.Notifications.addClickListener(_handleNotificationTap);
    OneSignal.Notifications.addForegroundWillDisplayListener(
      _handleForegroundNotification,
    );
    OneSignal.User.pushSubscription.addObserver(_pushObserver);
    OneSignal.Notifications.addPermissionObserver(_permissionObserver);

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      _currentUserId = currentUser.id;
      await OneSignal.login(currentUser.id);
      await _syncCurrentSubscription();
    }

    _isInitialized = true;
  }

  void _handleForegroundNotification(OSNotificationWillDisplayEvent event) {
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
    await initialize();
    if (!_isInitialized) return;

    if (_currentUserId != userId) {
      await OneSignal.login(userId);
      _currentUserId = userId;
    }

    await requestPermissionIfNeeded();
    await _syncCurrentSubscription();
  }

  Future<void> logout() async {
    final userId =
        _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await _deleteStoredSubscription(userId);
    }

    _currentUserId = null;

    if (!_isInitialized) return;
    await OneSignal.logout();
  }

  Future<void> savePlayerId(String userId) async {
    final subscriptionId = OneSignal.User.pushSubscription.id;
    if (subscriptionId == null || subscriptionId.isEmpty) return;

    await Supabase.instance.client.from('user_onesignal_players').upsert({
      'user_id': userId,
      'onesignal_player_id': subscriptionId,
    }, onConflict: 'user_id');
  }

  Future<String?> getPlayerId() async {
    return OneSignal.User.pushSubscription.id;
  }

  Future<bool> requestPermissionIfNeeded() async {
    await initialize();
    if (!_isInitialized) return false;

    if (OneSignal.Notifications.permission) {
      return true;
    }

    return OneSignal.Notifications.requestPermission(true);
  }

  Future<void> _syncCurrentSubscription() async {
    final userId = _currentUserId;
    if (userId == null || _isSyncingSubscription) return;

    _isSyncingSubscription = true;
    try {
      await savePlayerId(userId);
    } finally {
      _isSyncingSubscription = false;
    }
  }

  Future<void> _deleteStoredSubscription(String userId) async {
    await Supabase.instance.client
        .from('user_onesignal_players')
        .delete()
        .eq('user_id', userId);
  }

  void _handlePermissionChange(bool granted) {
    if (granted) {
      unawaited(_syncCurrentSubscription());
    }
  }

  void _handlePushSubscriptionChange(OSPushSubscriptionChangedState state) {
    if (state.current.id != null && state.current.id != state.previous.id) {
      unawaited(_syncCurrentSubscription());
    }
  }
}
