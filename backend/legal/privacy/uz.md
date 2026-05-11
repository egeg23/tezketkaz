# Maxfiylik siyosati

_Oxirgi yangilanish: 2026-yil 1-may._

TezKetKaz («biz», «bizning») O'zbekiston Respublikasi va Qozog'iston Respublikasi hududida xaridorlar, do'konlar va kuryerlarni bog'lovchi TezKetKaz yetkazib berish platformasini yuritadi. Ushbu siyosat qanday shaxsiy ma'lumotlarni yig'ishimizni, ulardan qanday foydalanishimizni, kimga uzatishimizni va sizning huquqlaringizni tushuntiradi. TezKetKaz'dan foydalanish orqali siz quyidagi shartlarga rozilik bildirgan hisoblanasiz.

## 1. Biz kimmiz

«TezKetKaz» MChJ — TezKetKaz mobil ilovalari, vendorlik portali, kuryer ilovasi va veb-saytlari orqali qayta ishlanadigan shaxsiy ma'lumotlarning operatori. Yuridik manzil: Toshkent shahri, O'zbekiston Respublikasi. Shaxsiy ma'lumotlarga oid savollar uchun: **support@tezketkaz.uz**.

## 2. Qanday ma'lumotlarni yig'amiz

Sizning rolingizga qarab quyidagi turdagi shaxsiy ma'lumotlar yig'iladi:

- **Hisob ma'lumotlari:** telefon raqami (asosiy identifikator sifatida), ko'rsatiladigan ism, afzal ko'rilgan til, mamlakat (UZ yoki KZ) hamda kirish uchun ishlatilgan OAuth identifikatori (Google / Apple / Yandex).
- **Manzil va geolokatsiya:** saqlangan yetkazib berish manzillari (yorliq, matn manzil, kenglik/uzunlik), kuryerning smena vaqtidagi GPS koordinatalari, har bir buyurtma uchun olib ketish va yetkazib berish nuqtalari. Kuryerlar uchun smena faol bo'lganda koordinatalar bir necha soniyada yoziladi. Xaridorlar uchun qurilma joylashuvi faqat sessiya davomida va sizning roziligingiz bilan olinadi.
- **Buyurtma ma'lumotlari:** mahsulotlar, modifikatorlar, summalar, qo'llanilgan kuponlar va sadoqat ballari, do'kon, biriktirilgan kuryer, yetkazib berish ko'rsatmalari, baholash va izohlar.
- **To'lov ma'lumotlari:** karta raqamining to'liq holatini saqlamaymiz. Naqdsiz to'lovlar uchun Click, Payme, Uzum (O'zbekiston) yoki Kaspi (Qozog'iston) tomonidan berilgan **karta tokeni** hamda oxirgi to'rt raqam va to'lov tizimi saqlanadi. Naqd buyurtmalar uchun faqat summa yoziladi.
- **Aloqalar:** xaridor, do'kon, kuryer va qo'llab-quvvatlash o'rtasidagi ilova ichidagi chat, qo'llab-quvvatlash xizmatiga yuborilgan murojaatlar va fayllar, OTP va kirish hodisalari audit uchun.
- **Qurilma va push ma'lumotlari:** bildirishnomalarni yetkazish uchun Firebase Cloud Messaging (FCM) tokenlari, qurilma modeli, OS versiyasi va ilova versiyasi diagnostika uchun.
- **KYC hujjatlari (faqat kuryerlar):** shaxsni tasdiqlovchi hujjatlar nusxasi, selfi, haydovchilik guvohnomasi (mavjud bo'lsa), transport vositasi suratlari va to'lovlar uchun bank rekvizitlari.

## 3. Ma'lumotlardan qanday foydalanamiz

Shaxsiy ma'lumotlarni quyidagi qonuniy asoslarda qayta ishlaymiz: (i) ro'yxatdan o'tishda tuzilgan shartnomani bajarish; (ii) xavfsiz va firibgarliksiz xizmatni ta'minlashdagi qonuniy manfaatimiz; (iii) soliq, buxgalteriya va iste'molchi himoyasi qonunchiligi talablari; (iv) marketing push xabarlari va ixtiyoriy analitika uchun aniq roziligingiz.

Xususan, ma'lumotlardan quyidagi maqsadlarda foydalanamiz:

- hisobni yaratish va autentifikatsiya qilish;
- buyurtmalarni qabul qilish, do'konlarga yo'naltirish, kuryerlarni belgilash va real vaqt rejimida kuzatishni ko'rsatish;
- yetkazib berish narxi, surge koeffitsienti va kuryer mukofotini hisoblash;
- firibgarlik va suiiste'molga qarshi tekshiruvlar (masalan, ko'p bekor qilinadigan akkauntlarni aniqlash);
- qaytarish va bahslarni hal etish;
- mijozlarga qo'llab-quvvatlash xizmatini ko'rsatish;
- tranzaksion email va push xabarlarni yuborish (buyurtma holati, kvitansiyalar) — hisob faol bo'lguncha bekor qilib bo'lmaydi;
- marketing push va reklama xatlarini yuborish — **faqat** `notificationPrefs` orqali rozilik berilgan bo'lsa;
- agregatlangan va anonimlashtirilgan analitika orqali xizmatni yaxshilash.

## 4. Ma'lumotlarni uzatadigan uchinchi tomonlar

Quyidagi protsessorlarga minimal zarur ma'lumotlarni uzatamiz:

- **Click, Payme, Uzum, Kaspi** — to'lovlarni qayta ishlash. Ular telefon raqamingiz, buyurtma summasi va (tokenizatsiya uchun) ularning xavfsiz formalariga kiritilgan karta ma'lumotlarini oladi.
- **Yandex Maps va Yandex Geocoder** — manzilni avtomatik to'ldirish, marshrut va ETA hisoblash. Koordinatalar ism va telefonsiz uzatiladi.
- **Google Firebase** — FCM push xabarlari, ishdan chiqish hisobotlari va analitika. FCM tokenlar o'z-o'zidan shaxsni aniqlamaydi.
- **Sentry** — xatolarni kuzatish. Yuborishdan oldin telefon raqamlari va elektron pochtalar olib tashlanadi; faqat stek-treyslar, so'rov identifikatorlari va anonim foydalanuvchi identifikatorlari uzatiladi.
- **Resend** — tranzaksion elektron pochta (buyurtma tasdiqlari, qaytarish kvitansiyalari).
- **Soliq organlari, sudlar va huquqni muhofaza qiluvchi organlar** — faqat O'zbekiston yoki Qozog'iston qonunchiligi talab qilgan tegishli rasmiy so'rov asosida.

Biz shaxsiy ma'lumotlaringizni sotmaymiz va ilovada uchinchi tomon reklama tarmoqlarini ko'rsatmaymiz.

## 5. Saqlash muddatlari

Buyurtma yozuvlari yakunlangandan so'ng **besh yil** saqlanadi — soliq va buxgalteriya talablariga muvofiq. Kuryerlarning KYC hujjatlari kuryer akkaunti faolsizlantirilganidan keyin **uch yil** davomida saqlanadi. Qo'llab-quvvatlash murojaatlari ikki yil davomida saqlanadi. Hisobni o'chirsangiz (6-bo'limga qarang), **30 kunlik bekor qilish muddati** beriladi, so'ng akkaunt anonimlashtiriladi; buyurtma yozuvlari besh yillik muddatgacha saqlanadi, lekin identifikatorlardan tozalanadi.

## 6. Sizning huquqlaringiz

Quyidagi huquqlardan ilova orqali yoki **support@tezketkaz.uz** elektron pochtasi orqali foydalanishingiz mumkin:

- **Kirish va eksport.** Hisobingizga oid barcha ma'lumotlarning mashina o'qishi mumkin bo'lgan eksportini so'rash (Sozlamalar → Maxfiylik → Ma'lumotlarni eksport qilish).
- **Hisobni o'chirish.** Hisobni o'chirishni so'rash (Sozlamalar → Maxfiylik → Hisobni o'chirish). Hisob 30 kunlik kutish davridan keyin yakuniy o'chiriladi.
- **Tuzatish.** Telefon, ism, manzillar va to'lov usullarini istalgan vaqtda Sozlamalardan o'zgartirish.
- **Marketingdan voz kechish.** Sozlamalar → Bildirishnomalardan «Reklama xabarlari»ni o'chirish. Faol buyurtmalar mavjudligida tranzaksion bildirishnomalarni o'chirib bo'lmaydi.
- **Shikoyat.** O'zbekiston Respublikasi Axborotlashtirish va telekommunikatsiya sohasida nazorat qiluvchi davlat inspeksiyasiga murojaat qilishingiz mumkin.

## 7. Xavfsizlik

Ma'lumotlarni uzatishda TLS 1.2+, saqlashda AES-256, rolga asoslangan kirish nazorati va aylanma maxfiy kalitlar bilan himoya qilamiz. Administratorlarning foydalanuvchi ma'lumotlariga barcha murojaatlari logga olinadi. Kuryerlar va xodimlar maxfiylik majburiyatlarini imzolaydilar.

## 8. Bolalar

TezKetKaz 16 yoshdan kichik shaxslar uchun mo'ljallanmagan. Agar voyaga yetmagan shaxs ro'yxatdan o'tganini bilsangiz, biz bilan bog'laning, biz hisobni o'chirib tashlaymiz.

## 9. Siyosatdagi o'zgarishlar

Ushbu siyosatga o'zgartirishlar kiritishimiz mumkin. Muhim o'zgartirishlar haqida kamida 14 kun oldin ilova orqali xabar beramiz.

## 10. Aloqa

Maxfiylik bo'yicha har qanday savolingizni **support@tezketkaz.uz** manziliga yuboring.
