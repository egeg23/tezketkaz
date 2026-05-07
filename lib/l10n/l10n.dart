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

    // Verticals
    'vertical_grocery': {
      'uz': 'Mahsulotlar',
      'ru': 'Продукты',
      'en': 'Grocery',
    },
    'vertical_restaurant': {
      'uz': 'Ovqat',
      'ru': 'Еда',
      'en': 'Food',
    },
    'vertical_pharmacy': {
      'uz': 'Dorixona',
      'ru': 'Аптека',
      'en': 'Pharmacy',
    },
    'vertical_electronics': {
      'uz': 'Texnika',
      'ru': 'Техника',
      'en': 'Electronics',
    },

    // Search
    'recent_searches': {
      'uz': "So'nggi qidiruvlar",
      'ru': 'Недавние запросы',
      'en': 'Recent searches',
    },

    // Shops list
    'shops.title': {
      'uz': "Do'konlar",
      'ru': 'Магазины',
      'en': 'Shops',
    },
    'shops.search_hint': {
      'uz': "Do'kon qidirish...",
      'ru': 'Поиск магазинов...',
      'en': 'Search shops...',
    },
    'shops.empty_title': {
      'uz': "Do'konlar topilmadi",
      'ru': 'Магазины не найдены',
      'en': 'No shops found',
    },
    'shops.empty_desc': {
      'uz': 'Boshqa kategoriya yoki radiusni sinab ko\'ring',
      'ru': 'Попробуйте другую категорию или радиус',
      'en': 'Try a different vertical or radius',
    },

    // Product detail / modifiers
    'select_modifiers': {
      'uz': 'Variantni tanlang',
      'ru': 'Выберите варианты',
      'en': 'Select options',
    },
    'min_select_violation': {
      'uz': 'Majburiy guruh',
      'ru': 'Не выбраны обязательные опции',
      'en': 'Required options missing',
    },
    'product.add_to_cart': {
      'uz': "Savatga qo'shish",
      'ru': 'В корзину',
      'en': 'Add to cart',
    },
    'product.added_to_cart': {
      'uz': "Savatga qo'shildi",
      'ru': 'Добавлено в корзину',
      'en': 'Added to cart',
    },

    // Address book
    'address.book_title': {
      'uz': 'Manzillarim',
      'ru': 'Мои адреса',
      'en': 'My addresses',
    },
    'address.add': {
      'uz': "Manzil qo'shish",
      'ru': 'Добавить адрес',
      'en': 'Add address',
    },
    'address.edit': {
      'uz': 'Manzilni tahrirlash',
      'ru': 'Редактировать адрес',
      'en': 'Edit address',
    },
    'address.delete': {
      'uz': "O'chirish",
      'ru': 'Удалить',
      'en': 'Delete',
    },
    'address.confirm_delete': {
      'uz': "Manzilni o'chirilsinmi?",
      'ru': 'Удалить адрес?',
      'en': 'Delete this address?',
    },
    'address.empty_title': {
      'uz': "Manzillaringiz yo'q",
      'ru': 'У вас нет сохранённых адресов',
      'en': 'No saved addresses',
    },
    'address.empty_desc': {
      'uz': "Tezroq buyurtma berish uchun manzil qo'shing",
      'ru': 'Добавьте адрес, чтобы быстрее оформлять заказы',
      'en': 'Add an address to check out faster',
    },
    'address.label_hint': {
      'uz': 'Nomi (Uy / Ish)',
      'ru': 'Метка (Дом / Работа)',
      'en': 'Label (Home / Work)',
    },
    'address.default_badge': {
      'uz': 'Asosiy',
      'ru': 'По умолчанию',
      'en': 'Default',
    },
    'address.default_set': {
      'uz': 'Asosiy manzil yangilandi',
      'ru': 'Адрес по умолчанию обновлён',
      'en': 'Default address updated',
    },
    'make_default_address': {
      'uz': 'Asosiy qilish',
      'ru': 'Сделать основным',
      'en': 'Make default',
    },
    'address_entrance': {
      'uz': "Pod'ezd",
      'ru': 'Подъезд',
      'en': 'Entrance',
    },
    'address_floor': {
      'uz': 'Qavat',
      'ru': 'Этаж',
      'en': 'Floor',
    },
    'address_apartment': {
      'uz': 'Xonadon',
      'ru': 'Квартира',
      'en': 'Apartment',
    },
    'address_intercom': {
      'uz': 'Domofon',
      'ru': 'Домофон',
      'en': 'Intercom',
    },
    'address_instructions': {
      'uz': "Kuryer uchun izoh",
      'ru': 'Комментарий курьеру',
      'en': 'Courier notes',
    },

    // Map
    'map_pick_location': {
      'uz': 'Joylashuvni tanlang',
      'ru': 'Выберите местоположение',
      'en': 'Pick a location',
    },

    // Phase 2 — courier shift / dispatch
    'courier.go_online': {
      'uz': 'Smenani boshlash',
      'ru': 'Я на смене',
      'en': 'Go online',
    },
    'courier.go_offline': {
      'uz': 'Smenani tugatish',
      'ru': 'Off duty',
      'en': 'Go offline',
    },
    'courier.shift_duration': {
      'uz': 'Smena vaqti',
      'ru': 'Длительность смены',
      'en': 'Shift duration',
    },
    'courier.shift_earnings': {
      'uz': 'Smena daromadi',
      'ru': 'Заработок за смену',
      'en': 'Shift earnings',
    },
    'courier.pending_offer': {
      'uz': 'Yangi taklif',
      'ru': 'Новое предложение',
      'en': 'New offer',
    },
    'courier.accept': {
      'uz': 'Qabul qilish',
      'ru': 'Принять',
      'en': 'Accept',
    },
    'courier.decline': {
      'uz': 'Rad etish',
      'ru': 'Отклонить',
      'en': 'Decline',
    },
    'courier.no_offers': {
      'uz': 'Buyurtmalar kutilmoqda',
      'ru': 'Ожидаем заказы',
      'en': 'Waiting for orders',
    },

    // Phase 2 — cart pricing breakdown
    'cart.subtotal': {
      'uz': 'Mahsulotlar',
      'ru': 'Товары',
      'en': 'Subtotal',
    },
    'cart.delivery': {
      'uz': 'Yetkazib berish',
      'ru': 'Доставка',
      'en': 'Delivery',
    },
    'cart.total': {
      'uz': 'Jami',
      'ru': 'Итого',
      'en': 'Total',
    },
    'cart.eta': {
      'uz': 'Yetkazib berish: ~{minutes} daqiqa',
      'ru': 'Доставка через ~{minutes} мин',
      'en': 'Delivery in ~{minutes} min',
    },
    'cart.distance': {
      'uz': '{km} km',
      'ru': '{km} км',
      'en': '{km} km',
    },
    'cart.surge_badge': {
      'uz': 'Yuklama',
      'ru': 'Повышенный спрос',
      'en': 'Surge',
    },
    'cart.out_of_zone': {
      'uz': "Adresga yetkazib bo'lmaydi",
      'ru': 'Доставка не доступна',
      'en': 'Address out of delivery zone',
    },
    'cart.min_order_warn': {
      'uz': "Yana {amount} qo'shing",
      'ru': 'Добавьте ещё {amount} до минимума',
      'en': 'Add {amount} more to qualify',
    },

    // Phase 2 — dispatch lifecycle messages
    'dispatch.timeout': {
      'uz': "Taklif muddati tugadi",
      'ru': 'Время предложения истекло',
      'en': 'Offer timed out',
    },
    'dispatch.accepted': {
      'uz': 'Buyurtma sizga biriktirildi',
      'ru': 'Заказ закреплён за вами',
      'en': 'Order assigned to you',
    },
    'dispatch.assigned_to_other': {
      'uz': 'Buyurtmani boshqa kuryer oldi',
      'ru': 'Заказ ушёл другому курьеру',
      'en': 'Assigned to another courier',
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
