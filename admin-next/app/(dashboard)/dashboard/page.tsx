"use client";

import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  BarChart,
  Bar,
} from "recharts";
import { useStats } from "@/lib/queries";
import { uzs, pct } from "@/lib/formatters";
import { KpiCard } from "@/components/kpi-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export default function DashboardPage() {
  const { data, isLoading, error } = useStats();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Dashboard</h1>
        <p className="text-sm text-muted-foreground">
          KPIs and trends for the current week.
        </p>
      </div>

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          Failed to load stats: {(error as Error).message}
        </div>
      )}

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Orders this week"
          value={isLoading ? "…" : String(data?.totalOrders ?? 0)}
        />
        <KpiCard label="GMV" value={isLoading ? "…" : uzs(data?.gmv)} />
        <KpiCard
          label="Delivered rate"
          value={isLoading ? "…" : pct(data?.deliveredRate)}
        />
        <KpiCard label="AOV" value={isLoading ? "…" : uzs(data?.aov)} />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Orders by day (last 30 days)</CardTitle>
          </CardHeader>
          <CardContent className="h-72">
            {data?.ordersByDay?.length ? (
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={data.ordersByDay}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis />
                  <Tooltip />
                  <Line type="monotone" dataKey="orders" stroke="#2563eb" strokeWidth={2} dot={false} />
                </LineChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
                {isLoading ? "Loading..." : "No data"}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Top shops by GMV</CardTitle>
          </CardHeader>
          <CardContent className="h-72">
            {data?.topShops?.length ? (
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={data.topShops.slice(0, 10)}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="name" tick={{ fontSize: 11 }} interval={0} angle={-25} textAnchor="end" height={60} />
                  <YAxis />
                  <Tooltip formatter={(v) => uzs(Number(v))} />
                  <Bar dataKey="gmv" fill="#16a34a" />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
                {isLoading ? "Loading..." : "No data"}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
