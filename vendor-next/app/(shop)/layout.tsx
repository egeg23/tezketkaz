"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";
import { ShopSidebar } from "@/components/shop-sidebar";
import { ShopProvider } from "@/lib/shop-context";

export default function ShopLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const { accessToken, user, currentShopId } = useAuth();

  useEffect(() => {
    if (!accessToken || !user?.isShop) {
      router.replace("/login");
    }
  }, [accessToken, user, router]);

  if (!accessToken || !user?.isShop) {
    return (
      <div className="flex min-h-screen items-center justify-center text-sm text-muted-foreground">
        Redirecting...
      </div>
    );
  }

  return (
    <ShopProvider>
      <div className="flex min-h-screen">
        <ShopSidebar />
        <main className="flex-1 overflow-auto bg-muted/30 p-6">
          {currentShopId ? (
            children
          ) : (
            <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
              No shop linked to this account. Contact support.
            </div>
          )}
        </main>
      </div>
    </ShopProvider>
  );
}
