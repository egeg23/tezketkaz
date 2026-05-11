"use client";

import { useParams, useRouter } from "next/navigation";
import { toast } from "sonner";
import {
  useShopProducts,
  useUpdateProduct,
  useDeleteProduct,
} from "@/lib/queries";
import { useCurrentShop } from "@/lib/shop-context";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ProductForm } from "@/components/product-form";

export default function EditProductPage() {
  const params = useParams<{ id: string }>();
  const id = params?.id as string | undefined;
  const router = useRouter();
  const { shopId } = useCurrentShop();
  const { data, isLoading, error } = useShopProducts(shopId);
  const update = useUpdateProduct();
  const del = useDeleteProduct();

  const product = (data?.products ?? []).find((p) => p.id === id);

  if (isLoading) {
    return <div className="text-sm text-muted-foreground">Loading...</div>;
  }
  if (error) {
    return (
      <div className="text-sm text-destructive">{(error as Error).message}</div>
    );
  }
  if (!product) {
    return <div className="text-sm text-muted-foreground">Not found</div>;
  }

  async function onDelete() {
    if (!id) return;
    if (!confirm("Archive this product?")) return;
    try {
      await del.mutateAsync(id);
      toast.success("Product archived");
      router.push("/products");
    } catch (e) {
      toast.error((e as Error).message);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between">
        <div>
          <button
            type="button"
            onClick={() => router.push("/products")}
            className="text-xs text-muted-foreground hover:underline"
          >
            ← Back to products
          </button>
          <h1 className="text-2xl font-semibold">Edit: {product.name}</h1>
        </div>
        <Button variant="destructive" onClick={onDelete} disabled={del.isPending}>
          {del.isPending ? "Deleting..." : "Delete"}
        </Button>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Details</CardTitle>
        </CardHeader>
        <CardContent>
          <ProductForm
            initial={product}
            submitting={update.isPending}
            onCancel={() => router.push("/products")}
            submitLabel="Save changes"
            onSubmit={async (values) => {
              if (!id) return;
              try {
                await update.mutateAsync({ id, body: values });
                toast.success("Product saved");
                router.push("/products");
              } catch (err) {
                toast.error((err as Error).message);
              }
            }}
          />
        </CardContent>
      </Card>
    </div>
  );
}
