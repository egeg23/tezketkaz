interface Vertical {
  emoji: string;
  title: string;
  description: string;
  cta: string;
  accent: string;
}

const verticals: Vertical[] = [
  {
    emoji: "🍔",
    title: "Рестораны",
    description:
      "От локальных тандыров и узбекских классиков до бургеров, суши и десертов. Свежее, горячее, без надбавок.",
    cta: "Заказать еду",
    accent: "from-rose-400 to-amber-400",
  },
  {
    emoji: "🛒",
    title: "Продукты",
    description:
      "Korzinka, Makro, локальные рынки — собираем заказ и привозим за час. Можно заказать заранее на удобное время.",
    cta: "Купить продукты",
    accent: "from-emerald-400 to-teal-500",
  },
  {
    emoji: "💊",
    title: "Аптеки",
    description:
      "24/7 доставка лекарств из ближайших аптек. Цены такие же, как в зале, без скрытых наценок.",
    cta: "Найти лекарство",
    accent: "from-sky-400 to-indigo-500",
  },
  {
    emoji: "📱",
    title: "Электроника",
    description:
      "Зарядки, наушники, аксессуары и гаджеты из проверенных магазинов с привозом в день заказа.",
    cta: "Посмотреть",
    accent: "from-fuchsia-400 to-violet-500",
  },
];

/**
 * Four service categories TezKetKaz launches with. Each card is a flat
 * surface with a soft gradient corner — pulls focus without competing with
 * the brand navy/gold palette.
 */
export function Verticals() {
  return (
    <section id="verticals" className="section-y bg-slate-50">
      <div className="container-x">
        <div className="max-w-2xl reveal">
          <p className="text-sm font-semibold uppercase tracking-[0.2em] text-navy-700">
            Что доставляем
          </p>
          <h2 className="mt-3 text-3xl font-bold tracking-tight text-navy-900 sm:text-4xl lg:text-5xl">
            Всё, что нужно — в одном приложении
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-slate-600">
            Четыре категории на старте. Один заказ — один курьер — одна оплата.
          </p>
        </div>

        <div className="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {verticals.map((v, idx) => (
            <article
              key={v.title}
              className="group relative overflow-hidden rounded-3xl border border-slate-100 bg-white p-7 shadow-soft transition hover:-translate-y-1 hover:shadow-lift reveal"
              style={{ transitionDelay: `${idx * 60}ms` }}
            >
              <div
                aria-hidden="true"
                className={`absolute -right-12 -top-12 h-32 w-32 rounded-full bg-gradient-to-br ${v.accent} opacity-15 blur-2xl transition group-hover:opacity-30`}
              />
              <div className="relative">
                <div className="grid h-14 w-14 place-items-center rounded-2xl bg-slate-50 text-3xl shadow-inner">
                  <span aria-hidden="true">{v.emoji}</span>
                </div>
                <h3 className="mt-5 text-xl font-bold text-navy-900">
                  {v.title}
                </h3>
                <p className="mt-2 text-sm leading-relaxed text-slate-600">
                  {v.description}
                </p>
                <p className="mt-5 text-sm font-semibold text-navy-700">
                  {v.cta} →
                </p>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
