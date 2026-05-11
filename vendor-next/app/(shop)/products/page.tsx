"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { useShopProducts, useDeleteProduct } from "@/lib/queries";
import { useCurrentShop } from "@/lib/shop-context";
import { uzs, dateRuShort } from "@/lib/formatters";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";

export default function ProductsPage() {
  const { shopId } = useCurrentShop();
  const router = useRouter();
  const [search, setSearch] = useState("");
  const { data, isLoading, error } = useShopProducts(shopId);
  const del = useDeleteProduct();

  const products = (data?.products ?? []).filter((p) => {
    if (!search.trim()) return true;
    const q = search.toLowerCase();
    return (
      p.name.toLowerCase().includes(q) ||
      (p.nameUz || "").toLowerCase().includes(q) ||
      (p.category || "").toLowerCase().includes(q)
    );
  });

  async function onDelete(id: string) {
    if (!confirm("Archive this product?")) return;
    try {
      await del.mutateAsync(id);
      toast.success("Product archived");
    } catch (e) {
      toast.error((e as Error).message);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Products</h1>
        <Button asChild>
          <Link href="/products/new">New product</Link>
        </Button>
      </div>

      <Card>
        <CardContent className="flex items-center gap-3 pt-6">
          <Input
            placeholder="Search by name or category..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="max-w-md"
          />
          <div className="text-xs text-muted-foreground">
            {products.length} item{products.length === 1 ? "" : "s"}
          </div>
        </CardContent>
      </Card>

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          {(error as Error).message}
        </div>
      )}

      <Card>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              Loading...
            </div>
          ) : products.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              No products yet.
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead></TableHead>
                  <TableHead>Name</TableHead>
                  <TableHead>Category</TableHead>
                  <TableHead className="text-right">Price</TableHead>
                  <TableHead className="text-right">Stock</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Updated</TableHead>
                  <TableHead></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {products.map((p) => (
                  <TableRow key={p.id} className="cursor-pointer">
                    <TableCell
                      onClick={() => router.push(`/products/${p.id}`)}
                      className="w-12"
                    >
                      {p.imageUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={p.imageUrl}
                          alt=""
                          className="h-9 w-9 rounded-md border object-cover"
                        />
                      ) : (
                        <div className="h-9 w-9 rounded-md border bg-muted" />
                      )}
                    </TableCell>
                    <TableCell
                      onClick={() => router.push(`/products/${p.id}`)}
                      className="font-medium"
                    >
                      <div>{p.name}</div>
                      {p.nameUz && (
                        <div className="text-xs text-muted-foreground">
                          {p.nameUz}
                        </div>
                      )}
                    </TableCell>
                    <TableCell
                      onClick={() => router.push(`/products/${p.id}`)}
                      className="text-muted-foreground"
                    >
                      {p.category || "—"}
                    </TableCell>
                    <TableCell
                      onClick={() => router.push(`/products/${p.id}`)}
                      className="text-right"
                    >
                      {p.discountPrice ? (
                        <div>
                          <div>{uzs(p.discountPrice)}</div>
                          <div className="text-xs text-muted-foreground line-through">
                            {uzs(p.price)}
                          </div>
                        </div>
                      ) : (
                        uzs(p.price)
                      )}
                    </TableCell>
                    <TableCell
                      onClick={() => router.push(`/products/${p.id}`)}
                      className="text-right"
                    >
                      {p.stock ?? "—"}
                    </TableCell>
                    <TableCell
                      onClick={() => router.push(`/products/${p.id}`)}
                    >
                      {p.isAvailable ? (
                        <Badge variant="success">Available</Badge>
                      ) : (
                        <Badge variant="muted">Hidden</Badge>
                      )}
                    </TableCell>
                    <TableCell
                      onClick={() => router.push(`/products/${p.id}`)}
                      className="text-muted-foreground"
                    >
                      {dateRuShort(p.updatedAt)}
                    </TableCell>
                    <TableCell className="text-right">
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={(e) => {
                          e.stopPropagation();
                          onDelete(p.id);
                        }}
                      >
                        Delete
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
