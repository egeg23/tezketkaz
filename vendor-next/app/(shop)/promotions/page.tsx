"use client";

import { useShopCoupons } from "@/lib/queries";
import { useCurrentShop } from "@/lib/shop-context";
import { uzs, dateRuShort } from "@/lib/formatters";
import { ApiError } from "@/lib/api";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

export default function PromotionsPage() {
  const { shopId } = useCurrentShop();
  const { data, isLoading, error } = useShopCoupons(shopId);

  // Backend `/api/coupons` requires admin role. For shop owners this will
  // return 403 today — we present a read-only "contact admin" stub instead
  // of failing loudly.
  const forbidden = error instanceof ApiError && error.status === 403;
  const coupons = data?.coupons ?? [];

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Promotions</h1>

      <Card>
        <CardHeader>
          <CardTitle>Coupons scoped to this shop</CardTitle>
        </CardHeader>
        <CardContent>
          {forbidden ? (
            <div className="rounded-md border border-yellow-300 bg-yellow-50 p-4 text-sm text-yellow-900">
              Promotion management is currently admin-only. Please contact the
              TezKetKaz operations team to create or update shop-scoped
              coupons. This page will show your active coupons once the
              shop-owner API is exposed.
            </div>
          ) : error ? (
            <div className="text-sm text-destructive">
              {(error as Error).message}
            </div>
          ) : isLoading ? (
            <div className="text-sm text-muted-foreground">Loading...</div>
          ) : coupons.length === 0 ? (
            <div className="text-sm text-muted-foreground">
              No coupons yet. Contact your TezKetKaz account manager to launch
              a campaign.
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Code</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead className="text-right">Value</TableHead>
                  <TableHead>Valid from</TableHead>
                  <TableHead>Valid until</TableHead>
                  <TableHead>Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {coupons.map((c) => (
                  <TableRow key={c.code}>
                    <TableCell className="font-medium">{c.code}</TableCell>
                    <TableCell>{c.type}</TableCell>
                    <TableCell className="text-right">
                      {c.type === "PERCENT"
                        ? `${c.value}%`
                        : uzs(c.value)}
                    </TableCell>
                    <TableCell>{dateRuShort(c.validFrom)}</TableCell>
                    <TableCell>{dateRuShort(c.validUntil)}</TableCell>
                    <TableCell>
                      {c.isActive ? (
                        <Badge variant="success">Active</Badge>
                      ) : (
                        <Badge variant="muted">Inactive</Badge>
                      )}
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
