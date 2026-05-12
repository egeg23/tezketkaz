"use client";

// Phase 13.2.9 — GDPR-style cookie consent banner.
//
// Persists the user's choice to `localStorage.cookie_consent` as either
// `'accepted'` or `'rejected'`. Once a value is present, the banner stays
// hidden on subsequent renders. Other modules can read the same key (see
// `getCookieConsent`) before initialising analytics so rejected users
// genuinely don't get tracked.

import { useEffect, useState } from "react";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";

const STORAGE_KEY = "cookie_consent";

export type CookieConsent = "accepted" | "rejected";

export function getCookieConsent(): CookieConsent | null {
  if (typeof window === "undefined") return null;
  const v = window.localStorage.getItem(STORAGE_KEY);
  if (v === "accepted" || v === "rejected") return v;
  return null;
}

export function CookieBanner() {
  // Start hidden on SSR. We flip to visible only after the effect confirms
  // the user hasn't already chosen — avoids a flash of the banner on
  // hydration for returning users.
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (getCookieConsent() == null) setVisible(true);
  }, []);

  function persist(choice: CookieConsent) {
    try {
      window.localStorage.setItem(STORAGE_KEY, choice);
    } catch {
      // localStorage can throw in private-mode Safari; failing silently
      // means the banner will reappear on next visit, which is acceptable.
    }
    setVisible(false);
  }

  if (!visible) return null;

  return (
    <div
      role="dialog"
      aria-live="polite"
      aria-label="Cookie consent"
      className="fixed bottom-4 left-4 right-4 z-50 mx-auto max-w-2xl rounded-lg border bg-card shadow-lg sm:left-auto sm:right-4"
    >
      <div className="flex items-start gap-4 p-4">
        <div className="flex-1 text-sm">
          <p className="text-foreground">
            Мы используем cookies для аналитики. Подробнее в{" "}
            <a
              href="/legal/privacy"
              className="font-medium text-primary underline-offset-4 hover:underline"
            >
              политике конфиденциальности
            </a>
            .
          </p>
        </div>
        <button
          type="button"
          onClick={() => persist("rejected")}
          aria-label="Закрыть"
          className="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-accent-foreground"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
      <div className="flex items-center justify-end gap-2 border-t bg-muted/40 px-4 py-3">
        <Button variant="outline" size="sm" onClick={() => persist("rejected")}>
          Отклонить
        </Button>
        <Button size="sm" onClick={() => persist("accepted")}>
          Принять
        </Button>
      </div>
    </div>
  );
}
