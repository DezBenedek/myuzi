import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared flag so [ApiClient] can fail fast without Riverpod.
class NetStatus {
  static bool online = true;
}

class ConnectivityNotifier extends StateNotifier<bool> {
  ConnectivityNotifier() : super(true) {
    _init();
  }

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> _init() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _apply(results);
    } catch (_) {
      state = true;
      NetStatus.online = true;
    }
    _sub = _connectivity.onConnectivityChanged.listen(_apply);
  }

  void _apply(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    NetStatus.online = online;
    state = online;
  }

  Future<bool> checkNow() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _apply(results);
    } catch (_) {}
    return state;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// `true` = online, `false` = offline.
final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, bool>((ref) {
  return ConnectivityNotifier();
});
