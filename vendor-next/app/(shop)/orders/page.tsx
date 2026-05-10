"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useShopOrders } from "@/lib/queries";
import { useCurrentShop } from "@/lib/shop-context";
import { uzs, dateRu } from "@/lib/formatters";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Card, CardContent } from "@/components/ui/card";
import { StatusBadge } from "@/components/status-badge";
import { cn } from "@/lib/utils";
import type { Order } from "@/lib/queries";

type Tab = "new" | "active" | "done";

const NEW_STATUSES = new Set(["PENDING", "PLACED"]);
const ACTIVE_STATUSES = new Set([
  "CONFIRMED",
  "COLLECTING",
  "PREPARING",
  "READY",
  "READY_FOR_PICKUP",
  "PICKED_UP",
  "COURIER_ASSIGNED",
  "EN_ROUTE",
  "IN_DELIVERY",
  "ARRIVED_AT_CUSTOMER",
]);
const DONE_STATUSES = new Set([
  "DELIVERED",
  "COMPLETED",
  "CANCELLED",
  "CANCELED",
  "REFUNDED",
]);

function bucketFor(o: Order): Tab {
  const s = (o.status || "").toUpperCase();
  if (NEW_STATUSES.has(s)) return "new";
  if (ACTIVE_STATUSES.has(s)) return "active";
  if (DONE_STATUSES.has(s)) return "done";
  return "active";
}

export default function OrdersPage() {
  const { shopId } = useCurrentShop();
  const router = useRouter();
  const [tab, setTab] = useState<Tab>("new");
  const { data, isLoading, error } = useShopOrders(shopId);

  const orders = data?.orders ?? [];

  const buckets = useMemo(() => {
    const out = { new: [] as Order[], active: [] as Order[], done: [] as Order[] };
    for (const o of orders) {
      out[bucketFor(o)].push(o);
    }
    return out;
  }, [orders]);

  const list = buckets[tab];

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Orders</h1>

      <div className="flex gap-2 border-b">
        {(
          [
            { key: "new", label: "New", count: buckets.new.length },
            { key: "active", label: "Active", count: buckets.active.length },
            { key: "done", label: "Done", count: buckets.done.length },
          ] as { key: Tab; label: string; count: number }[]
        ).map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setTab(t.key)}
            className={cn(
              "border-b-2 px-3 py-2 text-sm transition-colors",
              tab === t.key
                ? "border-primary font-medium"
                : "border-transparent text-muted-foreground hover:text-foreground"
            )}
          >
            {t.label}
            <span className="ml-2 rounded-full bg-muted px-2 py-0.5 text-xs">
              {t.count}
            </span>
          </button>
        ))}
      </div>

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          {(error as Error).message}
        </div>
      )}

      <Card>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              Loading...
            </div>
          ) : list.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              No orders in this bucket.
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Order #</TableHead>
                  <TableHead>Customer</TableHead>
                  <TableHead>Courier</TableHead>
                  <TableHead>Items</TableHead>
                  <TableHead className="text-right">Total</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Created</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {list.map((o) => (
                  <TableRow
                    key={o.id}
                    className="cursor-pointer"
                    onClick={() => router.push(`/orders/${o.id}`)}
                  >
                    <TableCell className="font-medium">
                      {o.orderNumber || o.id.slice(0, 8)}
                    </TableCell>
                    <TableCell>
                      {o.buyer?.name || o.buyer?.phone || "—"}
                    </TableCell>
                    <TableCell>{o.courier?.name || "—"}</TableCell>
                    <TableCell className="text-muted-foreground">
                      {o.items?.length ?? 0}
                    </TableCell>
                    <TableCell className="text-right">{uzs(o.total)}</TableCell>
                    <TableCell>
                      <StatusBadge status={o.status} />
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {dateRu(o.createdAt)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
