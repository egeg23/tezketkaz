"use client";

import { useAuth } from "./auth";

export const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000";

export class ApiError extends Error {
  status: number;
  body: unknown;
  constructor(status: number, message: string, body: unknown) {
    super(message);
    this.status = status;
    this.body = body;
  }
}

interface ApiOptions extends Omit<RequestInit, "body"> {
  body?: unknown;
  // Set true to skip auth refresh-on-401 dance (e.g. login endpoints).
  skipAuth?: boolean;
}

let refreshInFlight: Promise<string | null> | null = null;

async function refreshAccessToken(): Promise<string | null> {
  const { refreshToken, clear, setAccessToken } = useAuth.getState();
  if (!refreshToken) return null;
  if (!refreshInFlight) {
    refreshInFlight = (async () => {
      try {
        const r = await fetch(`${API_URL}/api/auth/refresh`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ refreshToken }),
        });
        if (!r.ok) {
          clear();
          return null;
        }
        const j = (await r.json()) as { accessToken: string };
        setAccessToken(j.accessToken);
        return j.accessToken;
      } catch {
        clear();
        return null;
      } finally {
        refreshInFlight = null;
      }
    })();
  }
  return refreshInFlight;
}

export async function api<T = unknown>(
  path: string,
  opts: ApiOptions = {}
): Promise<T> {
  const url = path.startsWith("http") ? path : `${API_URL}${path}`;
  const { accessToken } = useAuth.getState();

  const headers: Record<string, string> = {
    accept: "application/json",
    ...((opts.headers as Record<string, string>) || {}),
  };
  if (opts.body !== undefined && !(opts.body instanceof FormData)) {
    headers["content-type"] = "application/json";
  }
  if (!opts.skipAuth && accessToken) {
    headers["authorization"] = `Bearer ${accessToken}`;
  }

  const init: RequestInit = {
    ...opts,
    headers,
    body:
      opts.body === undefined
        ? undefined
        : opts.body instanceof FormData
          ? opts.body
          : JSON.stringify(opts.body),
  };

  let res = await fetch(url, init);

  if (res.status === 401 && !opts.skipAuth) {
    const newToken = await refreshAccessToken();
    if (newToken) {
      headers["authorization"] = `Bearer ${newToken}`;
      res = await fetch(url, { ...init, headers });
    } else {
      if (typeof window !== "undefined" && !window.location.pathname.startsWith("/login")) {
        window.location.href = "/login";
      }
      throw new ApiError(401, "Unauthorized", null);
    }
  }

  const ct = res.headers.get("content-type") || "";
  const isJson = ct.includes("application/json");
  const payload = isJson ? await res.json().catch(() => null) : await res.text();

  if (!res.ok) {
    const msg =
      (isJson &&
        payload &&
        typeof payload === "object" &&
        ((payload as { message?: string; error?: string }).message ||
          (payload as { message?: string; error?: string }).error)) ||
      `Request failed: ${res.status}`;
    throw new ApiError(res.status, msg as string, payload);
  }
  return payload as T;
}

export async function apiBlob(path: string): Promise<Blob> {
  const url = path.startsWith("http") ? path : `${API_URL}${path}`;
  let token = useAuth.getState().accessToken;
  let r = await fetch(url, {
    headers: token ? { authorization: `Bearer ${token}` } : undefined,
  });
  // Mirror api()'s 401 → refresh → retry flow so blob downloads (CSV exports
  // etc.) don't fail spuriously when the access token has expired.
  if (r.status === 401) {
    token = await refreshAccessToken();
    if (!token) throw new ApiError(401, "Unauthorized", null);
    r = await fetch(url, { headers: { authorization: `Bearer ${token}` } });
  }
  if (!r.ok) throw new ApiError(r.status, `Download failed: ${r.status}`, null);
  return r.blob();
}
