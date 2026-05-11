import Link from "next/link";
import { Logo } from "./Logo";
import { LanguageSwitcher } from "./LanguageSwitcher";

interface NavProps {
  variant?: "light" | "dark";
}

/**
 * Top navigation bar — server component. Sticky on scroll, transparent over
 * dark hero (variant="light") or solid white over light page bodies.
 */
export function Nav({ variant = "light" }: NavProps) {
  const isLight = variant === "light";

  const wrapperClass = isLight
    ? "absolute inset-x-0 top-0 z-40"
    : "sticky top-0 z-40 border-b border-slate-100 bg-white/85 backdrop-blur";

  const linkClass = isLight
    ? "text-sm font-medium text-white/85 transition hover:text-white"
    : "text-sm font-medium text-slate-700 transition hover:text-navy-900";

  return (
    <header className={wrapperClass}>
      <div className="container-x flex h-20 items-center justify-between">
        <Logo variant={isLight ? "light" : "dark"} />

        <nav
          aria-label="Главное меню"
          className="hidden items-center gap-8 md:flex"
        >
          <Link href="/#verticals" className={linkClass}>
            Категории
          </Link>
          <Link href="/couriers" className={linkClass}>
            Курьерам
          </Link>
          <Link href="/partners" className={linkClass}>
            Партнёрам
          </Link>
        </nav>

        <div className="flex items-center gap-3">
          <LanguageSwitcher variant={variant} />
          <Link
            href="/#download"
            className={
              isLight
                ? "btn-primary hidden text-xs sm:inline-flex"
                : "btn-primary hidden text-xs sm:inline-flex"
            }
          >
            Скачать
          </Link>
        </div>
      </div>
    </header>
  );
}
