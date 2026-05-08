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
    Locale('kk'),
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
    final entry = _strings[key];
    if (entry == null) return key;
    // Kazakh shares Cyrillic with Russian, so Russian is a sensible fallback
    // when a `kk` translation is missing. Other locales fall back to uz then en.
    if (lang == 'kk') {
      return entry['kk'] ?? entry['ru'] ?? entry['uz'] ?? entry['en'] ?? key;
    }
    return entry[lang] ?? entry['uz'] ?? entry['en'] ?? key;
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

    // ── Phase 3 — Promo / coupons ─────────────────────────────────────────
    'promo.title': {
      'uz': 'Promo kodlar',
      'ru': 'Промокоды',
      'en': 'Promo codes',
    },
    'promo.empty': {
      'uz': "Sizga mos promo kod yo'q",
      'ru': 'Нет доступных промокодов',
      'en': 'No eligible promo codes',
    },
    'promo.enter_code': {
      'uz': 'Promo kod',
      'ru': 'Введите код',
      'en': 'Enter code',
    },
    'promo.apply': {
      'uz': "Qo'llash",
      'ru': 'Применить',
      'en': 'Apply',
    },
    'promo.until': {
      'uz': 'Amalda:',
      'ru': 'До:',
      'en': 'Until:',
    },
    'promo.copied': {
      'uz': 'Nusxalandi',
      'ru': 'Скопировано',
      'en': 'Copied',
    },

    // ── Phase 3 — Cart promo / loyalty / scheduling ──────────────────────
    'cart.promo_code': {
      'uz': 'Promo kod',
      'ru': 'Промокод',
      'en': 'Promo code',
    },
    'cart.promo_hint': {
      'uz': 'Kodni kiriting',
      'ru': 'Введите код',
      'en': 'Enter code',
    },
    'cart.promo_applied': {
      'uz': "Qo'llanildi",
      'ru': 'Применён',
      'en': 'Applied',
    },
    'cart.loyalty_points': {
      'uz': 'Bonus ballar',
      'ru': 'Бонусные баллы',
      'en': 'Loyalty points',
    },
    'cart.points_available': {
      'uz': 'Mavjud',
      'ru': 'Доступно',
      'en': 'Available',
    },
    'cart.points_too_small': {
      'uz': 'Ballarni ishlatish uchun summa yetarli emas',
      'ru': 'Сумма слишком маленькая для бонусов',
      'en': 'Subtotal is too small to spend points',
    },
    'cart.plan_delivery': {
      'uz': 'Yetkazib berish vaqti',
      'ru': 'Время доставки',
      'en': 'Delivery time',
    },
    'cart.plan_asap': {
      'uz': 'Hozir',
      'ru': 'Сейчас',
      'en': 'ASAP',
    },
    'cart.plan_schedule': {
      'uz': 'Rejalashtirish',
      'ru': 'Запланировать',
      'en': 'Schedule',
    },
    'cart.scheduled_for': {
      'uz': 'Tanlangan',
      'ru': 'Выбрано',
      'en': 'Scheduled for',
    },

    // ── Phase 3 — Loyalty screen ─────────────────────────────────────────
    'loyalty.title': {
      'uz': 'Bonuslar',
      'ru': 'Бонусы',
      'en': 'Rewards',
    },
    'loyalty.tier': {
      'uz': 'Daraja',
      'ru': 'Уровень',
      'en': 'Tier',
    },
    'loyalty.points': {
      'uz': 'Ballar',
      'ru': 'Баллы',
      'en': 'Points',
    },
    'loyalty.cashback': {
      'uz': 'Cashback',
      'ru': 'Кешбэк',
      'en': 'Cashback',
    },
    'loyalty.to_next': {
      'uz': 'Keyingi darajagacha:',
      'ru': 'До уровня:',
      'en': 'To next tier:',
    },
    'loyalty.max_tier': {
      'uz': 'Eng yuqori daraja!',
      'ru': 'Максимальный уровень!',
      'en': 'Top tier reached!',
    },
    'loyalty.your_referral': {
      'uz': 'Sizning referal kodingiz',
      'ru': 'Ваш реферальный код',
      'en': 'Your referral code',
    },
    'loyalty.have_friend_code': {
      'uz': "Do'stning kodi bormi?",
      'ru': 'Есть код друга?',
      'en': 'Have a friend\'s code?',
    },
    'loyalty.enter_friend_code': {
      'uz': 'Kodni kiriting',
      'ru': 'Введите код',
      'en': 'Enter code',
    },
    'loyalty.apply': {
      'uz': "Qo'llash",
      'ru': 'Применить',
      'en': 'Apply',
    },
    'loyalty.referral_applied': {
      'uz': "Referal kodi qo'llanildi",
      'ru': 'Реферальный код применён',
      'en': 'Referral code applied',
    },
    'loyalty.copied': {
      'uz': 'Nusxalandi',
      'ru': 'Скопировано',
      'en': 'Copied',
    },
    'loyalty.recent_activity': {
      'uz': "So'nggi harakatlar",
      'ru': 'Недавняя активность',
      'en': 'Recent activity',
    },
    'loyalty.no_activity': {
      'uz': "Hali harakat yo'q",
      'ru': 'Активности пока нет',
      'en': 'No activity yet',
    },

    // ── Phase 3 — Reviews ────────────────────────────────────────────────
    'reviews.title': {
      'uz': 'Sharhlar',
      'ru': 'Отзывы',
      'en': 'Reviews',
    },
    'reviews.tab_all': {
      'uz': 'Hammasi',
      'ru': 'Все',
      'en': 'All',
    },
    'reviews.empty': {
      'uz': "Sharhlar hali yo'q",
      'ru': 'Отзывов пока нет',
      'en': 'No reviews yet',
    },
    'reviews.count_suffix': {
      'uz': 'sharhlar',
      'ru': 'отзывов',
      'en': 'reviews',
    },

    // ── Phase 3 — Chat ───────────────────────────────────────────────────
    'chat.title': {
      'uz': 'Chat',
      'ru': 'Чат',
      'en': 'Chat',
    },
    'chat.online': {
      'uz': 'tarmoqda',
      'ru': 'в сети',
      'en': 'online',
    },
    'chat.offline': {
      'uz': 'tarmoqda emas',
      'ru': 'не в сети',
      'en': 'offline',
    },
    'chat.input_hint': {
      'uz': "Xabar yozing…",
      'ru': 'Введите сообщение…',
      'en': 'Type a message…',
    },
    'chat.send_failed': {
      'uz': 'Xabar yuborilmadi',
      'ru': 'Сообщение не отправлено',
      'en': 'Message failed',
    },
    'chat.image_unavailable': {
      'uz': 'Rasm yuborish hozircha mavjud emas',
      'ru': 'Загрузка изображений пока недоступна',
      'en': 'Image upload not yet available',
    },

    // ── Phase 3 — Time slots ─────────────────────────────────────────────
    'slots.today': {
      'uz': 'Bugun',
      'ru': 'Сегодня',
      'en': 'Today',
    },
    'slots.tomorrow': {
      'uz': 'Ertaga',
      'ru': 'Завтра',
      'en': 'Tomorrow',
    },

    // ── Phase 6 — Saved payment methods ──────────────────────────────────
    'payment.add_card': {
      'uz': "Karta qo'shish",
      'ru': 'Добавить карту',
      'en': 'Add card',
    },
    'payment.cards_list': {
      'uz': 'Kartalarim',
      'ru': 'Мои карты',
      'en': 'My cards',
    },
    'payment.set_default': {
      'uz': 'Asosiy qilish',
      'ru': 'Сделать основной',
      'en': 'Set as default',
    },
    'payment.delete': {
      'uz': "Kartani o'chirish",
      'ru': 'Удалить карту',
      'en': 'Delete card',
    },
    'payment.no_cards': {
      'uz': "Saqlangan kartalar yo'q",
      'ru': 'Нет сохранённых карт',
      'en': 'No saved cards',
    },
    'payment.use_new_card': {
      'uz': 'Yangi karta bilan to\'lash',
      'ru': 'Оплатить новой картой',
      'en': 'Pay with new card',
    },

    // ── Phase 6 — Cart address tile ──────────────────────────────────────
    'cart.address_tile_title': {
      'uz': 'Yetkazib berish manzili',
      'ru': 'Адрес доставки',
      'en': 'Delivery address',
    },
    'cart.address_choose': {
      'uz': 'Manzilni tanlang',
      'ru': 'Выберите адрес',
      'en': 'Choose address',
    },
    'cart.no_address_warning': {
      'uz': "Avval manzilni tanlang",
      'ru': 'Сначала выберите адрес',
      'en': 'Pick an address first',
    },

    // ── Phase 6 — Tipping ────────────────────────────────────────────────
    'tip.cta': {
      'uz': "Kuryerga rahmat aytish",
      'ru': 'Поблагодарить курьера',
      'en': 'Tip the courier',
    },
    'tip.5_percent': {
      'uz': '5%',
      'ru': '5%',
      'en': '5%',
    },
    'tip.10_percent': {
      'uz': '10%',
      'ru': '10%',
      'en': '10%',
    },
    'tip.15_percent': {
      'uz': '15%',
      'ru': '15%',
      'en': '15%',
    },
    'tip.custom': {
      'uz': 'Boshqa summa',
      'ru': 'Другая сумма',
      'en': 'Custom',
    },
    'tip.success': {
      'uz': 'Rahmat yuborildi 🙏',
      'ru': 'Чаевые отправлены 🙏',
      'en': 'Tip sent 🙏',
    },

    // ── Phase 6 — Geolocation ────────────────────────────────────────────
    'location.permission_denied': {
      'uz': "Geolokatsiya yo'q",
      'ru': 'Геолокация недоступна',
      'en': 'Location unavailable',
    },
    'location.current': {
      'uz': 'Joriy joylashuv',
      'ru': 'Моё местоположение',
      'en': 'Use current location',
    },

    // ── Phase 7.2 — Subscription ─────────────────────────────────────────
    'subscription.title': {
      'uz': 'Obuna',
      'ru': 'Подписка',
      'en': 'Subscription',
      'kk': 'Жазылым',
    },
    'subscription.tile_title': {
      'uz': 'Plus / Pro obuna',
      'ru': 'Plus / Pro подписка',
      'en': 'Plus / Pro membership',
      'kk': 'Plus / Pro жазылым',
    },
    'subscription.tile_subtitle': {
      'uz': 'Bepul yetkazib berish va cashback',
      'ru': 'Бесплатная доставка и кешбэк',
      'en': 'Free delivery and cashback',
      'kk': 'Тегін жеткізу және кешбэк',
    },
    'subscription.become_plus': {
      'uz': 'Plus a\'zo bo\'ling',
      'ru': 'Станьте Plus-участником',
      'en': 'Become a Plus member',
      'kk': 'Plus мүшесі болыңыз',
    },
    'subscription.become_subtitle': {
      'uz': 'Tejamkor obuna · har oy bekor qilish mumkin',
      'ru': 'Выгодная подписка · отмена в любое время',
      'en': 'Save more every order · cancel anytime',
      'kk': 'Үнемді жазылым · кез келген уақытта тоқтату',
    },
    'subscription.tier_plus': {
      'uz': 'Plus',
      'ru': 'Plus',
      'en': 'Plus',
      'kk': 'Plus',
    },
    'subscription.tier_pro': {
      'uz': 'Pro',
      'ru': 'Pro',
      'en': 'Pro',
      'kk': 'Pro',
    },
    'subscription.feat_free_delivery': {
      'uz': 'Bepul yetkazib berish',
      'ru': 'Бесплатная доставка',
      'en': 'Free delivery',
      'kk': 'Тегін жеткізу',
    },
    'subscription.feat_free_delivery_50': {
      'uz': 'Yetkazib berish 50% chegirma',
      'ru': '50% скидка на доставку',
      'en': '50% off delivery',
      'kk': 'Жеткізуге 50% жеңілдік',
    },
    'subscription.feat_cashback_2x': {
      'uz': '2× cashback',
      'ru': '2× кешбэк',
      'en': '2× cashback',
      'kk': '2× кешбэк',
    },
    'subscription.feat_cashback_5x': {
      'uz': '5× cashback',
      'ru': '5× кешбэк',
      'en': '5× cashback',
      'kk': '5× кешбэк',
    },
    'subscription.feat_priority_support': {
      'uz': 'Tezkor qo\'llab-quvvatlash',
      'ru': 'Приоритетная поддержка',
      'en': 'Priority support',
      'kk': 'Бірінші кезектегі қолдау',
    },
    'subscription.feat_exclusive_promo': {
      'uz': 'Maxsus aksiyalar',
      'ru': 'Эксклюзивные акции',
      'en': 'Exclusive promos',
      'kk': 'Эксклюзивті акциялар',
    },
    'subscription.period_monthly': {
      'uz': 'Oylik',
      'ru': 'Месяц',
      'en': 'Monthly',
      'kk': 'Айлық',
    },
    'subscription.period_yearly': {
      'uz': 'Yillik',
      'ru': 'Год',
      'en': 'Yearly',
      'kk': 'Жылдық',
    },
    'subscription.save_17': {
      'uz': '17% tejash',
      'ru': '−17%',
      'en': 'Save 17%',
      'kk': '17% үнемдеу',
    },
    'subscription.subscribe_cta': {
      'uz': 'Obuna bo\'lish',
      'ru': 'Оформить подписку',
      'en': 'Subscribe',
      'kk': 'Жазылу',
    },
    'subscription.cancel_cta': {
      'uz': 'Obunani bekor qilish',
      'ru': 'Отменить подписку',
      'en': 'Cancel subscription',
      'kk': 'Жазылымнан бас тарту',
    },
    'subscription.cancel_title': {
      'uz': 'Obunani bekor qilamizmi?',
      'ru': 'Отменить подписку?',
      'en': 'Cancel subscription?',
      'kk': 'Жазылымды тоқтату керек пе?',
    },
    'subscription.cancel_confirm': {
      'uz': 'Joriy davr oxirigacha foydalanishingiz mumkin.',
      'ru': 'Подписка будет действовать до конца оплаченного периода.',
      'en': 'You can keep using it until the end of the current period.',
      'kk': 'Ағымдағы кезеңнің соңына дейін қолдана аласыз.',
    },
    'subscription.reactivate_cta': {
      'uz': 'Yana faollashtirish',
      'ru': 'Возобновить',
      'en': 'Reactivate',
      'kk': 'Қайта іске қосу',
    },
    'subscription.renews_on': {
      'uz': 'Yangilanadi:',
      'ru': 'Продление:',
      'en': 'Renews on',
      'kk': 'Жаңартылады:',
    },
    'subscription.expires_on': {
      'uz': 'Tugaydi:',
      'ru': 'Истекает:',
      'en': 'Expires on',
      'kk': 'Аяқталады:',
    },
    'subscription.activated': {
      'uz': 'Obuna faollashtirildi 🎉',
      'ru': 'Подписка активирована 🎉',
      'en': 'Subscription activated 🎉',
      'kk': 'Жазылым іске қосылды 🎉',
    },

    // ── Phase 7.3 — Favourites ───────────────────────────────────────────
    'favorites.title': {
      'uz': 'Sevimli mahsulotlar',
      'ru': 'Избранное',
      'en': 'Favorites',
      'kk': 'Таңдаулылар',
    },
    'favorites.tab_products': {
      'uz': 'Mahsulotlar',
      'ru': 'Товары',
      'en': 'Products',
      'kk': 'Тауарлар',
    },
    'favorites.tab_shops': {
      'uz': "Do'konlar",
      'ru': 'Магазины',
      'en': 'Shops',
      'kk': 'Дүкендер',
    },
    'favorites.empty_products_title': {
      'uz': "Sevimli mahsulotlar yo'q",
      'ru': 'Нет избранных товаров',
      'en': 'No favourite products',
      'kk': 'Таңдаулы тауарлар жоқ',
    },
    'favorites.empty_products_desc': {
      'uz': "Mahsulotni saqlash uchun yurakcha tugmasini bosing",
      'ru': 'Нажмите сердечко, чтобы добавить товар',
      'en': 'Tap the heart on a product to save it here',
      'kk': 'Тауарды қосу үшін жүрекшені басыңыз',
    },
    'favorites.empty_shops_title': {
      'uz': "Sevimli do'konlar yo'q",
      'ru': 'Нет избранных магазинов',
      'en': 'No favourite shops',
      'kk': 'Таңдаулы дүкендер жоқ',
    },
    'favorites.empty_shops_desc': {
      'uz': "Do'konlar ro'yxatida yurakcha tugmasini bosing",
      'ru': 'Нажмите сердечко рядом с магазином',
      'en': 'Tap the heart next to a shop to save it',
      'kk': 'Дүкенге жанындағы жүрекшені басыңыз',
    },
    'profile.favorites': {
      'uz': 'Sevimli mahsulotlar',
      'ru': 'Избранное',
      'en': 'Favorites',
      'kk': 'Таңдаулылар',
    },

    // ── Phase 7.3 — Referral share ───────────────────────────────────────
    'loyalty.share_cta': {
      'uz': "Do'stlarga yuborish",
      'ru': 'Поделиться с друзьями',
      'en': 'Share with friends',
      'kk': 'Достарға жіберу',
    },
    'loyalty.share_text': {
      'uz':
          "TezKetKaz'ga qo'shiling! Kodim {code} bilan birinchi buyurtmaga 5000 UZS chegirma. Yuklab oling: https://tezketkaz.uz/r/{code}",
      'ru':
          'Присоединяйтесь к TezKetKaz! Используйте код {code} и получите 5000 UZS на первый заказ. Скачать: https://tezketkaz.uz/r/{code}',
      'en':
          'Join TezKetKaz! Use my code {code} for 5000 UZS off your first order. Download: https://tezketkaz.uz/r/{code}',
      'kk':
          'TezKetKaz-ға қосылыңыз! Менің {code} кодыммен бірінші тапсырысқа 5000 UZS жеңілдік. Жүктеп алыңыз: https://tezketkaz.uz/r/{code}',
    },

    // ── Phase 7.1 — Country / locale picker ──────────────────────────────
    'settings.country_locale': {
      'uz': 'Mamlakat va til',
      'ru': 'Страна и язык',
      'en': 'Country & language',
      'kk': 'Ел және тіл',
    },
    'settings.country': {
      'uz': 'Mamlakat',
      'ru': 'Страна',
      'en': 'Country',
      'kk': 'Ел',
    },
    'settings.locale': {
      'uz': 'Til',
      'ru': 'Язык',
      'en': 'Language',
      'kk': 'Тіл',
    },
  };
}

/// Конвертация для использования: `t(context, 'login.title')`
String t(BuildContext context, String key) => L10n.instance.t(key);
