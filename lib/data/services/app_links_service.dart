import 'dart:async';

import 'package:app_links/app_links.dart';

class AppLinksService {
  AppLinksService._internal();

  static final AppLinksService instance = AppLinksService._internal();

  final AppLinks _appLinks = AppLinks();
  final StreamController<Uri> _uriController =
      StreamController<Uri>.broadcast();

  bool _initialized = false;
  StreamSubscription<Uri>? _linkSubscription;

  Stream<Uri> get uriStream => _uriController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final initialLink = await _appLinks.getInitialLink();
    if (initialLink != null) {
      _uriController.add(initialLink);
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _uriController.add(uri);
    }, onError: (_) {});
  }

  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    await _uriController.close();
  }
}
