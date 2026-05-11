export interface FaqItem {
  question: string;
  answer: string;
}

interface FaqProps {
  title: string;
  items: FaqItem[];
}

/**
 * Pure-HTML accordion using <details>/<summary> — no client state, no
 * JavaScript, fully accessible by default, expandable by keyboard.
 */
export function Faq({ title, items }: FaqProps) {
  return (
    <section id="faq" className="section-y bg-white">
      <div className="container-x grid gap-12 lg:grid-cols-[1fr_2fr] lg:items-start">
        <div className="reveal">
          <p className="text-sm font-semibold uppercase tracking-[0.2em] text-navy-700">
            FAQ
          </p>
          <h2 className="mt-3 text-3xl font-bold tracking-tight text-navy-900 sm:text-4xl">
            {title}
          </h2>
          <p className="mt-4 text-base leading-relaxed text-slate-600">
            Не нашли ответ? Напишите на{" "}
            <a href="mailto:hello@tezketkaz.uz" className="link-navy">
              hello@tezketkaz.uz
            </a>{" "}
            — ответим в течение дня.
          </p>
        </div>

        <div className="space-y-3 reveal">
          {items.map((it) => (
            <details
              key={it.question}
              className="group rounded-2xl border border-slate-100 bg-slate-50/40 px-6 py-5 transition open:bg-white open:shadow-soft"
            >
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-left text-base font-semibold text-navy-900">
                <span>{it.question}</span>
                <span
                  aria-hidden="true"
                  className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-navy-50 text-navy-900 transition group-open:rotate-45"
                >
                  <svg
                    viewBox="0 0 24 24"
                    className="h-4 w-4"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.4"
                    strokeLinecap="round"
                  >
                    <path d="M12 5v14M5 12h14" />
                  </svg>
                </span>
              </summary>
              <p className="mt-3 text-sm leading-relaxed text-slate-600">
                {it.answer}
              </p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
