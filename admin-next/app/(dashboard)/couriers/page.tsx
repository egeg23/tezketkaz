"use client";

import { useState } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { useQuery } from "@tanstack/react-query";
import { api, API_URL } from "@/lib/api";
import {
  usePendingKYC,
  useApproveKYC,
  useRejectKYC,
  type AdminUser,
  type VerificationDoc,
} from "@/lib/queries";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { dateRuShort } from "@/lib/formatters";
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

const TABS = [
  { id: "all", label: "All couriers" },
  { id: "kyc", label: "Pending KYC" },
] as const;

type TabId = (typeof TABS)[number]["id"];

function useAllCouriers() {
  return useQuery<{ couriers: AdminUser[] }>({
    queryKey: ["admin-couriers"],
    queryFn: () => api(`/api/admin/couriers`),
  });
}

function CouriersTable() {
  const { data, isLoading } = useAllCouriers();
  const couriers = data?.couriers ?? [];
  if (isLoading) return <div className="p-6 text-center text-sm text-muted-foreground">Loading...</div>;
  if (!couriers.length) return <div className="p-6 text-center text-sm text-muted-foreground">No couriers</div>;
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Phone</TableHead>
          <TableHead>Name</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Online</TableHead>
          <TableHead className="text-right">Orders</TableHead>
          <TableHead className="text-right">Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {couriers.map((c) => (
          <TableRow key={c.id}>
            <TableCell className="font-mono text-xs">{c.phone}</TableCell>
            <TableCell>{c.name || "—"}</TableCell>
            <TableCell>
              <Badge
                variant={
                  c.courierStatus === "approved" ? "success"
                  : c.courierStatus === "rejected" ? "muted"
                  : "warning"
                }
              >
                {c.courierStatus}
              </Badge>
            </TableCell>
            <TableCell>{c.isOnline ? <Badge variant="success">online</Badge> : <Badge variant="muted">offline</Badge>}</TableCell>
            <TableCell className="text-right">{c.ordersCount ?? 0}</TableCell>
            <TableCell className="text-right">
              <Button size="sm" variant="ghost" asChild>
                <Link href={`/users/${c.id}`}>View</Link>
              </Button>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

function groupByUser(docs: VerificationDoc[]) {
  const map = new Map<string, { user: VerificationDoc["user"]; docs: VerificationDoc[] }>();
  for (const d of docs) {
    const key = d.userId;
    const e = map.get(key) || { user: d.user, docs: [] };
    e.docs.push(d);
    map.set(key, e);
  }
  return Array.from(map.values());
}

function KYCReviewQueue() {
  const { data, isLoading, refetch } = usePendingKYC({ status: "pending", limit: 100 });
  const approve = useApproveKYC();
  const reject = useRejectKYC();

  const [rejectingId, setRejectingId] = useState<string | null>(null);
  const [reason, setReason] = useState("");

  const docs = data?.docs ?? [];
  const groups = groupByUser(docs);

  async function onApprove(d: VerificationDoc) {
    try {
      await approve.mutateAsync(d.id);
      toast.success("Approved");
      await refetch();
    } catch (err) {
      toast.error((err as Error).message);
    }
  }
  async function submitReject() {
    if (!rejectingId) return;
    if (!reason.trim()) {
      toast.error("Reason required");
      return;
    }
    try {
      await reject.mutateAsync({ id: rejectingId, reason });
      toast.success("Rejected");
      setRejectingId(null);
      setReason("");
      await refetch();
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  if (isLoading) return <div className="p-6 text-center text-sm text-muted-foreground">Loading...</div>;
  if (!groups.length) return <div className="p-6 text-center text-sm text-muted-foreground">No pending docs</div>;

  return (
    <div className="space-y-4">
      {groups.map((g) => (
        <Card key={g.user?.id || "unknown"}>
          <CardHeader>
            <CardTitle>
              <span className="font-mono text-base">{g.user?.phone || "—"}</span>
              {g.user?.name ? <span className="ml-2 text-sm text-muted-foreground">{g.user.name}</span> : null}
              {g.user?.courierStatus ? (
                <Badge className="ml-2" variant="muted">{g.user.courierStatus}</Badge>
              ) : null}
            </CardTitle>
          </CardHeader>
          <CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {g.docs.map((d) => {
              const fullUrl = d.url.startsWith("http") ? d.url : `${API_URL}${d.url}`;
              return (
                <div key={d.id} className="rounded border p-3">
                  <div className="mb-2 flex items-center justify-between">
                    <Badge variant="warning">{d.type}</Badge>
                    <span className="text-xs text-muted-foreground">
                      {d.createdAt ? dateRuShort(d.createdAt) : "—"}
                    </span>
                  </div>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={fullUrl}
                    alt={d.type}
                    className="mb-2 h-40 w-full rounded object-cover"
                  />
                  <div className="flex justify-end gap-2">
                    <Button size="sm" variant="outline" onClick={() => { setRejectingId(d.id); setReason(""); }}>
                      Reject
                    </Button>
                    <Button size="sm" onClick={() => onApprove(d)} disabled={approve.isPending}>
                      Approve
                    </Button>
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      ))}

      <Dialog open={!!rejectingId} onOpenChange={(o) => { if (!o) setRejectingId(null); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reject document</DialogTitle>
          </DialogHeader>
          <div className="grid gap-2">
            <Label htmlFor="rr">Reason</Label>
            <Input
              id="rr"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. blurry photo, wrong document"
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRejectingId(null)}>Cancel</Button>
            <Button variant="destructive" onClick={submitReject} disabled={reject.isPending}>
              {reject.isPending ? "Rejecting..." : "Reject"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

export default function CouriersPage() {
  const [tab, setTab] = useState<TabId>("all");

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Couriers</h1>

      <div className="flex gap-2 border-b">
        {TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            onClick={() => setTab(t.id)}
            className={
              "border-b-2 px-3 py-2 text-sm font-medium " +
              (tab === t.id
                ? "border-primary text-foreground"
                : "border-transparent text-muted-foreground hover:text-foreground")
            }
          >
            {t.label}
          </button>
        ))}
      </div>

      <Card>
        <CardContent className="p-0">
          {tab === "all" ? <CouriersTable /> : <KYCReviewQueue />}
        </CardContent>
      </Card>
    </div>
  );
}
