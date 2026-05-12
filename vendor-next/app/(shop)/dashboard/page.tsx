"use client";

import { useShopStats, useShopReviews } from "@/lib/queries";
import { useCurrentShop } from "@/lib/shop-context";
import { uzs, pct, rating, dateRu } from "@/lib/formatters";
import { KpiCard } from "@/components/kpi-card";
import { SalesChart } from "@/components/sales-chart";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export default function DashboardPage() {
  const { shopId, shop } = useCurrentShop();
  const { data: stats, isLoading, error } = useShopStats(shopId, 14);
  const { data: reviewsData } = useShopReviews(shopId, undefined, 5);

  const todayOrders = stats?.todayOrders ?? 0;
  const todayGmv = stats?.todayGmv ?? 0;
  const pending = stats?.pendingOrders ?? 0;
  const deliveredRate = stats?.deliveredRate ?? 0;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">{shop?.name || "Dashboard"}</h1>
        <p className="text-sm text-muted-foreground">
          Today's activity and the last 14 days of sales.
        </p>
      </div>

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          {(error as Error).message}
        </div>
      )}

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Orders today"
          value={isLoading ? "…" : String(todayOrders)}
        />
        <KpiCard
          label="GMV today"
          value={isLoading ? "…" : uzs(todayGmv)}
        />
        <KpiCard
          label="Pending now"
          value={isLoading ? "…" : String(pending)}
          hint={pending > 0 ? "Awaiting your acceptance" : undefined}
        />
        <KpiCard
          label="Delivered rate"
          value={isLoading ? "…" : pct(deliveredRate)}
          hint={`Rating: ${rating(shop?.rating)}`}
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Sales — last 14 days</CardTitle>
        </CardHeader>
        <CardContent>
          <SalesChart data={stats?.salesByDay ?? []} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Recent reviews</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {(reviewsData?.reviews ?? []).length === 0 ? (
            <div className="text-sm text-muted-foreground">No reviews yet.</div>
          ) : (
            (reviewsData?.reviews ?? []).map((r) => (
              <div key={r.id} className="border-b pb-3 last:border-0">
                <div className="flex items-center justify-between">
                  <div className="font-medium">{r.reviewerName || "—"}</div>
                  <div className="text-sm text-yellow-700">
                    {"★".repeat(Math.max(0, Math.min(5, r.rating)))}
                    <span className="ml-1 text-muted-foreground">
                      {r.rating.toFixed(1)}
                    </span>
                  </div>
                </div>
                {r.text && <div className="mt-1 text-sm">{r.text}</div>}
                <div className="mt-1 text-xs text-muted-foreground">
                  {dateRu(r.createdAt)}
                </div>
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </div>
  );
}
