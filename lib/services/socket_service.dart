import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';
import 'api_client.dart';

typedef SocketHandler = void Function(dynamic data);

class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  io.Socket? _socket;

  Future<void> connect() async {
    if (_socket?.connected == true) return;

    final token = await ApiClient.instance.getToken();
    if (token == null) return;

    _socket = io.io(
      ApiConfig.baseUrl,
      io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setAuth({'token': token})
        .build(),
    );

    _socket!.connect();
    _socket!.onConnect((_) => print('🔌 Socket connected'));
    _socket!.onDisconnect((_) => print('🔌 Socket disconnected'));
    _socket!.onConnectError((err) => print('🔌 Connect error: $err'));
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  void on(String event, SocketHandler handler) {
    _socket?.on(event, handler);
  }

  void off(String event, [SocketHandler? handler]) {
    if (handler != null) {
      _socket?.off(event, handler);
    } else {
      _socket?.off(event);
    }
  }

  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  void subscribeToOrder(String orderId) {
    emit('order:subscribe', orderId);
  }

  void unsubscribeFromOrder(String orderId) {
    emit('order:unsubscribe', orderId);
  }

  // ── Phase 2 dispatch helpers ─────────────────────────────────────────────
  // The courier socket pushes `dispatch:offer`, `order:assigned`, and
  // `order:updated`. Consumers (e.g. `CourierStateProvider`) call `on(event,
  // handler)` directly; these helpers exist for typed convenience.

  void onDispatchOffer(SocketHandler handler) => on('dispatch:offer', handler);
  void offDispatchOffer([SocketHandler? handler]) =>
      off('dispatch:offer', handler);

  void onOrderAssigned(SocketHandler handler) => on('order:assigned', handler);
  void offOrderAssigned([SocketHandler? handler]) =>
      off('order:assigned', handler);

  void onOrderUpdated(SocketHandler handler) => on('order:updated', handler);
  void offOrderUpdated([SocketHandler? handler]) =>
      off('order:updated', handler);

  // ── Phase 3 chat helpers ─────────────────────────────────────────────────
  // Server emits `chat:message` with the full ChatMessage payload, plus
  // a generic `notification` channel used for global toasts (new chat
  // message arrived while user is on another screen, etc).

  void joinOrderChat(String orderId) {
    emit('chat:join', {'orderId': orderId});
  }

  void leaveOrderChat(String orderId) {
    emit('chat:leave', {'orderId': orderId});
  }

  void onChatMessage(SocketHandler handler) => on('chat:message', handler);
  void offChatMessage([SocketHandler? handler]) =>
      off('chat:message', handler);

  void onNotification(SocketHandler handler) => on('notification', handler);
  void offNotification([SocketHandler? handler]) =>
      off('notification', handler);

  bool get isConnected => _socket?.connected ?? false;
}
