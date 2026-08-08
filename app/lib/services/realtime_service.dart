import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef RealtimeHandler = void Function(Map<String, dynamic> event);

/// Durable Object WebSocket client for inbox / chat / incoming calls.
class RealtimeService {
  RealtimeService();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _ping;
  Timer? _reconnect;
  String? _baseUrl;
  String? _token;
  bool _wanted = false;
  int _backoffSec = 1;
  final _handlers = <RealtimeHandler>{};
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _controller.stream;
  bool get isConnected => _channel != null;

  void addHandler(RealtimeHandler handler) => _handlers.add(handler);
  void removeHandler(RealtimeHandler handler) => _handlers.remove(handler);

  void connect({required String baseUrl, required String token}) {
    _baseUrl = baseUrl;
    _token = token;
    _wanted = true;
    _open();
  }

  void disconnect() {
    _wanted = false;
    _reconnect?.cancel();
    _ping?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _sub = null;
  }

  void _open() {
    final base = _baseUrl;
    final token = _token;
    if (!_wanted || base == null || token == null || token.isEmpty) return;

    _ping?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    final wsBase = base
        .replaceFirst(RegExp(r'^https://'), 'wss://')
        .replaceFirst(RegExp(r'^http://'), 'ws://');
    final uri = Uri.parse('$wsBase/api/realtime/ws').replace(
      queryParameters: {'token': token},
    );

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _sub = channel.stream.listen(
        (raw) {
          _backoffSec = 1;
          if (raw is! String) return;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              final event = Map<String, dynamic>.from(decoded);
              if (!_controller.isClosed) _controller.add(event);
              for (final h in List.of(_handlers)) {
                try {
                  h(event);
                } catch (e) {
                  debugPrint('[realtime handler] $e');
                }
              }
            }
          } catch (_) {}
        },
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _ping?.cancel();
    _sub?.cancel();
    _channel = null;
    if (!_wanted) return;
    _reconnect?.cancel();
    final wait = _backoffSec;
    _backoffSec = (_backoffSec * 2).clamp(1, 30);
    _reconnect = Timer(Duration(seconds: wait), _open);
  }

  void dispose() {
    disconnect();
    _handlers.clear();
    unawaited(_controller.close());
  }
}
