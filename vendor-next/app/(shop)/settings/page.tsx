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

  useEffect(() => {
    if (shop) {
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
  }, [shop]);

  async function onSave(e: React.FormEvent) {
    e.preventDefault();
    if (!shopId) return;
    try {
      await update.mutateAsync({
        id: shopId,
        body: {
          name: name.trim(),
          description: description.trim() || null,
          address: address.trim(),
          phone: phone.trim() || null,
          currency: currency.trim() || "UZS",
          deliveryBaseFee: deliveryBaseFee.trim()
            ? Number(deliveryBaseFee)
            : null,
          deliveryPerKm: deliveryPerKm.trim() ? Number(deliveryPerKm) : null,
          freeDeliveryKm: freeDeliveryKm.trim() ? Number(freeDeliveryKm) : null,
          minOrderAmount: minOrderAmount.trim()
            ? Number(minOrderAmount)
            : null,
        },
      });
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
                onChange={(e) => setName(e.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="description">Description</Label>
              <Textarea
                id="description"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
              />
            </div>
            <div className="grid gap-4 md:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="address">Address</Label>
                <Input
                  id="address"
                  value={address}
                  onChange={(e) => setAddress(e.target.value)}
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="phone">Phone</Label>
                <Input
                  id="phone"
                  type="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
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
                  onChange={(e) => setCurrency(e.target.value.toUpperCase())}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="minOrderAmount">Minimum order</Label>
                <Input
                  id="minOrderAmount"
                  type="number"
                  min="0"
                  value={minOrderAmount}
                  onChange={(e) => setMinOrderAmount(e.target.value)}
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
                  onChange={(e) => setDeliveryBaseFee(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="deliveryPerKm">Fee per km</Label>
                <Input
                  id="deliveryPerKm"
                  type="number"
                  min="0"
                  value={deliveryPerKm}
                  onChange={(e) => setDeliveryPerKm(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="freeDeliveryKm">Free delivery within (km)</Label>
                <Input
                  id="freeDeliveryKm"
                  type="number"
                  min="0"
                  value={freeDeliveryKm}
                  onChange={(e) => setFreeDeliveryKm(e.target.value)}
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
