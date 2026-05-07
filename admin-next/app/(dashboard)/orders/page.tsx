"use client";

import { useState } from "react";
import { useOrders } from "@/lib/queries";
import { OrdersTable } from "@/components/orders-table";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

const STATUSES = [
  "",
  "PLACED",
  "CONFIRMED",
  "PREPARING",
  "READY",
  "PICKED_UP",
  "EN_ROUTE",
  "DELIVERED",
  "CANCELLED",
  "REFUNDED",
];

export default function OrdersPage() {
  const [status, setStatus] = useState("");
  const [q, setQ] = useState("");
  const [shopId, setShopId] = useState("");
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [history, setHistory] = useState<(string | undefined)[]>([undefined]);

  const { data, isLoading, error } = useOrders({
    status: status || undefined,
    q: q || undefined,
    shopId: shopId || undefined,
    cursor,
    limit: 25,
  });

  const orders = data?.data ?? [];

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Orders</h1>

      <Card>
        <CardContent className="flex flex-wrap items-end gap-3 pt-6">
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Status</label>
            <Select value={status} onChange={(e) => setStatus(e.target.value)}>
              {STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s || "All"}
                </option>
              ))}
            </Select>
          </div>
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Search</label>
            <Input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Order #, phone..."
            />
          </div>
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Shop ID</label>
            <Input value={shopId} onChange={(e) => setShopId(e.target.value)} placeholder="shop id" />
          </div>
          <Button
            variant="outline"
            onClick={() => {
              setCursor(undefined);
              setHistory([undefined]);
            }}
          >
            Reset
          </Button>
        </CardContent>
      </Card>

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          {(error as Error).message}
        </div>
      )}

      <Card>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="p-8 text-center text-sm text-muted-foreground">Loading...</div>
          ) : (
            <OrdersTable orders={orders} />
          )}
        </CardContent>
      </Card>

      <div className="flex items-center justify-between">
        <Button
          variant="outline"
          disabled={history.length <= 1}
          onClick={() => {
            const next = history.slice(0, -1);
            setHistory(next);
            setCursor(next[next.length - 1]);
          }}
        >
          Previous
        </Button>
        <Button
          variant="outline"
          disabled={!data?.nextCursor}
          onClick={() => {
            if (data?.nextCursor) {
              setHistory([...history, data.nextCursor]);
              setCursor(data.nextCursor);
            }
          }}
        >
          Next
        </Button>
      </div>
    </div>
  );
}
