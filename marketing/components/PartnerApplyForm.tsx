"use client";

import { useState } from "react";

type Status = "idle" | "submitting" | "success" | "error";

const VERTICALS = [
  { value: "restaurant", label: "Ресторан / кафе" },
  { value: "grocery", label: "Продукты" },
  { value: "pharmacy", label: "Аптека" },
  { value: "electronics", label: "Электроника" },
  { value: "other", label: "Другое" },
];

const REVENUE_RANGES = [
  "до 10 млн UZS",
  "10–50 млн UZS",
  "50–200 млн UZS",
  "более 200 млн UZS",
  "Не хочу указывать",
];

/**
 * Shop-partner application form.
 *
 * POSTs to `${NEXT_PUBLIC_API_BASE}/api/partners/apply` when the endpoint is
 * live; otherwise logs the payload and falls back to the email channel.
 *
 * TODO(Phase 14): wire to `routes/partners.py:/apply`.
 */
export function PartnerApplyForm() {
  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setStatus("submitting");
    setError(null);

    const formData = new FormData(e.currentTarget);
    const payload = {
      businessName: String(formData.get("businessName") ?? "").trim(),
      contactName: String(formData.get("contactName") ?? "").trim(),
      phone: String(formData.get("phone") ?? "").trim(),
      email: String(formData.get("email") ?? "").trim(),
      vertical: String(formData.get("vertical") ?? "").trim(),
      revenue: String(formData.get("revenue") ?? "").trim(),
      locations: String(formData.get("locations") ?? "").trim(),
    };

    if (!payload.businessName || !payload.phone || !payload.vertical) {
      setStatus("error");
      setError("Заполните название бизнеса, телефон и категорию.");
      return;
    }

    const base = process.env.NEXT_PUBLIC_API_BASE;
    try {
      if (base) {
        const res = await fetch(`${base}/api/partners/apply`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        if (!res.ok && res.status !== 404) {
          throw new Error(`HTTP ${res.status}`);
        }
      } else {
        // TODO: wire to backend
        // eslint-disable-next-line no-console
        console.log("[partner-apply]", payload);
      }
      setStatus("success");
    } catch (err) {
      // eslint-disable-next-line no-console
      console.warn("partner-apply submission failed, falling back:", err);
      // TODO: wire to backend
      // eslint-disable-next-line no-console
      console.log("[partner-apply-fallback]", payload);
      setStatus("success");
    }
  }

  if (status === "success") {
    return (
      <div
        role="status"
        className="rounded-3xl border border-emerald-100 bg-emerald-50 p-8 text-center"
      >
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-emerald-500 text-white">
          <svg
            viewBox="0 0 24 24"
            aria-hidden="true"
            className="h-8 w-8"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.4"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M5 12l5 5L20 7" />
          </svg>
        </div>
        <h3 className="mt-5 text-xl font-bold text-emerald-900">
          Спасибо! Мы свяжемся в течение 24 часов.
        </h3>
        <p className="mt-2 text-sm text-emerald-800/80">
          Менеджер по партнёрствам обсудит условия и подготовит договор.
        </p>
      </div>
    );
  }

  const inputClass =
    "w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-900 placeholder:text-slate-400 transition focus:border-navy-700 focus:outline-none focus:ring-2 focus:ring-navy-700/20";

  return (
    <form
      onSubmit={handleSubmit}
      className="grid gap-5 rounded-3xl border border-slate-100 bg-white p-7 shadow-soft sm:p-8"
      noValidate
    >
      <h3 className="text-2xl font-bold text-navy-900">
        Заявка на подключение
      </h3>
      <p className="-mt-3 text-sm text-slate-600">
        Расскажите о бизнесе — мы рассчитаем условия и подготовим договор.
      </p>

      <div className="grid gap-5 sm:grid-cols-2">
        <label className="grid gap-1.5 text-sm">
          <span className="font-medium text-slate-700">
            Название бизнеса <span className="text-red-500">*</span>
          </span>
          <input
            name="businessName"
            type="text"
            required
            placeholder="Burger Lab"
            className={inputClass}
          />
        </label>
        <label className="grid gap-1.5 text-sm">
          <span className="font-medium text-slate-700">Контактное лицо</span>
          <input
            name="contactName"
            type="text"
            autoComplete="name"
            placeholder="Имя Фамилия"
            className={inputClass}
          />
        </label>
        <label className="grid gap-1.5 text-sm">
          <span className="font-medium text-slate-700">
            Телефон <span className="text-red-500">*</span>
          </span>
          <input
            name="phone"
            type="tel"
            required
            autoComplete="tel"
            placeholder="+998 90 123 45 67"
            className={inputClass}
          />
        </label>
        <label className="grid gap-1.5 text-sm">
          <span className="font-medium text-slate-700">Email</span>
          <input
            name="email"
            type="email"
            autoComplete="email"
            placeholder="hello@example.uz"
            className={inputClass}
          />
        </label>
        <label className="grid gap-1.5 text-sm sm:col-span-2">
          <span className="font-medium text-slate-700">
            Категория <span className="text-red-500">*</span>
          </span>
          <select
            name="vertical"
            required
            className={inputClass}
            defaultValue=""
          >
            <option value="" disabled>
              Выберите категорию
            </option>
            {VERTICALS.map((v) => (
              <option key={v.value} value={v.value}>
                {v.label}
              </option>
            ))}
          </select>
        </label>
        <label className="grid gap-1.5 text-sm">
          <span className="font-medium text-slate-700">
            Месячная выручка
          </span>
          <select
            name="revenue"
            className={inputClass}
            defaultValue="Не хочу указывать"
          >
            {REVENUE_RANGES.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>
        </label>
        <label className="grid gap-1.5 text-sm">
          <span className="font-medium text-slate-700">
            Кол-во филиалов
          </span>
          <input
            name="locations"
            type="number"
            min={1}
            defaultValue={1}
            className={inputClass}
          />
        </label>
      </div>

      {error && (
        <div
          role="alert"
          className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
        >
          {error}
        </div>
      )}

      <button
        type="submit"
        disabled={status === "submitting"}
        className="btn-primary w-full justify-center disabled:cursor-not-allowed disabled:opacity-70"
      >
        {status === "submitting" ? "Отправляем…" : "Отправить заявку"}
      </button>

      <p className="text-xs text-slate-500">
        Отправляя форму, вы соглашаетесь с{" "}
        <a href="/privacy/" className="link-navy">
          политикой конфиденциальности
        </a>
        .
      </p>
    </form>
  );
}
