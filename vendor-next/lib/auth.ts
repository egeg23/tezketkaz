"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";

export interface ShopMembership {
  id: string;
  name: string;
  role: string;
}

export interface ShopUser {
  id: string;
  name?: string | null;
  phone?: string | null;
  isShop: boolean;
  isAdmin?: boolean;
  isBuyer?: boolean;
  isCourier?: boolean;
  locale?: string;
  // Backend's /api/auth/me returns shop memberships under `shops`.
  shops?: ShopMembership[];
  [k: string]: unknown;
}

interface AuthState {
  accessToken: string | null;
  refreshToken: string | null;
  user: ShopUser | null;
  currentShopId: string | null;
  setSession: (s: { accessToken: string; refreshToken: string; user: ShopUser }) => void;
  setAccessToken: (t: string) => void;
  setUser: (user: ShopUser) => void;
  setCurrentShopId: (id: string | null) => void;
  clear: () => void;
}

export const useAuth = create<AuthState>()(
  persist(
    (set, get) => ({
      accessToken: null,
      refreshToken: null,
      user: null,
      currentShopId: null,
      setSession: ({ accessToken, refreshToken, user }) => {
        // Pick the first shop membership as the default working shop.
        const firstShop = user.shops?.[0];
        const prev = get().currentShopId;
        // Keep the previously selected shop if it's still in the list.
        const keep =
          prev && user.shops?.some((s) => s.id === prev) ? prev : firstShop?.id ?? null;
        set({ accessToken, refreshToken, user, currentShopId: keep });
      },
      setAccessToken: (t) => set({ accessToken: t }),
      setUser: (user) => {
        const prev = get().currentShopId;
        const firstShop = user.shops?.[0];
        const keep =
          prev && user.shops?.some((s) => s.id === prev) ? prev : firstShop?.id ?? null;
        set({ user, currentShopId: keep });
      },
      setCurrentShopId: (id) => set({ currentShopId: id }),
      clear: () =>
        set({ accessToken: null, refreshToken: null, user: null, currentShopId: null }),
    }),
    { name: "tkk-vendor-auth" }
  )
);

export function getStoredTokens() {
  if (typeof window === "undefined") return { accessToken: null, refreshToken: null };
  const { accessToken, refreshToken } = useAuth.getState();
  return { accessToken, refreshToken };
}
