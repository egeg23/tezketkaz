import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Простая система локализации без code generation.
/// Поддерживает узбекский (uz), русский (ru), английский (en).
class L10n extends ChangeNotifier {
  L10n._();
  static final L10n instance = L10n._();

  Locale _locale = const Locale('uz');
  Locale get locale => _locale;

  static const supportedLocales = [
    Locale('uz'),
    Locale('ru'),
    Locale('en'),
  ];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('locale') ?? 'uz';
    _locale = Locale(code);
    notifyListeners();
  }

  Future<void> setLocale(Locale l) async {
    _locale = l;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', l.languageCode);
    notifyListeners();
  }

  String t(String key) {
    final lang = _locale.languageCode;
    return _strings[key]?[lang] ?? _strings[key]?['uz'] ?? key;
  }

  static const _strings = <String, Map<String, String>>{
    // Auth
    'login.title': {
      'uz': 'Kirish',
      'ru': 'Вход',
      'en': 'Sign in',
    },
    'login.subtitle': {
      'uz': 'Telefon raqamingizni kiriting va SMS kod oling',
      'ru': 'Введите номер телефона и получите SMS-код',
      'en': 'Enter your phone number to receive an SMS code',
    },
    'login.cta': {
      'uz': 'SMS kod olish',
      'ru': 'Получить SMS-код',
      'en': 'Get SMS code',
    },
    'otp.title': {
      'uz': 'SMS kod',
      'ru': 'SMS-код',
      'en': 'SMS code',
    },
    'otp.sent_to': {
      'uz': 'Kod yuborildi:',
      'ru': 'Код отправлен:',
      'en': 'Code sent to:',
    },
    'otp.resend': {
      'uz': 'Kodni qayta yuborish',
      'ru': 'Отправить ещё раз',
      'en': 'Resend code',
    },
    'otp.resend_in': {
      'uz': 'Qayta yuborish:',
      'ru': 'Повторно через:',
      'en': 'Resend in:',
    },
    'otp.verify': {
      'uz': 'Tasdiqlash',
      'ru': 'Подтвердить',
      'en': 'Verify',
    },

    // Common
    'common.cancel': {
      'uz': 'Bekor qilish',
      'ru': 'Отмена',
      'en': 'Cancel',
    },
    'common.confirm': {
      'uz': 'Tasdiqlash',
      'ru': 'Подтвердить',
      'en': 'Confirm',
    },
    'common.continue': {
      'uz': 'Davom etish',
      'ru': 'Продолжить',
      'en': 'Continue',
    },
    'common.back': {
      'uz': 'Orqaga',
      'ru': 'Назад',
      'en': 'Back',
    },
    'common.save': {
      'uz': 'Saqlash',
      'ru': 'Сохранить',
      'en': 'Save',
    },
    'common.error': {
      'uz': 'Xatolik',
      'ru': 'Ошибка',
      'en': 'Error',
    },
    'common.retry': {
      'uz': 'Qayta urinish',
      'ru': 'Повторить',
      'en': 'Retry',
    },
    'common.loading': {
      'uz': 'Yuklanmoqda...',
      'ru': 'Загрузка...',
      'en': 'Loading...',
    },

    // Buyer
    'buyer.home_title': {
      'uz': 'Bosh sahifa',
      'ru': 'Главная',
      'en': 'Home',
    },
    'buyer.search_placeholder': {
      'uz': 'Mahsulot qidirish...',
      'ru': 'Поиск товаров...',
      'en': 'Search products...',
    },
    'buyer.categories': {
      'uz': 'Kategoriyalar',
      'ru': 'Категории',
      'en': 'Categories',
    },
    'buyer.popular': {
      'uz': 'Ommabop',
      'ru': 'Популярное',
      'en': 'Popular',
    },
    'buyer.cart_empty': {
      'uz': 'Savat bo\'sh',
      'ru': 'Корзина пуста',
      'en': 'Cart is empty',
    },
    'buyer.place_order': {
      'uz': 'Buyurtma berish',
      'ru': 'Оформить заказ',
      'en': 'Place order',
    },
    'buyer.delivery_address': {
      'uz': 'Yetkazib berish manzili',
      'ru': 'Адрес доставки',
      'en': 'Delivery address',
    },
    'buyer.payment_method': {
      'uz': 'To\'lov usuli',
      'ru': 'Способ оплаты',
      'en': 'Payment method',
    },
    'buyer.my_orders': {
      'uz': 'Mening buyurtmalarim',
      'ru': 'Мои заказы',
      'en': 'My orders',
    },

    // Roles
    'role.buyer': {
      'uz': 'Xaridor',
      'ru': 'Покупатель',
      'en': 'Buyer',
    },
    'role.courier': {
      'uz': 'Kuryer',
      'ru': 'Курьер',
      'en': 'Courier',
    },
    'role.shop': {
      'uz': 'Do\'kon',
      'ru': 'Магазин',
      'en': 'Shop',
    },

    // Profile
    'profile.title': {
      'uz': 'Profil',
      'ru': 'Профиль',
      'en': 'Profile',
    },
    'profile.logout': {
      'uz': 'Chiqish',
      'ru': 'Выйти',
      'en': 'Sign out',
    },
    'profile.language': {
      'uz': 'Til',
      'ru': 'Язык',
      'en': 'Language',
    },

    // Orders
    'order.status.pending': {
      'uz': 'Yangi',
      'ru': 'Новый',
      'en': 'New',
    },
    'order.status.collecting': {
      'uz': 'Yig\'ilmoqda',
      'ru': 'Собирается',
      'en': 'Collecting',
    },
    'order.status.ready': {
      'uz': 'Tayyor',
      'ru': 'Готов',
      'en': 'Ready',
    },
    'order.status.in_delivery': {
      'uz': 'Yetkazilmoqda',
      'ru': 'В пути',
      'en': 'On the way',
    },
    'order.status.delivered': {
      'uz': 'Yetkazildi',
      'ru': 'Доставлен',
      'en': 'Delivered',
    },
  };
}

/// Конвертация для использования: `t(context, 'login.title')`
String t(BuildContext context, String key) => L10n.instance.t(key);
