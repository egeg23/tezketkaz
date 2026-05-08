"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { toast } from "sonner";
import { useMarkPayoutPaid, usePayout } from "@/lib/queries";
import { uzs, dateRu, dateRuShort } from "@/lib/formatters";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { StatusBadge } from "@/components/status-badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export default function PayoutDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params?.id as string | undefined;
  const { data: p, isLoading, error } = usePayout(id);
  const pay = useMarkPayoutPaid();

  const [txnRef, setTxnRef] = useState("");
  const [notes, setNotes] = useState("");

  if (isLoading) return <div className="text-sm text-muted-foreground">Loading...</div>;
  if (error) return <div className="text-sm text-destructive">{(error as Error).message}</div>;
  if (!p) return <div className="text-sm text-muted-foreground">Not found</div>;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!id) return;
    try {
      await pay.mutateAsync({ id, txnRef, notes: notes || undefined });
      toast.success("Marked paid");
      setTxnRef("");
      setNotes("");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">
          Payout — {p.recipientName || p.recipientId}
        </h1>
        <div className="mt-1 flex items-center gap-2 text-sm text-muted-foreground">
          <StatusBadge status={p.status} />
          {p.paidAt ? <span>Paid {dateRu(p.paidAt)}</span> : null}
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader><CardTitle>Period</CardTitle></CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div><span className="text-muted-foreground">Start:</span> {dateRuShort(p.periodStart)}</div>
            <div><span className="text-muted-foreground">End:</span> {dateRuShort(p.periodEnd)}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Amounts</CardTitle></CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div><span className="text-muted-foreground">Gross:</span> {uzs(p.grossAmount)}</div>
            <div><span className="text-muted-foreground">Fees:</span> {uzs(p.feeAmount)}</div>
            <div className="font-semibold"><span className="text-muted-foreground">Net:</span> {uzs(p.netAmount)}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Reference</CardTitle></CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div><span className="text-muted-foreground">Type:</span> {p.recipientType}</div>
            <div><span className="text-muted-foreground">TxnRef:</span> {p.txnRef || "—"}</div>
            <div><span className="text-muted-foreground">Notes:</span> {p.notes || "—"}</div>
          </CardContent>
        </Card>
      </div>

      {p.status !== "PAID" && (
        <Card>
          <CardHeader><CardTitle>Mark as paid</CardTitle></CardHeader>
          <CardContent>
            <form onSubmit={submit} className="grid gap-3 sm:grid-cols-3">
              <div className="grid gap-2">
                <Label htmlFor="txn">Txn reference</Label>
                <Input id="txn" value={txnRef} onChange={(e) => setTxnRef(e.target.value)} required />
              </div>
              <div className="grid gap-2 sm:col-span-2">
                <Label htmlFor="notes">Notes</Label>
                <Textarea id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
              </div>
              <div className="sm:col-span-3">
                <Button type="submit" disabled={pay.isPending}>
                  {pay.isPending ? "Saving..." : "Mark paid"}
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader><CardTitle>Lines</CardTitle></CardHeader>
        <CardContent className="p-0">
          {p.lines?.length ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Order</TableHead>
                  <TableHead className="text-right">Amount</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {p.lines.map((l, i) => (
                  <TableRow key={i}>
                    <TableCell className="font-medium">{l.orderNumber || l.orderId}</TableCell>
                    <TableCell className="text-right">{uzs(l.amount)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <div className="p-6 text-center text-sm text-muted-foreground">No lines</div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
