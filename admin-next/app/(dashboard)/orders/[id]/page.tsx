"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { toast } from "sonner";
import { useOrder, useRefundOrder, useResolveDispute } from "@/lib/queries";
import { uzs, dateRu } from "@/lib/formatters";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/status-badge";
import { Input } from "@/components/ui/input";
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
  const id = params?.id as string | undefined;
  const { data: order, isLoading, error } = useOrder(id);

  const refund = useRefundOrder();
  const resolve = useResolveDispute();

  const [refundOpen, setRefundOpen] = useState(false);
  const [refundAmount, setRefundAmount] = useState("");
  const [refundReason, setRefundReason] = useState("");

  const [disputeOpen, setDisputeOpen] = useState(false);
  const [resolution, setResolution] = useState("");
  const [resolveAmount, setResolveAmount] = useState("");
  const [resolveNote, setResolveNote] = useState("");

  if (isLoading) return <div className="text-sm text-muted-foreground">Loading...</div>;
  if (error) return <div className="text-sm text-destructive">{(error as Error).message}</div>;
  if (!order) return <div className="text-sm text-muted-foreground">Not found</div>;

  async function submitRefund(e: React.FormEvent) {
    e.preventDefault();
    if (!id) return;
    try {
      await refund.mutateAsync({
        id,
        amount: Number(refundAmount),
        reason: refundReason,
      });
      toast.success("Refund issued");
      setRefundOpen(false);
      setRefundAmount("");
      setRefundReason("");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function submitResolve(e: React.FormEvent) {
    e.preventDefault();
    if (!order?.dispute) return;
    try {
      await resolve.mutateAsync({
        id: order.dispute.id,
        resolution,
        refundAmount: resolveAmount ? Number(resolveAmount) : undefined,
        note: resolveNote || undefined,
      });
      toast.success("Dispute resolved");
      setDisputeOpen(false);
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Order {order.orderNumber}</h1>
          <div className="mt-1 flex items-center gap-2">
            <StatusBadge status={order.status} />
            <span className="text-sm text-muted-foreground">{dateRu(order.createdAt)}</span>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="destructive" onClick={() => setRefundOpen(true)}>
            Refund
          </Button>
          {order.dispute && (
            <Button onClick={() => setDisputeOpen(true)}>Resolve dispute</Button>
          )}
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader><CardTitle>Customer</CardTitle></CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div><span className="text-muted-foreground">Name:</span> {order.buyer?.name || "—"}</div>
            <div><span className="text-muted-foreground">Phone:</span> {order.buyer?.phone || "—"}</div>
            <div><span className="text-muted-foreground">ID:</span> {order.buyer?.id || "—"}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Shop</CardTitle></CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div><span className="text-muted-foreground">Name:</span> {order.shop?.name || "—"}</div>
            <div><span className="text-muted-foreground">ID:</span> {order.shop?.id || "—"}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Courier</CardTitle></CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div><span className="text-muted-foreground">Name:</span> {order.courier?.name || "—"}</div>
            <div><span className="text-muted-foreground">Phone:</span> {order.courier?.phone || "—"}</div>
            <div><span className="text-muted-foreground">ID:</span> {order.courier?.id || "—"}</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader><CardTitle>Items</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          {(order.items ?? []).map((item) => (
            <div key={item.id} className="flex items-start justify-between border-b pb-2 last:border-0">
              <div>
                <div className="font-medium">{item.qty} × {item.name}</div>
                {item.modifiers?.length ? (
                  <div className="mt-1 text-xs text-muted-foreground">
                    {item.modifiers.map((m, i) => (
                      <span key={i}>
                        {m.name}{m.value ? `: ${m.value}` : ""}{m.price ? ` (+${uzs(m.price)})` : ""}
                        {i < (item.modifiers!.length - 1) ? ", " : ""}
                      </span>
                    ))}
                  </div>
                ) : null}
              </div>
              <div className="text-sm">{uzs(item.price * item.qty)}</div>
            </div>
          ))}
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

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader><CardTitle>Payment</CardTitle></CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div><span className="text-muted-foreground">Method:</span> {order.payment?.method || "—"}</div>
            <div><span className="text-muted-foreground">Status:</span> <StatusBadge status={order.payment?.status} /></div>
            <div><span className="text-muted-foreground">Amount:</span> {uzs(order.payment?.amount)}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Status timeline</CardTitle></CardHeader>
          <CardContent className="space-y-2 text-sm">
            {(order.timeline ?? []).map((t, i) => (
              <div key={i} className="flex items-center gap-3">
                <StatusBadge status={t.status} />
                <span className="text-muted-foreground">{dateRu(t.at)}</span>
                {t.note && <span className="text-muted-foreground">— {t.note}</span>}
              </div>
            ))}
            {!order.timeline?.length && <div className="text-muted-foreground">No timeline</div>}
          </CardContent>
        </Card>
      </div>

      <Dialog open={refundOpen} onOpenChange={setRefundOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Refund order</DialogTitle>
            <DialogDescription>This will refund the buyer through the original payment method.</DialogDescription>
          </DialogHeader>
          <form onSubmit={submitRefund} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="amount">Amount (UZS)</Label>
              <Input
                id="amount"
                type="number"
                value={refundAmount}
                onChange={(e) => setRefundAmount(e.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="reason">Reason</Label>
              <Textarea
                id="reason"
                value={refundReason}
                onChange={(e) => setRefundReason(e.target.value)}
                required
              />
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setRefundOpen(false)}>Cancel</Button>
              <Button type="submit" variant="destructive" disabled={refund.isPending}>
                {refund.isPending ? "Refunding..." : "Refund"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      <Dialog open={disputeOpen} onOpenChange={setDisputeOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Resolve dispute</DialogTitle>
          </DialogHeader>
          <form onSubmit={submitResolve} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="resolution">Resolution</Label>
              <Input
                id="resolution"
                value={resolution}
                onChange={(e) => setResolution(e.target.value)}
                placeholder="REFUND, REJECTED, ..."
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="ramount">Refund amount (optional)</Label>
              <Input
                id="ramount"
                type="number"
                value={resolveAmount}
                onChange={(e) => setResolveAmount(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="note">Note</Label>
              <Textarea
                id="note"
                value={resolveNote}
                onChange={(e) => setResolveNote(e.target.value)}
              />
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setDisputeOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={resolve.isPending}>
                {resolve.isPending ? "Saving..." : "Resolve"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
