"use client";

import * as React from "react";
import { useAuth } from "./auth";
import { useShop } from "./queries";
import type { Shop } from "./queries";

interface ShopContextValue {
  shopId: string | null;
  shop: Shop | null;
  isLoading: boolean;
  error: Error | null;
}

const ShopContext = React.createContext<ShopContextValue>({
  shopId: null,
  shop: null,
  isLoading: false,
  error: null,
});

export function ShopProvider({ children }: { children: React.ReactNode }) {
  const currentShopId = useAuth((s) => s.currentShopId);
  const { data, isLoading, error } = useShop(currentShopId);

  const value: ShopContextValue = React.useMemo(
    () => ({
      shopId: currentShopId,
      shop: data?.shop ?? null,
      isLoading,
      error: (error as Error) || null,
    }),
    [currentShopId, data, isLoading, error]
  );

  return <ShopContext.Provider value={value}>{children}</ShopContext.Provider>;
}

export function useCurrentShop() {
  return React.useContext(ShopContext);
}
