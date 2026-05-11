import type { Metadata } from "next";
import { Nav } from "@/components/Nav";
import { Footer } from "@/components/Footer";
import { Faq } from "@/components/Faq";
import { CourierApplyForm } from "@/components/CourierApplyForm";

export const metadata: Metadata = {
  title: "Стань курьером TezKetKaz · от 50 000 до 100 000 сум в день",
  description:
    "Гибкий график, еженедельные выплаты, бонусы за качество. Подайте заявку и начните зарабатывать в TezKetKaz уже на этой неделе.",
};

const BENEFITS = [
  {
    icon: "⏱",
    title: "Гибкий график",
    text: "Выходите на смену когда удобно — никаких обязательных часов и штрафов за пропуск.",
  },
  {
    icon: "💰",
    title: "Выплаты раз в неделю",
    text: "Каждый понедельник зарплата приходит на карту или Click без комиссии.",
  },
  {
    icon: "🎯",
    title: "Бонусы за качество",
    text: "Высокий рейтинг и стабильное завершение заказов = до 25% сверху от тарифа.",
  },
  {
    icon: "📱",
    title: "Понятное приложение",
    text: "Прозрачный заработок по каждому заказу, навигация и поддержка прямо в смартфоне.",
  },
];

const FAQ_ITEMS = [
  {
    question: "Сколько реально можно зарабатывать?",
    answer:
      "При полной смене 8–10 часов средний курьер забирает 80 000–100 000 сум в день. Новички обычно стартуют с 50 000 сум и выходят на полный ритм за 2 недели.",
  },
  {
    question: "Нужен ли свой транспорт?",
    answer:
      "Да — велосипед, самокат, мотоцикл или авто. Если транспорта пока нет, мы расскажем про партнёрский прокат с льготными условиями.",
  },
  {
    question: "Какие документы нужны?",
    answer:
      "Паспорт, ИНН и, при необходимости, регистрация самозанятого или ИП. Помогаем с оформлением и оплачиваем госпошлину.",
  },
  {
    question: "Как быстро смогу выйти на смену?",
    answer:
      "Обычно 1–3 дня: онлайн-собеседование, короткое обучение и активация в приложении. После этого — сразу заказы.",
  },
  {
    question: "Есть ли поддержка ночью?",
    answer:
      "Да, круглосуточная линия поддержки и старший координатор смены. Если что-то пошло не так — звоните, разберёмся за минуты.",
  },
];

export default function CouriersPage() {
  return (
    <>
      <Nav variant="light" />
      <main>
        {/* Hero */}
        <section className="relative isolate overflow-hidden bg-hero-gradient pt-32 pb-20 text-white sm:pt-40 sm:pb-28">
          <div
            aria-hidden="true"
            className="absolute -right-32 -top-24 h-[480px] w-[480px] rounded-full bg-brand-gold/25 blur-3xl"
          />
          <div
            aria-hidden="true"
            className="absolute -bottom-40 left-0 h-[500px] w-[500px] rounded-full bg-navy-500/40 blur-3xl"
          />

          <div className="container-x relative grid items-center gap-12 lg:grid-cols-2">
            <div>
              <span className="inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 py-1.5 text-xs font-semibold uppercase tracking-wider text-white/85 backdrop-blur">
                Открыт набор · Ташкент
              </span>
              <h1 className="mt-6 text-balance text-4xl font-extrabold leading-[1.05] tracking-tight sm:text-5xl lg:text-6xl">
                Стань курьером{" "}
                <span className="bg-gold-gradient bg-clip-text text-transparent">
                  TezKetKaz
                </span>
              </h1>
              <p className="mt-5 text-lg text-white/85 sm:text-xl">
                Зарабатывай{" "}
                <span className="font-semibold text-brand-gold">
                  50 000–100 000 сум в день
                </span>{" "}
                — и сам решай, когда работать.
              </p>

              <ul className="mt-8 grid gap-3 text-sm text-white/85 sm:grid-cols-2">
                <li className="flex items-center gap-2">
                  <span className="h-2 w-2 rounded-full bg-brand-gold" />
                  Выплаты раз в неделю
                </li>
                <li className="flex items-center gap-2">
                  <span className="h-2 w-2 rounded-full bg-brand-gold" />
                  Бонусы за рейтинг
                </li>
                <li className="flex items-center gap-2">
                  <span className="h-2 w-2 rounded-full bg-brand-gold" />
                  Гибкий график
                </li>
                <li className="flex items-center gap-2">
                  <span className="h-2 w-2 rounded-full bg-brand-gold" />
                  Поддержка 24/7
                </li>
              </ul>

              <div className="mt-9 flex flex-wrap gap-3">
                <a href="#apply" className="btn-primary">
                  Подать заявку
                </a>
                <a href="#faq" className="btn-ghost-light">
                  Частые вопросы
                </a>
              </div>
            </div>

            <div className="relative lg:justify-self-end">
              <div className="grid gap-4">
                <div className="rounded-3xl border border-white/15 bg-white/10 p-7 backdrop-blur">
                  <div className="text-xs uppercase tracking-wider text-white/70">
                    Лучшая смена недели
                  </div>
                  <div className="mt-3 text-5xl font-extrabold tracking-tight">
                    142 800
                    <span className="ml-2 text-base font-medium text-white/70">
                      сум
                    </span>
                  </div>
                  <div className="mt-2 text-sm text-white/70">
                    Курьер Самир, велосипед, 11 часов на линии
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="rounded-3xl border border-white/15 bg-white/10 p-5 backdrop-blur">
                    <div className="text-2xl font-bold text-brand-gold">
                      4.91
                    </div>
                    <div className="mt-1 text-xs uppercase tracking-wider text-white/70">
                      средний рейтинг
                    </div>
                  </div>
                  <div className="rounded-3xl border border-white/15 bg-white/10 p-5 backdrop-blur">
                    <div className="text-2xl font-bold text-brand-gold">
                      6 дней
                    </div>
                    <div className="mt-1 text-xs uppercase tracking-wider text-white/70">
                      до первой выплаты
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Benefits */}
        <section className="section-y bg-white">
          <div className="container-x">
            <div className="max-w-2xl reveal">
              <p className="text-sm font-semibold uppercase tracking-[0.2em] text-navy-700">
                Почему курьеры выбирают нас
              </p>
              <h2 className="mt-3 text-3xl font-bold tracking-tight text-navy-900 sm:text-4xl">
                Условия, на которых правда зарабатывают
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

        {/* Apply */}
        <section id="apply" className="section-y bg-slate-50">
          <div className="container-x grid gap-12 lg:grid-cols-[1fr_1.1fr] lg:items-start">
            <div className="reveal">
              <p className="text-sm font-semibold uppercase tracking-[0.2em] text-navy-700">
                Заявка
              </p>
              <h2 className="mt-3 text-3xl font-bold tracking-tight text-navy-900 sm:text-4xl">
                Заполните анкету — мы перезвоним за день
              </h2>
              <p className="mt-4 text-base leading-relaxed text-slate-600">
                Это короткая анкета на 1 минуту. После отправки менеджер
                свяжется с вами по WhatsApp или Telegram и расскажет, как
                подключиться к платформе.
              </p>

              <ol className="mt-8 space-y-4 text-sm text-slate-700">
                {[
                  "Отправьте анкету",
                  "Получите звонок от менеджера",
                  "Пройдите короткое обучение",
                  "Выйдите на первую смену",
                ].map((step, i) => (
                  <li key={step} className="flex items-start gap-3">
                    <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-navy-900 text-xs font-bold text-white">
                      {i + 1}
                    </span>
                    <span className="pt-0.5">{step}</span>
                  </li>
                ))}
              </ol>
            </div>

            <div className="reveal">
              <CourierApplyForm />
            </div>
          </div>
        </section>

        <Faq title="Частые вопросы курьеров" items={FAQ_ITEMS} />
      </main>
      <Footer />
    </>
  );
}
