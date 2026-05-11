"use client";

import { useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { toast } from "sonner";
import {
  useOrder,
  useAcceptOrder,
  useMarkOrderReady,
  useCancelOrder,
} from "@/lib/queries";
import { uzs, dateRu } from "@/lib/formatters";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/status-badge";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

export default function OrderDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const id = params?.id as string | undefined;
  const { data, isLoading, error } = useOrder(id);

  const accept = useAcceptOrder();
  const markReady = useMarkOrderReady();
  const cancel = useCancelOrder();

  const [cancelOpen, setCancelOpen] = useState(false);
  const [cancelReason, setCancelReason] = useState("");

  if (isLoading) return <div className="text-sm text-muted-foreground">Loading...</div>;
  if (error)
    return <div className="text-sm text-destructive">{(error as Error).message}</div>;
  if (!data?.order)
    return <div className="text-sm text-muted-foreground">Not found</div>;

  const order = data.order;
  const status = (order.status || "").toUpperCase();
  const isPending = status === "PENDING" || status === "PLACED";
  const isCollecting = status === "COLLECTING" || status === "CONFIRMED";
  const isOpen = !["DELIVERED", "COMPLETED", "CANCELLED", "CANCELED", "REFUNDED"].includes(status);

  async function doAccept() {
    if (!id) return;
    try {
      await accept.mutateAsync(id);
      toast.success("Order accepted");
    } catch (e) {
      toast.error((e as Error).message);
    }
  }

  async function doReady() {
    if (!id) return;
    try {
      await markReady.mutateAsync(id);
      toast.success("Order marked ready");
    } catch (e) {
      toast.error((e as Error).message);
    }
  }

  async function doCancel(e: React.FormEvent) {
    e.preventDefault();
    if (!id) return;
    try {
      await cancel.mutateAsync({ id, reason: cancelReason || undefined });
      toast.success("Order cancelled");
      setCancelOpen(false);
      setCancelReason("");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <button
            type="button"
            onClick={() => router.push("/orders")}
            className="mb-1 text-xs text-muted-foreground hover:underline"
          >
            ← Back to orders
          </button>
          <h1 className="text-2xl font-semibold">
            Order {order.orderNumber || order.id.slice(0, 8)}
          </h1>
          <div className="mt-1 flex items-center gap-2">
            <StatusBadge status={order.status} />
            <span className="text-sm text-muted-foreground">
              {dateRu(order.createdAt)}
            </span>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {isPending && (
            <Button onClick={doAccept} disabled={accept.isPending}>
              {accept.isPending ? "Accepting..." : "Accept order"}
            </Button>
          )}
          {isCollecting && (
            <Button onClick={doReady} disabled={markReady.isPending}>
              {markReady.isPending ? "Saving..." : "Mark ready"}
            </Button>
          )}
          {isOpen && (
            <Button
              variant="destructive"
              onClick={() => setCancelOpen(true)}
              disabled={cancel.isPending}
            >
              Cancel order
            </Button>
          )}
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Customer</CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div>
              <span className="text-muted-foreground">Name:</span>{" "}
              {order.buyer?.name || "—"}
            </div>
            <div>
              <span className="text-muted-foreground">Phone:</span>{" "}
              {order.buyer?.phone || "—"}
            </div>
            {order.address && (
              <div>
                <span className="text-muted-foreground">Address:</span>{" "}
                {order.address}
              </div>
            )}
            {order.notes && (
              <div>
                <span className="text-muted-foreground">Notes:</span>{" "}
                {order.notes}
              </div>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Courier</CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div>
              <span className="text-muted-foreground">Name:</span>{" "}
              {order.courier?.name || "—"}
            </div>
            <div>
              <span className="text-muted-foreground">Phone:</span>{" "}
              {order.courier?.phone || "—"}
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Items</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {(order.items ?? []).map((item) => (
            <div
              key={item.id}
              className="flex items-start justify-between border-b pb-2 last:border-0"
            >
              <div>
                <div className="font-medium">
                  {item.qty} × {item.name}
                </div>
              </div>
              <div className="text-sm">{uzs(item.price * item.qty)}</div>
            </div>
          ))}
          {!order.items?.length && (
            <div className="text-sm text-muted-foreground">No items</div>
          )}
          <div className="flex justify-between pt-2 text-sm">
            <span className="text-muted-foreground">Subtotal</span>
            <span>{uzs(order.subtotal)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Delivery</span>
            <span>{uzs(order.deliveryFee)}</span>
          </div>
          <div className="flex justify-between border-t pt-2 font-semibold">
            <span>Total</span>
            <span>{uzs(order.total)}</span>
          </div>
        </CardContent>
      </Card>

      <Dialog open={cancelOpen} onOpenChange={setCancelOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Cancel order</DialogTitle>
            <DialogDescription>
              The buyer is notified and the order is closed. This cannot be
              undone.
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={doCancel} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="reason">Reason</Label>
              <Textarea
                id="reason"
                value={cancelReason}
                onChange={(e) => setCancelReason(e.target.value)}
                placeholder="Out of stock, store closed, ..."
              />
            </div>
            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => setCancelOpen(false)}
              >
                Back
              </Button>
              <Button
                type="submit"
                variant="destructive"
                disabled={cancel.isPending}
              >
                {cancel.isPending ? "Cancelling..." : "Cancel order"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
