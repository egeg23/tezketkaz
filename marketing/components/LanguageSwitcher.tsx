"use client";

import { useEffect, useState } from "react";

type Locale = "ru" | "uz" | "en";

const LABELS: Record<Locale, string> = {
  ru: "RU",
  uz: "UZ",
  en: "EN",
};

interface LanguageSwitcherProps {
  variant?: "light" | "dark";
}

/**
 * UI-only language switcher for the pre-i18n marketing site (Phase 13.3.5).
 *
 * Selection is persisted in localStorage so it survives page navigation but
 * the actual translations land in Phase 14 alongside `app/[locale]/...`.
 * For now, switching only swaps a couple of static UI labels via a custom
 * event that interested components can opt into.
 */
export function LanguageSwitcher({
  variant = "light",
}: LanguageSwitcherProps) {
  const [open, setOpen] = useState(false);
  const [locale, setLocale] = useState<Locale>("ru");

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem("tkz-locale") as Locale | null;
      if (stored && ["ru", "uz", "en"].includes(stored)) {
        setLocale(stored);
      }
    } catch {
      // ignore — SSR / privacy mode
    }
  }, []);

  function pick(next: Locale) {
    setLocale(next);
    setOpen(false);
    try {
      window.localStorage.setItem("tkz-locale", next);
      window.dispatchEvent(
        new CustomEvent("tkz:locale-change", { detail: next }),
      );
    } catch {
      // ignore
    }
  }

  const isLight = variant === "light";
  const triggerClass = isLight
    ? "inline-flex items-center gap-1 rounded-full border border-white/25 bg-white/5 px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-white backdrop-blur transition hover:bg-white/10"
    : "inline-flex items-center gap-1 rounded-full border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-slate-700 transition hover:border-navy-700 hover:text-navy-900";

  return (
    <div className="relative">
      <button
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label="Сменить язык"
        className={triggerClass}
        onClick={() => setOpen((v) => !v)}
        onBlur={() => setTimeout(() => setOpen(false), 120)}
      >
        <span aria-hidden="true">🌐</span>
        <span>{LABELS[locale]}</span>
      </button>

      {open && (
        <ul
          role="listbox"
          className="absolute right-0 top-full z-50 mt-2 w-28 overflow-hidden rounded-xl border border-slate-100 bg-white shadow-lift"
        >
          {(["ru", "uz", "en"] as Locale[]).map((code) => (
            <li key={code}>
              <button
                type="button"
                role="option"
                aria-selected={locale === code}
                onClick={() => pick(code)}
                className={`flex w-full items-center justify-between px-3 py-2 text-left text-sm transition ${
                  locale === code
                    ? "bg-navy-50 text-navy-900"
                    : "text-slate-700 hover:bg-slate-50"
                }`}
              >
                <span className="font-semibold">{LABELS[code]}</span>
                <span className="text-xs text-slate-500">
                  {code === "ru"
                    ? "Русский"
                    : code === "uz"
                      ? "Oʻzbekcha"
                      : "English"}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
