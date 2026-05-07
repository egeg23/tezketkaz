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
import { uzs, dateRuShort } from "@/lib/formatters";
import type { Payout } from "@/lib/queries";

export function PayoutsTable({ payouts }: { payouts: Payout[] }) {
  const router = useRouter();
  if (!payouts.length) {
    return <div className="rounded-lg border p-8 text-center text-sm text-muted-foreground">No payouts</div>;
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Recipient</TableHead>
          <TableHead>Type</TableHead>
          <TableHead>Period</TableHead>
          <TableHead className="text-right">Net</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Paid at</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {payouts.map((p) => (
          <TableRow
            key={p.id}
            className="cursor-pointer"
            onClick={() => router.push(`/finance/${p.id}`)}
          >
            <TableCell className="font-medium">{p.recipientName || p.recipientId}</TableCell>
            <TableCell>{p.recipientType}</TableCell>
            <TableCell>{dateRuShort(p.periodStart)}</TableCell>
            <TableCell className="text-right">{uzs(p.netAmount)}</TableCell>
            <TableCell><StatusBadge status={p.status} /></TableCell>
            <TableCell className="text-muted-foreground">{dateRuShort(p.paidAt)}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
