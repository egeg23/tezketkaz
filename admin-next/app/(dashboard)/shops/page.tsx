"use client";

import { useState } from "react";
import Link from "next/link";
import { toast } from "sonner";
import {
  useShops,
  useSuspendShop,
  useActivateShop,
  type Shop,
} from "@/lib/queries";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { uzs } from "@/lib/formatters";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

const VERTICALS = ["", "grocery", "restaurant", "pharmacy", "electronics"];

export default function ShopsPage() {
  const [vertical, setVertical] = useState("");
  const [status, setStatus] = useState("");
  const [q, setQ] = useState("");
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [history, setHistory] = useState<(string | undefined)[]>([undefined]);

  const { data, isLoading, error, refetch } = useShops({
    vertical: vertical || undefined,
    status: status || undefined,
    q: q || undefined,
    cursor,
    limit: 25,
  });
  const suspend = useSuspendShop();
  const activate = useActivateShop();

  const shops = data?.shops ?? [];

  async function onSuspend(s: Shop) {
    if (!confirm(`Suspend shop "${s.name}"?`)) return;
    try {
      await suspend.mutateAsync({ id: s.id });
      toast.success("Suspended");
      await refetch();
    } catch (err) {
      toast.error((err as Error).message);
    }
  }
  async function onActivate(s: Shop) {
    try {
      await activate.mutateAsync(s.id);
      toast.success("Activated");
      await refetch();
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Shops</h1>

      <Card>
        <CardContent className="flex flex-wrap items-end gap-3 pt-6">
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Vertical</label>
            <Select value={vertical} onChange={(e) => setVertical(e.target.value)}>
              {VERTICALS.map((v) => (
                <option key={v} value={v}>
                  {v || "All"}
                </option>
              ))}
            </Select>
          </div>
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Status</label>
            <Select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">All</option>
              <option value="active">Active</option>
              <option value="inactive">Inactive</option>
            </Select>
          </div>
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Search</label>
            <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="name, address, phone" />
          </div>
          <Button
            variant="outline"
            onClick={() => {
              setCursor(undefined);
              setHistory([undefined]);
              setVertical("");
              setStatus("");
              setQ("");
            }}
          >
            Reset
          </Button>
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
            <div className="p-8 text-center text-sm text-muted-foreground">Loading...</div>
          ) : shops.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">No shops</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>ID</TableHead>
                  <TableHead>Name</TableHead>
                  <TableHead>Vertical</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Members</TableHead>
                  <TableHead className="text-right">Orders</TableHead>
                  <TableHead className="text-right">30d GMV</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {shops.map((s) => (
                  <TableRow key={s.id}>
                    <TableCell className="font-mono text-xs">{s.id.slice(0, 8)}</TableCell>
                    <TableCell>
                      <Link href={`/shops/${s.id}`} className="font-medium hover:underline">
                        {s.name}
                      </Link>
                    </TableCell>
                    <TableCell>
                      <Badge variant="muted">{s.vertical}</Badge>
                    </TableCell>
                    <TableCell>
                      <Badge variant={s.isActive ? "success" : "muted"}>
                        {s.isActive ? "active" : "inactive"}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">{s.membersCount ?? 0}</TableCell>
                    <TableCell className="text-right">{s.ordersCount ?? 0}</TableCell>
                    <TableCell className="text-right">{uzs(s.last30dGMV ?? 0)}</TableCell>
                    <TableCell className="text-right">
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button size="sm" variant="ghost">…</Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem asChild>
                            <Link href={`/shops/${s.id}`}>View</Link>
                          </DropdownMenuItem>
                          {s.isActive ? (
                            <DropdownMenuItem onClick={() => onSuspend(s)}>Suspend</DropdownMenuItem>
                          ) : (
                            <DropdownMenuItem onClick={() => onActivate(s)}>Activate</DropdownMenuItem>
                          )}
                          <DropdownMenuItem asChild>
                            <Link href={`/shops/${s.id}`}>Edit</Link>
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <div className="flex items-center justify-between">
        <Button
          variant="outline"
          disabled={history.length <= 1}
          onClick={() => {
            const next = history.slice(0, -1);
            setHistory(next);
            setCursor(next[next.length - 1]);
          }}
        >
          Previous
        </Button>
        <Button
          variant="outline"
          disabled={!data?.nextCursor}
          onClick={() => {
            if (data?.nextCursor) {
              setHistory([...history, data.nextCursor]);
              setCursor(data.nextCursor);
            }
          }}
        >
          Next
        </Button>
      </div>
    </div>
  );
}
