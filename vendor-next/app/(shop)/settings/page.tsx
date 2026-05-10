"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useUpdateShop } from "@/lib/queries";
import { useCurrentShop } from "@/lib/shop-context";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

export default function SettingsPage() {
  const { shop, shopId, isLoading, error } = useCurrentShop();
  const update = useUpdateShop();

  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [address, setAddress] = useState("");
  const [phone, setPhone] = useState("");
  const [currency, setCurrency] = useState("UZS");
  const [deliveryBaseFee, setDeliveryBaseFee] = useState("");
  const [deliveryPerKm, setDeliveryPerKm] = useState("");
  const [freeDeliveryKm, setFreeDeliveryKm] = useState("");
  const [minOrderAmount, setMinOrderAmount] = useState("");
  // Track whether the user has edited the form so a background refetch can't
  // clobber in-progress changes.
  const [isDirty, setIsDirty] = useState(false);

  useEffect(() => {
    if (shop && !isDirty) {
      setName(shop.name || "");
      setDescription(shop.description || "");
      setAddress(shop.address || "");
      setPhone(shop.phone || "");
      setCurrency(shop.currency || "UZS");
      setDeliveryBaseFee(
        shop.deliveryBaseFee != null ? String(shop.deliveryBaseFee) : ""
      );
      setDeliveryPerKm(
        shop.deliveryPerKm != null ? String(shop.deliveryPerKm) : ""
      );
      setFreeDeliveryKm(
        shop.freeDeliveryKm != null ? String(shop.freeDeliveryKm) : ""
      );
      setMinOrderAmount(
        shop.minOrderAmount != null ? String(shop.minOrderAmount) : ""
      );
    }
  }, [shop, isDirty]);

  // Reset the dirty flag when the user switches to a different shop so the
  // form repopulates from the new row.
  useEffect(() => {
    setIsDirty(false);
  }, [shopId]);

  // Parse a string field as a non-negative number, returning null when empty
  // and throwing on negative / NaN so the user sees a clear toast.
  function parseOptionalNonNegative(value: string, label: string): number | null {
    const v = value.trim();
    if (!v) return null;
    const n = Number(v);
    if (!Number.isFinite(n) || n < 0) {
      throw new Error(`${label} must be a non-negative number`);
    }
    return n;
  }

  async function onSave(e: React.FormEvent) {
    e.preventDefault();
    if (!shopId) return;
    let baseFee: number | null;
    let perKm: number | null;
    let freeKm: number | null;
    let minOrder: number | null;
    try {
      baseFee = parseOptionalNonNegative(deliveryBaseFee, "Base delivery fee");
      perKm = parseOptionalNonNegative(deliveryPerKm, "Fee per km");
      freeKm = parseOptionalNonNegative(freeDeliveryKm, "Free delivery within");
      minOrder = parseOptionalNonNegative(minOrderAmount, "Minimum order");
    } catch (err) {
      toast.error((err as Error).message);
      return;
    }
    try {
      await update.mutateAsync({
        id: shopId,
        body: {
          name: name.trim(),
          description: description.trim() || null,
          address: address.trim(),
          phone: phone.trim() || null,
          currency: currency.trim() || "UZS",
          deliveryBaseFee: baseFee,
          deliveryPerKm: perKm,
          freeDeliveryKm: freeKm,
          minOrderAmount: minOrder,
        },
      });
      setIsDirty(false);
      toast.success("Shop settings saved");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Settings</h1>

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          {(error as Error).message}
        </div>
      )}

      <form onSubmit={onSave} className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Storefront</CardTitle>
            <CardDescription>
              Information your customers see in the buyer app.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="name">Shop name</Label>
              <Input
                id="name"
                value={name}
                onChange={(e) => { setIsDirty(true); setName(e.target.value); }}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="description">Description</Label>
              <Textarea
                id="description"
                value={description}
                onChange={(e) => { setIsDirty(true); setDescription(e.target.value); }}
              />
            </div>
            <div className="grid gap-4 md:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="address">Address</Label>
                <Input
                  id="address"
                  value={address}
                  onChange={(e) => { setIsDirty(true); setAddress(e.target.value); }}
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="phone">Phone</Label>
                <Input
                  id="phone"
                  type="tel"
                  value={phone}
                  onChange={(e) => { setIsDirty(true); setPhone(e.target.value); }}
                />
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Delivery economics</CardTitle>
            <CardDescription>
              Used by the checkout flow to compute delivery fees and minimum
              order thresholds.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-4 md:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="currency">Currency</Label>
                <Input
                  id="currency"
                  value={currency}
                  onChange={(e) => { setIsDirty(true); setCurrency(e.target.value.toUpperCase()); }}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="minOrderAmount">Minimum order</Label>
                <Input
                  id="minOrderAmount"
                  type="number"
                  min="0"
                  value={minOrderAmount}
                  onChange={(e) => { setIsDirty(true); setMinOrderAmount(e.target.value); }}
                />
              </div>
            </div>
            <div className="grid gap-4 md:grid-cols-3">
              <div className="space-y-2">
                <Label htmlFor="deliveryBaseFee">Base delivery fee</Label>
                <Input
                  id="deliveryBaseFee"
                  type="number"
                  min="0"
                  value={deliveryBaseFee}
                  onChange={(e) => { setIsDirty(true); setDeliveryBaseFee(e.target.value); }}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="deliveryPerKm">Fee per km</Label>
                <Input
                  id="deliveryPerKm"
                  type="number"
                  min="0"
                  value={deliveryPerKm}
                  onChange={(e) => { setIsDirty(true); setDeliveryPerKm(e.target.value); }}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="freeDeliveryKm">Free delivery within (km)</Label>
                <Input
                  id="freeDeliveryKm"
                  type="number"
                  min="0"
                  value={freeDeliveryKm}
                  onChange={(e) => { setIsDirty(true); setFreeDeliveryKm(e.target.value); }}
                />
              </div>
            </div>
          </CardContent>
        </Card>

        <div className="flex justify-end gap-2">
          <Button type="submit" disabled={update.isPending || isLoading}>
            {update.isPending ? "Saving..." : "Save settings"}
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">
          Note: The shop-owner-callable PATCH endpoint is assumed at
          <code className="mx-1">PATCH /api/shops/:id</code>. If the backend
          only exposes the admin-scoped route, this save will 403 and the
          backend team needs to wire up an owner-callable endpoint.
        </p>
      </form>
    </div>
  );
}
