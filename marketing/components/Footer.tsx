import Link from "next/link";
import { Logo } from "./Logo";

/**
 * Site footer with sitemap, social links, and legal info.
 *
 * Social links are placeholders — replace `href` values once the marketing
 * team confirms the production handles.
 */
export function Footer() {
  const year = new Date().getFullYear();

  return (
    <footer className="bg-navy-900 text-white">
      <div className="container-x py-16 lg:py-20">
        <div className="grid gap-12 lg:grid-cols-[1.4fr_1fr_1fr_1fr]">
          <div>
            <Logo variant="light" />
            <p className="mt-5 max-w-sm text-sm leading-relaxed text-white/70">
              TezKetKaz — сервис быстрой доставки в Ташкенте. Скоро в
              Самарканде, Алматы и Бишкеке.
            </p>
            <div className="mt-7 flex items-center gap-3">
              <a
                href="https://t.me/tezketkaz"
                aria-label="Telegram TezKetKaz"
                target="_blank"
                rel="noopener noreferrer"
                className="grid h-10 w-10 place-items-center rounded-full border border-white/20 bg-white/5 transition hover:bg-white/10"
              >
                <svg
                  viewBox="0 0 24 24"
                  className="h-5 w-5 fill-current"
                  aria-hidden="true"
                >
                  <path d="M9.04 16.62l-.36 4.04c.52 0 .74-.22 1.01-.49l2.42-2.32 5.02 3.66c.92.51 1.57.24 1.81-.85L22.93 4.5c.32-1.37-.5-1.91-1.39-1.58L2.36 10.16c-1.35.52-1.33 1.27-.23 1.61l4.96 1.55L18.7 6.27c.54-.32 1.03-.14.63.21" />
                </svg>
              </a>
              <a
                href="https://instagram.com/tezketkaz"
                aria-label="Instagram TezKetKaz"
                target="_blank"
                rel="noopener noreferrer"
                className="grid h-10 w-10 place-items-center rounded-full border border-white/20 bg-white/5 transition hover:bg-white/10"
              >
                <svg
                  viewBox="0 0 24 24"
                  className="h-5 w-5"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.7"
                  aria-hidden="true"
                >
                  <rect x="3" y="3" width="18" height="18" rx="5" />
                  <circle cx="12" cy="12" r="4" />
                  <circle cx="17.5" cy="6.5" r="0.9" fill="currentColor" />
                </svg>
              </a>
              <a
                href="mailto:hello@tezketkaz.uz"
                aria-label="Написать на почту"
                className="grid h-10 w-10 place-items-center rounded-full border border-white/20 bg-white/5 transition hover:bg-white/10"
              >
                <svg
                  viewBox="0 0 24 24"
                  className="h-5 w-5"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.7"
                  aria-hidden="true"
                >
                  <rect x="3" y="5" width="18" height="14" rx="2" />
                  <path d="M3 7l9 6 9-6" />
                </svg>
              </a>
            </div>
          </div>

          <div>
            <h3 className="text-xs font-semibold uppercase tracking-[0.2em] text-white/60">
              Продукт
            </h3>
            <ul className="mt-5 space-y-3 text-sm text-white/85">
              <li>
                <Link href="/#verticals" className="hover:text-brand-gold">
                  Категории
                </Link>
              </li>
              <li>
                <Link href="/#download" className="hover:text-brand-gold">
                  Скачать приложение
                </Link>
              </li>
            </ul>
          </div>

          <div>
            <h3 className="text-xs font-semibold uppercase tracking-[0.2em] text-white/60">
              Сотрудничество
            </h3>
            <ul className="mt-5 space-y-3 text-sm text-white/85">
              <li>
                <Link href="/partners" className="hover:text-brand-gold">
                  Стать партнёром
                </Link>
              </li>
              <li>
                <Link href="/couriers" className="hover:text-brand-gold">
                  Стать курьером
                </Link>
              </li>
            </ul>
          </div>

          <div>
            <h3 className="text-xs font-semibold uppercase tracking-[0.2em] text-white/60">
              Правовое
            </h3>
            <ul className="mt-5 space-y-3 text-sm text-white/85">
              <li>
                <Link href="/privacy" className="hover:text-brand-gold">
                  Политика конфиденциальности
                </Link>
              </li>
              <li>
                <Link href="/terms" className="hover:text-brand-gold">
                  Условия использования
                </Link>
              </li>
            </ul>
          </div>
        </div>

        <div className="mt-14 flex flex-col items-start justify-between gap-4 border-t border-white/10 pt-8 text-xs text-white/55 sm:flex-row sm:items-center">
          <p>© {year} TezKetKaz. Все права защищены.</p>
          <p>Ташкент · Узбекистан</p>
        </div>
      </div>
    </footer>
  );
}
