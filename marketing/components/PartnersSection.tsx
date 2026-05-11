import Link from "next/link";

/**
 * Lead-gen card for shop partners. Sits between Stats and CouriersSection
 * on the homepage and drives traffic to /partners for the long-form pitch
 * and application form.
 */
export function PartnersSection() {
  return (
    <section className="section-y bg-white">
      <div className="container-x">
        <div className="relative overflow-hidden rounded-[2.5rem] bg-hero-gradient p-10 text-white shadow-lift sm:p-14 lg:p-20 reveal">
          <div
            aria-hidden="true"
            className="absolute -right-24 -top-24 h-72 w-72 rounded-full bg-brand-gold/30 blur-3xl"
          />
          <div
            aria-hidden="true"
            className="absolute -bottom-32 -left-24 h-80 w-80 rounded-full bg-white/10 blur-3xl"
          />

          <div className="relative grid gap-10 lg:grid-cols-2 lg:items-center">
            <div>
              <span className="inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 py-1.5 text-xs font-semibold uppercase tracking-wider text-white/85 backdrop-blur">
                Для бизнеса
              </span>
              <h2 className="mt-5 text-3xl font-bold tracking-tight sm:text-4xl lg:text-5xl">
                Подключите бизнес к TezKetKaz
              </h2>
              <p className="mt-5 max-w-xl text-base leading-relaxed text-white/85 sm:text-lg">
                Удвойте выручку за счёт доставки. Бесплатное подключение,
                собственный дашборд аналитики, прозрачные комиссии и поддержка
                24/7 — на русском и узбекском.
              </p>

              <ul className="mt-7 grid gap-3 text-sm text-white/90">
                <li className="flex items-start gap-3">
                  <span className="mt-1 h-2 w-2 rounded-full bg-brand-gold" />
                  Без платы за подключение и абонентки
                </li>
                <li className="flex items-start gap-3">
                  <span className="mt-1 h-2 w-2 rounded-full bg-brand-gold" />
                  Выплаты еженедельно, без скрытых комиссий
                </li>
                <li className="flex items-start gap-3">
                  <span className="mt-1 h-2 w-2 rounded-full bg-brand-gold" />
                  Поддержка интеграции с iiko, R-Keeper, 1С
                </li>
              </ul>

              <div className="mt-9 flex flex-wrap gap-3">
                <Link href="/partners" className="btn-primary">
                  Оставить заявку
                </Link>
                <Link href="/partners#how" className="btn-ghost-light">
                  Как это работает
                </Link>
              </div>
            </div>

            <div className="relative">
              <div className="grid gap-4 sm:grid-cols-2">
                {[
                  { stat: "+58%", label: "к среднему чеку" },
                  { stat: "7 дней", label: "до запуска заказов" },
                  { stat: "0 UZS", label: "за подключение" },
                  { stat: "24/7", label: "поддержка партнёров" },
                ].map((s) => (
                  <div
                    key={s.label}
                    className="rounded-2xl border border-white/15 bg-white/10 p-5 backdrop-blur"
                  >
                    <div className="text-2xl font-bold text-brand-gold sm:text-3xl">
                      {s.stat}
                    </div>
                    <div className="mt-1 text-xs uppercase tracking-wider text-white/70">
                      {s.label}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
