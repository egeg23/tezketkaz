"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";

export interface AdminUser {
  id: string;
  name?: string;
  phone?: string;
  isAdmin: boolean;
  [k: string]: unknown;
}

interface AuthState {
  accessToken: string | null;
  refreshToken: string | null;
  user: AdminUser | null;
  setSession: (s: { accessToken: string; refreshToken: string; user: AdminUser }) => void;
  setAccessToken: (t: string) => void;
  clear: () => void;
}

export const useAuth = create<AuthState>()(
  persist(
    (set) => ({
      accessToken: null,
      refreshToken: null,
      user: null,
      setSession: ({ accessToken, refreshToken, user }) =>
        set({ accessToken, refreshToken, user }),
      setAccessToken: (t) => set({ accessToken: t }),
      clear: () => set({ accessToken: null, refreshToken: null, user: null }),
    }),
    { name: "tkk-admin-auth" }
  )
);

export function getStoredTokens() {
  if (typeof window === "undefined") return { accessToken: null, refreshToken: null };
  const { accessToken, refreshToken } = useAuth.getState();
  return { accessToken, refreshToken };
}
