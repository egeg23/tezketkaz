import type { Metadata } from "next";
import "./globals.css";
import { QueryProvider } from "@/components/query-provider";
import { Toaster } from "@/components/ui/sonner";
import { CookieBanner } from "@/components/CookieBanner";

export const metadata: Metadata = {
  title: "TezKetKaz Vendor",
  description: "TezKetKaz vendor portal for shop owners",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <QueryProvider>
          {children}
          <Toaster />
          <CookieBanner />
        </QueryProvider>
      </body>
    </html>
  );
}
