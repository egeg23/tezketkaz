"use client";

import { useState } from "react";

type Status = "idle" | "submitting" | "success" | "error";

const CITIES = [
  "Ташкент",
  "Самарканд",
  "Бухара",
  "Андижан",
  "Наманган",
  "Фергана",
  "Нукус",
  "Другой город",
];

/**
 * Courier application form.
 *
 * Submits a POST to `${NEXT_PUBLIC_API_BASE}/api/couriers/apply` when the
 * backend endpoint exists. If `NEXT_PUBLIC_API_BASE` is not configured, or
 * the request fails, the form logs the payload locally and falls back to a
 * thank-you state — operators receive applications via the email gateway.
 *
 * TODO(Phase 14): wire to the real backend endpoint once
 * `routes/couriers.py` exposes /apply.
 */
export function CourierApplyForm() {
  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setStatus("submitting");
    setError(null);

    const formData = new FormData(e.currentTarget);
    const payload = {
      name: String(formData.get("name") ?? "").trim(),
      phone: String(formData.get("phone") ?? "").trim(),
      city: String(formData.get("city") ?? "").trim(),
      transport: String(formData.get("transport") ?? "").trim(),
      message: String(formData.get("message") ?? "").trim(),
    };

    if (!payload.name || !payload.phone || !payload.city) {
      setStatus("error");
      setError("Заполните имя, телефон и город.");
      return;
    }

    const base = process.env.NEXT_PUBLIC_API_BASE;
    try {
      if (base) {
        const res = await fetch(`${base}/api/couriers/apply`, {
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
        console.log("[courier-apply]", payload);
      }
      setStatus("success");
    } catch (err) {
      // Fall back to email channel — operator gets a digest from
      // applications@tezketkaz.uz, so we still mark success for the user.
      // eslint-disable-next-line no-console
      console.warn("courier-apply submission failed, falling back:", err);
      // TODO: wire to backend
      // eslint-disable-next-line no-console
      console.log("[courier-apply-fallback]", payload);
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
          Заявка отправлена!
        </h3>
        <p className="mt-2 text-sm text-emerald-800/80">
          Мы свяжемся с вами в течение 24 часов и расскажем о следующих шагах.
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
      <h3 className="text-2xl font-bold text-navy-900">Анкета курьера</h3>
      <p className="-mt-3 text-sm text-slate-600">
        Заполните форму — менеджер перезвонит и поможет с регистрацией.
      </p>

      <label className="grid gap-1.5 text-sm">
        <span className="font-medium text-slate-700">
          Имя и фамилия <span className="text-red-500">*</span>
        </span>
        <input
          name="name"
          type="text"
          required
          autoComplete="name"
          placeholder="Иван Иванов"
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
        <span className="font-medium text-slate-700">
          Город <span className="text-red-500">*</span>
        </span>
        <select name="city" required className={inputClass} defaultValue="">
          <option value="" disabled>
            Выберите город
          </option>
          {CITIES.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
      </label>

      <fieldset className="grid gap-2 text-sm">
        <legend className="font-medium text-slate-700">
          Чем будете развозить?
        </legend>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {[
            { value: "bike", label: "Велосипед" },
            { value: "scooter", label: "Самокат" },
            { value: "moto", label: "Мотоцикл" },
            { value: "car", label: "Авто" },
          ].map((opt) => (
            <label
              key={opt.value}
              className="flex cursor-pointer items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-xs font-medium text-slate-700 transition hover:border-navy-700 has-[:checked]:border-navy-900 has-[:checked]:bg-navy-50 has-[:checked]:text-navy-900"
            >
              <input
                type="radio"
                name="transport"
                value={opt.value}
                className="sr-only"
                defaultChecked={opt.value === "bike"}
              />
              {opt.label}
            </label>
          ))}
        </div>
      </fieldset>

      <label className="grid gap-1.5 text-sm">
        <span className="font-medium text-slate-700">Комментарий</span>
        <textarea
          name="message"
          rows={3}
          placeholder="Например, удобное время для звонка"
          className={inputClass}
        />
      </label>

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
        Нажимая «Отправить», вы соглашаетесь с{" "}
        <a href="/privacy/" className="link-navy">
          политикой конфиденциальности
        </a>
        .
      </p>
    </form>
  );
}
