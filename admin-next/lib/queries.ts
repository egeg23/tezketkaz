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

// ---------- Phase 6.12 — Shops ----------

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
  lastWeekGMV?: number;
  members?: Array<{
    id: string;
    role: string;
    user: { id: string; name?: string | null; phone?: string | null };
  }>;
  createdAt?: string;
  updatedAt?: string;
}

export interface ShopListResponse {
  shops: Shop[];
  nextCursor?: string | null;
}

export interface ShopsQuery {
  status?: string;
  vertical?: string;
  q?: string;
  cursor?: string;
  limit?: number;
}

export function useShops(params: ShopsQuery = {}) {
  const q = new URLSearchParams();
  if (params.status) q.set("status", params.status);
  if (params.vertical) q.set("vertical", params.vertical);
  if (params.q) q.set("q", params.q);
  if (params.cursor) q.set("cursor", params.cursor);
  if (params.limit) q.set("limit", String(params.limit));
  return useQuery<ShopListResponse>({
    queryKey: ["admin-shops", params],
    queryFn: () => api<ShopListResponse>(`/api/admin/shops?${q.toString()}`),
    placeholderData: keepPreviousData,
  });
}

export function useShop(id: string | undefined) {
  return useQuery<{
    shop: Shop;
    membersCount: number;
    ordersCount: number;
    productsCount: number;
    last30dGMV: number;
  }>({
    queryKey: ["admin-shop", id],
    queryFn: () => api(`/api/admin/shops/${id}`),
    enabled: !!id,
  });
}

export function useUpdateShop() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; body: Partial<Shop> }) =>
      api(`/api/admin/shops/${vars.id}`, { method: "PATCH", body: vars.body }),
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ["admin-shop", v.id] });
      qc.invalidateQueries({ queryKey: ["admin-shops"] });
    },
  });
}

export function useSuspendShop() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; reason?: string }) =>
      api(`/api/admin/shops/${vars.id}/suspend`, {
        method: "POST",
        body: { reason: vars.reason },
      }),
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ["admin-shop", v.id] });
      qc.invalidateQueries({ queryKey: ["admin-shops"] });
    },
  });
}

export function useActivateShop() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      api(`/api/admin/shops/${id}/activate`, { method: "POST" }),
    onSuccess: (_d, id) => {
      qc.invalidateQueries({ queryKey: ["admin-shop", id] });
      qc.invalidateQueries({ queryKey: ["admin-shops"] });
    },
  });
}

export function useDeleteShop() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      api(`/api/admin/shops/${id}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin-shops"] }),
  });
}

// ---------- Phase 6.12 — Users ----------

export interface AdminUser {
  id: string;
  phone: string;
  name?: string | null;
  isBuyer: boolean;
  isCourier: boolean;
  isShop: boolean;
  isAdmin: boolean;
  courierStatus: string;
  locale: string;
  rating?: number;
  ordersCount?: number;
  isOnline?: boolean;
  lastSeenAt?: string | null;
  createdAt?: string;
}

export interface UserListResponse {
  users: AdminUser[];
  nextCursor?: string | null;
}

export interface UsersQuery {
  role?: string;
  status?: string;
  q?: string;
  cursor?: string;
  limit?: number;
}

export function useUsers(params: UsersQuery = {}) {
  const q = new URLSearchParams();
  if (params.role) q.set("role", params.role);
  if (params.status) q.set("status", params.status);
  if (params.q) q.set("q", params.q);
  if (params.cursor) q.set("cursor", params.cursor);
  if (params.limit) q.set("limit", String(params.limit));
  return useQuery<UserListResponse>({
    queryKey: ["admin-users", params],
    queryFn: () => api<UserListResponse>(`/api/admin/users?${q.toString()}`),
    placeholderData: keepPreviousData,
  });
}

export function useUser(id: string | undefined) {
  return useQuery<{
    user: AdminUser & {
      shopMemberships: Array<{ id: string; role: string; shop: { id: string; name: string } }>;
      loyalty?: { tier: string; points: number; cashback: number } | null;
    };
    ordersCount: number;
    totalSpent: number;
    lastSeenAt?: string | null;
    recentOrders: Array<{
      id: string;
      orderNumber?: string | null;
      status: string;
      total: number;
      createdAt: string;
      deliveredAt?: string | null;
      shopId: string;
    }>;
  }>({
    queryKey: ["admin-user", id],
    queryFn: () => api(`/api/admin/users/${id}`),
    enabled: !!id,
  });
}

export function useUpdateUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; body: Partial<AdminUser> }) =>
      api(`/api/admin/users/${vars.id}`, { method: "PATCH", body: vars.body }),
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ["admin-user", v.id] });
      qc.invalidateQueries({ queryKey: ["admin-users"] });
    },
  });
}

export function useBanUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; reason: string }) =>
      api(`/api/admin/users/${vars.id}/ban`, {
        method: "POST",
        body: { reason: vars.reason },
      }),
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ["admin-user", v.id] });
      qc.invalidateQueries({ queryKey: ["admin-users"] });
    },
  });
}

export function useUnbanUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      api(`/api/admin/users/${id}/unban`, { method: "POST" }),
    onSuccess: (_d, id) => {
      qc.invalidateQueries({ queryKey: ["admin-user", id] });
      qc.invalidateQueries({ queryKey: ["admin-users"] });
    },
  });
}

// ---------- Phase 6.5 — KYC verification ----------

export interface VerificationDoc {
  id: string;
  userId: string;
  type: string;
  url: string;
  status: "pending" | "approved" | "rejected" | string;
  reviewedById?: string | null;
  reviewedAt?: string | null;
  rejectionReason?: string | null;
  createdAt?: string;
  user?: { id: string; name?: string | null; phone?: string | null; courierStatus?: string };
}

export interface VerificationListResponse {
  docs: VerificationDoc[];
  nextCursor?: string | null;
}

export interface KYCQuery {
  status?: string;
  type?: string;
  cursor?: string;
  limit?: number;
}

export function usePendingKYC(params: KYCQuery = { status: "pending" }) {
  const q = new URLSearchParams();
  if (params.status) q.set("status", params.status);
  if (params.type) q.set("type", params.type);
  if (params.cursor) q.set("cursor", params.cursor);
  if (params.limit) q.set("limit", String(params.limit));
  return useQuery<VerificationListResponse>({
    queryKey: ["admin-verification", params],
    queryFn: () => api<VerificationListResponse>(`/api/admin/verification?${q.toString()}`),
    placeholderData: keepPreviousData,
  });
}

export function useApproveKYC() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      api(`/api/admin/verification/${id}/approve`, { method: "POST" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["admin-verification"] });
      qc.invalidateQueries({ queryKey: ["admin-users"] });
    },
  });
}

export function useRejectKYC() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; reason: string }) =>
      api(`/api/admin/verification/${vars.id}/reject`, {
        method: "POST",
        body: { reason: vars.reason },
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["admin-verification"] });
    },
  });
}

// ---------- Phase 7.3 — Banners ----------

export interface Banner {
  id: string;
  titleUz: string;
  titleRu: string;
  titleEn?: string | null;
  subtitleUz?: string | null;
  subtitleRu?: string | null;
  subtitleEn?: string | null;
  imageUrl: string;
  deepLink?: string | null;
  vertical: string;
  country?: string | null;
  priority: number;
  isActive: boolean;
  validFrom?: string | null;
  validUntil?: string | null;
  viewsCount?: number;
  clicksCount?: number;
  createdAt?: string;
  updatedAt?: string;
}

export interface BannerListResponse {
  banners: Banner[];
  nextCursor?: string | null;
}

export interface BannerStats {
  views: number;
  clicks: number;
  ctr: number;
  last30dayDailyViews: { day: string; count: number }[];
}

export function useBanners() {
  return useQuery<BannerListResponse>({
    queryKey: ["admin-banners"],
    queryFn: () => api<BannerListResponse>(`/api/admin/banners`),
  });
}

export function useCreateBanner() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: Partial<Banner>) =>
      api(`/api/admin/banners`, { method: "POST", body }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin-banners"] }),
  });
}

export function useUpdateBanner() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (vars: { id: string; body: Partial<Banner> }) =>
      api(`/api/admin/banners/${vars.id}`, { method: "PATCH", body: vars.body }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin-banners"] }),
  });
}

export function useDeleteBanner() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      api(`/api/admin/banners/${id}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin-banners"] }),
  });
}

export function useBannerStats(id: string | undefined) {
  return useQuery<BannerStats>({
    queryKey: ["admin-banner-stats", id],
    queryFn: () => api<BannerStats>(`/api/admin/banners/${id}/stats`),
    enabled: !!id,
  });
}

export function useUploadBannerImage() {
  return useMutation({
    mutationFn: async (file: File) => {
      const fd = new FormData();
      fd.append("image", file);
      return api<{ url: string; filename: string; size: number }>(
        `/api/admin/banners/upload-image`,
        { method: "POST", body: fd }
      );
    },
  });
}
