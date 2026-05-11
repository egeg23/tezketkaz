import Link from "next/link";

/**
 * Lead-gen card for couriers. Headline metric matches the courier-side
 * earnings model (50–100k UZS/день) from the operations playbook.
 */
export function CouriersSection() {
  return (
    <section className="section-y bg-slate-50">
      <div className="container-x">
        <div className="relative overflow-hidden rounded-[2.5rem] border border-slate-100 bg-white p-10 shadow-soft sm:p-14 lg:p-20 reveal">
          <div
            aria-hidden="true"
            className="absolute -left-24 -top-24 h-72 w-72 rounded-full bg-brand-gold/20 blur-3xl"
          />
          <div
            aria-hidden="true"
            className="absolute -bottom-24 -right-24 h-72 w-72 rounded-full bg-navy-700/10 blur-3xl"
          />

          <div className="relative grid gap-10 lg:grid-cols-2 lg:items-center">
            <div className="order-2 lg:order-1">
              <div className="grid h-20 w-20 place-items-center rounded-3xl bg-gold-gradient text-4xl shadow-soft">
                <span aria-hidden="true">⚡️</span>
              </div>
              <p className="mt-5 text-sm font-semibold uppercase tracking-[0.2em] text-navy-700">
                Заработай с TezKetKaz
              </p>
              <h2 className="mt-3 text-3xl font-bold tracking-tight text-navy-900 sm:text-4xl lg:text-5xl">
                <span className="bg-gold-gradient bg-clip-text text-transparent">
                  50 000 – 100 000
                </span>{" "}
                сум в день
              </h2>
              <p className="mt-5 max-w-xl text-base leading-relaxed text-slate-600 sm:text-lg">
                Гибкий график, понятный тариф, моментальная сводка по
                заработку. Подходит как студентам, так и тем, кто хочет
                стабильный заработок на полной занятости.
              </p>

              <ul className="mt-7 grid gap-3 text-sm text-slate-700">
                <li className="flex items-start gap-3">
                  <span className="mt-1 h-2 w-2 rounded-full bg-navy-900" />
                  Самозанятость или индивидуальный предприниматель
                </li>
                <li className="flex items-start gap-3">
                  <span className="mt-1 h-2 w-2 rounded-full bg-navy-900" />
                  Бонусы за рейтинг и регулярные смены
                </li>
                <li className="flex items-start gap-3">
                  <span className="mt-1 h-2 w-2 rounded-full bg-navy-900" />
                  Поддержка и обучение — бесплатно
                </li>
              </ul>

              <div className="mt-9 flex flex-wrap gap-3">
                <Link href="/couriers" className="btn-primary">
                  Стать курьером
                </Link>
                <Link
                  href="/couriers#faq"
                  className="inline-flex items-center justify-center gap-2 rounded-full border border-slate-200 px-6 py-3 text-sm font-semibold text-navy-900 transition hover:border-navy-900 hover:bg-slate-50"
                >
                  Частые вопросы
                </Link>
              </div>
            </div>

            <div className="order-1 lg:order-2">
              <div className="relative mx-auto max-w-sm rounded-3xl bg-hero-gradient p-1 shadow-lift">
                <div className="rounded-[22px] bg-navy-900 p-7 text-white">
                  <div className="flex items-center justify-between">
                    <span className="text-xs uppercase tracking-wider text-white/60">
                      Сегодня
                    </span>
                    <span className="rounded-full bg-brand-gold px-3 py-1 text-[10px] font-bold text-navy-900">
                      ОНЛАЙН
                    </span>
                  </div>
                  <div className="mt-5">
                    <div className="text-sm text-white/70">Заработано</div>
                    <div className="mt-1 text-5xl font-extrabold tracking-tight">
                      87 400
                      <span className="ml-2 text-base font-medium text-white/60">
                        сум
                      </span>
                    </div>
                  </div>
                  <div className="mt-6 grid grid-cols-3 gap-3 text-center text-xs">
                    <div className="rounded-xl bg-white/10 p-3">
                      <div className="text-base font-bold text-brand-gold">
                        14
                      </div>
                      <div className="mt-0.5 text-white/60">заказов</div>
                    </div>
                    <div className="rounded-xl bg-white/10 p-3">
                      <div className="text-base font-bold text-brand-gold">
                        6.2 ч
                      </div>
                      <div className="mt-0.5 text-white/60">онлайн</div>
                    </div>
                    <div className="rounded-xl bg-white/10 p-3">
                      <div className="text-base font-bold text-brand-gold">
                        4.96
                      </div>
                      <div className="mt-0.5 text-white/60">рейтинг</div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
