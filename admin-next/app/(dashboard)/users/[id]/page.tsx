"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { toast } from "sonner";
import {
  useUser,
  useUpdateUser,
  useBanUser,
  useUnbanUser,
  type AdminUser,
} from "@/lib/queries";
import { api } from "@/lib/api";
import { useQuery } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { uzs, dateRu, dateRuShort } from "@/lib/formatters";
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

const COURIER_STATUSES = ["none", "pending", "approved", "rejected"];

interface AuditLog {
  id: string;
  action: string;
  targetType?: string | null;
  targetId?: string | null;
  metadata?: string | null;
  createdAt: string;
}

function useAuditFor(actorId: string | undefined) {
  return useQuery<{ logs: AuditLog[] }>({
    queryKey: ["admin-audit", "actor", actorId],
    queryFn: () => api(`/api/admin/audit`),
    enabled: !!actorId,
    select: (data) => ({
      logs: (data.logs || []).filter((l: AuditLog & { actorId?: string | null }) => {
        const aid = (l as unknown as { actorId?: string | null }).actorId;
        return aid === actorId;
      }),
    }),
  });
}

export default function UserDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params?.id as string | undefined;
  const { data, isLoading, error } = useUser(id);
  const update = useUpdateUser();
  const ban = useBanUser();
  const unban = useUnbanUser();
  const audit = useAuditFor(id);

  const [form, setForm] = useState<Partial<AdminUser>>({});
  const [banOpen, setBanOpen] = useState(false);
  const [banReason, setBanReason] = useState("");

  useEffect(() => {
    if (data?.user) {
      const u = data.user;
      setForm({
        name: u.name ?? "",
        isAdmin: u.isAdmin,
        isCourier: u.isCourier,
        isShop: u.isShop,
        courierStatus: u.courierStatus,
        locale: u.locale,
      });
    }
  }, [data?.user]);

  if (isLoading) return <div className="text-sm text-muted-foreground">Loading...</div>;
  if (error) return <div className="text-sm text-destructive">{(error as Error).message}</div>;
  if (!data?.user || !id) return <div className="text-sm text-muted-foreground">Not found</div>;

  const u = data.user;

  async function onSave(e: React.FormEvent) {
    e.preventDefault();
    if (!id) return;
    try {
      await update.mutateAsync({ id, body: form });
      toast.success("Saved");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function submitBan() {
    if (!id) return;
    if (!banReason.trim()) {
      toast.error("Reason required");
      return;
    }
    try {
      await ban.mutateAsync({ id, reason: banReason });
      toast.success("Banned");
      setBanOpen(false);
      setBanReason("");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onUnban() {
    if (!id) return;
    try {
      await unban.mutateAsync(id);
      toast.success("Unbanned");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  // Heuristic: a user with all role flags off + courierStatus=rejected is banned.
  const looksBanned = !u.isBuyer || (
    !u.isAdmin && !u.isCourier && !u.isShop && u.courierStatus === "rejected"
  );

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">{u.name || u.phone}</h1>
        <div className="mt-1 flex items-center gap-2 text-sm text-muted-foreground">
          <span className="font-mono">{u.phone}</span>
          {u.isAdmin ? <Badge variant="destructive">admin</Badge> : null}
          {u.isCourier ? <Badge variant="warning">courier</Badge> : null}
          {u.isShop ? <Badge variant="success">shop</Badge> : null}
          {u.isBuyer ? <Badge variant="info">buyer</Badge> : null}
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader><CardTitle>Orders</CardTitle></CardHeader>
          <CardContent className="text-3xl font-semibold">{data.ordersCount}</CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Spent</CardTitle></CardHeader>
          <CardContent className="text-3xl font-semibold">{uzs(data.totalSpent)}</CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Last seen</CardTitle></CardHeader>
          <CardContent className="text-lg">
            {data.lastSeenAt ? dateRu(data.lastSeenAt) : "—"}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle>Edit user</CardTitle>
            <div className="flex gap-2">
              {looksBanned ? (
                <Button variant="outline" onClick={onUnban}>Unban</Button>
              ) : (
                <Button variant="destructive" onClick={() => setBanOpen(true)}>Ban</Button>
              )}
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <form onSubmit={onSave} className="grid gap-4 sm:grid-cols-2">
            <div className="grid gap-2">
              <Label htmlFor="name">Name</Label>
              <Input
                id="name"
                value={form.name ?? ""}
                onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="locale">Locale</Label>
              <Select
                id="locale"
                value={form.locale ?? "uz"}
                onChange={(e) => setForm((f) => ({ ...f, locale: e.target.value }))}
              >
                <option value="uz">uz</option>
                <option value="ru">ru</option>
                <option value="en">en</option>
              </Select>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="cs">Courier status</Label>
              <Select
                id="cs"
                value={form.courierStatus ?? "none"}
                onChange={(e) => setForm((f) => ({ ...f, courierStatus: e.target.value }))}
              >
                {COURIER_STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
              </Select>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="ic">Roles</Label>
              <div className="flex flex-wrap items-center gap-3 text-sm">
                <label className="flex items-center gap-1">
                  <input
                    type="checkbox"
                    checked={!!form.isAdmin}
                    onChange={(e) => setForm((f) => ({ ...f, isAdmin: e.target.checked }))}
                  />
                  admin
                </label>
                <label className="flex items-center gap-1">
                  <input
                    type="checkbox"
                    checked={!!form.isCourier}
                    onChange={(e) => setForm((f) => ({ ...f, isCourier: e.target.checked }))}
                  />
                  courier
                </label>
                <label className="flex items-center gap-1">
                  <input
                    type="checkbox"
                    checked={!!form.isShop}
                    onChange={(e) => setForm((f) => ({ ...f, isShop: e.target.checked }))}
                  />
                  shop
                </label>
              </div>
            </div>
            <div className="sm:col-span-2">
              <Button type="submit" disabled={update.isPending}>
                {update.isPending ? "Saving..." : "Save changes"}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Recent orders</CardTitle></CardHeader>
        <CardContent className="p-0">
          {data.recentOrders?.length ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Order</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Total</TableHead>
                  <TableHead>Created</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.recentOrders.map((o) => (
                  <TableRow key={o.id}>
                    <TableCell className="font-mono text-xs">{o.orderNumber || o.id.slice(0, 8)}</TableCell>
                    <TableCell><Badge variant="muted">{o.status}</Badge></TableCell>
                    <TableCell className="text-right">{uzs(o.total)}</TableCell>
                    <TableCell>{dateRuShort(o.createdAt)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <div className="p-6 text-center text-sm text-muted-foreground">No orders</div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Audit log (acted by this user)</CardTitle></CardHeader>
        <CardContent className="p-0">
          {audit.isLoading ? (
            <div className="p-6 text-center text-sm text-muted-foreground">Loading...</div>
          ) : !audit.data?.logs?.length ? (
            <div className="p-6 text-center text-sm text-muted-foreground">No actions</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Action</TableHead>
                  <TableHead>Target</TableHead>
                  <TableHead>When</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {audit.data.logs.slice(0, 50).map((l) => (
                  <TableRow key={l.id}>
                    <TableCell className="font-medium">{l.action}</TableCell>
                    <TableCell className="text-xs">{l.targetType || "—"} {l.targetId?.slice(0, 8) || ""}</TableCell>
                    <TableCell>{dateRuShort(l.createdAt)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Dialog open={banOpen} onOpenChange={setBanOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Ban user</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">
              This revokes all refresh tokens, clears role flags, and marks
              courier status as rejected. The user can re-authenticate after unban.
            </p>
            <div className="grid gap-2">
              <Label htmlFor="reason">Reason</Label>
              <Input
                id="reason"
                value={banReason}
                onChange={(e) => setBanReason(e.target.value)}
                placeholder="e.g. fraud, spam, abuse"
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setBanOpen(false)}>Cancel</Button>
            <Button variant="destructive" onClick={submitBan} disabled={ban.isPending}>
              {ban.isPending ? "Banning..." : "Ban"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
