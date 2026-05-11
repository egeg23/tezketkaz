"use client";

import { useState } from "react";

interface DownloadCTAProps {
  variant?: "light" | "dark";
  size?: "md" | "lg";
}

/**
 * App Store / Google Play badges.
 *
 * Real store URLs are not available pre-launch, so clicking surfaces a
 * tooltip "Скоро в App Store / Google Play". Replace the href values once
 * the app is published.
 */
export function DownloadCTA({
  variant = "light",
  size = "lg",
}: DownloadCTAProps) {
  const [tooltipFor, setTooltipFor] = useState<"ios" | "android" | null>(null);

  const padding =
    size === "lg" ? "px-6 py-3.5 sm:px-7 sm:py-4" : "px-5 py-3";
  const baseLight =
    "group relative inline-flex items-center gap-3 rounded-2xl border border-white/20 bg-black/60 text-white shadow-soft backdrop-blur transition hover:bg-black/75 hover:-translate-y-0.5";
  const baseDark =
    "group relative inline-flex items-center gap-3 rounded-2xl border border-navy-900 bg-navy-900 text-white shadow-soft transition hover:bg-navy-700 hover:-translate-y-0.5";

  const baseClass = variant === "light" ? baseLight : baseDark;

  function showTooltip(which: "ios" | "android") {
    setTooltipFor(which);
    window.setTimeout(() => setTooltipFor(null), 2400);
  }

  return (
    <div className="flex flex-wrap items-center gap-3">
      <a
        href="#"
        aria-label="Скоро в App Store"
        onClick={(e) => {
          e.preventDefault();
          showTooltip("ios");
        }}
        className={`${baseClass} ${padding}`}
      >
        <svg
          viewBox="0 0 24 24"
          aria-hidden="true"
          className="h-7 w-7 fill-current"
        >
          <path d="M17.05 12.74c-.02-2.31 1.89-3.43 1.98-3.48-1.08-1.58-2.76-1.8-3.36-1.82-1.43-.15-2.79.84-3.51.84-.74 0-1.85-.82-3.05-.8-1.56.02-3.01.91-3.82 2.31-1.63 2.83-.42 7.01 1.17 9.31.78 1.12 1.71 2.37 2.93 2.33 1.18-.05 1.63-.76 3.06-.76 1.43 0 1.83.76 3.07.74 1.27-.02 2.07-1.13 2.85-2.26.9-1.3 1.27-2.56 1.29-2.62-.03-.01-2.47-.95-2.5-3.77-.02-2.35 1.91-3.48 2-3.54zm-2.34-6.5c.65-.79 1.09-1.88.97-2.97-.93.04-2.07.63-2.74 1.4-.6.69-1.13 1.81-.99 2.86 1.04.08 2.11-.52 2.76-1.29z" />
        </svg>
        <span className="flex flex-col items-start text-left leading-tight">
          <span className="text-[10px] uppercase tracking-wide opacity-80">
            Скоро в
          </span>
          <span className="text-base font-semibold">App Store</span>
        </span>
        {tooltipFor === "ios" && (
          <span
            role="status"
            className="absolute -top-9 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-md bg-navy-900 px-3 py-1.5 text-xs font-medium text-white shadow-lift"
          >
            Скоро в App Store
          </span>
        )}
      </a>

      <a
        href="#"
        aria-label="Скоро в Google Play"
        onClick={(e) => {
          e.preventDefault();
          showTooltip("android");
        }}
        className={`${baseClass} ${padding}`}
      >
        <svg
          viewBox="0 0 24 24"
          aria-hidden="true"
          className="h-7 w-7 fill-current"
        >
          <path d="M3.6 2.1c-.3.3-.5.7-.5 1.2v17.3c0 .5.2.9.5 1.2l9.4-9.9-9.4-9.8zm10.4 8.7L5.8 2.3l11.7 6.7-3.5 3.5-.0-1.7zm0 2.4l3.5 3.5L5.8 21.7l8.2-8.5zM18.6 11l3.1 1.8c.6.4.6 1.4 0 1.8l-3.1 1.8-3.7-3.7L18.6 11z" />
        </svg>
        <span className="flex flex-col items-start text-left leading-tight">
          <span className="text-[10px] uppercase tracking-wide opacity-80">
            Скоро в
          </span>
          <span className="text-base font-semibold">Google Play</span>
        </span>
        {tooltipFor === "android" && (
          <span
            role="status"
            className="absolute -top-9 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-md bg-navy-900 px-3 py-1.5 text-xs font-medium text-white shadow-lift"
          >
            Скоро в Google Play
          </span>
        )}
      </a>
    </div>
  );
}
