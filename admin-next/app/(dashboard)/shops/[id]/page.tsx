"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { toast } from "sonner";
import {
  useShop,
  useUpdateShop,
  useSuspendShop,
  useActivateShop,
  type Shop,
} from "@/lib/queries";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { uzs, dateRu } from "@/lib/formatters";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

const VERTICALS = ["grocery", "restaurant", "pharmacy", "electronics"];
const CURRENCIES = ["UZS", "KZT", "KGS"];

export default function ShopDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params?.id as string | undefined;
  const { data, isLoading, error } = useShop(id);
  const update = useUpdateShop();
  const suspend = useSuspendShop();
  const activate = useActivateShop();

  const [form, setForm] = useState<Partial<Shop>>({});

  useEffect(() => {
    if (data?.shop) {
      const s = data.shop;
      setForm({
        name: s.name,
        address: s.address,
        phone: s.phone ?? "",
        vertical: s.vertical,
        currency: s.currency ?? "UZS",
        isActive: s.isActive,
        deliveryBaseFee: s.deliveryBaseFee ?? null,
        deliveryPerKm: s.deliveryPerKm ?? null,
        freeDeliveryKm: s.freeDeliveryKm ?? null,
        minOrderAmount: s.minOrderAmount ?? null,
      });
    }
  }, [data?.shop]);

  if (isLoading) return <div className="text-sm text-muted-foreground">Loading...</div>;
  if (error) return <div className="text-sm text-destructive">{(error as Error).message}</div>;
  if (!data?.shop || !id) return <div className="text-sm text-muted-foreground">Not found</div>;

  const shop = data.shop;

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

  async function onSuspend() {
    if (!id) return;
    if (!confirm(`Suspend "${shop.name}"?`)) return;
    try {
      await suspend.mutateAsync({ id });
      toast.success("Suspended");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }
  async function onActivate() {
    if (!id) return;
    try {
      await activate.mutateAsync(id);
      toast.success("Activated");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">{shop.name}</h1>
        <div className="mt-1 flex items-center gap-2 text-sm text-muted-foreground">
          <Badge variant={shop.isActive ? "success" : "muted"}>
            {shop.isActive ? "active" : "inactive"}
          </Badge>
          <Badge variant="muted">{shop.vertical}</Badge>
          <span className="font-mono">{shop.id}</span>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader><CardTitle>Members</CardTitle></CardHeader>
          <CardContent className="text-3xl font-semibold">{data.membersCount}</CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Orders</CardTitle></CardHeader>
          <CardContent className="text-3xl font-semibold">{data.ordersCount}</CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>30d GMV</CardTitle></CardHeader>
          <CardContent className="text-3xl font-semibold">{uzs(data.last30dGMV)}</CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle>Edit shop</CardTitle>
            <div className="flex gap-2">
              {shop.isActive ? (
                <Button variant="outline" onClick={onSuspend}>Suspend</Button>
              ) : (
                <Button variant="outline" onClick={onActivate}>Activate</Button>
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
                required
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="phone">Phone</Label>
              <Input
                id="phone"
                value={form.phone ?? ""}
                onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
              />
            </div>
            <div className="grid gap-2 sm:col-span-2">
              <Label htmlFor="address">Address</Label>
              <Input
                id="address"
                value={form.address ?? ""}
                onChange={(e) => setForm((f) => ({ ...f, address: e.target.value }))}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="vertical">Vertical</Label>
              <Select
                id="vertical"
                value={form.vertical ?? "grocery"}
                onChange={(e) => setForm((f) => ({ ...f, vertical: e.target.value }))}
              >
                {VERTICALS.map((v) => <option key={v} value={v}>{v}</option>)}
              </Select>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="currency">Currency</Label>
              <Select
                id="currency"
                value={form.currency ?? "UZS"}
                onChange={(e) => setForm((f) => ({ ...f, currency: e.target.value }))}
              >
                {CURRENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
              </Select>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="bf">Delivery base fee</Label>
              <Input
                id="bf"
                type="number"
                value={form.deliveryBaseFee ?? ""}
                onChange={(e) => setForm((f) => ({ ...f, deliveryBaseFee: e.target.value === "" ? null : Number(e.target.value) }))}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="pkm">Delivery per km</Label>
              <Input
                id="pkm"
                type="number"
                value={form.deliveryPerKm ?? ""}
                onChange={(e) => setForm((f) => ({ ...f, deliveryPerKm: e.target.value === "" ? null : Number(e.target.value) }))}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="fkm">Free delivery km</Label>
              <Input
                id="fkm"
                type="number"
                value={form.freeDeliveryKm ?? ""}
                onChange={(e) => setForm((f) => ({ ...f, freeDeliveryKm: e.target.value === "" ? null : Number(e.target.value) }))}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="moa">Min order amount</Label>
              <Input
                id="moa"
                type="number"
                value={form.minOrderAmount ?? ""}
                onChange={(e) => setForm((f) => ({ ...f, minOrderAmount: e.target.value === "" ? null : Number(e.target.value) }))}
              />
            </div>
            <div className="grid gap-2 sm:col-span-2">
              <Label htmlFor="active">Active</Label>
              <Select
                id="active"
                value={form.isActive ? "1" : "0"}
                onChange={(e) => setForm((f) => ({ ...f, isActive: e.target.value === "1" }))}
              >
                <option value="1">Active</option>
                <option value="0">Inactive</option>
              </Select>
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
        <CardHeader><CardTitle>Members</CardTitle></CardHeader>
        <CardContent className="p-0">
          {shop.members?.length ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Phone</TableHead>
                  <TableHead>Name</TableHead>
                  <TableHead>Role</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {shop.members.map((m) => (
                  <TableRow key={m.id}>
                    <TableCell className="font-mono text-xs">{m.user.phone || "—"}</TableCell>
                    <TableCell>{m.user.name || "—"}</TableCell>
                    <TableCell><Badge variant="muted">{m.role}</Badge></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <div className="p-6 text-center text-sm text-muted-foreground">No members</div>
          )}
        </CardContent>
      </Card>

      <div className="text-xs text-muted-foreground">
        Created: {dateRu(shop.createdAt)}
      </div>
    </div>
  );
}
