"use client";

import {
  useMutation,
  useQuery,
  useQueryClient,
  keepPreviousData,
} from "@tanstack/react-query";
import { api } from "./api";

// ─────────────────────────────────────────────────────────────────────────────
// Types — best-effort. Backend is source of truth; envelope shapes are guessed
// based on admin-next and backend routes. Adjust as endpoints stabilize.
// ─────────────────────────────────────────────────────────────────────────────

export interface Shop {
  id: string;
  name: string;
  description?: string | null;
  logoUrl?: string | null;
  address: string;
  lat?: number | null;
  lng?: number | null;
  phone?: string | null;
  vertical: string;
  isActive: boolean;
  rating?: number;
  openTime?: string;
  closeTime?: string;
  deliveryBaseFee?: number | null;
  deliveryPerKm?: number | null;
  freeDeliveryKm?: number | null;
  minOrderAmount?: number | null;
  currency?: string;
  membersCount?: number;
  ordersCount?: number;
  last30dGMV?: number;
  createdAt?: string;
  updatedAt?: string;
}

export interface Product {
  id: string;
  shopId: string;
  name: string;
  nameUz?: string | null;
  description?: string | null;
  price: number;
  discountPrice?: number | null;
  unit?: string | null;
  category?: string | null;
  categoryId?: string | null;
  imageUrl?: string | null;
  stock?: number | null;
  isAvailable?: boolean;
  createdAt?: string;
  updatedAt?: string;
}

export interface OrderItem {
  id: string;
  name: string;
  qty: number;
  price: number;
}

export interface Order {
  id: string;
  orderNumber?: string | null;
  status: string;
  total: number;
  subtotal?: number;
  deliveryFee?: number;
  createdAt: string;
  updatedAt?: string;
  shopId: string;
  buyerId?: string;
  buyer?: { id: string; name?: string; phone?: string } | null;
  courier?: { id: string; name?: string; phone?: string } | null;
  items?: OrderItem[];
  address?: string | null;
  notes?: string | null;
}

export interface WorkingHoursRow {
  id?: string;
  shopId?: string;
  dayOfWeek: number; // 0..6, Sun..Sat
  startsAt: string;
  endsAt: string;
  isClosed: boolean;
}

export interface Review {
  id: string;
  orderId: string;
  reviewerId: string;
  reviewerName?: string | null;
  reviewerAvatar?: string | null;
  targetType: string;
  targetId: string;
  rating: number;
  text?: string | null;
  photos?: string[];
  createdAt: string;
}

export interface ReviewListResponse {
  reviews: Review[];
  nextCursor?: string | null;
}

export interface Coupon {
  code: string;
  type: string;
  value: number;
  minOrder?: number | null;
  maxDiscount?: number | null;
  validFrom?: string;
  validUntil?: string;
  usageLimit?: number | null;
  usagePerUser?: number | null;
  vertical?: string | null;
  shopId?: string | null;
  firstOrderOnly?: boolean;
  isActive?: boolean;
  createdAt?: string;
}

// Shop stats — TODO: backend currently lacks a shop-scoped /stats endpoint.
// We declare the shape we *want* the backend to expose and fall back to a
// client-side aggregation over `/api/orders/shop/:shopId` until it lands.
export interface ShopStats {
  todayOrders: number;
  todayGmv: number;
  pendingOrders: number;
  deliveredRate: number;
  rating: number;
  reviewsCount: number;
  // 14 daily points {date,'YYYY-MM-DD', orders, gmv}.
  salesByDay: { date: string; orders: number; gmv: number }[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Shop info
// ─────────────────────────────────────────────────────────────────────────────

export function useShop(id: string | null | undefined) {
  return useQuery<{ shop: Shop }>({
    queryKey: ["shop", id],
    queryFn: () => api<{ shop: Shop }>(`/api/shops/${id}`),
    enabled: !!id,
  });
}

export function useUpdateShop() {
  const qc = useQueryClient();
  return useMutation({
    // Phase 13.2.7 — backend now exposes an owner-callable PATCH /api/shops/:id
    // (ShopMember owner/manager required) alongside the admin route.
    mutationFn: (vars: { id: string; body: Partial<Shop> }) =>
      api(`/api/shops/${vars.id}`, { method: "PATCH", body: vars.body }),
    onSuccess: (_d, v) => qc.invalidateQueries({ queryKey: ["shop", v.id] }),
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats — best-effort. Tries `/api/shops/:id/stats?days=14` first, falls back
// to building it from the orders list.
// ─────────────────────────────────────────────────────────────────────────────

export function useShopStats(shopId: string | null | undefined, days = 14) {
  return useQuery<ShopStats>({
    queryKey: ["shop-stats", shopId, days],
    enabled: !!shopId,
    queryFn: async (): Promise<ShopStats> => {
      try {
        return await api<ShopStats>(`/api/shops/${shopId}/stats?days=${days}`);
      } catch {
        // Fallback aggregation from the orders list.
        const { orders } = await api<{ orders: Order[] }>(
          `/api/orders/shop/${shopId}`
        );
        const sinceMs = Date.now() - days * 86_400_000;
        const todayMs = (() => {
          const d = new Date();
          d.setHours(0, 0, 0, 0);
          return d.getTime();
        })();
        const sales = new Map<string, { orders: number; gmv: number }>();
        for (let i = days - 1; i >= 0; i--) {
          const d = new Date();
          d.setDate(d.getDate() - i);
          d.setHours(0, 0, 0, 0);
          const key = d.toISOString().slice(0, 10);
          sales.set(key, { orders: 0, gmv: 0 });
        }
        let todayOrders = 0;
        let todayGmv = 0;
        let pendingOrders = 0;
        let delivered = 0;
        let cancelled = 0;
        for (const o of orders || []) {
          const t = new Date(o.createdAt).getTime();
          if (Number.isNaN(t)) continue;
          if (t >= sinceMs) {
            const key = new Date(o.createdAt).toISOString().slice(0, 10);
            const bucket = sales.get(key);
            if (bucket) {
              bucket.orders += 1;
              bucket.gmv += o.total || 0;
            }
          }
          if (t >= todayMs) {
            todayOrders += 1;
            todayGmv += o.total || 0;
          }
          const status = (o.status || "").toUpperCase();
          if (status === "PENDING") pendingOrders += 1;
          if (status === "DELIVERED" || status === "COMPLETED") delivered += 1;
          if (status === "CANCELLED" || status === "CANCELED") cancelled += 1;
        }
        const total = delivered + cancelled;
        const salesByDay = Array.from(sales.entries()).map(([date, v]) => ({
          date,
          orders: v.orders,
          gmv: v.gmv,
        }));
        return {
          todayOrders,
          todayGmv,
          pendingOrders,
          deliveredRate: total > 0 ? delivered / total : 0,
          rating: 0,
          reviewsCount: 0,
          salesByDay,
        };
      }
    },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Orders
// ─────────────────────────────────────────────────────────────────────────────

export function useShopOrders(shopId: string | null | undefined) {
  return useQuery<{ orders: Order[] }>({
    queryKey: ["shop-orders", shopId],
    queryFn: () => api<{ orders: Order[] }>(`/api/orders/shop/${shopId}`),
    enabled: !!shopId,
    placeholderData: keepPreviousData,
    refetchInterval: 15_000,
  });
}

export function useOrder(id: string | null | undefined) {
  return useQuery<{ order: Order }>({
    queryKey: ["order", id],
    queryFn: () => api<{ order: Order }>(`/api/orders/${id}`),
    enabled: !!id,
  });
}

export function useAcceptOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      api<{ order: Order }>(`/api/orders/${id}/shop/accept`, { method: "POST" }),
    onSuccess: (_d, id) => {
      qc.invalidateQueries({ queryKey: ["order", id] });
      qc.invalidateQueries({ queryKey: ["shop-orders"] });
    },
  });
}

export function useMarkOrderReady() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      api<{ order: Order }>(`/api/orders/${id}/shop/ready`, { method: "POST" }),
    onSuccess: (_d, id) => {
      qc.invalidateQueries({ queryKey: ["order", id] });
      qc.invalidateQueries({ queryKey: ["shop-orders"] });
    },
  });
}

export function useCancelOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; reason?: string }) =>
      api<{ order: Order }>(`/api/orders/${vars.id}/shop/cancel`, {
        method: "POST",
        body: { reason: vars.reason },
      }),
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ["order", v.id] });
      qc.invalidateQueries({ queryKey: ["shop-orders"] });
    },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Products
// ─────────────────────────────────────────────────────────────────────────────

export function useShopProducts(shopId: string | null | undefined) {
  return useQuery<{ products: Product[] }>({
    queryKey: ["shop-products", shopId],
    queryFn: () => api<{ products: Product[] }>(`/api/products/shop/${shopId}`),
    enabled: !!shopId,
  });
}

export function useProduct(
  id: string | null | undefined,
  shopId: string | null | undefined,
) {
  // The backend has no GET /api/products/:id endpoint, so we list-by-shop and
  // resolve by id client-side. The list response is small and the list-cache
  // is shared with /products, so this is essentially free after the first call.
  return useQuery<{ product: Product | null }>({
    queryKey: ["product", shopId, id],
    enabled: !!id && !!shopId,
    queryFn: async () => {
      const { products } = await api<{ products: Product[] }>(
        `/api/products?shopId=${shopId}&limit=1000`,
      );
      return { product: products.find((p) => p.id === id) ?? null };
    },
  });
}

export function useCreateProduct() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: Partial<Product> & { shopId: string }) =>
      api<{ product: Product }>(`/api/products`, { method: "POST", body }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["shop-products"] }),
  });
}

export function useUpdateProduct() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; body: Partial<Product> }) =>
      api<{ product: Product }>(`/api/products/${vars.id}`, {
        method: "PATCH",
        body: vars.body,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["shop-products"] }),
  });
}

export function useDeleteProduct() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      api(`/api/products/${id}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["shop-products"] }),
  });
}

export function useUploadProductImage() {
  return useMutation({
    mutationFn: async (file: File) => {
      const fd = new FormData();
      fd.append("image", file);
      return api<{ url: string; filename: string; size: number }>(
        `/api/products/upload-image`,
        { method: "POST", body: fd }
      );
    },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Working hours
// ─────────────────────────────────────────────────────────────────────────────

export function useWorkingHours(shopId: string | null | undefined) {
  return useQuery<{ items: WorkingHoursRow[] }>({
    queryKey: ["working-hours", shopId],
    queryFn: () =>
      api<{ items: WorkingHoursRow[] }>(`/api/shops/${shopId}/working-hours`),
    enabled: !!shopId,
  });
}

export function useSaveWorkingHours() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { shopId: string; items: WorkingHoursRow[] }) =>
      api<{ items: WorkingHoursRow[] }>(
        `/api/shops/${vars.shopId}/working-hours`,
        { method: "PUT", body: { items: vars.items } }
      ),
    onSuccess: (_d, v) =>
      qc.invalidateQueries({ queryKey: ["working-hours", v.shopId] }),
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Reviews
// ─────────────────────────────────────────────────────────────────────────────

export function useShopReviews(
  shopId: string | null | undefined,
  cursor?: string,
  limit = 20
) {
  const q = new URLSearchParams();
  q.set("targetType", "SHOP");
  if (shopId) q.set("targetId", shopId);
  if (cursor) q.set("cursor", cursor);
  q.set("limit", String(limit));
  return useQuery<ReviewListResponse>({
    queryKey: ["shop-reviews", shopId, cursor, limit],
    queryFn: () => api<ReviewListResponse>(`/api/reviews?${q.toString()}`),
    enabled: !!shopId,
    placeholderData: keepPreviousData,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Coupons (read-only — admin owns mutations; shop owners see scoped list).
// ─────────────────────────────────────────────────────────────────────────────

export function useShopCoupons(shopId: string | null | undefined) {
  // Phase 13.2.7 — switched to the owner-callable `/api/shops/:id/coupons`
  // endpoint added in Phase 13.2.6. The admin-only `/api/coupons` route is
  // no longer reachable from the vendor portal.
  return useQuery<{ coupons: Coupon[] }>({
    queryKey: ["shop-coupons", shopId],
    queryFn: () => api<{ coupons: Coupon[] }>(`/api/shops/${shopId}/coupons`),
    enabled: !!shopId,
    retry: false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth — /api/auth/me (refresh roles + shop memberships post-login).
// ─────────────────────────────────────────────────────────────────────────────

import type { ShopUser } from "./auth";

export function useMe() {
  return useQuery<{ user: ShopUser }>({
    queryKey: ["me"],
    queryFn: () => api<{ user: ShopUser }>(`/api/auth/me`),
  });
}
