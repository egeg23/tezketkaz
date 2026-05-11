import type { Metadata } from "next";
import { Nav } from "@/components/Nav";
import { Footer } from "@/components/Footer";
import { Faq } from "@/components/Faq";
import { PartnerApplyForm } from "@/components/PartnerApplyForm";

export const metadata: Metadata = {
  title: "Подключи бизнес к TezKetKaz — удвой выручку через доставку",
  description:
    "Подключение за 7 дней, без платы за установку, удобный дашборд аналитики. Подайте заявку — менеджер обсудит условия.",
};

const BENEFITS = [
  {
    icon: "📈",
    title: "До +58% к выручке",
    text: "Доставка приносит новых клиентов, не каннибализируя поток в офлайне.",
  },
  {
    icon: "🤝",
    title: "0 сум за подключение",
    text: "Никаких установочных сборов и абонентки — комиссия только за выполненные заказы.",
  },
  {
    icon: "📊",
    title: "Дашборд аналитики",
    text: "Видите выручку, средний чек, отмены и рейтинг в реальном времени.",
  },
  {
    icon: "🔌",
    title: "Готовые интеграции",
    text: "Подключаем iiko, R-Keeper, 1С, Poster и Frontpad — не нужно дублировать меню вручную.",
  },
];

const STEPS = [
  {
    title: "Заявка",
    text: "Заполните форму на этой странице — займёт пару минут.",
  },
  {
    title: "Договор",
    text: "Подписываем электронный договор за 1 день, без визита в офис.",
  },
  {
    title: "Загрузка каталога",
    text: "Помогаем выгрузить меню и фото товаров — или подтягиваем из вашей кассы.",
  },
  {
    title: "Старт",
    text: "Активируем точку, запускаем первый промо-период и начинаем принимать заказы.",
  },
];

const FAQ_ITEMS = [
  {
    question: "Какая комиссия TezKetKaz?",
    answer:
      "Базовая комиссия — 18% с заказа, она включает доставку курьером, платёжный шлюз и поддержку. Для точек с собственной доставкой действует льготный тариф.",
  },
  {
    question: "Кто отвечает за курьеров?",
    answer:
      "TezKetKaz берёт на себя всю операционную работу: подбор, обучение, контроль качества, страховку. Вы готовите заказ — мы доставляем.",
  },
  {
    question: "Как выводятся деньги?",
    answer:
      "Еженедельные переводы на расчётный счёт юр. лица или ИП. По запросу — ежедневные выплаты с моментальным переводом через Click for Business.",
  },
  {
    question: "Можно ли продавать на TezKetKaz и в офлайне одновременно?",
    answer:
      "Да, это базовый кейс. Вы продолжаете обычный поток клиентов в зал и добавляете новый канал. Меню в приложении и в зале можно различать (цены, позиции, акции).",
  },
  {
    question: "Сколько занимает запуск?",
    answer:
      "От 3 до 7 дней. Зависит от того, нужно ли фотографировать меню и подключать интеграции. Самый быстрый случай — ресторан с готовыми фото запускается за день.",
  },
];

export default function PartnersPage() {
  return (
    <>
      <Nav variant="light" />
      <main>
        {/* Hero */}
        <section className="relative isolate overflow-hidden bg-hero-gradient pt-32 pb-20 text-white sm:pt-40 sm:pb-28">
          <div
            aria-hidden="true"
            className="absolute -left-24 -top-24 h-[420px] w-[420px] rounded-full bg-brand-gold/25 blur-3xl"
          />
          <div
            aria-hidden="true"
            className="absolute -bottom-32 -right-24 h-[480px] w-[480px] rounded-full bg-navy-500/40 blur-3xl"
          />

          <div className="container-x relative grid items-center gap-12 lg:grid-cols-2">
            <div>
              <span className="inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 py-1.5 text-xs font-semibold uppercase tracking-wider text-white/85 backdrop-blur">
                Для бизнеса · Узбекистан
              </span>
              <h1 className="mt-6 text-balance text-4xl font-extrabold leading-[1.05] tracking-tight sm:text-5xl lg:text-6xl">
                Подключите бизнес к{" "}
                <span className="bg-gold-gradient bg-clip-text text-transparent">
                  TezKetKaz
                </span>
              </h1>
              <p className="mt-5 text-lg text-white/85 sm:text-xl">
                Доставка под ключ для ресторанов, магазинов, аптек и
                электроники. Без платы за подключение и без сюрпризов в
                комиссии.
              </p>

              <div className="mt-9 flex flex-wrap gap-3">
                <a href="#apply" className="btn-primary">
                  Оставить заявку
                </a>
                <a href="#how" className="btn-ghost-light">
                  Как это работает
                </a>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              {[
                { stat: "+58%", label: "к среднему чеку" },
                { stat: "7 дней", label: "до запуска" },
                { stat: "0 UZS", label: "за подключение" },
                { stat: "24/7", label: "поддержка" },
              ].map((s) => (
                <div
                  key={s.label}
                  className="rounded-3xl border border-white/15 bg-white/10 p-6 backdrop-blur"
                >
                  <div className="text-3xl font-extrabold text-brand-gold">
                    {s.stat}
                  </div>
                  <div className="mt-1 text-xs uppercase tracking-wider text-white/70">
                    {s.label}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Benefits */}
        <section className="section-y bg-white">
          <div className="container-x">
            <div className="max-w-2xl reveal">
              <p className="text-sm font-semibold uppercase tracking-[0.2em] text-navy-700">
                Что вы получаете
              </p>
              <h2 className="mt-3 text-3xl font-bold tracking-tight text-navy-900 sm:text-4xl">
                Условия, удобные для бизнеса
              </h2>
            </div>

            <div className="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
              {BENEFITS.map((b, idx) => (
                <article
                  key={b.title}
                  className="surface-card reveal"
                  style={{ transitionDelay: `${idx * 60}ms` }}
                >
                  <div className="grid h-12 w-12 place-items-center rounded-2xl bg-navy-50 text-2xl">
                    <span aria-hidden="true">{b.icon}</span>
                  </div>
                  <h3 className="mt-5 text-lg font-bold text-navy-900">
                    {b.title}
                  </h3>
                  <p className="mt-2 text-sm leading-relaxed text-slate-600">
                    {b.text}
                  </p>
                </article>
              ))}
            </div>
          </div>
        </section>

        {/* How it works */}
        <section id="how" className="section-y bg-slate-50">
          <div className="container-x">
            <div className="max-w-2xl reveal">
              <p className="text-sm font-semibold uppercase tracking-[0.2em] text-navy-700">
                Как подключиться
              </p>
              <h2 className="mt-3 text-3xl font-bold tracking-tight text-navy-900 sm:text-4xl">
                Запуск за 4 шага
              </h2>
            </div>

            <ol className="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
              {STEPS.map((s, i) => (
                <li
                  key={s.title}
                  className="relative rounded-3xl border border-slate-100 bg-white p-7 shadow-soft reveal"
                  style={{ transitionDelay: `${i * 80}ms` }}
                >
                  <span className="absolute -top-5 left-7 grid h-10 w-10 place-items-center rounded-full bg-navy-900 text-sm font-bold text-brand-gold shadow-soft">
                    {i + 1}
                  </span>
                  <h3 className="mt-3 text-lg font-bold text-navy-900">
                    {s.title}
                  </h3>
                  <p className="mt-2 text-sm leading-relaxed text-slate-600">
                    {s.text}
                  </p>
                </li>
              ))}
            </ol>
          </div>
        </section>

        {/* Apply */}
        <section id="apply" className="section-y bg-white">
          <div className="container-x grid gap-12 lg:grid-cols-[1fr_1.2fr] lg:items-start">
            <div className="reveal">
              <p className="text-sm font-semibold uppercase tracking-[0.2em] text-navy-700">
                Заявка
              </p>
              <h2 className="mt-3 text-3xl font-bold tracking-tight text-navy-900 sm:text-4xl">
                Расскажите о бизнесе
              </h2>
              <p className="mt-4 text-base leading-relaxed text-slate-600">
                Менеджер по партнёрствам перезвонит в течение 24 часов и
                подберёт оптимальные условия — комиссию, способ выплат и
                интеграцию.
              </p>

              <div className="mt-8 rounded-2xl border border-slate-100 bg-slate-50 p-6">
                <p className="text-sm font-semibold text-navy-900">
                  Прямой контакт
                </p>
                <p className="mt-2 text-sm text-slate-600">
                  Telegram:{" "}
                  <a
                    href="https://t.me/tezketkaz_partners"
                    className="link-navy"
                  >
                    @tezketkaz_partners
                  </a>
                  <br />
                  Email:{" "}
                  <a
                    href="mailto:partners@tezketkaz.uz"
                    className="link-navy"
                  >
                    partners@tezketkaz.uz
                  </a>
                </p>
              </div>
            </div>

            <div className="reveal">
              <PartnerApplyForm />
            </div>
          </div>
        </section>

        <Faq title="Частые вопросы партнёров" items={FAQ_ITEMS} />
      </main>
      <Footer />
    </>
  );
}
