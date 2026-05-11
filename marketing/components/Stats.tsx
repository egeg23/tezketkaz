interface Stat {
  value: string;
  label: string;
}

const stats: Stat[] = [
  { value: "10 000+", label: "выполненных заказов" },
  { value: "200+", label: "ресторанов и магазинов" },
  { value: "50+", label: "активных курьеров" },
  { value: "30 мин", label: "среднее время доставки" },
];

/**
 * Trust strip with launch metrics. Numbers are early-stage placeholders;
 * they will be wired to a backend stats endpoint after launch.
 */
export function Stats() {
  return (
    <section className="relative isolate overflow-hidden bg-navy-900 py-20 text-white">
      <div
        aria-hidden="true"
        className="absolute -left-32 top-1/2 -z-10 h-[420px] w-[420px] -translate-y-1/2 rounded-full bg-navy-700/50 blur-3xl"
      />
      <div
        aria-hidden="true"
        className="absolute -right-32 top-0 -z-10 h-[320px] w-[320px] rounded-full bg-brand-gold/20 blur-3xl"
      />

      <div className="container-x grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
        {stats.map((s, idx) => (
          <div
            key={s.label}
            className="reveal"
            style={{ transitionDelay: `${idx * 70}ms` }}
          >
            <div className="text-4xl font-extrabold tracking-tight text-white sm:text-5xl">
              {s.value}
            </div>
            <div className="mt-2 text-sm uppercase tracking-wider text-white/70">
              {s.label}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
