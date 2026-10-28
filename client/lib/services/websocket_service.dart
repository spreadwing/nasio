import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';

typedef OnWsMessage = void Function(Map<String, dynamic> data);

class WebSocketService {
  static WebSocketService? _instance;
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isDisposed = false;
  bool _isConnected = false;

  final List<OnWsMessage> _listeners = [];

  WebSocketService._();

  static WebSocketService get instance {
    _instance ??= WebSocketService._();
    return _instance!;
  }

  bool get isConnected => _isConnected;

  void addListener(OnWsMessage listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(OnWsMessage listener) {
    _listeners.remove(listener);
  }

  void connect() {
    _isDisposed = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();

    final wsUrl = StorageService.getWsUrl();
    if (kDebugMode) {
      print('Connecting WebSocket to: $wsUrl');
    }

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _startHeartbeat();

      _channel?.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (err) {
          if (kDebugMode) {
            print('WebSocket error: $err');
          }
          _handleDisconnect();
        },
        onDone: () {
          if (kDebugMode) {
            print('WebSocket closed');
          }
          _handleDisconnect();
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('WebSocket connection failed: $e');
      }
      _handleDisconnect();
    }
  }

  void _handleMessage(dynamic raw) {
    if (raw == 'pong') {
      return;
    }
    try {
      final json = jsonDecode(raw.toString()) as Map<String, dynamic>;
      for (final listener in List.of(_listeners)) {
        listener(json);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing WebSocket message: $e');
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isConnected && _channel != null) {
        _channel?.sink.add('ping');
      }
    });
  }

  void _handleDisconnect() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _channel = null;

    if (!_isDisposed) {
      // 3秒后尝试重连
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        connect();
      });
    }
  }

  void disconnect() {
    _isDisposed = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }
}
