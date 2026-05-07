"use client";

import {
  useMutation,
  useQuery,
  useQueryClient,
  keepPreviousData,
} from "@tanstack/react-query";
import { api, apiBlob } from "./api";

// ---------- Types (best-effort; backend is source of truth) ----------

export interface DashboardStats {
  totalOrders: number;
  gmv: number;
  deliveredRate: number; // 0..1
  aov: number;
  ordersByDay: { date: string; orders: number; gmv: number }[];
  topShops: { shopId: string; name: string; gmv: number; orders: number }[];
  openDisputes: number;
}

export interface Order {
  id: string;
  orderNumber: string;
  status: string;
  total: number;
  subtotal?: number;
  deliveryFee?: number;
  createdAt: string;
  updatedAt?: string;
  shop?: { id: string; name: string };
  buyer?: { id: string; name?: string; phone?: string };
  courier?: { id: string; name?: string; phone?: string } | null;
  items?: Array<{
    id: string;
    name: string;
    qty: number;
    price: number;
    modifiers?: Array<{ name: string; value?: string; price?: number }>;
  }>;
  payment?: { method?: string; status?: string; amount?: number };
  timeline?: Array<{ status: string; at: string; note?: string }>;
  dispute?: Dispute | null;
}

export interface OrderListResponse {
  data: Order[];
  nextCursor?: string | null;
}

export interface Coupon {
  id: string;
  code: string;
  type: "PERCENT" | "FIXED" | string;
  value: number;
  validFrom?: string;
  validUntil?: string;
  usedCount?: number;
  maxUses?: number;
  minOrderAmount?: number;
  status?: "ACTIVE" | "INACTIVE" | string;
}

export interface Payout {
  id: string;
  recipientType: "SHOP" | "COURIER" | string;
  recipientId: string;
  recipientName?: string;
  periodStart: string;
  periodEnd?: string;
  netAmount: number;
  grossAmount?: number;
  feeAmount?: number;
  status: "PENDING" | "PAID" | "FAILED" | string;
  txnRef?: string | null;
  paidAt?: string | null;
  notes?: string | null;
  lines?: Array<{ orderId: string; orderNumber?: string; amount: number }>;
}

export interface PayoutListResponse {
  data: Payout[];
  nextCursor?: string | null;
}

export interface Dispute {
  id: string;
  orderId: string;
  orderNumber?: string;
  openedBy?: { id: string; name?: string; role?: string };
  reason: string;
  description?: string;
  status: "OPEN" | "RESOLVED" | "REJECTED" | string;
  refundAmount?: number | null;
  resolution?: string | null;
  createdAt: string;
}

export interface DisputeListResponse {
  data: Dispute[];
  nextCursor?: string | null;
}

// ---------- Dashboard ----------

export function useStats(params: { since?: string; until?: string } = {}) {
  const q = new URLSearchParams();
  if (params.since) q.set("since", params.since);
  if (params.until) q.set("until", params.until);
  return useQuery<DashboardStats>({
    queryKey: ["stats", params.since, params.until],
    queryFn: () => api<DashboardStats>(`/api/admin/dashboard/stats?${q.toString()}`),
  });
}

// ---------- Orders ----------

export interface OrdersQuery {
  status?: string;
  shopId?: string;
  q?: string;
  cursor?: string;
  limit?: number;
}

export function useOrders(params: OrdersQuery = {}) {
  const q = new URLSearchParams();
  if (params.status) q.set("status", params.status);
  if (params.shopId) q.set("shopId", params.shopId);
  if (params.q) q.set("q", params.q);
  if (params.cursor) q.set("cursor", params.cursor);
  if (params.limit) q.set("limit", String(params.limit));
  return useQuery<OrderListResponse>({
    queryKey: ["orders", params],
    queryFn: () => api<OrderListResponse>(`/api/orders?${q.toString()}`),
    placeholderData: keepPreviousData,
  });
}

export function useOrder(id: string | undefined) {
  return useQuery<Order>({
    queryKey: ["order", id],
    queryFn: () => api<Order>(`/api/orders/${id}`),
    enabled: !!id,
  });
}

export function useRefundOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; amount: number; reason: string }) =>
      api(`/api/admin/orders/${vars.id}/refund`, {
        method: "POST",
        body: { amount: vars.amount, reason: vars.reason },
      }),
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ["order", v.id] });
      qc.invalidateQueries({ queryKey: ["orders"] });
    },
  });
}

// ---------- Coupons ----------

export function useCoupons() {
  return useQuery<{ data: Coupon[] } | Coupon[]>({
    queryKey: ["coupons"],
    queryFn: () => api(`/api/coupons`),
  });
}

export function useCreateCoupon() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: Partial<Coupon>) =>
      api(`/api/coupons`, { method: "POST", body }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["coupons"] }),
  });
}

export function useUpdateCoupon() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; body: Partial<Coupon> }) =>
      api(`/api/coupons/${vars.id}`, { method: "PATCH", body: vars.body }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["coupons"] }),
  });
}

export function useDeleteCoupon() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => api(`/api/coupons/${id}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["coupons"] }),
  });
}

// ---------- Payouts ----------

export interface PayoutsQuery {
  recipientType?: string;
  status?: string;
  periodStart?: string;
  cursor?: string;
  limit?: number;
}

export function usePayouts(params: PayoutsQuery = {}) {
  const q = new URLSearchParams();
  if (params.recipientType) q.set("recipientType", params.recipientType);
  if (params.status) q.set("status", params.status);
  if (params.periodStart) q.set("periodStart", params.periodStart);
  if (params.cursor) q.set("cursor", params.cursor);
  if (params.limit) q.set("limit", String(params.limit));
  return useQuery<PayoutListResponse>({
    queryKey: ["payouts", params],
    queryFn: () => api<PayoutListResponse>(`/api/admin/payouts?${q.toString()}`),
    placeholderData: keepPreviousData,
  });
}

export function usePayout(id: string | undefined) {
  return useQuery<Payout>({
    queryKey: ["payout", id],
    queryFn: () => api<Payout>(`/api/admin/payouts/${id}`),
    enabled: !!id,
  });
}

export function useGeneratePayouts() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: { weekStart?: string }) =>
      api(`/api/admin/payouts/generate`, { method: "POST", body }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["payouts"] }),
  });
}

export function useMarkPayoutPaid() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; txnRef: string; notes?: string }) =>
      api(`/api/admin/payouts/${vars.id}/pay`, {
        method: "POST",
        body: { txnRef: vars.txnRef, notes: vars.notes },
      }),
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ["payout", v.id] });
      qc.invalidateQueries({ queryKey: ["payouts"] });
    },
  });
}

export async function downloadPayoutsCsv(periodStart: string) {
  const blob = await apiBlob(
    `/api/admin/payouts/export.csv?periodStart=${encodeURIComponent(periodStart)}`
  );
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `payouts-${periodStart}.csv`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

// ---------- Disputes ----------

export interface DisputesQuery {
  status?: string;
  cursor?: string;
  limit?: number;
}

export function useDisputes(params: DisputesQuery = {}) {
  const q = new URLSearchParams();
  if (params.status) q.set("status", params.status);
  if (params.cursor) q.set("cursor", params.cursor);
  if (params.limit) q.set("limit", String(params.limit));
  return useQuery<DisputeListResponse>({
    queryKey: ["disputes", params],
    queryFn: () => api<DisputeListResponse>(`/api/admin/disputes?${q.toString()}`),
    placeholderData: keepPreviousData,
  });
}

export function useResolveDispute() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: {
      id: string;
      resolution: string;
      refundAmount?: number;
      note?: string;
    }) =>
      api(`/api/admin/disputes/${vars.id}/resolve`, {
        method: "POST",
        body: {
          resolution: vars.resolution,
          refundAmount: vars.refundAmount,
          note: vars.note,
        },
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["disputes"] }),
  });
}
