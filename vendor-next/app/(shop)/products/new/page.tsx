"use client";

import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { useCreateProduct } from "@/lib/queries";
import { useCurrentShop } from "@/lib/shop-context";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { ProductForm } from "@/components/product-form";

export default function NewProductPage() {
  const { shopId } = useCurrentShop();
  const router = useRouter();
  const create = useCreateProduct();

  return (
    <div className="space-y-4">
      <div>
        <button
          type="button"
          onClick={() => router.push("/products")}
          className="text-xs text-muted-foreground hover:underline"
        >
          ← Back to products
        </button>
        <h1 className="text-2xl font-semibold">New product</h1>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Details</CardTitle>
        </CardHeader>
        <CardContent>
          {!shopId ? (
            <div className="text-sm text-muted-foreground">
              No shop selected.
            </div>
          ) : (
            <ProductForm
              submitting={create.isPending}
              onCancel={() => router.push("/products")}
              submitLabel="Create product"
              onSubmit={async (values) => {
                try {
                  await create.mutateAsync({ ...values, shopId });
                  toast.success("Product created");
                  router.push("/products");
                } catch (err) {
                  toast.error((err as Error).message);
                }
              }}
            />
          )}
        </CardContent>
      </Card>
    </div>
  );
}
