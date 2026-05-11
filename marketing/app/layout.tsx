import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import Script from "next/script";
import "./globals.css";

const inter = Inter({
  subsets: ["latin", "cyrillic"],
  display: "swap",
  variable: "--font-inter",
});

const SITE_URL = "https://tezketkaz.uz";
const SITE_TITLE = "TezKetKaz — Доставка из любимых мест за 30 минут";
const SITE_DESCRIPTION =
  "TezKetKaz — сервис быстрой доставки в Ташкенте: рестораны, продукты, аптеки и электроника. Закажите в приложении и получите за 30 минут.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: SITE_TITLE,
    template: "%s · TezKetKaz",
  },
  description: SITE_DESCRIPTION,
  applicationName: "TezKetKaz",
  keywords: [
    "TezKetKaz",
    "доставка",
    "Ташкент",
    "Узбекистан",
    "еда",
    "продукты",
    "аптека",
    "электроника",
    "delivery Tashkent",
  ],
  authors: [{ name: "TezKetKaz" }],
  openGraph: {
    type: "website",
    locale: "ru_RU",
    url: SITE_URL,
    siteName: "TezKetKaz",
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    images: [
      {
        url: "/og-image.png",
        width: 1200,
        height: 630,
        alt: "TezKetKaz — быстрая доставка по Ташкенту",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    images: ["/og-image.png"],
  },
  icons: {
    icon: [
      { url: "/icon.png", sizes: "any" },
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
    ],
    apple: "/icon-192.png",
  },
  robots: {
    index: true,
    follow: true,
  },
  alternates: {
    canonical: SITE_URL,
  },
};

export const viewport: Viewport = {
  themeColor: "#1A237E",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ru" className={inter.variable}>
      <body className="bg-white font-sans text-slate-900 antialiased">
        {children}
        {/* Reveal-on-scroll observer (CSS-only animation triggered via data
            attribute). Tiny inline script — no framer-motion dependency. */}
        <Script id="reveal-observer" strategy="afterInteractive">
          {`
            (function () {
              if (typeof window === 'undefined') return;
              var els = document.querySelectorAll('.reveal');
              if (!('IntersectionObserver' in window) || !els.length) {
                els.forEach(function (el) { el.setAttribute('data-revealed', 'true'); });
                return;
              }
              var io = new IntersectionObserver(function (entries) {
                entries.forEach(function (entry) {
                  if (entry.isIntersecting) {
                    entry.target.setAttribute('data-revealed', 'true');
                    io.unobserve(entry.target);
                  }
                });
              }, { rootMargin: '0px 0px -10% 0px', threshold: 0.08 });
              els.forEach(function (el) { io.observe(el); });
            })();
          `}
        </Script>
      </body>
    </html>
  );
}
