"use client";

import { useState } from "react";
import { toast } from "sonner";
import {
  useCoupons,
  useCreateCoupon,
  useDeleteCoupon,
  useUpdateCoupon,
  type Coupon,
} from "@/lib/queries";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { StatusBadge } from "@/components/status-badge";
import { uzs, dateRuShort } from "@/lib/formatters";
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

const EMPTY: Partial<Coupon> = {
  code: "",
  type: "PERCENT",
  value: 0,
  status: "ACTIVE",
};

export default function CouponsPage() {
  const { data, isLoading } = useCoupons();
  const create = useCreateCoupon();
  const update = useUpdateCoupon();
  const remove = useDeleteCoupon();

  const list = Array.isArray(data) ? data : data?.data ?? [];

  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<Coupon | null>(null);
  const [form, setForm] = useState<Partial<Coupon>>(EMPTY);

  function openCreate() {
    setEditing(null);
    setForm(EMPTY);
    setOpen(true);
  }
  function openEdit(c: Coupon) {
    setEditing(c);
    setForm({
      code: c.code,
      type: c.type,
      value: c.value,
      validFrom: c.validFrom,
      validUntil: c.validUntil,
      maxUses: c.maxUses,
      minOrderAmount: c.minOrderAmount,
      status: c.status,
    });
    setOpen(true);
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    try {
      const payload: Partial<Coupon> = {
        ...form,
        value: Number(form.value ?? 0),
        maxUses: form.maxUses ? Number(form.maxUses) : undefined,
        minOrderAmount: form.minOrderAmount ? Number(form.minOrderAmount) : undefined,
      };
      if (editing) {
        await update.mutateAsync({ id: editing.id, body: payload });
        toast.success("Coupon updated");
      } else {
        await create.mutateAsync(payload);
        toast.success("Coupon created");
      }
      setOpen(false);
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onDelete(c: Coupon) {
    if (!confirm(`Delete coupon ${c.code}?`)) return;
    try {
      await remove.mutateAsync(c.id);
      toast.success("Deleted");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Coupons</h1>
        <Button onClick={openCreate}>Create coupon</Button>
      </div>

      <Card>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="p-8 text-center text-sm text-muted-foreground">Loading...</div>
          ) : list.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">No coupons</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Code</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>Value</TableHead>
                  <TableHead>Valid until</TableHead>
                  <TableHead>Used</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {list.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell className="font-medium">{c.code}</TableCell>
                    <TableCell>{c.type}</TableCell>
                    <TableCell>
                      {c.type === "PERCENT" ? `${c.value}%` : uzs(c.value)}
                    </TableCell>
                    <TableCell>{dateRuShort(c.validUntil)}</TableCell>
                    <TableCell>
                      {c.usedCount ?? 0}{c.maxUses ? ` / ${c.maxUses}` : ""}
                    </TableCell>
                    <TableCell><StatusBadge status={c.status} /></TableCell>
                    <TableCell className="text-right">
                      <Button size="sm" variant="ghost" onClick={() => openEdit(c)}>Edit</Button>
                      <Button size="sm" variant="ghost" onClick={() => onDelete(c)}>Delete</Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{editing ? "Edit coupon" : "Create coupon"}</DialogTitle>
          </DialogHeader>
          <form onSubmit={submit} className="space-y-3">
            <div className="grid gap-2">
              <Label htmlFor="code">Code</Label>
              <Input
                id="code"
                value={form.code ?? ""}
                onChange={(e) => setForm((f) => ({ ...f, code: e.target.value }))}
                required
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="grid gap-2">
                <Label htmlFor="type">Type</Label>
                <Select
                  id="type"
                  value={form.type ?? "PERCENT"}
                  onChange={(e) => setForm((f) => ({ ...f, type: e.target.value }))}
                >
                  <option value="PERCENT">PERCENT</option>
                  <option value="FIXED">FIXED</option>
                </Select>
              </div>
              <div className="grid gap-2">
                <Label htmlFor="value">Value</Label>
                <Input
                  id="value"
                  type="number"
                  value={form.value ?? 0}
                  onChange={(e) => setForm((f) => ({ ...f, value: Number(e.target.value) }))}
                  required
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="grid gap-2">
                <Label htmlFor="vf">Valid from</Label>
                <Input
                  id="vf"
                  type="date"
                  value={form.validFrom?.slice(0, 10) ?? ""}
                  onChange={(e) => setForm((f) => ({ ...f, validFrom: e.target.value || undefined }))}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="vu">Valid until</Label>
                <Input
                  id="vu"
                  type="date"
                  value={form.validUntil?.slice(0, 10) ?? ""}
                  onChange={(e) => setForm((f) => ({ ...f, validUntil: e.target.value || undefined }))}
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="grid gap-2">
                <Label htmlFor="max">Max uses</Label>
                <Input
                  id="max"
                  type="number"
                  value={form.maxUses ?? ""}
                  onChange={(e) => setForm((f) => ({ ...f, maxUses: e.target.value ? Number(e.target.value) : undefined }))}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="min">Min order amount</Label>
                <Input
                  id="min"
                  type="number"
                  value={form.minOrderAmount ?? ""}
                  onChange={(e) => setForm((f) => ({ ...f, minOrderAmount: e.target.value ? Number(e.target.value) : undefined }))}
                />
              </div>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="status">Status</Label>
              <Select
                id="status"
                value={form.status ?? "ACTIVE"}
                onChange={(e) => setForm((f) => ({ ...f, status: e.target.value }))}
              >
                <option value="ACTIVE">ACTIVE</option>
                <option value="INACTIVE">INACTIVE</option>
              </Select>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={create.isPending || update.isPending}>
                {editing ? "Save" : "Create"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
