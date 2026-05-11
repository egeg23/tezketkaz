import { DownloadCTA } from "./DownloadCTA";

/**
 * Full-bleed navy gradient hero. The background blends:
 *   - the brand gradient (navy → indigo)
 *   - a faint Tashkent-evoking unsplash photo at low opacity to add depth
 *     without overwhelming the brand colors
 */
export function Hero() {
  return (
    <section className="relative isolate overflow-hidden bg-hero-gradient pt-32 pb-24 sm:pt-40 sm:pb-32 lg:pt-48 lg:pb-40">
      {/* Photographic atmosphere layer */}
      <div
        aria-hidden="true"
        className="absolute inset-0 -z-10 opacity-25 mix-blend-soft-light"
        style={{
          backgroundImage:
            "url('https://images.unsplash.com/photo-1551782450-a2132b4ba21d?auto=format&fit=crop&w=2000&q=70')",
          backgroundSize: "cover",
          backgroundPosition: "center",
        }}
      />
      {/* Top-right gold glow */}
      <div
        aria-hidden="true"
        className="absolute -right-32 -top-32 -z-10 h-[480px] w-[480px] rounded-full bg-brand-gold/25 blur-3xl"
      />
      {/* Bottom-left indigo glow */}
      <div
        aria-hidden="true"
        className="absolute -bottom-40 -left-32 -z-10 h-[560px] w-[560px] rounded-full bg-navy-500/30 blur-3xl"
      />

      <div className="container-x relative">
        <div className="max-w-3xl">
          <span className="inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 py-1.5 text-xs font-semibold uppercase tracking-wider text-white/85 backdrop-blur animate-fade-up">
            <span className="h-2 w-2 rounded-full bg-brand-gold" />
            Запуск в Ташкенте · 2026
          </span>

          <h1
            className="mt-7 text-balance text-4xl font-extrabold leading-[1.05] tracking-tight text-white sm:text-5xl lg:text-6xl xl:text-7xl animate-fade-up"
            style={{ animationDelay: "120ms" }}
          >
            Доставка из любимых мест{" "}
            <span className="bg-gold-gradient bg-clip-text text-transparent">
              за 30 минут
            </span>
          </h1>

          <p
            className="mt-6 max-w-2xl text-lg leading-relaxed text-white/85 sm:text-xl animate-fade-up"
            style={{ animationDelay: "220ms" }}
          >
            Рестораны, продукты, лекарства и электроника — в одном приложении.
            Прозрачные цены, живое отслеживание курьера на карте и оплата
            картой или Click/Payme.
          </p>

          <div
            id="download"
            className="mt-10 flex flex-col items-start gap-5 animate-fade-up"
            style={{ animationDelay: "320ms" }}
          >
            <DownloadCTA variant="light" size="lg" />
            <p className="text-sm text-white/65">
              Бесплатное приложение · iOS 15+ и Android 9+
            </p>
          </div>
        </div>

        {/* Decorative "phone preview" card on large screens */}
        <div
          className="pointer-events-none absolute right-0 top-1/2 hidden -translate-y-1/2 lg:block"
          aria-hidden="true"
        >
          <div className="relative h-[460px] w-[260px] rotate-6 rounded-[44px] border border-white/15 bg-gradient-to-b from-white/15 to-white/0 p-3 shadow-lift backdrop-blur">
            <div className="flex h-full flex-col gap-3 rounded-[34px] bg-navy-900/55 p-5">
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-semibold uppercase tracking-wider text-white/60">
                  TezKetKaz
                </span>
                <span className="rounded-full bg-brand-gold px-2 py-0.5 text-[10px] font-bold text-navy-900">
                  ETA 28 мин
                </span>
              </div>
              <div className="flex items-center gap-3 rounded-2xl bg-white/10 p-3 text-white">
                <div className="grid h-10 w-10 place-items-center rounded-full bg-brand-gold text-lg">
                  🍔
                </div>
                <div className="flex-1">
                  <div className="text-xs font-semibold">Burger Lab</div>
                  <div className="text-[10px] text-white/60">
                    4.8 ★ · 15–25 мин
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-3 rounded-2xl bg-white/10 p-3 text-white">
                <div className="grid h-10 w-10 place-items-center rounded-full bg-brand-gold text-lg">
                  🛒
                </div>
                <div className="flex-1">
                  <div className="text-xs font-semibold">Korzinka 24/7</div>
                  <div className="text-[10px] text-white/60">
                    Продукты · 20 мин
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-3 rounded-2xl bg-white/10 p-3 text-white">
                <div className="grid h-10 w-10 place-items-center rounded-full bg-brand-gold text-lg">
                  💊
                </div>
                <div className="flex-1">
                  <div className="text-xs font-semibold">Oxford Pharm</div>
                  <div className="text-[10px] text-white/60">
                    Аптека · 18 мин
                  </div>
                </div>
              </div>
              <div className="mt-auto rounded-2xl bg-brand-gold p-3 text-center">
                <div className="text-xs font-bold text-navy-900">
                  Заказать сейчас
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
