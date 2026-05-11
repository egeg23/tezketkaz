interface Feature {
  icon: React.ReactNode;
  title: string;
  description: string;
}

const features: Feature[] = [
  {
    title: "Реалтайм отслеживание",
    description:
      "Следите за курьером на карте, получайте уведомления о статусе заказа и точный ETA до подъезда.",
    icon: (
      <svg
        viewBox="0 0 24 24"
        aria-hidden="true"
        className="h-7 w-7"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M12 2C8 2 5 5 5 9c0 5 7 13 7 13s7-8 7-13c0-4-3-7-7-7z" />
        <circle cx="12" cy="9" r="2.5" />
      </svg>
    ),
  },
  {
    title: "Безопасная оплата",
    description:
      "Картой, через Click, Payme или наличными при получении. Возвраты происходят автоматически.",
    icon: (
      <svg
        viewBox="0 0 24 24"
        aria-hidden="true"
        className="h-7 w-7"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <rect x="3" y="6" width="18" height="13" rx="2.5" />
        <path d="M3 10h18" />
        <path d="M7 15h4" />
      </svg>
    ),
  },
  {
    title: "Кешбэк и Plus-подписка",
    description:
      "Возвращаем до 5% бонусами за каждый заказ. Подписка TezKetKaz Plus — бесплатная доставка и приоритет.",
    icon: (
      <svg
        viewBox="0 0 24 24"
        aria-hidden="true"
        className="h-7 w-7"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z" fill="currentColor" />
      </svg>
    ),
  },
];

/**
 * Three-up feature grid — uses simple stroke icons (no lucide dep) and a
 * gradient ring around each icon to tie back to the brand palette.
 */
export function Features() {
  return (
    <section className="section-y bg-white">
      <div className="container-x">
        <div className="max-w-2xl reveal">
          <p className="text-sm font-semibold uppercase tracking-[0.2em] text-navy-700">
            Почему TezKetKaz
          </p>
          <h2 className="mt-3 text-3xl font-bold tracking-tight text-navy-900 sm:text-4xl lg:text-5xl">
            Каждая деталь — для скорости
          </h2>
        </div>

        <div className="mt-14 grid gap-6 md:grid-cols-3">
          {features.map((f, idx) => (
            <article
              key={f.title}
              className="surface-card reveal"
              style={{ transitionDelay: `${idx * 80}ms` }}
            >
              <div className="relative inline-flex">
                <div
                  aria-hidden="true"
                  className="absolute inset-0 rounded-2xl bg-gold-gradient opacity-90 blur-[2px]"
                />
                <div className="relative grid h-14 w-14 place-items-center rounded-2xl bg-navy-900 text-brand-gold">
                  {f.icon}
                </div>
              </div>
              <h3 className="mt-6 text-xl font-bold text-navy-900">
                {f.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-slate-600">
                {f.description}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
