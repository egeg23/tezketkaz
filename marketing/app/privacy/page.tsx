import type { Metadata } from "next";
import { Nav } from "@/components/Nav";
import { Footer } from "@/components/Footer";

export const metadata: Metadata = {
  title: "Политика конфиденциальности",
  description:
    "Политика конфиденциальности TezKetKaz — как мы собираем, храним и используем данные пользователей сервиса доставки.",
};

const apiBase = process.env.NEXT_PUBLIC_API_BASE ?? "https://api.tezketkaz.uz";

/**
 * Static stub that links to the canonical privacy policy served by the
 * backend (`/api/legal/privacy?locale=ru`). The backend page renders the
 * latest, version-stamped legal text and is what the mobile app embeds.
 */
export default function PrivacyPage() {
  const ruUrl = `${apiBase}/api/legal/privacy?locale=ru`;
  const uzUrl = `${apiBase}/api/legal/privacy?locale=uz`;
  const enUrl = `${apiBase}/api/legal/privacy?locale=en`;

  return (
    <>
      <Nav variant="dark" />
      <main className="bg-white">
        <article className="container-x max-w-3xl py-20 lg:py-28">
          <p className="text-sm font-semibold uppercase tracking-[0.2em] text-navy-700">
            Правовое
          </p>
          <h1 className="mt-3 text-4xl font-extrabold tracking-tight text-navy-900 sm:text-5xl">
            Политика конфиденциальности
          </h1>
          <p className="mt-5 text-base leading-relaxed text-slate-600">
            Полный текст политики конфиденциальности TezKetKaz, включая
            актуальный реестр обрабатываемых данных, публикуется на сервере
            и обновляется автоматически.
          </p>

          <div className="mt-10 space-y-4">
            <a
              href={ruUrl}
              className="flex items-center justify-between rounded-2xl border border-slate-100 bg-slate-50 px-6 py-5 transition hover:border-navy-700 hover:bg-white hover:shadow-soft"
            >
              <div>
                <div className="text-base font-semibold text-navy-900">
                  Открыть на русском
                </div>
                <div className="mt-1 text-xs text-slate-500">{ruUrl}</div>
              </div>
              <span aria-hidden="true" className="text-navy-700">
                →
              </span>
            </a>
            <a
              href={uzUrl}
              className="flex items-center justify-between rounded-2xl border border-slate-100 bg-slate-50 px-6 py-5 transition hover:border-navy-700 hover:bg-white hover:shadow-soft"
            >
              <div>
                <div className="text-base font-semibold text-navy-900">
                  Oʻzbekcha versiya
                </div>
                <div className="mt-1 text-xs text-slate-500">{uzUrl}</div>
              </div>
              <span aria-hidden="true" className="text-navy-700">
                →
              </span>
            </a>
            <a
              href={enUrl}
              className="flex items-center justify-between rounded-2xl border border-slate-100 bg-slate-50 px-6 py-5 transition hover:border-navy-700 hover:bg-white hover:shadow-soft"
            >
              <div>
                <div className="text-base font-semibold text-navy-900">
                  English version
                </div>
                <div className="mt-1 text-xs text-slate-500">{enUrl}</div>
              </div>
              <span aria-hidden="true" className="text-navy-700">
                →
              </span>
            </a>
          </div>

          <p className="mt-12 text-sm text-slate-500">
            Связаться по вопросам обработки данных:{" "}
            <a
              href="mailto:privacy@tezketkaz.uz"
              className="link-navy"
            >
              privacy@tezketkaz.uz
            </a>
            .
          </p>
        </article>
      </main>
      <Footer />
    </>
  );
}
