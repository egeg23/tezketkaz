"use client";

import { useState } from "react";
import { toast } from "sonner";
import { useUploadProductImage } from "@/lib/queries";
import type { Product } from "@/lib/queries";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

export type ProductFormValues = Partial<Product>;

interface ProductFormProps {
  initial?: ProductFormValues;
  submitting?: boolean;
  onSubmit: (values: ProductFormValues) => Promise<void> | void;
  onCancel?: () => void;
  submitLabel?: string;
}

export function ProductForm({
  initial,
  submitting,
  onSubmit,
  onCancel,
  submitLabel = "Save",
}: ProductFormProps) {
  const [name, setName] = useState(initial?.name ?? "");
  const [nameUz, setNameUz] = useState(initial?.nameUz ?? "");
  const [description, setDescription] = useState(initial?.description ?? "");
  const [price, setPrice] = useState<string>(
    initial?.price !== undefined ? String(initial?.price) : ""
  );
  const [discountPrice, setDiscountPrice] = useState<string>(
    initial?.discountPrice != null ? String(initial.discountPrice) : ""
  );
  const [unit, setUnit] = useState(initial?.unit ?? "");
  const [category, setCategory] = useState(initial?.category ?? "");
  const [stock, setStock] = useState<string>(
    initial?.stock != null ? String(initial.stock) : ""
  );
  const [imageUrl, setImageUrl] = useState(initial?.imageUrl ?? "");
  const [isAvailable, setIsAvailable] = useState<boolean>(
    initial?.isAvailable ?? true
  );

  const upload = useUploadProductImage();

  async function onPickFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    try {
      const res = await upload.mutateAsync(f);
      setImageUrl(res.url);
      toast.success("Image uploaded");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) {
      toast.error("Name is required");
      return;
    }
    if (!price.trim() || Number.isNaN(Number(price))) {
      toast.error("Valid price is required");
      return;
    }
    await onSubmit({
      name: name.trim(),
      nameUz: nameUz.trim() || null,
      description: description.trim() || null,
      price: Number(price),
      discountPrice: discountPrice.trim() ? Number(discountPrice) : null,
      unit: unit.trim() || null,
      category: category.trim() || null,
      stock: stock.trim() ? Number(stock) : null,
      imageUrl: imageUrl.trim() || null,
      isAvailable,
    });
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="name">Name (RU)</Label>
          <Input
            id="name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            required
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="nameUz">Name (UZ)</Label>
          <Input
            id="nameUz"
            value={nameUz ?? ""}
            onChange={(e) => setNameUz(e.target.value)}
          />
        </div>
      </div>

      <div className="space-y-2">
        <Label htmlFor="description">Description</Label>
        <Textarea
          id="description"
          value={description ?? ""}
          onChange={(e) => setDescription(e.target.value)}
        />
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <div className="space-y-2">
          <Label htmlFor="price">Price (UZS)</Label>
          <Input
            id="price"
            type="number"
            min="0"
            value={price}
            onChange={(e) => setPrice(e.target.value)}
            required
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="discountPrice">Discount price</Label>
          <Input
            id="discountPrice"
            type="number"
            min="0"
            value={discountPrice}
            onChange={(e) => setDiscountPrice(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="stock">Stock</Label>
          <Input
            id="stock"
            type="number"
            min="0"
            value={stock}
            onChange={(e) => setStock(e.target.value)}
          />
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="unit">Unit</Label>
          <Input
            id="unit"
            placeholder="кг, шт, л..."
            value={unit ?? ""}
            onChange={(e) => setUnit(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="category">Category slug</Label>
          <Input
            id="category"
            placeholder="produce, bakery..."
            value={category ?? ""}
            onChange={(e) => setCategory(e.target.value)}
          />
        </div>
      </div>

      <div className="space-y-2">
        <Label htmlFor="image">Image</Label>
        <div className="flex items-center gap-3">
          <Input
            id="image"
            type="file"
            accept="image/*"
            onChange={onPickFile}
            disabled={upload.isPending}
          />
          {imageUrl && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={imageUrl}
              alt=""
              className="h-12 w-12 rounded-md border object-cover"
            />
          )}
        </div>
        {imageUrl && (
          <div className="text-xs text-muted-foreground">{imageUrl}</div>
        )}
      </div>

      <div className="flex items-center gap-2">
        <input
          id="isAvailable"
          type="checkbox"
          checked={isAvailable}
          onChange={(e) => setIsAvailable(e.target.checked)}
          className="h-4 w-4 rounded border-input"
        />
        <Label htmlFor="isAvailable" className="cursor-pointer">
          Available for sale
        </Label>
      </div>

      <div className="flex gap-2">
        <Button type="submit" disabled={submitting}>
          {submitting ? "Saving..." : submitLabel}
        </Button>
        {onCancel && (
          <Button type="button" variant="outline" onClick={onCancel}>
            Cancel
          </Button>
        )}
      </div>
    </form>
  );
}
