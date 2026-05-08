"use client";

import { useState } from "react";
import { toast } from "sonner";
import { useDisputes, useResolveDispute, type Dispute } from "@/lib/queries";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { StatusBadge } from "@/components/status-badge";
import { uzs, dateRu } from "@/lib/formatters";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export default function DisputesPage() {
  const [status, setStatus] = useState("");
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [history, setHistory] = useState<(string | undefined)[]>([undefined]);
  const { data, isLoading } = useDisputes({
    status: status || undefined,
    cursor,
    limit: 25,
  });
  const resolve = useResolveDispute();

  const [editing, setEditing] = useState<Dispute | null>(null);
  const [resolution, setResolution] = useState("");
  const [refundAmount, setRefundAmount] = useState("");
  const [note, setNote] = useState("");

  function open(d: Dispute) {
    setEditing(d);
    setResolution("");
    setRefundAmount("");
    setNote("");
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!editing) return;
    try {
      await resolve.mutateAsync({
        id: editing.id,
        resolution,
        refundAmount: refundAmount ? Number(refundAmount) : undefined,
        note: note || undefined,
      });
      toast.success("Dispute resolved");
      setEditing(null);
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  const list = data?.data ?? [];

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Disputes</h1>

      <Card>
        <CardContent className="flex flex-wrap items-end gap-3 pt-6">
          <div className="grid gap-1">
            <Label>Status</Label>
            <Select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">All</option>
              <option value="OPEN">OPEN</option>
              <option value="RESOLVED">RESOLVED</option>
              <option value="REJECTED">REJECTED</option>
            </Select>
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

      <Card>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="p-8 text-center text-sm text-muted-foreground">Loading...</div>
          ) : list.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">No disputes</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Order</TableHead>
                  <TableHead>Opener</TableHead>
                  <TableHead>Reason</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Refund</TableHead>
                  <TableHead>Created</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {list.map((d) => (
                  <TableRow key={d.id} className="cursor-pointer" onClick={() => open(d)}>
                    <TableCell className="font-medium">{d.orderNumber || d.orderId}</TableCell>
                    <TableCell>{d.openedBy?.name || d.openedBy?.role || "—"}</TableCell>
                    <TableCell>{d.reason}</TableCell>
                    <TableCell><StatusBadge status={d.status} /></TableCell>
                    <TableCell className="text-right">{uzs(d.refundAmount)}</TableCell>
                    <TableCell className="text-muted-foreground">{dateRu(d.createdAt)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
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

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Resolve dispute {editing?.orderNumber}</DialogTitle>
          </DialogHeader>
          <form onSubmit={submit} className="space-y-4">
            <div className="text-sm">
              <div><span className="text-muted-foreground">Reason:</span> {editing?.reason}</div>
              {editing?.description && (
                <div className="mt-1 text-muted-foreground">{editing.description}</div>
              )}
            </div>
            <div className="grid gap-2">
              <Label htmlFor="r">Resolution</Label>
              <Input
                id="r"
                value={resolution}
                onChange={(e) => setResolution(e.target.value)}
                placeholder="REFUND, REJECTED, ..."
                required
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="ra">Refund amount (optional)</Label>
              <Input
                id="ra"
                type="number"
                value={refundAmount}
                onChange={(e) => setRefundAmount(e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="n">Note</Label>
              <Textarea id="n" value={note} onChange={(e) => setNote(e.target.value)} />
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setEditing(null)}>
                Cancel
              </Button>
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
