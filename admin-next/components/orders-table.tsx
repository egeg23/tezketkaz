"use client";

import { useRouter } from "next/navigation";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { StatusBadge } from "./status-badge";
import { uzs, dateRu } from "@/lib/formatters";
import type { Order } from "@/lib/queries";

export function OrdersTable({ orders }: { orders: Order[] }) {
  const router = useRouter();
  if (!orders.length) {
    return <div className="rounded-lg border p-8 text-center text-sm text-muted-foreground">No orders</div>;
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Order #</TableHead>
          <TableHead>Buyer</TableHead>
          <TableHead>Shop</TableHead>
          <TableHead>Courier</TableHead>
          <TableHead className="text-right">Total</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Created</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {orders.map((o) => (
          <TableRow
            key={o.id}
            className="cursor-pointer"
            onClick={() => router.push(`/orders/${o.id}`)}
          >
            <TableCell className="font-medium">{o.orderNumber}</TableCell>
            <TableCell>{o.buyer?.name || o.buyer?.phone || "—"}</TableCell>
            <TableCell>{o.shop?.name || "—"}</TableCell>
            <TableCell>{o.courier?.name || "—"}</TableCell>
            <TableCell className="text-right">{uzs(o.total)}</TableCell>
            <TableCell><StatusBadge status={o.status} /></TableCell>
            <TableCell className="text-muted-foreground">{dateRu(o.createdAt)}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
