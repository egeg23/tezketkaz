import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import 'api_client.dart';

/// Платёжный сервис для Узбекистана.
///
/// Как работает:
/// 1. Клиент создаёт заказ → backend возвращает payment URL для выбранного метода
/// 2. Клиент открывает URL в браузере / WebView (зависит от провайдера)
/// 3. После оплаты провайдер делает callback на backend → backend проставляет `isPaid: true`
/// 4. Клиент получает push / socket event и видит обновлённый статус
///
/// Прежде чем подключать провайдеров, нужно получить:
/// - Click: merchant_id + secret_key на https://click.uz/business
/// - Payme: merchant_id + key на https://business.payme.uz
/// - Uzum: merchant_id на https://business.uzum.uz
///
/// Все ключи хранятся ТОЛЬКО на backend (в .env), мобильный клиент их не видит.

enum PaymentMethod { click, payme, uzumpay, cash }

class PaymentResult {
  final bool success;
  final String? error;
  final String? transactionId;

  PaymentResult({required this.success, this.error, this.transactionId});
}

class PaymentService {
  PaymentService._();
  static final PaymentService instance = PaymentService._();

  /// Инициирует оплату заказа выбранным методом.
  /// Для cash — просто помечает заказ "оплата при получении" (наличные).
  Future<PaymentResult> pay({
    required String orderId,
    required PaymentMethod method,
    required double amount,
  }) async {
    if (method == PaymentMethod.cash) {
      return PaymentResult(success: true);
    }

    if (ApiConfig.useMockData) {
      // Mock — мгновенно "оплачено"
      await Future.delayed(const Duration(seconds: 1));
      return PaymentResult(success: true, transactionId: 'mock_${DateTime.now().millisecondsSinceEpoch}');
    }

    try {
      final res = await ApiClient.instance.post('/api/payments/init', {
        'orderId': orderId,
        'method': method.name,
      });

      final paymentUrl = res.data['url'] as String;
      // Открываем платёжный URL в системном браузере
      // (для Click и Payme это работает; Uzum имеет нативный SDK через deep link)
      final ok = await launchUrl(
        Uri.parse(paymentUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!ok) return PaymentResult(success: false, error: 'Could not open payment page');

      // Backend получит callback от провайдера и обновит статус.
      // Клиент дождётся обновления через socket.
      return PaymentResult(success: true);
    } catch (e) {
      return PaymentResult(success: false, error: e.toString());
    }
  }

  /// Получить список доступных методов с локализованными названиями
  static List<({PaymentMethod method, String name, String emoji, String hint, bool requiresPaid})> all() => [
    (method: PaymentMethod.click,   name: 'Click',     emoji: '💳', hint: '38% foydalanuvchi',     requiresPaid: true),
    (method: PaymentMethod.payme,   name: 'Payme',     emoji: '💳', hint: '10M+ foydalanuvchi',    requiresPaid: true),
    (method: PaymentMethod.uzumpay, name: 'Uzum Pay',  emoji: '💜', hint: '0% komissiya',          requiresPaid: true),
    (method: PaymentMethod.cash,    name: 'Naqd pul',  emoji: '💵', hint: 'Yetkazib berishda',     requiresPaid: false),
  ];
}
