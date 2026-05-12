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
      'kk': 'Кіру',
    },
    'login.subtitle': {
      'uz': 'Telefon raqamingizni kiriting va SMS kod oling',
      'ru': 'Введите номер телефона и получите SMS-код',
      'en': 'Enter your phone number to receive an SMS code',
      'kk': 'Телефон нөміріңізді енгізіп, SMS код алыңыз',
    },
    'login.cta': {
      'uz': 'SMS kod olish',
      'ru': 'Получить SMS-код',
      'en': 'Get SMS code',
      'kk': 'SMS код алу',
    },
    'otp.title': {
      'uz': 'SMS kod',
      'ru': 'SMS-код',
      'en': 'SMS code',
      'kk': 'SMS код',
    },
    'otp.sent_to': {
      'uz': 'Kod yuborildi:',
      'ru': 'Код отправлен:',
      'en': 'Code sent to:',
      'kk': 'Код жіберілді:',
    },
    'otp.resend': {
      'uz': 'Kodni qayta yuborish',
      'ru': 'Отправить ещё раз',
      'en': 'Resend code',
      'kk': 'Кодты қайта жіберу',
    },
    'otp.resend_in': {
      'uz': 'Qayta yuborish:',
      'ru': 'Повторно через:',
      'en': 'Resend in:',
      'kk': 'Қайта жіберу:',
    },
    'otp.verify': {
      'uz': 'Tasdiqlash',
      'ru': 'Подтвердить',
      'en': 'Verify',
      'kk': 'Растау',
    },

    // ── Phase 13.1.5 — Legal acceptance (T&C / Privacy Policy) ──────────────
    'auth.legal_consent_intro': {
      'uz': 'Men quyidagilarga roziman:',
      'ru': 'Я согласен(а) с',
      'en': 'I agree to the',
      'kk': 'Мен төмендегімен келісемін:',
    },
    'auth.legal_consent_and': {
      'uz': 'va',
      'ru': 'и',
      'en': 'and the',
      'kk': 'және',
    },
    'auth.terms_link': {
      'uz': 'Foydalanish shartlari',
      'ru': 'Условиями использования',
      'en': 'Terms of Service',
      'kk': 'Қолдану шарттары',
    },
    'auth.privacy_link': {
      'uz': 'Maxfiylik siyosati',
      'ru': 'Политикой конфиденциальности',
      'en': 'Privacy Policy',
      'kk': 'Құпиялылық саясаты',
    },
    'auth.legal_submit_blocked': {
      'uz': "Davom etish uchun shartlarni qabul qiling",
      'ru': 'Чтобы продолжить, примите условия',
      'en': 'Accept the terms to continue',
      'kk': 'Жалғастыру үшін шарттарды қабылдаңыз',
    },
    'auth.legal_updated_title': {
      'uz': 'Shartlar yangilandi',
      'ru': 'Условия обновлены',
      'en': 'Terms updated',
      'kk': 'Шарттар жаңартылды',
    },
    'auth.legal_updated_body': {
      'uz': "Iltimos, yangi Foydalanish shartlari va Maxfiylik siyosatini qabul qiling.",
      'ru': 'Пожалуйста, примите обновлённые Условия использования и Политику конфиденциальности.',
      'en': 'Please accept the updated Terms of Service and Privacy Policy.',
      'kk': 'Жаңартылған Қолдану шарттары мен Құпиялылық саясатын қабылдаңыз.',
    },
    'auth.legal_review': {
      'uz': "Ko'rib chiqish",
      'ru': 'Прочитать',
      'en': 'Review',
      'kk': 'Қарап шығу',
    },
    'auth.legal_accept_cta': {
      'uz': 'Qabul qilish',
      'ru': 'Принять',
      'en': 'Accept',
      'kk': 'Қабылдау',
    },
    'auth.social_apple_error': {
      'uz': 'Apple bilan kirishda xatolik',
      'ru': 'Ошибка входа через Apple',
      'en': 'Apple sign-in failed',
      'kk': 'Apple арқылы кіру қатесі',
    },
    'auth.social_google_error': {
      'uz': 'Google bilan kirishda xatolik',
      'ru': 'Ошибка входа через Google',
      'en': 'Google sign-in failed',
      'kk': 'Google арқылы кіру қатесі',
    },
    'login.terms_blurb': {
      'uz': 'Kirish orqali siz\nFoydalanish shartlarimizga rozilik bildirasiz',
      'ru': 'Войдя, вы соглашаетесь\nс нашими Условиями использования',
      'en': 'By signing in you agree\nto our Terms of Service',
      'kk': 'Кіру арқылы сіз\nҚолдану шарттарымен келісесіз',
    },
    'legal.title': {
      'uz': "Huquqiy hujjatlar",
      'ru': 'Юридические документы',
      'en': 'Legal',
      'kk': 'Заңды құжаттар',
    },
    'legal.terms_title': {
      'uz': 'Shartlar',
      'ru': 'Условия',
      'en': 'Terms',
      'kk': 'Шарттар',
    },
    'legal.privacy_title': {
      'uz': 'Maxfiylik',
      'ru': 'Конфиденциальность',
      'en': 'Privacy',
      'kk': 'Құпиялылық',
    },
    'legal.terms_body_stub': {
      'uz': "Foydalanish shartlarining toʻliq matni tez orada chiqadi.",
      'ru': 'Полный текст Условий использования будет доступен в ближайшее время.',
      'en': 'Full Terms of Service text will be available soon.',
      'kk': 'Қолдану шарттарының толық мәтіні жақын арада жарияланады.',
    },
    'legal.privacy_body_stub': {
      'uz': "Maxfiylik siyosatining toʻliq matni tez orada chiqadi.",
      'ru': 'Полный текст Политики конфиденциальности будет доступен в ближайшее время.',
      'en': 'Full Privacy Policy text will be available soon.',
      'kk': 'Құпиялылық саясатының толық мәтіні жақын арада жарияланады.',
    },

    // Common
    'common.cancel': {
      'uz': 'Bekor qilish',
      'ru': 'Отмена',
      'en': 'Cancel',
      'kk': 'Бас тарту',
    },
    'common.confirm': {
      'uz': 'Tasdiqlash',
      'ru': 'Подтвердить',
      'en': 'Confirm',
      'kk': 'Растау',
    },
    'common.continue': {
      'uz': 'Davom etish',
      'ru': 'Продолжить',
      'en': 'Continue',
      'kk': 'Жалғастыру',
    },
    'common.back': {
      'uz': 'Orqaga',
      'ru': 'Назад',
      'en': 'Back',
      'kk': 'Артқа',
    },
    'common.save': {
      'uz': 'Saqlash',
      'ru': 'Сохранить',
      'en': 'Save',
      'kk': 'Сақтау',
    },
    'common.error': {
      'uz': 'Xatolik',
      'ru': 'Ошибка',
      'en': 'Error',
      'kk': 'Қате',
    },
    'common.retry': {
      'uz': 'Qayta urinish',
      'ru': 'Повторить',
      'en': 'Retry',
      'kk': 'Қайталау',
    },
    'common.loading': {
      'uz': 'Yuklanmoqda...',
      'ru': 'Загрузка...',
      'en': 'Loading...',
      'kk': 'Жүктелуде...',
    },
    'common.see_all': {
      'uz': 'Barchasi',
      'ru': 'Все',
      'en': 'See all',
      'kk': 'Барлығы',
    },

    // Buyer
    'buyer.home_title': {
      'uz': 'Bosh sahifa',
      'ru': 'Главная',
      'en': 'Home',
      'kk': 'Басты бет',
    },
    'buyer.search_placeholder': {
      'uz': 'Mahsulot qidirish...',
      'ru': 'Поиск товаров...',
      'en': 'Search products...',
      'kk': 'Тауар іздеу...',
    },
    'buyer.categories': {
      'uz': 'Kategoriyalar',
      'ru': 'Категории',
      'en': 'Categories',
      'kk': 'Санаттар',
    },
    'buyer.popular': {
      'uz': 'Ommabop',
      'ru': 'Популярное',
      'en': 'Popular',
      'kk': 'Танымал',
    },
    'buyer.cart_empty': {
      'uz': 'Savat bo\'sh',
      'ru': 'Корзина пуста',
      'en': 'Cart is empty',
      'kk': 'Себет бос',
    },
    'buyer.place_order': {
      'uz': 'Buyurtma berish',
      'ru': 'Оформить заказ',
      'en': 'Place order',
      'kk': 'Тапсырыс рәсімдеу',
    },
    'buyer.delivery_address': {
      'uz': 'Yetkazib berish manzili',
      'ru': 'Адрес доставки',
      'en': 'Delivery address',
      'kk': 'Жеткізу мекенжайы',
    },
    'buyer.payment_method': {
      'uz': 'To\'lov usuli',
      'ru': 'Способ оплаты',
      'en': 'Payment method',
      'kk': 'Төлем тәсілі',
    },
    'buyer.my_orders': {
      'uz': 'Mening buyurtmalarim',
      'ru': 'Мои заказы',
      'en': 'My orders',
      'kk': 'Менің тапсырыстарым',
    },

    // Roles
    'role.buyer': {
      'uz': 'Xaridor',
      'ru': 'Покупатель',
      'en': 'Buyer',
      'kk': 'Сатып алушы',
    },
    'role.courier': {
      'uz': 'Kuryer',
      'ru': 'Курьер',
      'en': 'Courier',
      'kk': 'Курьер',
    },
    'role.shop': {
      'uz': 'Do\'kon',
      'ru': 'Магазин',
      'en': 'Shop',
      'kk': 'Дүкен',
    },

    // Profile
    'profile.title': {
      'uz': 'Profil',
      'ru': 'Профиль',
      'en': 'Profile',
      'kk': 'Профиль',
    },
    'profile.logout': {
      'uz': 'Chiqish',
      'ru': 'Выйти',
      'en': 'Sign out',
      'kk': 'Шығу',
    },
    'profile.language': {
      'uz': 'Til',
      'ru': 'Язык',
      'en': 'Language',
      'kk': 'Тіл',
    },

    // Verticals
    'vertical_grocery': {
      'uz': 'Mahsulotlar',
      'ru': 'Продукты',
      'en': 'Grocery',
      'kk': 'Азық-түлік',
    },
    'vertical_restaurant': {
      'uz': 'Ovqat',
      'ru': 'Еда',
      'en': 'Food',
      'kk': 'Тағам',
    },
    'vertical_pharmacy': {
      'uz': 'Dorixona',
      'ru': 'Аптека',
      'en': 'Pharmacy',
      'kk': 'Дәріхана',
    },
    'vertical_electronics': {
      'uz': 'Texnika',
      'ru': 'Техника',
      'en': 'Electronics',
      'kk': 'Техника',
    },

    // Search
    'recent_searches': {
      'uz': "So'nggi qidiruvlar",
      'ru': 'Недавние запросы',
      'en': 'Recent searches',
      'kk': 'Соңғы сұраныстар',
    },

    // Shops list
    'shops.title': {
      'uz': "Do'konlar",
      'ru': 'Магазины',
      'en': 'Shops',
      'kk': 'Дүкендер',
    },
    'shops.search_hint': {
      'uz': "Do'kon qidirish...",
      'ru': 'Поиск магазинов...',
      'en': 'Search shops...',
      'kk': 'Дүкен іздеу...',
    },
    'shops.empty_title': {
      'uz': "Do'konlar topilmadi",
      'ru': 'Магазины не найдены',
      'en': 'No shops found',
      'kk': 'Дүкендер табылмады',
    },
    'shops.empty_desc': {
      'uz': 'Boshqa kategoriya yoki radiusni sinab ko\'ring',
      'ru': 'Попробуйте другую категорию или радиус',
      'en': 'Try a different vertical or radius',
      'kk': 'Басқа санатты немесе радиусты қолданып көріңіз',
    },

    // Product detail / modifiers
    'select_modifiers': {
      'uz': 'Variantni tanlang',
      'ru': 'Выберите варианты',
      'en': 'Select options',
      'kk': 'Нұсқаны таңдаңыз',
    },
    'min_select_violation': {
      'uz': 'Majburiy guruh',
      'ru': 'Не выбраны обязательные опции',
      'en': 'Required options missing',
      'kk': 'Міндетті опциялар таңдалмаған',
    },
    'product.add_to_cart': {
      'uz': "Savatga qo'shish",
      'ru': 'В корзину',
      'en': 'Add to cart',
      'kk': 'Себетке қосу',
    },
    'product.added_to_cart': {
      'uz': "Savatga qo'shildi",
      'ru': 'Добавлено в корзину',
      'en': 'Added to cart',
      'kk': 'Себетке қосылды',
    },

    // Address book
    'address.book_title': {
      'uz': 'Manzillarim',
      'ru': 'Мои адреса',
      'en': 'My addresses',
      'kk': 'Менің мекенжайларым',
    },
    'address.add': {
      'uz': "Manzil qo'shish",
      'ru': 'Добавить адрес',
      'en': 'Add address',
      'kk': 'Мекенжай қосу',
    },
    'address.edit': {
      'uz': 'Manzilni tahrirlash',
      'ru': 'Редактировать адрес',
      'en': 'Edit address',
      'kk': 'Мекенжайды өңдеу',
    },
    'address.delete': {
      'uz': "O'chirish",
      'ru': 'Удалить',
      'en': 'Delete',
      'kk': 'Жою',
    },
    'address.confirm_delete': {
      'uz': "Manzilni o'chirilsinmi?",
      'ru': 'Удалить адрес?',
      'en': 'Delete this address?',
      'kk': 'Мекенжайды жою керек пе?',
    },
    'address.empty_title': {
      'uz': "Manzillaringiz yo'q",
      'ru': 'У вас нет сохранённых адресов',
      'en': 'No saved addresses',
      'kk': 'Сақталған мекенжайлар жоқ',
    },
    'address.empty_desc': {
      'uz': "Tezroq buyurtma berish uchun manzil qo'shing",
      'ru': 'Добавьте адрес, чтобы быстрее оформлять заказы',
      'en': 'Add an address to check out faster',
      'kk': 'Тапсырысты тезірек рәсімдеу үшін мекенжай қосыңыз',
    },
    'address.label_hint': {
      'uz': 'Nomi (Uy / Ish)',
      'ru': 'Метка (Дом / Работа)',
      'en': 'Label (Home / Work)',
      'kk': 'Белгі (Үй / Жұмыс)',
    },
    'address.default_badge': {
      'uz': 'Asosiy',
      'ru': 'По умолчанию',
      'en': 'Default',
      'kk': 'Әдепкі',
    },
    'address.default_set': {
      'uz': 'Asosiy manzil yangilandi',
      'ru': 'Адрес по умолчанию обновлён',
      'en': 'Default address updated',
      'kk': 'Әдепкі мекенжай жаңартылды',
    },
    'make_default_address': {
      'uz': 'Asosiy qilish',
      'ru': 'Сделать основным',
      'en': 'Make default',
      'kk': 'Негізгі ету',
    },
    'address_entrance': {
      'uz': "Pod'ezd",
      'ru': 'Подъезд',
      'en': 'Entrance',
      'kk': 'Кіреберіс',
    },
    'address_floor': {
      'uz': 'Qavat',
      'ru': 'Этаж',
      'en': 'Floor',
      'kk': 'Қабат',
    },
    'address_apartment': {
      'uz': 'Xonadon',
      'ru': 'Квартира',
      'en': 'Apartment',
      'kk': 'Пәтер',
    },
    'address_intercom': {
      'uz': 'Domofon',
      'ru': 'Домофон',
      'en': 'Intercom',
      'kk': 'Домофон',
    },
    'address_instructions': {
      'uz': "Kuryer uchun izoh",
      'ru': 'Комментарий курьеру',
      'en': 'Courier notes',
      'kk': 'Курьерге түсініктеме',
    },

    // Map
    'map_pick_location': {
      'uz': 'Joylashuvni tanlang',
      'ru': 'Выберите местоположение',
      'en': 'Pick a location',
      'kk': 'Орналасуды таңдаңыз',
    },

    // Phase 2 — courier shift / dispatch
    'courier.go_online': {
      'uz': 'Smenani boshlash',
      'ru': 'Я на смене',
      'en': 'Go online',
      'kk': 'Мен сменадамын',
    },
    'courier.go_offline': {
      'uz': 'Smenani tugatish',
      'ru': 'Off duty',
      'en': 'Go offline',
      'kk': 'Сменадан шығу',
    },
    'courier.shift_duration': {
      'uz': 'Smena vaqti',
      'ru': 'Длительность смены',
      'en': 'Shift duration',
      'kk': 'Смена ұзақтығы',
    },
    'courier.shift_earnings': {
      'uz': 'Smena daromadi',
      'ru': 'Заработок за смену',
      'en': 'Shift earnings',
      'kk': 'Смена табысы',
    },
    'courier.pending_offer': {
      'uz': 'Yangi taklif',
      'ru': 'Новое предложение',
      'en': 'New offer',
      'kk': 'Жаңа ұсыныс',
    },
    'courier.accept': {
      'uz': 'Qabul qilish',
      'ru': 'Принять',
      'en': 'Accept',
      'kk': 'Қабылдау',
    },
    'courier.decline': {
      'uz': 'Rad etish',
      'ru': 'Отклонить',
      'en': 'Decline',
      'kk': 'Бас тарту',
    },
    'courier.no_offers': {
      'uz': 'Buyurtmalar kutilmoqda',
      'ru': 'Ожидаем заказы',
      'en': 'Waiting for orders',
      'kk': 'Тапсырыстар күтілуде',
    },

    // Phase 2 — cart pricing breakdown
    'cart.subtotal': {
      'uz': 'Mahsulotlar',
      'ru': 'Товары',
      'en': 'Subtotal',
      'kk': 'Тауарлар',
    },
    'cart.delivery': {
      'uz': 'Yetkazib berish',
      'ru': 'Доставка',
      'en': 'Delivery',
      'kk': 'Жеткізу',
    },
    'cart.total': {
      'uz': 'Jami',
      'ru': 'Итого',
      'en': 'Total',
      'kk': 'Барлығы',
    },
    'cart.eta': {
      'uz': 'Yetkazib berish: ~{minutes} daqiqa',
      'ru': 'Доставка через ~{minutes} мин',
      'en': 'Delivery in ~{minutes} min',
      'kk': 'Жеткізу: ~{minutes} мин',
    },
    'cart.distance': {
      'uz': '{km} km',
      'ru': '{km} км',
      'en': '{km} km',
      'kk': '{km} км',
    },
    'cart.surge_badge': {
      'uz': 'Yuklama',
      'ru': 'Повышенный спрос',
      'en': 'Surge',
      'kk': 'Жоғары сұраныс',
    },
    'cart.out_of_zone': {
      'uz': "Adresga yetkazib bo'lmaydi",
      'ru': 'Доставка не доступна',
      'en': 'Address out of delivery zone',
      'kk': 'Бұл мекенжайға жеткізу қолжетімсіз',
    },
    'cart.promo_invalid': {
      'uz': 'Promo kod yaroqsiz',
      'ru': 'Промокод недействителен',
      'en': 'Invalid promo code',
      'kk': 'Промокод жарамсыз',
    },
    'subscription.add_card_first': {
      'uz': "Avval karta qo'shing",
      'ru': 'Сначала добавьте карту',
      'en': 'Please add a card first',
      'kk': 'Алдымен карта қосыңыз',
    },
    'group.code_copied': {
      'uz': 'Kod nusxalandi',
      'ru': 'Код скопирован',
      'en': 'Code copied',
      'kk': 'Код көшірілді',
    },
    'group.my_basket': {
      'uz': 'Mening savatim',
      'ru': 'Моя корзина',
      'en': 'My basket',
      'kk': 'Менің себетім',
    },
    'group.add_items': {
      'uz': "Mahsulot qo'shish",
      'ru': 'Добавить товары',
      'en': 'Add items',
      'kk': 'Тауар қосу',
    },
    'group.view_tracking': {
      'uz': 'Buyurtmani kuzatish',
      'ru': 'Отслеживать заказ',
      'en': 'View order tracking',
      'kk': 'Тапсырысты бақылау',
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
      'kk': 'Ұсыныс мерзімі өтті',
    },
    'dispatch.accepted': {
      'uz': 'Buyurtma sizga biriktirildi',
      'ru': 'Заказ закреплён за вами',
      'en': 'Order assigned to you',
      'kk': 'Тапсырыс сізге бекітілді',
    },
    'dispatch.assigned_to_other': {
      'uz': 'Buyurtmani boshqa kuryer oldi',
      'ru': 'Заказ ушёл другому курьеру',
      'en': 'Assigned to another courier',
      'kk': 'Тапсырыс басқа курьерге кетті',
    },

    // Orders
    'order.status.pending': {
      'uz': 'Yangi',
      'ru': 'Новый',
      'en': 'New',
      'kk': 'Жаңа',
    },
    'order.status.collecting': {
      'uz': 'Yig\'ilmoqda',
      'ru': 'Собирается',
      'en': 'Collecting',
      'kk': 'Жиналуда',
    },
    'order.status.ready': {
      'uz': 'Tayyor',
      'ru': 'Готов',
      'en': 'Ready',
      'kk': 'Дайын',
    },
    'order.status.in_delivery': {
      'uz': 'Yetkazilmoqda',
      'ru': 'В пути',
      'en': 'On the way',
      'kk': 'Жолда',
    },
    'order.status.delivered': {
      'uz': 'Yetkazildi',
      'ru': 'Доставлен',
      'en': 'Delivered',
      'kk': 'Жеткізілді',
    },

    // ── Phase 3 — Promo / coupons ─────────────────────────────────────────
    'promo.title': {
      'uz': 'Promo kodlar',
      'ru': 'Промокоды',
      'en': 'Promo codes',
      'kk': 'Промокодтар',
    },
    'promo.empty': {
      'uz': "Sizga mos promo kod yo'q",
      'ru': 'Нет доступных промокодов',
      'en': 'No eligible promo codes',
      'kk': 'Қолжетімді промокодтар жоқ',
    },
    'promo.enter_code': {
      'uz': 'Promo kod',
      'ru': 'Введите код',
      'en': 'Enter code',
      'kk': 'Промокод',
    },
    'promo.apply': {
      'uz': "Qo'llash",
      'ru': 'Применить',
      'en': 'Apply',
      'kk': 'Қолдану',
    },
    'promo.until': {
      'uz': 'Amalda:',
      'ru': 'До:',
      'en': 'Until:',
      'kk': 'Дейін:',
    },
    'promo.copied': {
      'uz': 'Nusxalandi',
      'ru': 'Скопировано',
      'en': 'Copied',
      'kk': 'Көшірілді',
    },

    // ── Phase 3 — Cart promo / loyalty / scheduling ──────────────────────
    'cart.promo_code': {
      'uz': 'Promo kod',
      'ru': 'Промокод',
      'en': 'Promo code',
      'kk': 'Промокод',
    },
    'cart.promo_hint': {
      'uz': 'Kodni kiriting',
      'ru': 'Введите код',
      'en': 'Enter code',
      'kk': 'Кодты енгізіңіз',
    },
    'cart.promo_applied': {
      'uz': "Qo'llanildi",
      'ru': 'Применён',
      'en': 'Applied',
      'kk': 'Қолданылды',
    },
    'cart.loyalty_points': {
      'uz': 'Bonus ballar',
      'ru': 'Бонусные баллы',
      'en': 'Loyalty points',
      'kk': 'Бонустық ұпайлар',
    },
    'cart.points_available': {
      'uz': 'Mavjud',
      'ru': 'Доступно',
      'en': 'Available',
      'kk': 'Қолжетімді',
    },
    'cart.points_too_small': {
      'uz': 'Ballarni ishlatish uchun summa yetarli emas',
      'ru': 'Сумма слишком маленькая для бонусов',
      'en': 'Subtotal is too small to spend points',
      'kk': 'Ұпай жұмсау үшін сома жеткіліксіз',
    },
    'cart.plan_delivery': {
      'uz': 'Yetkazib berish vaqti',
      'ru': 'Время доставки',
      'en': 'Delivery time',
      'kk': 'Жеткізу уақыты',
    },
    'cart.plan_asap': {
      'uz': 'Hozir',
      'ru': 'Сейчас',
      'en': 'ASAP',
      'kk': 'Қазір',
    },
    'cart.plan_schedule': {
      'uz': 'Rejalashtirish',
      'ru': 'Запланировать',
      'en': 'Schedule',
      'kk': 'Жоспарлау',
    },
    'cart.scheduled_for': {
      'uz': 'Tanlangan',
      'ru': 'Выбрано',
      'en': 'Scheduled for',
      'kk': 'Таңдалған',
    },

    // ── Phase 3 — Loyalty screen ─────────────────────────────────────────
    'loyalty.title': {
      'uz': 'Bonuslar',
      'ru': 'Бонусы',
      'en': 'Rewards',
      'kk': 'Бонустар',
    },
    'loyalty.tier': {
      'uz': 'Daraja',
      'ru': 'Уровень',
      'en': 'Tier',
      'kk': 'Деңгей',
    },
    'loyalty.points': {
      'uz': 'Ballar',
      'ru': 'Баллы',
      'en': 'Points',
      'kk': 'Ұпайлар',
    },
    'loyalty.cashback': {
      'uz': 'Cashback',
      'ru': 'Кешбэк',
      'en': 'Cashback',
      'kk': 'Кешбэк',
    },
    'loyalty.to_next': {
      'uz': 'Keyingi darajagacha:',
      'ru': 'До уровня:',
      'en': 'To next tier:',
      'kk': 'Келесі деңгейге дейін:',
    },
    'loyalty.max_tier': {
      'uz': 'Eng yuqori daraja!',
      'ru': 'Максимальный уровень!',
      'en': 'Top tier reached!',
      'kk': 'Ең жоғары деңгей!',
    },
    'loyalty.your_referral': {
      'uz': 'Sizning referal kodingiz',
      'ru': 'Ваш реферальный код',
      'en': 'Your referral code',
      'kk': 'Сіздің рефералдық кодыңыз',
    },
    'loyalty.have_friend_code': {
      'uz': "Do'stning kodi bormi?",
      'ru': 'Есть код друга?',
      'en': 'Have a friend\'s code?',
      'kk': 'Достың коды бар ма?',
    },
    'loyalty.enter_friend_code': {
      'uz': 'Kodni kiriting',
      'ru': 'Введите код',
      'en': 'Enter code',
      'kk': 'Кодты енгізіңіз',
    },
    'loyalty.apply': {
      'uz': "Qo'llash",
      'ru': 'Применить',
      'en': 'Apply',
      'kk': 'Қолдану',
    },
    'loyalty.referral_applied': {
      'uz': "Referal kodi qo'llanildi",
      'ru': 'Реферальный код применён',
      'en': 'Referral code applied',
      'kk': 'Рефералдық код қолданылды',
    },
    'loyalty.copied': {
      'uz': 'Nusxalandi',
      'ru': 'Скопировано',
      'en': 'Copied',
      'kk': 'Көшірілді',
    },
    'loyalty.recent_activity': {
      'uz': "So'nggi harakatlar",
      'ru': 'Недавняя активность',
      'en': 'Recent activity',
      'kk': 'Соңғы әрекеттер',
    },
    'loyalty.no_activity': {
      'uz': "Hali harakat yo'q",
      'ru': 'Активности пока нет',
      'en': 'No activity yet',
      'kk': 'Әзірге әрекет жоқ',
    },

    // ── Phase 3 — Reviews ────────────────────────────────────────────────
    'reviews.title': {
      'uz': 'Sharhlar',
      'ru': 'Отзывы',
      'en': 'Reviews',
      'kk': 'Пікірлер',
    },
    'reviews.tab_all': {
      'uz': 'Hammasi',
      'ru': 'Все',
      'en': 'All',
      'kk': 'Барлығы',
    },
    'reviews.empty': {
      'uz': "Sharhlar hali yo'q",
      'ru': 'Отзывов пока нет',
      'en': 'No reviews yet',
      'kk': 'Әзірге пікір жоқ',
    },
    'reviews.count_suffix': {
      'uz': 'sharhlar',
      'ru': 'отзывов',
      'en': 'reviews',
      'kk': 'пікір',
    },

    // ── Phase 3 — Chat ───────────────────────────────────────────────────
    'chat.title': {
      'uz': 'Chat',
      'ru': 'Чат',
      'en': 'Chat',
      'kk': 'Чат',
    },
    'chat.online': {
      'uz': 'tarmoqda',
      'ru': 'в сети',
      'en': 'online',
      'kk': 'желіде',
    },
    'chat.offline': {
      'uz': 'tarmoqda emas',
      'ru': 'не в сети',
      'en': 'offline',
      'kk': 'желіде емес',
    },
    'chat.input_hint': {
      'uz': "Xabar yozing…",
      'ru': 'Введите сообщение…',
      'en': 'Type a message…',
      'kk': 'Хабарлама жазыңыз…',
    },
    'chat.send_failed': {
      'uz': 'Xabar yuborilmadi',
      'ru': 'Сообщение не отправлено',
      'en': 'Message failed',
      'kk': 'Хабар жіберілмеді',
    },
    'chat.image_unavailable': {
      'uz': 'Rasm yuborish hozircha mavjud emas',
      'ru': 'Загрузка изображений пока недоступна',
      'en': 'Image upload not yet available',
      'kk': 'Сурет жүктеу әзірге қолжетімсіз',
    },

    // ── Phase 3 — Time slots ─────────────────────────────────────────────
    'slots.today': {
      'uz': 'Bugun',
      'ru': 'Сегодня',
      'en': 'Today',
      'kk': 'Бүгін',
    },
    'slots.tomorrow': {
      'uz': 'Ertaga',
      'ru': 'Завтра',
      'en': 'Tomorrow',
      'kk': 'Ертең',
    },

    // ── Phase 6 — Saved payment methods ──────────────────────────────────
    'payment.add_card': {
      'uz': "Karta qo'shish",
      'ru': 'Добавить карту',
      'en': 'Add card',
      'kk': 'Карта қосу',
    },
    'payment.cards_list': {
      'uz': 'Kartalarim',
      'ru': 'Мои карты',
      'en': 'My cards',
      'kk': 'Менің карталарым',
    },
    'payment.set_default': {
      'uz': 'Asosiy qilish',
      'ru': 'Сделать основной',
      'en': 'Set as default',
      'kk': 'Негізгі ету',
    },
    'payment.delete': {
      'uz': "Kartani o'chirish",
      'ru': 'Удалить карту',
      'en': 'Delete card',
      'kk': 'Картаны жою',
    },
    'payment.no_cards': {
      'uz': "Saqlangan kartalar yo'q",
      'ru': 'Нет сохранённых карт',
      'en': 'No saved cards',
      'kk': 'Сақталған карталар жоқ',
    },
    'payment.use_new_card': {
      'uz': 'Yangi karta bilan to\'lash',
      'ru': 'Оплатить новой картой',
      'en': 'Pay with new card',
      'kk': 'Жаңа картамен төлеу',
    },

    // ── Phase 6 — Cart address tile ──────────────────────────────────────
    'cart.address_tile_title': {
      'uz': 'Yetkazib berish manzili',
      'ru': 'Адрес доставки',
      'en': 'Delivery address',
      'kk': 'Жеткізу мекенжайы',
    },
    'cart.address_choose': {
      'uz': 'Manzilni tanlang',
      'ru': 'Выберите адрес',
      'en': 'Choose address',
      'kk': 'Мекенжайды таңдаңыз',
    },
    'cart.no_address_warning': {
      'uz': "Avval manzilni tanlang",
      'ru': 'Сначала выберите адрес',
      'en': 'Pick an address first',
      'kk': 'Алдымен мекенжайды таңдаңыз',
    },

    // ── Phase 6 — Tipping ────────────────────────────────────────────────
    'tip.cta': {
      'uz': "Kuryerga rahmat aytish",
      'ru': 'Поблагодарить курьера',
      'en': 'Tip the courier',
      'kk': 'Курьерге шай ақы беру',
    },
    'tip.5_percent': {
      'uz': '5%',
      'ru': '5%',
      'en': '5%',
      'kk': '5%',
    },
    'tip.10_percent': {
      'uz': '10%',
      'ru': '10%',
      'en': '10%',
      'kk': '10%',
    },
    'tip.15_percent': {
      'uz': '15%',
      'ru': '15%',
      'en': '15%',
      'kk': '15%',
    },
    'tip.custom': {
      'uz': 'Boshqa summa',
      'ru': 'Другая сумма',
      'en': 'Custom',
      'kk': 'Басқа сома',
    },
    'tip.success': {
      'uz': 'Rahmat yuborildi 🙏',
      'ru': 'Чаевые отправлены 🙏',
      'en': 'Tip sent 🙏',
      'kk': 'Шай ақы жіберілді 🙏',
    },

    // ── Phase 6 — Geolocation ────────────────────────────────────────────
    'location.permission_denied': {
      'uz': "Geolokatsiya yo'q",
      'ru': 'Геолокация недоступна',
      'en': 'Location unavailable',
      'kk': 'Геолокация қолжетімсіз',
    },
    'location.current': {
      'uz': 'Joriy joylashuv',
      'ru': 'Моё местоположение',
      'en': 'Use current location',
      'kk': 'Менің орналасуым',
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

    // ── Phase 8.2 — Tip estimate / batch dispatch ────────────────────────
    'dispatch.tip_estimate_chip': {
      'uz': '💰 + ~{amount}',
      'ru': '💰 + ~{amount}',
      'en': '💰 + ~{amount}',
      'kk': '💰 + ~{amount}',
    },
    'dispatch.batch_badge': {
      'uz': 'BATCH × {count}',
      'ru': 'BATCH × {count}',
      'en': 'BATCH × {count}',
      'kk': 'BATCH × {count}',
    },
    'dispatch.batch_progress': {
      'uz': 'Buyurtma {index}/{total}',
      'ru': 'Заказ {index}/{total}',
      'en': 'Order {index}/{total}',
      'kk': 'Тапсырыс {index}/{total}',
    },

    // ── Phase 8.3 — Performance dashboard ────────────────────────────────
    'performance.title': {
      'uz': 'Samaradorlik',
      'ru': 'Эффективность',
      'en': 'Performance',
      'kk': 'Тиімділік',
    },
    'performance.acceptance': {
      'uz': 'Qabul qilish',
      'ru': 'Приём заказов',
      'en': 'Acceptance',
      'kk': 'Қабылдау',
    },
    'performance.completion': {
      'uz': 'Bajarish',
      'ru': 'Завершение',
      'en': 'Completion',
      'kk': 'Аяқтау',
    },
    'performance.on_time': {
      'uz': 'Vaqtida',
      'ru': 'Вовремя',
      'en': 'On time',
      'kk': 'Уақытында',
    },
    'performance.avg_rating': {
      'uz': "O'rtacha reyting",
      'ru': 'Средний рейтинг',
      'en': 'Avg rating',
      'kk': 'Орташа рейтинг',
    },
    'performance.tips_total': {
      'uz': 'Chayryak jami',
      'ru': 'Всего чаевых',
      'en': 'Tips total',
      'kk': 'Барлық шай ақы',
    },
    'performance.no_data': {
      'uz': "Ma'lumot yetarli emas",
      'ru': 'Недостаточно данных',
      'en': 'Not enough data yet',
      'kk': 'Дерек жеткіліксіз',
    },

    // ── Phase 8.4 — Heatmap toggle ───────────────────────────────────────
    'heatmap.toggle_show': {
      'uz': '🔥 Hududdagi buyurtmalar',
      'ru': '🔥 Заказы рядом',
      'en': '🔥 Orders nearby',
      'kk': '🔥 Жақын тапсырыстар',
    },
    'heatmap.toggle_hide': {
      'uz': '🔥 Yashirish',
      'ru': '🔥 Скрыть',
      'en': '🔥 Hide',
      'kk': '🔥 Жасыру',
    },

    // ── Phase 8.1 — Stacked / batch deliveries ───────────────────────────
    'batch.upcoming_pickup': {
      'uz': 'Keyingi olinish',
      'ru': 'Следующий забор',
      'en': 'Next pickup',
      'kk': 'Келесі алу',
    },
    'batch.view_overview': {
      'uz': "Hammasini ko'rish",
      'ru': 'Все заказы',
      'en': 'View batch',
      'kk': 'Барлығын көру',
    },

    // ── Phase 13.2.5 — Courier delivery-photo proof ─────────────────────────
    'delivery_photo.title': {
      'uz': 'Yetkazib berish surati',
      'ru': 'Фото доставки',
      'en': 'Delivery photo',
      'kk': 'Жеткізу фотосы',
    },
    'delivery_photo.preview_title': {
      'uz': 'Suratni tasdiqlang',
      'ru': 'Проверьте снимок',
      'en': 'Confirm photo',
      'kk': 'Суретті растаңыз',
    },
    'delivery_photo.retry': {
      'uz': 'Qayta urinib',
      'ru': 'Переснять',
      'en': 'Retry',
      'kk': 'Қайта түсіру',
    },
    'delivery_photo.submit': {
      'uz': 'Yuborish',
      'ru': 'Отправить',
      'en': 'Submit',
      'kk': 'Жіберу',
    },
    'delivery_photo.tap_to_view': {
      'uz': 'Toʻliq koʻrish uchun bosing',
      'ru': 'Нажмите, чтобы открыть',
      'en': 'Tap to view',
      'kk': 'Толық көру үшін басыңыз',
    },
    'delivery_photo.delivered_at': {
      'uz': 'Topshirildi · {time}',
      'ru': 'Доставлено · {time}',
      'en': 'Delivered · {time}',
      'kk': 'Жеткізілді · {time}',
    },
    'delivery_photo.camera_unavailable': {
      'uz': 'Kamera ochilmadi. Ruxsatni tekshiring.',
      'ru': 'Камера недоступна. Проверьте разрешения.',
      'en': 'Camera unavailable. Check permissions.',
      'kk': 'Камера қолжетімсіз. Рұқсаттарды тексеріңіз.',
    },
    'delivery_photo.upload_failed': {
      'uz': 'Suratni yuklab boʻlmadi. Qayta urinib koʻring.',
      'ru': 'Не удалось загрузить фото. Повторите попытку.',
      'en': 'Failed to upload photo. Try again.',
      'kk': 'Фотоны жүктеу мүмкін болмады. Қайталап көріңіз.',
    },

    // ── Phase 8.5 — Instant payout ───────────────────────────────────────
    'payout.cashout_now': {
      'uz': 'Hozir yechib olish',
      'ru': 'Вывести сейчас',
      'en': 'Cash out now',
      'kk': 'Қазір шығару',
    },
    'payout.balance': {
      'uz': 'Mavjud balans',
      'ru': 'Доступный баланс',
      'en': 'Available balance',
      'kk': 'Қолжетімді баланс',
    },
    'payout.below_min': {
      'uz': 'Minimal summa: {amount}',
      'ru': 'Минимум для вывода: {amount}',
      'en': 'Minimum payout: {amount}',
      'kk': 'Ең аз шығару сомасы: {amount}',
    },
    'payout.pending': {
      'uz': "So'rov qabul qilindi — admin 24 soat ichida ishlov beradi",
      'ru':
          'Запрос принят — администратор обработает в течение 24 часов',
      'en': 'Pending request — admin will process within 24h',
      'kk': 'Сұраныс қабылданды — әкімші 24 сағат ішінде өңдейді',
    },
    'payout.requested_success': {
      'uz': "So'rov yuborildi 🎉",
      'ru': 'Запрос отправлен 🎉',
      'en': 'Payout requested 🎉',
      'kk': 'Сұраныс жіберілді 🎉',
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

    // ── Phase 9.3 — Social sign-in ───────────────────────────────────────
    'auth.continue_with_apple': {
      'uz': 'Apple bilan kirish',
      'ru': 'Войти через Apple',
      'en': 'Continue with Apple',
      'kk': 'Apple арқылы кіру',
    },
    'auth.continue_with_google': {
      'uz': 'Google bilan kirish',
      'ru': 'Войти через Google',
      'en': 'Continue with Google',
      'kk': 'Google арқылы кіру',
    },
    'auth.or': {
      'uz': 'yoki',
      'ru': 'или',
      'en': 'or',
      'kk': 'немесе',
    },

    // ── Phase 9.1 / 9.2 — Privacy & GDPR ─────────────────────────────────
    'privacy.title': {
      'uz': "Maxfiylik va ma'lumotlar",
      'ru': 'Приватность и данные',
      'en': 'Privacy & data',
      'kk': 'Құпиялылық және деректер',
    },
    'privacy.export_data': {
      'uz': "Ma'lumotlarimni yuklash",
      'ru': 'Экспорт моих данных',
      'en': 'Export my data',
      'kk': 'Деректерімді экспорттау',
    },
    'privacy.export_pending': {
      'uz': "So'rov tayyorlanmoqda. Tayyor bo'lganda email orqali xabar beramiz.",
      'ru': 'Запрос обрабатывается. Мы пришлём email, когда архив будет готов.',
      'en': 'Your export is being prepared. We\'ll email you when it\'s ready.',
      'kk': 'Сұраныс өңделуде. Дайын болғанда email жібереміз.',
    },
    'privacy.export_ready': {
      'uz': 'Eksport tayyor',
      'ru': 'Экспорт готов',
      'en': 'Export ready',
      'kk': 'Экспорт дайын',
    },
    'privacy.export_expired': {
      'uz': 'Muddati tugagan',
      'ru': 'Срок истёк',
      'en': 'Expires',
      'kk': 'Мерзімі өткен',
    },
    'privacy.download': {
      'uz': 'Yuklab olish',
      'ru': 'Скачать',
      'en': 'Download',
      'kk': 'Жүктеп алу',
    },
    'privacy.delete_account': {
      'uz': "Hisobni o'chirish",
      'ru': 'Удалить аккаунт',
      'en': 'Delete account',
      'kk': 'Аккаунтты жою',
    },
    'privacy.delete_confirm': {
      'uz':
          "Hisobingiz 30 kun ichida o'chiriladi. Buyurtma tarixi qonuniy talablarga muvofiq 5 yil saqlanadi.",
      'ru':
          'Ваш аккаунт будет удалён через 30 дней. История заказов хранится 5 лет согласно закону.',
      'en':
          'Your account will be deleted after a 30-day grace period. Order history is kept 5 years for legal compliance.',
      'kk':
          'Аккаунтыңыз 30 күннен кейін жойылады. Тапсырыстар тарихы заң талабы бойынша 5 жыл сақталады.',
    },
    'privacy.delete_reason_hint': {
      'uz': 'Sabab (ixtiyoriy)',
      'ru': 'Причина (необязательно)',
      'en': 'Reason (optional)',
      'kk': 'Себеп (міндетті емес)',
    },
    'privacy.delete_scheduled': {
      'uz': "Hisobingiz {date} sanasida o'chiriladi. Bu sanagacha bekor qilishingiz mumkin.",
      'ru': 'Аккаунт будет удалён {date}. До этой даты можно отменить.',
      'en': 'Your account will be deleted on {date}. You can cancel before then.',
      'kk': 'Аккаунт {date} күні жойылады. Бұған дейін бас тартуға болады.',
    },
    'privacy.cancel_deletion': {
      'uz': "O'chirishni bekor qilish",
      'ru': 'Отменить удаление',
      'en': 'Cancel deletion',
      'kk': 'Жоюды болдырмау',
    },
    'privacy.no_deletion': {
      'uz': "O'chirish so'rovi yo'q",
      'ru': 'Запросов на удаление нет',
      'en': 'No pending deletion request',
      'kk': 'Жою сұранысы жоқ',
    },
    'privacy.legal_note': {
      'uz':
          "Bu Phase 9 GDPR uchun. Buyurtma tarixi qonuniy talablar tufayli 5 yil saqlanadi.",
      'ru':
          'Это раздел Phase 9 GDPR. История заказов хранится 5 лет согласно требованиям закона.',
      'en':
          'This is for Phase 9 GDPR compliance. Order history is retained 5 years for legal compliance.',
      'kk':
          'Бұл Phase 9 GDPR бөлімі. Тапсырыс тарихы заң бойынша 5 жыл сақталады.',
    },

    // ── Phase 10.1 — Group orders ─────────────────────────────────────────
    'group.create': {
      'uz': "Guruh buyurtma tuzish",
      'ru': 'Создать групповой заказ',
      'en': 'Make this a group order',
      'kk': 'Топтық тапсырыс жасау',
    },
    'group.join': {
      'uz': "Guruhga qo'shilish",
      'ru': 'Присоединиться',
      'en': 'Join group',
      'kk': 'Топқа қосылу',
    },
    'group.invite': {
      'uz': 'Taklif yuborish',
      'ru': 'Поделиться приглашением',
      'en': 'Share invite',
      'kk': 'Шақыру жіберу',
    },
    'group.share_code': {
      'uz': "Qo'shilish kodi",
      'ru': 'Код приглашения',
      'en': 'Join code',
      'kk': 'Қосылу коды',
    },
    'group.host_label': {
      'uz': 'Tashkilotchi',
      'ru': 'Организатор',
      'en': 'Host',
      'kk': 'Ұйымдастырушы',
    },
    'group.member_label': {
      'uz': 'Siz',
      'ru': 'Вы',
      'en': 'You',
      'kk': 'Сіз',
    },
    'group.lock_order': {
      'uz': 'Buyurtmani qulflash',
      'ru': 'Зафиксировать заказ',
      'en': 'Lock order',
      'kk': 'Тапсырысты бекіту',
    },
    'group.pay_my_share': {
      'uz': "O'z ulushimni to'lash",
      'ru': 'Оплатить свою долю',
      'en': 'Pay my share',
      'kk': 'Өз үлесімді төлеу',
    },
    'group.pay_for_all': {
      'uz': "Hammasi uchun to'lash",
      'ru': 'Оплатить за всех',
      'en': 'Pay for everyone',
      'kk': 'Барлығы үшін төлеу',
    },
    'group.cancelled': {
      'uz': 'Bu guruh bekor qilindi',
      'ru': 'Группа отменена',
      'en': 'This group was cancelled',
      'kk': 'Бұл топ тоқтатылды',
    },
    'group.expired': {
      'uz': 'Muddati tugadi',
      'ru': 'Срок истёк',
      'en': 'Group expired',
      'kk': 'Мерзімі бітті',
    },
    'group.locked_at': {
      'uz': 'Qulflangan',
      'ru': 'Зафиксировано',
      'en': 'Locked',
      'kk': 'Бекітілген',
    },

    // ── Phase 10.2 — Customer support ─────────────────────────────────────
    'support.title': {
      'uz': 'Yordam',
      'ru': 'Поддержка',
      'en': 'Support',
      'kk': 'Қолдау',
    },
    'support.new_ticket': {
      'uz': 'Yangi murojaat',
      'ru': 'Новое обращение',
      'en': 'New ticket',
      'kk': 'Жаңа өтініш',
    },
    'support.subject_hint': {
      'uz': 'Mavzu',
      'ru': 'Тема',
      'en': 'Subject',
      'kk': 'Тақырып',
    },
    'support.body_hint': {
      'uz': 'Muammoni batafsil tasvirlab bering',
      'ru': 'Опишите проблему подробнее',
      'en': 'Describe your issue in detail',
      'kk': 'Мәселені толығырақ сипаттаңыз',
    },
    'support.category_order': {
      'uz': 'Buyurtma',
      'ru': 'Заказ',
      'en': 'Order',
      'kk': 'Тапсырыс',
    },
    'support.category_payment': {
      'uz': "To'lov",
      'ru': 'Оплата',
      'en': 'Payment',
      'kk': 'Төлем',
    },
    'support.category_delivery': {
      'uz': 'Yetkazib berish',
      'ru': 'Доставка',
      'en': 'Delivery',
      'kk': 'Жеткізу',
    },
    'support.category_account': {
      'uz': 'Hisob',
      'ru': 'Аккаунт',
      'en': 'Account',
      'kk': 'Аккаунт',
    },
    'support.category_other': {
      'uz': 'Boshqa',
      'ru': 'Другое',
      'en': 'Other',
      'kk': 'Басқа',
    },
    'support.priority_low': {
      'uz': 'Past',
      'ru': 'Низкий',
      'en': 'Low',
      'kk': 'Төмен',
    },
    'support.priority_normal': {
      'uz': 'Oddiy',
      'ru': 'Обычный',
      'en': 'Normal',
      'kk': 'Қалыпты',
    },
    'support.priority_high': {
      'uz': 'Yuqori',
      'ru': 'Высокий',
      'en': 'High',
      'kk': 'Жоғары',
    },
    'support.priority_urgent': {
      'uz': 'Shoshilinch',
      'ru': 'Срочно',
      'en': 'Urgent',
      'kk': 'Шұғыл',
    },
    'support.status_open': {
      'uz': 'Ochiq',
      'ru': 'Открыт',
      'en': 'Open',
      'kk': 'Ашық',
    },
    'support.status_pending': {
      'uz': 'Kutilmoqda',
      'ru': 'В ожидании',
      'en': 'Pending',
      'kk': 'Күтуде',
    },
    'support.status_resolved': {
      'uz': 'Hal qilindi',
      'ru': 'Решено',
      'en': 'Resolved',
      'kk': 'Шешілді',
    },
    'support.status_closed': {
      'uz': 'Yopildi',
      'ru': 'Закрыт',
      'en': 'Closed',
      'kk': 'Жабық',
    },
    'support.close_ticket': {
      'uz': 'Yopish',
      'ru': 'Закрыть',
      'en': 'Close',
      'kk': 'Жабу',
    },
    'support.no_tickets': {
      'uz': "Murojaatlar yo'q",
      'ru': 'Обращений нет',
      'en': 'No tickets yet',
      'kk': 'Өтініштер жоқ',
    },

    // ── Phase 11 — Onboarding ────────────────────────────────────────────
    'onboarding.slide1_title': {
      'uz': 'TezKetKaz',
      'ru': 'TezKetKaz',
      'en': 'TezKetKaz',
      'kk': 'TezKetKaz',
    },
    'onboarding.slide1_body': {
      'uz': 'Bir-ikki klik bilan eng yaqin do\'kondan tezda yetkazib beramiz.',
      'ru': 'Быстрая доставка из ближайших магазинов в пару кликов.',
      'en': 'Lightning-fast delivery from your nearest shops in a couple of taps.',
      'kk': 'Жақын дүкендерден бірнеше басумен жылдам жеткізу.',
    },
    'onboarding.slide2_title': {
      'uz': 'Restoranlar, do\'konlar, dorixonalar',
      'ru': 'Рестораны, магазины, аптеки',
      'en': 'Restaurants, shops, pharmacies',
      'kk': 'Мейрамханалар, дүкендер, дәріханалар',
    },
    'onboarding.slide2_body': {
      'uz': 'Hammasi bitta ilovada — kerakli kategoriyani tanlang.',
      'ru': 'Всё в одном приложении — выберите нужную категорию.',
      'en': 'All in one app — pick the vertical you need.',
      'kk': 'Барлығы бір қосымшада — қажет санатты таңдаңыз.',
    },
    'onboarding.slide3_title': {
      'uz': 'Real vaqtda kuzatib boring',
      'ru': 'Отслеживайте курьера в реальном времени',
      'en': 'Real-time courier tracking',
      'kk': 'Курьерді нақты уақытта бақылау',
    },
    'onboarding.slide3_body': {
      'uz': 'Buyurtmangiz qayerda ekanini xaritada ko\'ring.',
      'ru': 'Смотрите, где ваш заказ, прямо на карте.',
      'en': 'See exactly where your order is on the map.',
      'kk': 'Тапсырысыңыз қайда екенін картадан көріңіз.',
    },
    'onboarding.slide4_title': {
      'uz': 'Boshlash uchun tayyormisiz?',
      'ru': 'Готовы начать?',
      'en': 'Ready to get started?',
      'kk': 'Бастауға дайынсыз ба?',
    },
    'onboarding.slide4_body': {
      'uz': 'Telefon raqamingiz bilan kiring va birinchi buyurtmangizni bering.',
      'ru': 'Войдите по номеру телефона и оформите первый заказ.',
      'en': 'Continue with your phone number and place your first order.',
      'kk': 'Телефон нөміріңізбен кіріп, бірінші тапсырысыңызды беріңіз.',
    },
    'onboarding.skip': {
      'uz': "O'tkazib yuborish",
      'ru': 'Пропустить',
      'en': 'Skip',
      'kk': 'Өткізіп жіберу',
    },
    'onboarding.next': {
      'uz': 'Keyingisi',
      'ru': 'Далее',
      'en': 'Next',
      'kk': 'Келесі',
    },
    'onboarding.continue': {
      'uz': 'Boshlash',
      'ru': 'Начать',
      'en': "Let's go",
      'kk': 'Бастау',
    },

    // ── Phase 11 — Multi-shop cart ───────────────────────────────────────
    'cart.switcher_label': {
      'uz': 'Sizning savatlaringiz',
      'ru': 'Ваши корзины',
      'en': 'Your carts',
      'kk': 'Сіздің себеттеріңіз',
    },
    'cart.added_to_shop': {
      'uz': "{shopName} savatiga qo'shildi",
      'ru': 'Добавлено в корзину {shopName}',
      'en': 'Added to {shopName}',
      'kk': '{shopName} себетіне қосылды',
    },
    'cart.stale_items_warning': {
      'uz': 'Diqqat: {count} ta mahsulot endi mavjud emas',
      'ru': 'Внимание: {count} товаров больше недоступно',
      'en': '{count} item(s) are no longer available',
      'kk': 'Назар аударыңыз: {count} тауар енді қолжетімсіз',
    },

    // ── Phase 10.3 — Dark mode ────────────────────────────────────────────
    'theme.title': {
      'uz': 'Tungi rejim',
      'ru': 'Тёмная тема',
      'en': 'Theme',
      'kk': 'Тақырып',
    },
    'theme.system': {
      'uz': 'Avto',
      'ru': 'Авто',
      'en': 'Auto',
      'kk': 'Авто',
    },
    'theme.light': {
      'uz': 'Yorug\'',
      'ru': 'Светлая',
      'en': 'Light',
      'kk': 'Ашық',
    },
    'theme.dark': {
      'uz': 'Tungi',
      'ru': 'Тёмная',
      'en': 'Dark',
      'kk': 'Қараңғы',
    },

    // ── Phase 12 — Legal screen (Privacy / Terms) ─────────────────────────
    'profile.legal_tile': {
      'uz': 'Maxfiylik / shartlar',
      'ru': 'Приватность / Условия',
      'en': 'Privacy / Terms',
      'kk': 'Құпиялылық / Шарттар',
    },
    'legal.privacy_tab': {
      'uz': 'Maxfiylik siyosati',
      'ru': 'Политика конфиденциальности',
      'en': 'Privacy Policy',
      'kk': 'Құпиялылық саясаты',
    },
    'legal.terms_tab': {
      'uz': 'Foydalanish shartlari',
      'ru': 'Условия использования',
      'en': 'Terms of Service',
      'kk': 'Пайдалану шарттары',
    },
    'legal.loading': {
      'uz': 'Hujjat yuklanmoqda…',
      'ru': 'Загружаем документ…',
      'en': 'Loading document…',
      'kk': 'Құжат жүктелуде…',
    },
    'legal.error': {
      'uz': 'Hujjatni yuklab bo\'lmadi. Internetni tekshirib, qayta urinib ko\'ring.',
      'ru': 'Не удалось загрузить документ. Проверьте интернет и повторите.',
      'en': 'Could not load the document. Check your connection and retry.',
      'kk': 'Құжатты жүктеу мүмкін болмады. Интернетті тексеріп, қайталаңыз.',
    },

    // ── Phase 13.2 — Courier verification (KYC) ──────────────────────────
    'courier.verification.title': {
      'uz': "Kuryer ro'yxatdan o'tish",
      'ru': 'Регистрация курьера',
      'en': 'Courier sign-up',
      'kk': 'Курьер тіркелуі',
    },
    'courier.verification.generic_error': {
      'uz': 'Xatolik yuz berdi',
      'ru': 'Произошла ошибка',
      'en': 'Something went wrong',
      'kk': 'Қате орын алды',
    },
    'courier.verification.submitted_title': {
      'uz': 'Ariza yuborildi!',
      'ru': 'Заявка отправлена!',
      'en': 'Application submitted!',
      'kk': 'Өтініш жіберілді!',
    },
    'courier.verification.submitted_body': {
      'uz': "Arizangiz 1-2 ish kuni ichida ko'rib chiqiladi. Natija haqida SMS va push-xabar olasiz.",
      'ru': 'Ваша заявка будет рассмотрена в течение 1-2 рабочих дней. Результат придёт по SMS и push-уведомлению.',
      'en': 'Your application will be reviewed within 1-2 business days. You\'ll receive the result via SMS and push notification.',
      'kk': 'Өтінішіңіз 1-2 жұмыс күні ішінде қаралады. Нәтиже туралы SMS және push хабарлама аласыз.',
    },
    'courier.verification.go_home': {
      'uz': 'Bosh sahifaga qaytish',
      'ru': 'Вернуться на главную',
      'en': 'Back to home',
      'kk': 'Басты бетке оралу',
    },
    'courier.verification.upload_failed': {
      'uz': "Yuklab bo'lmadi",
      'ru': 'Не удалось загрузить',
      'en': 'Upload failed',
      'kk': 'Жүктеу мүмкін болмады',
    },
    'courier.verification.source_camera': {
      'uz': 'Kamera',
      'ru': 'Камера',
      'en': 'Camera',
      'kk': 'Камера',
    },
    'courier.verification.source_gallery': {
      'uz': 'Galereya',
      'ru': 'Галерея',
      'en': 'Gallery',
      'kk': 'Галерея',
    },
    'courier.verification.next_cta': {
      'uz': 'Keyingisi',
      'ru': 'Далее',
      'en': 'Next',
      'kk': 'Келесі',
    },
    'courier.verification.submit_cta': {
      'uz': 'Ariza yuborish',
      'ru': 'Отправить заявку',
      'en': 'Submit application',
      'kk': 'Өтінішті жіберу',
    },
    'courier.verification.personal_title': {
      'uz': "Shaxsiy ma'lumot",
      'ru': 'Личные данные',
      'en': 'Personal info',
      'kk': 'Жеке деректер',
    },
    'courier.verification.personal_subtitle': {
      'uz': "To'liq ism-sharifingizni kiriting",
      'ru': 'Введите ваше ФИО',
      'en': 'Enter your full name',
      'kk': 'Толық аты-жөніңізді енгізіңіз',
    },
    'courier.verification.full_name_label': {
      'uz': "To'liq ism-sharif",
      'ru': 'ФИО',
      'en': 'Full name',
      'kk': 'Толық аты-жөні',
    },
    'courier.verification.full_name_hint': {
      'uz': 'Ism Familiya Otasining ismi',
      'ru': 'Имя Фамилия Отчество',
      'en': 'First Last Middle',
      'kk': 'Аты Тегі Әкесінің аты',
    },
    'courier.verification.docs_title': {
      'uz': 'Hujjatlar',
      'ru': 'Документы',
      'en': 'Documents',
      'kk': 'Құжаттар',
    },
    'courier.verification.docs_subtitle': {
      'uz': "Hujjatlar Soliq qo'mitasi orqali tekshiriladi",
      'ru': 'Документы проверяются через налоговый комитет',
      'en': 'Documents are verified through the tax authority',
      'kk': 'Құжаттар салық комитеті арқылы тексеріледі',
    },
    'courier.verification.stir_label': {
      'uz': 'STIR (INN)',
      'ru': 'СТИР (ИНН)',
      'en': 'TIN (STIR)',
      'kk': 'СТИР (ЖСН)',
    },
    'courier.verification.stir_hint': {
      'uz': '9 ta raqam',
      'ru': '9 цифр',
      'en': '9 digits',
      'kk': '9 сан',
    },
    'courier.verification.stir_helper': {
      'uz': "Soliq to'lovchining individual raqami",
      'ru': 'Индивидуальный номер налогоплательщика',
      'en': 'Individual taxpayer number',
      'kk': 'Жеке салық төлеушінің нөмірі',
    },
    'courier.verification.passport_label': {
      'uz': 'Pasport seriyasi va raqami',
      'ru': 'Серия и номер паспорта',
      'en': 'Passport series and number',
      'kk': 'Паспорт сериясы мен нөмірі',
    },
    'courier.verification.passport_hint': {
      'uz': 'AA 1234567',
      'ru': 'AA 1234567',
      'en': 'AA 1234567',
      'kk': 'AA 1234567',
    },
    'courier.verification.passport_helper': {
      'uz': '2 harf + 7 raqam',
      'ru': '2 буквы + 7 цифр',
      'en': '2 letters + 7 digits',
      'kk': '2 әріп + 7 сан',
    },
    'courier.verification.doc_photos_title': {
      'uz': 'Hujjat fotosuratlari',
      'ru': 'Фото документов',
      'en': 'Document photos',
      'kk': 'Құжат суреттері',
    },
    'courier.verification.doc_photos_subtitle': {
      'uz': "Har bir hujjat aniq va to'liq ko'rinadigan bo'lsin",
      'ru': 'Каждый документ должен быть чётко и полностью виден',
      'en': 'Each document should be clear and fully visible',
      'kk': 'Әр құжат анық және толық көрінуі керек',
    },
    'courier.verification.docs_load_error': {
      'uz': "Hujjatlarni yuklab bo'lmadi",
      'ru': 'Не удалось загрузить документы',
      'en': 'Could not load documents',
      'kk': 'Құжаттарды жүктеу мүмкін болмады',
    },
    'courier.verification.privacy_note': {
      'uz': "Ma'lumotlaringiz shifrlangan holda saqlanadi va faqat tekshirish uchun ishlatiladi.",
      'ru': 'Ваши данные хранятся в зашифрованном виде и используются только для проверки.',
      'en': 'Your data is stored encrypted and used only for verification.',
      'kk': 'Деректеріңіз шифрланған түрде сақталады және тек тексеру үшін пайдаланылады.',
    },
    'courier.verification.doc_passport_front': {
      'uz': 'Pasport (old tomoni)',
      'ru': 'Паспорт (лицевая сторона)',
      'en': 'Passport (front)',
      'kk': 'Паспорт (алдыңғы жағы)',
    },
    'courier.verification.doc_passport_back': {
      'uz': 'Pasport (orqa tomoni)',
      'ru': 'Паспорт (обратная сторона)',
      'en': 'Passport (back)',
      'kk': 'Паспорт (артқы жағы)',
    },
    'courier.verification.doc_selfie': {
      'uz': 'Selfie pasport bilan',
      'ru': 'Селфи с паспортом',
      'en': 'Selfie with passport',
      'kk': 'Паспортпен селфи',
    },
    'courier.verification.doc_self_employed_cert': {
      'uz': "Samozanyatiy ma'lumotnomasi",
      'ru': 'Справка самозанятого',
      'en': 'Self-employed certificate',
      'kk': 'Өзін-өзі жұмыспен қамту анықтамасы',
    },
    'courier.verification.status_not_uploaded': {
      'uz': 'Yuklanmagan',
      'ru': 'Не загружено',
      'en': 'Not uploaded',
      'kk': 'Жүктелмеген',
    },
    'courier.verification.status_approved': {
      'uz': '✓ Tasdiqlangan',
      'ru': '✓ Подтверждено',
      'en': '✓ Approved',
      'kk': '✓ Расталды',
    },
    'courier.verification.status_rejected': {
      'uz': '✗ Rad etilgan',
      'ru': '✗ Отклонено',
      'en': '✗ Rejected',
      'kk': '✗ Қабылданбады',
    },
    'courier.verification.status_pending': {
      'uz': '⏳ Tekshirilmoqda',
      'ru': '⏳ На проверке',
      'en': '⏳ Pending',
      'kk': '⏳ Тексерілуде',
    },
    'courier.verification.self_emp_title': {
      'uz': "O'z-o'zini band qilish",
      'ru': 'Самозанятость',
      'en': 'Self-employment',
      'kk': 'Өзін-өзі жұмыспен қамту',
    },
    'courier.verification.self_emp_body': {
      'uz': "O'zbekistonda kuryer sifatida ishlash uchun o'z-o'zini band qilgan (самозанятый) maqomiga ega bo'lishingiz kerak.",
      'ru': 'Чтобы работать курьером в Узбекистане, нужно иметь статус самозанятого.',
      'en': 'To work as a courier in Uzbekistan you must have self-employed status.',
      'kk': 'Өзбекстанда курьер болып жұмыс істеу үшін өзін-өзі жұмыспен қамтыған мәртебесі болуы керек.',
    },
    'courier.verification.self_emp_step1_title': {
      'uz': 'my.soliq.uz saytiga kiring',
      'ru': 'Перейдите на сайт my.soliq.uz',
      'en': 'Visit my.soliq.uz',
      'kk': 'my.soliq.uz сайтына кіріңіз',
    },
    'courier.verification.self_emp_step1_subtitle': {
      'uz': "Soliq qo'mitasining rasmiy portali",
      'ru': 'Официальный портал налогового комитета',
      'en': 'Official tax authority portal',
      'kk': 'Салық комитетінің ресми порталы',
    },
    'courier.verification.self_emp_step2_title': {
      'uz': "\"O'z-o'zini band qilish\" bo'limini toping",
      'ru': 'Найдите раздел «Самозанятость»',
      'en': 'Find the "Self-employment" section',
      'kk': '«Өзін-өзі жұмыспен қамту» бөлімін табыңыз',
    },
    'courier.verification.self_emp_step2_subtitle': {
      'uz': "Ro'yxatdan o'tish bepul va tezkor",
      'ru': 'Регистрация бесплатная и быстрая',
      'en': 'Registration is free and quick',
      'kk': 'Тіркелу тегін және жылдам',
    },
    'courier.verification.self_emp_step3_title': {
      'uz': 'Ariza toldiring',
      'ru': 'Заполните заявление',
      'en': 'Fill out the application',
      'kk': 'Өтінішті толтырыңыз',
    },
    'courier.verification.self_emp_step3_subtitle': {
      'uz': "Daromaddan 1% soliq — tovar aylanmasi 1 mlrd so'mgacha",
      'ru': '1% налог с дохода — оборот до 1 млрд сум',
      'en': '1% tax on income — turnover up to 1 bn UZS',
      'kk': 'Кірістен 1% салық — айналым 1 млрд сомға дейін',
    },
    'courier.verification.self_emp_confirm': {
      'uz': "Men o'z-o'zini band qilgan maqomiga egaman yoki uni olishga roziman",
      'ru': 'У меня есть статус самозанятого или я согласен(а) его получить',
      'en': 'I have self-employed status or I agree to get it',
      'kk': 'Менде өзін-өзі жұмыспен қамтыған мәртебесі бар немесе оны алуға келісемін',
    },

    // ── Phase 13.2 — Shop settings ───────────────────────────────────────
    'shop_settings.title': {
      'uz': "Do'kon sozlamalari",
      'ru': 'Настройки магазина',
      'en': 'Shop settings',
      'kk': 'Дүкен баптаулары',
    },
    'shop_settings.tab_hours': {
      'uz': 'Ish vaqti',
      'ru': 'Часы работы',
      'en': 'Working hours',
      'kk': 'Жұмыс уақыты',
    },
    'shop_settings.tab_settings': {
      'uz': 'Sozlamalar',
      'ru': 'Настройки',
      'en': 'Settings',
      'kk': 'Баптаулар',
    },
    'shop_settings.shop_not_found': {
      'uz': "Do'kon topilmadi",
      'ru': 'Магазин не найден',
      'en': 'Shop not found',
      'kk': 'Дүкен табылмады',
    },
    'shop_settings.saved': {
      'uz': '✅ Ish vaqti saqlandi',
      'ru': '✅ Часы работы сохранены',
      'en': '✅ Working hours saved',
      'kk': '✅ Жұмыс уақыты сақталды',
    },
    'shop_settings.error_prefix': {
      'uz': 'Xatolik',
      'ru': 'Ошибка',
      'en': 'Error',
      'kk': 'Қате',
    },
    'shop_settings.open_label': {
      'uz': 'Ochiq',
      'ru': 'Открыто',
      'en': 'Open',
      'kk': 'Ашық',
    },
    'shop_settings.closed_label': {
      'uz': 'Yopiq',
      'ru': 'Закрыто',
      'en': 'Closed',
      'kk': 'Жабық',
    },
    'shop_settings.opens_at': {
      'uz': 'Ochilish',
      'ru': 'Открытие',
      'en': 'Opens',
      'kk': 'Ашылу',
    },
    'shop_settings.closes_at': {
      'uz': 'Yopilish',
      'ru': 'Закрытие',
      'en': 'Closes',
      'kk': 'Жабылу',
    },
    'shop_settings.currency_title': {
      'uz': 'Valyuta',
      'ru': 'Валюта',
      'en': 'Currency',
      'kk': 'Валюта',
    },
    'shop_settings.currency_uzs': {
      'uz': "UZS — so'm",
      'ru': 'UZS — сум',
      'en': 'UZS — som',
      'kk': 'UZS — сом',
    },
    'shop_settings.currency_phase7_note': {
      'uz': 'KZT / KGS — Phase 7da faollashadi',
      'ru': 'KZT / KGS — будут активированы в Phase 7',
      'en': 'KZT / KGS — activated in Phase 7',
      'kk': 'KZT / KGS — Phase 7 кезінде іске қосылады',
    },
    'shop_settings.notifications_title': {
      'uz': 'Bildirishnomalar',
      'ru': 'Уведомления',
      'en': 'Notifications',
      'kk': 'Хабарламалар',
    },
    'shop_settings.notifications_body': {
      'uz': 'Yangi buyurtmalar push + ovoz orqali keladi',
      'ru': 'Новые заказы приходят через push + звук',
      'en': 'New orders arrive via push + sound',
      'kk': 'Жаңа тапсырыстар push + дыбыс арқылы келеді',
    },

    // Day names
    'day.sunday': {
      'uz': 'Yakshanba',
      'ru': 'Воскресенье',
      'en': 'Sunday',
      'kk': 'Жексенбі',
    },
    'day.monday': {
      'uz': 'Dushanba',
      'ru': 'Понедельник',
      'en': 'Monday',
      'kk': 'Дүйсенбі',
    },
    'day.tuesday': {
      'uz': 'Seshanba',
      'ru': 'Вторник',
      'en': 'Tuesday',
      'kk': 'Сейсенбі',
    },
    'day.wednesday': {
      'uz': 'Chorshanba',
      'ru': 'Среда',
      'en': 'Wednesday',
      'kk': 'Сәрсенбі',
    },
    'day.thursday': {
      'uz': 'Payshanba',
      'ru': 'Четверг',
      'en': 'Thursday',
      'kk': 'Бейсенбі',
    },
    'day.friday': {
      'uz': 'Juma',
      'ru': 'Пятница',
      'en': 'Friday',
      'kk': 'Жұма',
    },
    'day.saturday': {
      'uz': 'Shanba',
      'ru': 'Суббота',
      'en': 'Saturday',
      'kk': 'Сенбі',
    },

    // ── Phase 13.2 — Courier home extras ─────────────────────────────────
    'courier.shift_on': {
      'uz': 'Smenadaman',
      'ru': 'Я на смене',
      'en': 'On shift',
      'kk': 'Сменадамын',
    },
    'courier.shift_off': {
      'uz': 'Smenada emasman',
      'ru': 'Не на смене',
      'en': 'Off duty',
      'kk': 'Сменада емеспін',
    },
    'courier.offline_title': {
      'uz': 'Siz oflayn rejimdasiz',
      'ru': 'Вы офлайн',
      'en': 'You are offline',
      'kk': 'Сіз желіде емессіз',
    },
    'courier.offline_subtitle': {
      'uz': 'Buyurtma olish uchun smenani boshlang',
      'ru': 'Начните смену, чтобы получать заказы',
      'en': 'Start your shift to receive orders',
      'kk': 'Тапсырыс алу үшін сменаны бастаңыз',
    },
    'courier.waiting_active': {
      'uz': 'Joriy buyurtmani yetkazing',
      'ru': 'Доставьте текущий заказ',
      'en': 'Deliver your active order',
      'kk': 'Ағымдағы тапсырысты жеткізіңіз',
    },
    'courier.waiting_idle': {
      'uz': 'Buyurtmalar kutilmoqda...',
      'ru': 'Ожидаем заказы...',
      'en': 'Waiting for orders...',
      'kk': 'Тапсырыстар күтілуде...',
    },
    'courier.waiting_subtitle': {
      'uz': 'Yangi taklif kelganda sizga xabar beramiz',
      'ru': 'Сообщим, когда придёт новое предложение',
      'en': 'We\'ll notify you when a new offer arrives',
      'kk': 'Жаңа ұсыныс келгенде хабарлаймыз',
    },

    // ── Phase 13.2 — Cart screen literals ─────────────────────────────────
    'cart.eta_short': {
      'uz': '~{minutes} daqiqada yetkaziladi',
      'ru': 'Доставка через ~{minutes} мин',
      'en': 'Delivery in ~{minutes} min',
      'kk': '~{minutes} мин ішінде жеткізіледі',
    },
    'cart.distance_short': {
      'uz': '{km} km',
      'ru': '{km} км',
      'en': '{km} km',
      'kk': '{km} км',
    },
    'cart.min_order_subtitle': {
      'uz': 'Minimal buyurtma {amount}',
      'ru': 'Минимальный заказ {amount}',
      'en': 'Minimum order {amount}',
      'kk': 'Минималды тапсырыс {amount}',
    },

    // ── Phase 13.2 — Auth fallback errors ────────────────────────────────
    'login.send_otp_failed': {
      'uz': 'Xatolik',
      'ru': 'Ошибка',
      'en': 'Error',
      'kk': 'Қате',
    },
    'otp.invalid_code': {
      'uz': "Noto'g'ri kod",
      'ru': 'Неверный код',
      'en': 'Invalid code',
      'kk': 'Қате код',
    },
    'otp.prototype_hint': {
      'uz': "Prototip: 123456 kodidan foydalaning",
      'ru': 'Прототип: используйте код 123456',
      'en': 'Prototype: use code 123456',
      'kk': 'Прототип: 123456 кодын пайдаланыңыз',
    },

    // ── Phase 13.2.3 — Role selection (first-run after OTP / onboarding) ───
    'role_select.title': {
      'uz': 'Qanday foydalanasiz?',
      'ru': 'Как будете пользоваться?',
      'en': 'How will you use the app?',
      'kk': 'Қалай қолданасыз?',
    },
    'role_select.subtitle': {
      'uz': 'Sizga mos rejimni tanlang. Keyin profil orqali almashtirish mumkin.',
      'ru': 'Выберите подходящий режим. Позже его можно сменить в профиле.',
      'en': 'Pick a mode that fits you. You can switch later from the profile.',
      'kk': 'Өзіңізге қолайлы режимді таңдаңыз. Кейін профильден ауыстыруға болады.',
    },
    'role_select.buyer_desc': {
      'uz': 'Mahsulot va ovqat buyurtma qiling, eshikgacha yetkazib beramiz.',
      'ru': 'Заказывайте товары и еду — доставим до двери.',
      'en': 'Order groceries and food, delivered to your door.',
      'kk': 'Тауар мен тағам тапсырыс беріңіз — есікке дейін жеткіземіз.',
    },
    'role_select.courier_desc': {
      'uz': 'Buyurtma yetkazib daromad qiling — moslashuvchan jadval.',
      'ru': 'Доставляйте заказы и зарабатывайте — гибкий график.',
      'en': 'Earn by delivering orders on a flexible schedule.',
      'kk': 'Тапсырыс жеткізіп табыс табыңыз — икемді кесте.',
    },
    'role_select.shop_desc': {
      'uz': "Do'koningizni ulang va onlayn buyurtma qabul qiling.",
      'ru': 'Подключите свой магазин и принимайте онлайн-заказы.',
      'en': 'Connect your shop and start accepting online orders.',
      'kk': 'Дүкеніңізді қосып, онлайн тапсырыс қабылдаңыз.',
    },
    'role_select.switch_later_hint': {
      'uz': "Profil → \"Rejimni almashtirish\" orqali istalgan vaqtda almashtirishingiz mumkin.",
      'ru': 'Сменить режим можно в любой момент: Профиль → «Сменить режим».',
      'en': 'You can switch modes anytime from Profile → "Switch role".',
      'kk': 'Профиль → «Режимді ауыстыру» арқылы кез келген уақытта ауыстыруға болады.',
    },

    // ── Phase 13.2.3 — Courier onboarding (perks → KYC CTA) ────────────────
    'courier_onboarding.title': {
      'uz': "Kuryer bo'ling",
      'ru': 'Станьте курьером',
      'en': 'Become a courier',
      'kk': 'Курьер болыңыз',
    },
    'courier_onboarding.subtitle': {
      'uz': "Bo'sh vaqtingizda ishlang, har bir buyurtma uchun haq oling.",
      'ru': 'Работайте в свободное время и получайте оплату за каждый заказ.',
      'en': 'Work on your own schedule and get paid for every delivery.',
      'kk': 'Бос уақытыңызда жұмыс істеп, әр тапсырыс үшін ақы алыңыз.',
    },
    'courier_onboarding.perk1_title': {
      'uz': "Haftalik to'lovlar",
      'ru': 'Еженедельные выплаты',
      'en': 'Weekly payouts',
      'kk': 'Апта сайынғы төлемдер',
    },
    'courier_onboarding.perk1_body': {
      'uz': "Daromadingiz har hafta kartangizga o'tkaziladi. Tezkor yechib olish ham mavjud.",
      'ru': 'Заработок переводится на карту каждую неделю. Можно вывести мгновенно.',
      'en': 'Earnings hit your card every week, with instant cash-out available.',
      'kk': 'Табысыңыз картаңызға апта сайын аударылады. Жедел шығаруға болады.',
    },
    'courier_onboarding.perk2_title': {
      'uz': 'Moslashuvchan smenalar',
      'ru': 'Гибкий график',
      'en': 'Flexible shifts',
      'kk': 'Икемді ауысымдар',
    },
    'courier_onboarding.perk2_body': {
      'uz': "O'zingiz xohlagan vaqtda online bo'ling va buyurtma qabul qiling.",
      'ru': 'Выходите на смену когда удобно — заказы поступают автоматически.',
      'en': 'Go online whenever you want — orders are dispatched to you.',
      'kk': 'Қалаған уақытыңызда онлайн болып, тапсырыс қабылдаңыз.',
    },
    'courier_onboarding.perk3_title': {
      'uz': 'Sizning hududingizdagi buyurtmalar',
      'ru': 'Заказы рядом с вами',
      'en': 'Orders near you',
      'kk': 'Жаныңыздағы тапсырыстар',
    },
    'courier_onboarding.perk3_body': {
      'uz': "Eng yaqin yetkazib berishlar — kam vaqt, ko'p qatnov.",
      'ru': 'Получайте ближайшие заказы — меньше километров, больше доставок.',
      'en': 'Get the closest deliveries — less driving, more drops.',
      'kk': 'Ең жақын тапсырыстар — аз жол, көп жеткізу.',
    },
    'courier_onboarding.cta': {
      'uz': 'Kuryer sifatida ariza berish',
      'ru': 'Подать заявку курьера',
      'en': 'Apply as courier',
      'kk': 'Курьерге өтінім беру',
    },

    // ── Phase 13.2.3 — Shop onboarding (perks → settings/connect CTA) ──────
    'shop_onboarding.title': {
      'uz': "Do'koningizni ulang",
      'ru': 'Подключите свой магазин',
      'en': 'Bring your shop online',
      'kk': 'Дүкеніңізді қосыңыз',
    },
    'shop_onboarding.subtitle': {
      'uz': 'Onlayn buyurtmalarni qabul qiling, mahsulotlaringizni boshqaring.',
      'ru': 'Принимайте онлайн-заказы и управляйте каталогом из приложения.',
      'en': 'Accept online orders and manage your catalogue from one app.',
      'kk': 'Онлайн тапсырыс қабылдаңыз және каталогты қосымшадан басқарыңыз.',
    },
    'shop_onboarding.perk1_title': {
      'uz': 'Yagona buyurtma paneli',
      'ru': 'Единая панель заказов',
      'en': 'One inbox for orders',
      'kk': 'Тапсырыстарға арналған бір тақта',
    },
    'shop_onboarding.perk1_body': {
      'uz': 'Yangi buyurtmalar, tayyorlash holati va kuryer biriktirish — bir ekranda.',
      'ru': 'Новые заказы, статус сборки и закрепление курьера — на одном экране.',
      'en': 'New orders, prep state and courier handoff — all in one place.',
      'kk': 'Жаңа тапсырыстар, дайындық күйі және курьер тағайындау — бір экранда.',
    },
    'shop_onboarding.perk2_title': {
      'uz': "O'sish hisobotlari",
      'ru': 'Отчёты по росту',
      'en': 'Growth reports',
      'kk': 'Өсу есептері',
    },
    'shop_onboarding.perk2_body': {
      'uz': "Sotuv, top mahsulotlar va o'rtacha chek — ko'rgazmali grafiklarda.",
      'ru': 'Выручка, топ-товары, средний чек — в наглядных графиках.',
      'en': 'Revenue, best-sellers and average cheque — in clear charts.',
      'kk': 'Кіріс, ең көп сатылатын тауарлар, орташа чек — кестелерде.',
    },
    'shop_onboarding.perk3_title': {
      'uz': "Tezkor to'lovlar",
      'ru': 'Быстрые выплаты',
      'en': 'Fast payouts',
      'kk': 'Жылдам төлемдер',
    },
    'shop_onboarding.perk3_body': {
      'uz': "Tushumlar haftalik tarzda do'kon hisobiga o'tkaziladi.",
      'ru': 'Выплаты на счёт магазина — еженедельно.',
      'en': 'Payouts settle to your shop account every week.',
      'kk': 'Төлемдер дүкен шотына апта сайын түседі.',
    },
    'shop_onboarding.cta_create': {
      'uz': "Do'kon yaratish",
      'ru': 'Создать магазин',
      'en': 'Create your shop',
      'kk': 'Дүкен жасау',
    },
    'shop_onboarding.cta_open_dashboard': {
      'uz': "Do'kon paneliga o'tish",
      'ru': 'Открыть панель магазина',
      'en': 'Open shop dashboard',
      'kk': 'Дүкен панелін ашу',
    },

    // ── Phase 13.2.4 — KYC re-upload (rejected documents) ──────────────────
    'kyc.reupload_cta': {
      'uz': 'Qayta yuklash',
      'ru': 'Загрузить заново',
      'en': 'Re-upload',
      'kk': 'Қайта жүктеу',
    },
    'kyc.reupload_success': {
      'uz': 'Hujjat qayta yuklandi — qayta tekshiriladi',
      'ru': 'Документ загружен повторно — снова на проверке',
      'en': 'Document re-uploaded — pending review',
      'kk': 'Құжат қайта жүктелді — қайта тексеріледі',
    },
    'kyc.rejection_generic': {
      'uz': 'Hujjat rad etildi. Iltimos, qayta yuklang.',
      'ru': 'Документ отклонён. Пожалуйста, загрузите заново.',
      'en': 'Document rejected. Please re-upload.',
      'kk': 'Құжат қабылданбады. Қайта жүктеңіз.',
    },

    // ── Phase 13.2.8 — Courier heatmap full screen ─────────────────────────
    'heatmap.screen_title': {
      'uz': 'Talab xaritasi',
      'ru': 'Карта спроса',
      'en': 'Demand heatmap',
      'kk': 'Сұраныс картасы',
    },
    'heatmap.refresh': {
      'uz': 'Yangilash',
      'ru': 'Обновить',
      'en': 'Refresh',
      'kk': 'Жаңарту',
    },
    'heatmap.loading': {
      'uz': 'Yuklanmoqda...',
      'ru': 'Загружается...',
      'en': 'Loading...',
      'kk': 'Жүктелуде...',
    },
    'heatmap.empty_title': {
      'uz': 'Hozir issiq nuqtalar yo\'q',
      'ru': 'Сейчас нет горячих зон',
      'en': 'No hot zones right now',
      'kk': 'Қазір ыстық аймақтар жоқ',
    },
    'heatmap.empty_subtitle': {
      'uz': 'Soatiga bir necha marta tekshiring',
      'ru': 'Проверяйте чаще — спрос меняется',
      'en': 'Check back soon — demand changes hourly',
      'kk': 'Жиі тексеріңіз — сұраныс өзгеріп тұрады',
    },
    'heatmap.high_demand_card': {
      'uz': '🔥 Yuqori talab — hozir boring (+30% bonus)',
      'ru': '🔥 Высокий спрос — выезжайте сейчас (+30% к оплате)',
      'en': '🔥 High demand — go now for +30% pay multiplier',
      'kk': '🔥 Жоғары сұраныс — қазір барыңыз (+30% бонус)',
    },
    'heatmap.medium_demand_card': {
      'uz': 'O\'rtacha talab',
      'ru': 'Средний спрос',
      'en': 'Medium demand',
      'kk': 'Орташа сұраныс',
    },
    'heatmap.low_demand_card': {
      'uz': 'Past talab',
      'ru': 'Низкий спрос',
      'en': 'Low demand',
      'kk': 'Төмен сұраныс',
    },
    'heatmap.orders_count': {
      'uz': '{count} buyurtma',
      'ru': '{count} заказов',
      'en': '{count} orders',
      'kk': '{count} тапсырыс',
    },
    'heatmap.open_directions': {
      'uz': 'Yo\'lni ko\'rsatish',
      'ru': 'Открыть маршрут',
      'en': 'Open directions',
      'kk': 'Бағытты ашу',
    },
    'heatmap.legend_high': {
      'uz': 'Yuqori',
      'ru': 'Высокий',
      'en': 'High',
      'kk': 'Жоғары',
    },
    'heatmap.legend_medium': {
      'uz': 'O\'rta',
      'ru': 'Средний',
      'en': 'Medium',
      'kk': 'Орта',
    },
    'heatmap.legend_low': {
      'uz': 'Past',
      'ru': 'Низкий',
      'en': 'Low',
      'kk': 'Төмен',
    },
    'heatmap.refresh_failed': {
      'uz': 'Yangilab bo\'lmadi — qaytadan urinib ko\'ring',
      'ru': 'Не удалось обновить — попробуйте снова',
      'en': 'Refresh failed — try again',
      'kk': 'Жаңарту сәтсіз болды — қайталап көріңіз',
    },

    // ── Phase 13.2.6 — Common shared strings used by new shop screens ──────
    'common.refresh': {
      'uz': 'Yangilash',
      'ru': 'Обновить',
      'en': 'Refresh',
      'kk': 'Жаңарту',
    },
    // `common.cancel` / `common.error` are defined near the top of the map
    // — keeping the canonical definition there avoids the const-Map
    // duplicate-key warning that Dart 3 promotes to an error.
    'common.delete': {
      'uz': "O'chirish",
      'ru': 'Удалить',
      'en': 'Delete',
      'kk': 'Өшіру',
    },
    'common.currency_uzs': {
      'uz': "so'm",
      'ru': 'сум',
      'en': 'UZS',
      'kk': 'сом',
    },

    // ── Phase 13.2.6 — Shop refunds screen ─────────────────────────────────
    'shop.refunds.title': {
      'uz': 'Qaytarish so\'rovlari',
      'ru': 'Запросы на возврат',
      'en': 'Refund requests',
      'kk': 'Қайтару сұраулары',
    },
    'shop.refunds.subtitle': {
      'uz': 'Buyurtmalar bo\'yicha nizolarni hal qilish',
      'ru': 'Разрешение споров по заказам',
      'en': 'Resolve buyer disputes',
      'kk': 'Тапсырыстар бойынша даулар',
    },
    'shop.refunds.empty': {
      'uz': "Hozircha so'rovlar yo'q",
      'ru': 'Пока нет запросов',
      'en': 'No refund requests yet',
      'kk': 'Әзірге сұраулар жоқ',
    },
    'shop.refunds.no_shop': {
      'uz': "Do'kon ulanmagan",
      'ru': 'Магазин не подключён',
      'en': 'No shop connected',
      'kk': 'Дүкен қосылмаған',
    },
    'shop.refunds.filter_open': {
      'uz': 'Ochiq',
      'ru': 'Открытые',
      'en': 'Open',
      'kk': 'Ашық',
    },
    'shop.refunds.filter_resolved': {
      'uz': 'Hal qilingan',
      'ru': 'Решённые',
      'en': 'Resolved',
      'kk': 'Шешілген',
    },
    'shop.refunds.filter_rejected': {
      'uz': 'Rad etilgan',
      'ru': 'Отклонённые',
      'en': 'Rejected',
      'kk': 'Қабылданбаған',
    },
    'shop.refunds.filter_all': {
      'uz': 'Hammasi',
      'ru': 'Все',
      'en': 'All',
      'kk': 'Барлығы',
    },
    'shop.refunds.status_open': {
      'uz': 'Ochiq',
      'ru': 'Открыт',
      'en': 'Open',
      'kk': 'Ашық',
    },
    'shop.refunds.status_under_review': {
      'uz': 'Tekshirilmoqda',
      'ru': 'На проверке',
      'en': 'Under review',
      'kk': 'Тексеруде',
    },
    'shop.refunds.status_resolved': {
      'uz': 'Hal qilingan',
      'ru': 'Решён',
      'en': 'Resolved',
      'kk': 'Шешілген',
    },
    'shop.refunds.status_rejected': {
      'uz': 'Rad etilgan',
      'ru': 'Отклонён',
      'en': 'Rejected',
      'kk': 'Қабылданбаған',
    },
    'shop.refunds.reason_missing_items': {
      'uz': 'Mahsulot yetishmaydi',
      'ru': 'Не хватает товаров',
      'en': 'Missing items',
      'kk': 'Тауар жетіспейді',
    },
    'shop.refunds.reason_wrong_items': {
      'uz': "Noto'g'ri mahsulot",
      'ru': 'Не тот товар',
      'en': 'Wrong items',
      'kk': 'Қате тауар',
    },
    'shop.refunds.reason_late': {
      'uz': 'Kechikish',
      'ru': 'Опоздание',
      'en': 'Late delivery',
      'kk': 'Кешігу',
    },
    'shop.refunds.reason_damaged': {
      'uz': 'Shikastlangan',
      'ru': 'Повреждён',
      'en': 'Damaged',
      'kk': 'Зақымдалған',
    },
    'shop.refunds.reason_other': {
      'uz': 'Boshqa',
      'ru': 'Другое',
      'en': 'Other',
      'kk': 'Басқа',
    },
    'shop.refunds.already_refunded': {
      'uz': 'Qaytarilgan',
      'ru': 'Возвращено',
      'en': 'Refunded',
      'kk': 'Қайтарылды',
    },
    'shop.refunds.detail_title': {
      'uz': "Qaytarish so'rovi",
      'ru': 'Запрос возврата',
      'en': 'Refund request',
      'kk': 'Қайтару сұрауы',
    },
    'shop.refunds.order_section': {
      'uz': 'Buyurtma',
      'ru': 'Заказ',
      'en': 'Order',
      'kk': 'Тапсырыс',
    },
    'shop.refunds.order_id': {
      'uz': 'Buyurtma raqami',
      'ru': 'Номер заказа',
      'en': 'Order #',
      'kk': 'Тапсырыс №',
    },
    'shop.refunds.customer': {
      'uz': 'Mijoz',
      'ru': 'Клиент',
      'en': 'Customer',
      'kk': 'Тұтынушы',
    },
    'shop.refunds.amount': {
      'uz': 'Summa',
      'ru': 'Сумма',
      'en': 'Amount',
      'kk': 'Сома',
    },
    'shop.refunds.reason_section': {
      'uz': 'Sabab',
      'ru': 'Причина',
      'en': 'Reason',
      'kk': 'Себеп',
    },
    'shop.refunds.reason': {
      'uz': 'Sabab',
      'ru': 'Причина',
      'en': 'Reason',
      'kk': 'Себеп',
    },
    'shop.refunds.resolution_section': {
      'uz': 'Yechim',
      'ru': 'Решение',
      'en': 'Resolution',
      'kk': 'Шешім',
    },
    'shop.refunds.status': {
      'uz': 'Status',
      'ru': 'Статус',
      'en': 'Status',
      'kk': 'Күй',
    },
    'shop.refunds.action': {
      'uz': 'Harakat',
      'ru': 'Действие',
      'en': 'Action',
      'kk': 'Әрекет',
    },
    'shop.refunds.note': {
      'uz': 'Izoh',
      'ru': 'Комментарий',
      'en': 'Note',
      'kk': 'Ескерту',
    },
    'shop.refunds.note_hint': {
      'uz': 'Mijoz uchun qisqacha izoh',
      'ru': 'Краткое пояснение для клиента',
      'en': 'Short note for the customer',
      'kk': 'Тұтынушыға қысқа түсіндірме',
    },
    'shop.refunds.action_section': {
      'uz': 'Qaror',
      'ru': 'Решение',
      'en': 'Decision',
      'kk': 'Шешім',
    },
    'shop.refunds.partial': {
      'uz': 'Qisman qaytarish',
      'ru': 'Частичный возврат',
      'en': 'Partial refund',
      'kk': 'Ішінара қайтару',
    },
    'shop.refunds.partial_help': {
      'uz': "Buyurtma summasidan kichik miqdorni qaytarish",
      'ru': 'Вернуть меньше полной суммы заказа',
      'en': 'Refund less than the full order total',
      'kk': 'Тапсырыс сомасынан аз қайтару',
    },
    'shop.refunds.refund_amount': {
      'uz': 'Qaytarish summasi',
      'ru': 'Сумма возврата',
      'en': 'Refund amount',
      'kk': 'Қайтару сомасы',
    },
    'shop.refunds.amount_invalid': {
      'uz': "Summa noto'g'ri",
      'ru': 'Неверная сумма',
      'en': 'Invalid amount',
      'kk': 'Сома қате',
    },
    'shop.refunds.approve': {
      'uz': 'Tasdiqlash',
      'ru': 'Одобрить',
      'en': 'Approve',
      'kk': 'Растау',
    },
    'shop.refunds.reject': {
      'uz': 'Rad etish',
      'ru': 'Отклонить',
      'en': 'Reject',
      'kk': 'Қабылдамау',
    },
    'shop.refunds.success': {
      'uz': "Qaror saqlandi",
      'ru': 'Решение сохранено',
      'en': 'Decision saved',
      'kk': 'Шешім сақталды',
    },
    'shop.refunds.resolution_refund': {
      'uz': "To'liq qaytarish",
      'ru': 'Полный возврат',
      'en': 'Full refund',
      'kk': 'Толық қайтару',
    },
    'shop.refunds.resolution_partial_refund': {
      'uz': 'Qisman qaytarish',
      'ru': 'Частичный возврат',
      'en': 'Partial refund',
      'kk': 'Ішінара қайтару',
    },
    'shop.refunds.resolution_replacement': {
      'uz': 'Almashtirish',
      'ru': 'Замена',
      'en': 'Replacement',
      'kk': 'Алмастыру',
    },
    'shop.refunds.resolution_rejected': {
      'uz': 'Rad etildi',
      'ru': 'Отклонено',
      'en': 'Rejected',
      'kk': 'Қабылданбады',
    },
    'shop.refunds.resolution_no_action': {
      'uz': 'Harakat yo\'q',
      'ru': 'Без действий',
      'en': 'No action',
      'kk': 'Әрекетсіз',
    },

    // ── Phase 13.2.6 — Shop promo / coupons screen ─────────────────────────
    'shop.promo.title': {
      'uz': 'Promokodlar',
      'ru': 'Промокоды',
      'en': 'Promo codes',
      'kk': 'Промокодтар',
    },
    'shop.promo.subtitle': {
      'uz': 'Chegirma kuponlarini boshqarish',
      'ru': 'Управление скидочными купонами',
      'en': 'Manage discount coupons',
      'kk': 'Жеңілдік купондарын басқару',
    },
    'shop.promo.no_shop': {
      'uz': "Do'kon ulanmagan",
      'ru': 'Магазин не подключён',
      'en': 'No shop connected',
      'kk': 'Дүкен қосылмаған',
    },
    'shop.promo.empty': {
      'uz': "Promokodlar yo'q",
      'ru': 'Промокодов нет',
      'en': 'No promo codes',
      'kk': 'Промокодтар жоқ',
    },
    'shop.promo.empty_hint': {
      'uz': "Birinchi kuponni yaratish uchun '+' tugmasini bosing",
      'ru': 'Нажмите «+», чтобы создать первый купон',
      'en': 'Tap "+" to create your first coupon',
      'kk': 'Алғашқы купонды жасау үшін «+» басыңыз',
    },
    'shop.promo.create': {
      'uz': 'Yaratish',
      'ru': 'Создать',
      'en': 'Create',
      'kk': 'Жасау',
    },
    'shop.promo.create_title': {
      'uz': 'Yangi promokod',
      'ru': 'Новый промокод',
      'en': 'New promo code',
      'kk': 'Жаңа промокод',
    },
    'shop.promo.edit_title': {
      'uz': 'Promokodni tahrirlash',
      'ru': 'Редактировать промокод',
      'en': 'Edit promo code',
      'kk': 'Промокодты өңдеу',
    },
    'shop.promo.save': {
      'uz': 'Saqlash',
      'ru': 'Сохранить',
      'en': 'Save',
      'kk': 'Сақтау',
    },
    'shop.promo.active': {
      'uz': 'Faol',
      'ru': 'Активен',
      'en': 'Active',
      'kk': 'Белсенді',
    },
    'shop.promo.inactive': {
      'uz': 'Faol emas',
      'ru': 'Не активен',
      'en': 'Inactive',
      'kk': 'Белсенді емес',
    },
    'shop.promo.expired': {
      'uz': 'Muddati tugagan',
      'ru': 'Просрочен',
      'en': 'Expired',
      'kk': 'Мерзімі өткен',
    },
    'shop.promo.activate': {
      'uz': 'Yoqish',
      'ru': 'Включить',
      'en': 'Activate',
      'kk': 'Қосу',
    },
    'shop.promo.deactivate': {
      'uz': "O'chirish",
      'ru': 'Выключить',
      'en': 'Deactivate',
      'kk': 'Сөндіру',
    },
    'shop.promo.code': {
      'uz': 'Kod',
      'ru': 'Код',
      'en': 'Code',
      'kk': 'Код',
    },
    'shop.promo.generate': {
      'uz': 'Tasodifiy yaratish',
      'ru': 'Сгенерировать',
      'en': 'Generate random',
      'kk': 'Кездейсоқ жасау',
    },
    'shop.promo.type': {
      'uz': 'Chegirma turi',
      'ru': 'Тип скидки',
      'en': 'Discount type',
      'kk': 'Жеңілдік түрі',
    },
    'shop.promo.type_percent': {
      'uz': 'Foiz (%)',
      'ru': 'Процент (%)',
      'en': 'Percent (%)',
      'kk': 'Пайыз (%)',
    },
    'shop.promo.type_fixed': {
      'uz': "Belgilangan summa",
      'ru': 'Фиксированная сумма',
      'en': 'Fixed amount',
      'kk': 'Тіркелген сома',
    },
    'shop.promo.type_free_delivery': {
      'uz': "Yetkazib berish bepul",
      'ru': 'Бесплатная доставка',
      'en': 'Free delivery',
      'kk': 'Тегін жеткізу',
    },
    'shop.promo.value_percent': {
      'uz': 'Foiz qiymati',
      'ru': 'Размер скидки',
      'en': 'Percent value',
      'kk': 'Пайыз мөлшері',
    },
    'shop.promo.value_fixed': {
      'uz': 'Chegirma summasi',
      'ru': 'Сумма скидки',
      'en': 'Discount amount',
      'kk': 'Жеңілдік сомасы',
    },
    'shop.promo.min_order': {
      'uz': 'Minimal buyurtma',
      'ru': 'Минимальный заказ',
      'en': 'Minimum order',
      'kk': 'Ең аз тапсырыс',
    },
    'shop.promo.min_order_help': {
      'uz': "Bo'sh — cheklov yo'q",
      'ru': 'Пусто — без ограничений',
      'en': 'Empty — no minimum',
      'kk': 'Бос — шектеусіз',
    },
    'shop.promo.max_discount': {
      'uz': 'Maksimal chegirma',
      'ru': 'Максимальная скидка',
      'en': 'Max discount',
      'kk': 'Ең көп жеңілдік',
    },
    'shop.promo.max_discount_help': {
      'uz': "Bo'sh — cheklov yo'q",
      'ru': 'Пусто — без ограничений',
      'en': 'Empty — no cap',
      'kk': 'Бос — шектеусіз',
    },
    'shop.promo.usage_limit': {
      'uz': 'Foydalanish chegarasi',
      'ru': 'Лимит использований',
      'en': 'Usage limit',
      'kk': 'Қолдану шегі',
    },
    'shop.promo.usage_limit_help': {
      'uz': "Bo'sh — cheksiz",
      'ru': 'Пусто — без лимита',
      'en': 'Empty — unlimited',
      'kk': 'Бос — шексіз',
    },
    'shop.promo.valid_from': {
      'uz': 'Boshlanish sanasi',
      'ru': 'Дата начала',
      'en': 'Valid from',
      'kk': 'Бастау күні',
    },
    'shop.promo.valid_until': {
      'uz': 'Tugash sanasi',
      'ru': 'Дата окончания',
      'en': 'Valid until',
      'kk': 'Аяқтау күні',
    },
    'shop.promo.is_active': {
      'uz': 'Faol',
      'ru': 'Активен',
      'en': 'Active',
      'kk': 'Белсенді',
    },
    'shop.promo.uses': {
      'uz': 'foydalanildi',
      'ru': 'использовано',
      'en': 'uses',
      'kk': 'қолданыс',
    },
    'shop.promo.delete_confirm_title': {
      'uz': "Promokodni o'chirish?",
      'ru': 'Удалить промокод?',
      'en': 'Delete promo code?',
      'kk': 'Промокодты өшіру?',
    },
    'shop.promo.delete_confirm_body': {
      'uz': "Bu amalni qaytarib bo'lmaydi. Agar kupon ishlatilgan bo'lsa, faqat o'chirib qo'yiladi.",
      'ru': 'Действие необратимо. Если купон уже использовался, он будет деактивирован.',
      'en': 'This cannot be undone. If the coupon was redeemed it will be deactivated instead.',
      'kk': 'Әрекет қайтарылмайды. Егер купон қолданылған болса, тек өшіріледі.',
    },
    'shop.promo.error_code': {
      'uz': 'Kod kamida 3 belgidan iborat',
      'ru': 'Код должен содержать не менее 3 символов',
      'en': 'Code must be at least 3 characters',
      'kk': 'Код кемінде 3 таңбадан',
    },
    'shop.promo.error_value': {
      'uz': "Qiymat 0 dan katta bo'lishi kerak",
      'ru': 'Значение должно быть больше 0',
      'en': 'Value must be greater than 0',
      'kk': 'Мән 0-ден жоғары болуы керек',
    },
    'shop.promo.error_percent_range': {
      'uz': '1 dan 100 gacha qiymat kiriting',
      'ru': 'Введите значение от 1 до 100',
      'en': 'Enter a value between 1 and 100',
      'kk': '1 мен 100 арасында мәнді енгізіңіз',
    },
    'shop.promo.error_dates': {
      'uz': "Tugash sanasi boshlanishdan keyin bo'lishi kerak",
      'ru': 'Дата окончания должна быть позже даты начала',
      'en': 'End date must be after start date',
      'kk': 'Аяқталу күні бастау күнінен кейін болуы керек',
    },

    // ── Phase 13.2.6 — Shop analytics screen ───────────────────────────────
    'shop.analytics.title': {
      'uz': 'Statistika',
      'ru': 'Аналитика',
      'en': 'Analytics',
      'kk': 'Статистика',
    },
    'shop.analytics.subtitle': {
      'uz': "Sotuvlar, top mahsulotlar va o'rtacha chek",
      'ru': 'Продажи, топ-товары и средний чек',
      'en': 'Sales, top products and average ticket',
      'kk': 'Сатылымдар, үздік тауарлар, орташа чек',
    },
    'shop.analytics.no_shop': {
      'uz': "Do'kon ulanmagan",
      'ru': 'Магазин не подключён',
      'en': 'No shop connected',
      'kk': 'Дүкен қосылмаған',
    },
    'shop.analytics.today': {
      'uz': 'Bugun',
      'ru': 'Сегодня',
      'en': 'Today',
      'kk': 'Бүгін',
    },
    'shop.analytics.week': {
      'uz': 'Hafta',
      'ru': 'Неделя',
      'en': 'This week',
      'kk': 'Апта',
    },
    'shop.analytics.month': {
      'uz': 'Oy',
      'ru': 'Месяц',
      'en': 'This month',
      'kk': 'Ай',
    },
    'shop.analytics.orders_short': {
      'uz': 'Buyurtma',
      'ru': 'Заказы',
      'en': 'Orders',
      'kk': 'Тапсырыс',
    },
    'shop.analytics.avg_ticket': {
      'uz': "O'rtacha chek",
      'ru': 'Средний чек',
      'en': 'Avg ticket',
      'kk': 'Орташа чек',
    },
    'shop.analytics.chart_title': {
      'uz': 'Kunlik buyurtmalar',
      'ru': 'Заказы по дням',
      'en': 'Daily orders',
      'kk': 'Күндік тапсырыстар',
    },
    'shop.analytics.chart_window': {
      'uz': "So'nggi 30 kun",
      'ru': 'Последние 30 дней',
      'en': 'Last 30 days',
      'kk': 'Соңғы 30 күн',
    },
    'shop.analytics.chart_empty': {
      'uz': "Ma'lumotlar yo'q",
      'ru': 'Нет данных',
      'en': 'No data',
      'kk': 'Дерек жоқ',
    },
    'shop.analytics.top_product': {
      'uz': 'Eng ko\'p sotilgan',
      'ru': 'Самый продаваемый',
      'en': 'Top product',
      'kk': 'Ең көп сатылған',
    },
    'shop.analytics.sold_30d': {
      'uz': "dona (30 kun)",
      'ru': 'шт. (30 дней)',
      'en': 'sold (30 d)',
      'kk': 'дана (30 күн)',
    },

    // Phase 13.3.3 — PDF receipt download.
    'receipt.download': {
      'uz': 'Chekni yuklab olish',
      'ru': 'Скачать чек',
      'en': 'Download receipt',
      'kk': 'Түбіртекті жүктеу',
    },
    'receipt.error': {
      'uz': "Chekni ochib bo'lmadi",
      'ru': 'Не удалось открыть чек',
      'en': 'Could not open the receipt',
      'kk': 'Түбіртекті ашу мүмкін болмады',
    },

    // Phase 13.3.4 — pull-to-refresh + empty / loading list states.
    'list.pull_to_refresh': {
      'uz': "Yangilash uchun pastga torting",
      'ru': 'Потяните вниз, чтобы обновить',
      'en': 'Pull down to refresh',
      'kk': 'Жаңарту үшін төмен тартыңыз',
    },
    'list.refreshing': {
      'uz': 'Yangilanmoqda…',
      'ru': 'Обновляется…',
      'en': 'Refreshing…',
      'kk': 'Жаңартылуда…',
    },

    // ── Tracking + buyer orders (centralised after audit) ───────────────────
    'tracking.confirm_received_snack': {
      'uz': 'Yetkazib berish tasdiqlandi 🎉',
      'ru': 'Доставка подтверждена 🎉',
      'en': 'Delivery confirmed 🎉',
      'kk': 'Жеткізу расталды 🎉',
    },
    'tracking.error_prefix': {
      'uz': 'Xatolik',
      'ru': 'Ошибка',
      'en': 'Error',
      'kk': 'Қате',
    },
    'tracking.order_not_found': {
      'uz': 'Buyurtma topilmadi',
      'ru': 'Заказ не найден',
      'en': 'Order not found',
      'kk': 'Тапсырыс табылмады',
    },
    'tracking.confirm_cta': {
      'uz': 'Qabul qildim',
      'ru': 'Получено',
      'en': "I received it",
      'kk': 'Қабылдадым',
    },
    'tracking.rate_and_close': {
      'uz': 'Baholash va yopish',
      'ru': 'Оценить и закрыть',
      'en': 'Rate and close',
      'kk': 'Бағалау және жабу',
    },
    'tracking.chat_tooltip': {
      'uz': 'Chat',
      'ru': 'Чат',
      'en': 'Chat',
      'kk': 'Чат',
    },
    'tracking.order_number_prefix': {
      'uz': 'Buyurtma raqami:',
      'ru': 'Номер заказа:',
      'en': 'Order #:',
      'kk': 'Тапсырыс №:',
    },
    'tracking.courier_label': {
      'uz': 'Kuryer',
      'ru': 'Курьер',
      'en': 'Courier',
      'kk': 'Курьер',
    },

    'orders.title': {
      'uz': 'Mening buyurtmalarim',
      'ru': 'Мои заказы',
      'en': 'My orders',
      'kk': 'Менің тапсырыстарым',
    },
    'orders.empty': {
      'uz': "Hali buyurtma yo'q",
      'ru': 'Пока нет заказов',
      'en': 'No orders yet',
      'kk': 'Әзірге тапсырыстар жоқ',
    },
    'orders.active_section': {
      'uz': 'Faol buyurtmalar',
      'ru': 'Активные заказы',
      'en': 'Active orders',
      'kk': 'Белсенді тапсырыстар',
    },
    'orders.history_section': {
      'uz': 'Tarix',
      'ru': 'История',
      'en': 'History',
      'kk': 'Тарих',
    },
    'orders.track_cta': {
      'uz': 'Buyurtmani kuzatish',
      'ru': 'Отследить заказ',
      'en': 'Track order',
      'kk': 'Тапсырысты бақылау',
    },
    'orders.rate_cta': {
      'uz': 'Baholash',
      'ru': 'Оценить',
      'en': 'Rate',
      'kk': 'Бағалау',
    },
    'orders.reorder_cta': {
      'uz': 'Qayta buyurtma',
      'ru': 'Повторить заказ',
      'en': 'Reorder',
      'kk': 'Қайтадан тапсырыс беру',
    },
    'orders.courier_prefix': {
      'uz': 'Kuryer:',
      'ru': 'Курьер:',
      'en': 'Courier:',
      'kk': 'Курьер:',
    },
    'orders.cart_updated': {
      'uz': 'Savat yangilandi',
      'ru': 'Корзина обновлена',
      'en': 'Cart updated',
      'kk': 'Себет жаңартылды',
    },
    'orders.items_unavailable_prefix': {
      'uz': "Bu mahsulotlar mavjud emas:",
      'ru': 'Эти товары недоступны:',
      'en': 'These items are unavailable:',
      'kk': 'Бұл тауарлар қол жетімсіз:',
    },
    'orders.rating_thanks': {
      'uz': 'Rahmat! Baho yuborildi.',
      'ru': 'Спасибо! Оценка отправлена.',
      'en': 'Thanks! Your rating has been sent.',
      'kk': 'Рақмет! Бағалау жіберілді.',
    },
    'orders.rate_shop_title': {
      'uz': "Do'konni baholang",
      'ru': 'Оцените магазин',
      'en': 'Rate the shop',
      'kk': 'Дүкенді бағалаңыз',
    },
    'orders.rate_courier_title': {
      'uz': 'Kuryerni baholang',
      'ru': 'Оцените курьера',
      'en': 'Rate the courier',
      'kk': 'Курьерді бағалаңыз',
    },
    'orders.rate_product_title': {
      'uz': 'Mahsulotni baholang',
      'ru': 'Оцените товар',
      'en': 'Rate the product',
      'kk': 'Тауарды бағалаңыз',
    },
  };
}

/// Конвертация для использования: `t(context, 'login.title')`
String t(BuildContext context, String key) => L10n.instance.t(key);
