"use client";

import { useState } from "react";
import Link from "next/link";
import { useUsers, type AdminUser } from "@/lib/queries";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { dateRuShort } from "@/lib/formatters";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

const ROLES = ["", "buyer", "courier", "shop", "admin"];

function RoleBadges({ u }: { u: AdminUser }) {
  return (
    <div className="flex flex-wrap gap-1">
      {u.isBuyer ? <Badge variant="info">buyer</Badge> : null}
      {u.isCourier ? <Badge variant="warning">courier</Badge> : null}
      {u.isShop ? <Badge variant="success">shop</Badge> : null}
      {u.isAdmin ? <Badge variant="destructive">admin</Badge> : null}
    </div>
  );
}

export default function UsersPage() {
  const [role, setRole] = useState("");
  const [q, setQ] = useState("");
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [history, setHistory] = useState<(string | undefined)[]>([undefined]);

  const { data, isLoading, error } = useUsers({
    role: role || undefined,
    q: q || undefined,
    cursor,
    limit: 25,
  });

  const users = data?.users ?? [];

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Users</h1>

      <Card>
        <CardContent className="flex flex-wrap items-end gap-3 pt-6">
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Role</label>
            <Select value={role} onChange={(e) => setRole(e.target.value)}>
              {ROLES.map((r) => (
                <option key={r} value={r}>
                  {r || "All"}
                </option>
              ))}
            </Select>
          </div>
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Search</label>
            <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="phone or name" />
          </div>
          <Button
            variant="outline"
            onClick={() => {
              setCursor(undefined);
              setHistory([undefined]);
              setRole("");
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
          ) : users.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">No users</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>ID</TableHead>
                  <TableHead>Phone</TableHead>
                  <TableHead>Name</TableHead>
                  <TableHead>Roles</TableHead>
                  <TableHead>Courier</TableHead>
                  <TableHead className="text-right">Orders</TableHead>
                  <TableHead>Last seen</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {users.map((u) => (
                  <TableRow key={u.id}>
                    <TableCell className="font-mono text-xs">{u.id.slice(0, 8)}</TableCell>
                    <TableCell className="font-mono text-xs">{u.phone}</TableCell>
                    <TableCell>
                      <Link href={`/users/${u.id}`} className="font-medium hover:underline">
                        {u.name || "—"}
                      </Link>
                    </TableCell>
                    <TableCell><RoleBadges u={u} /></TableCell>
                    <TableCell>
                      {u.courierStatus !== "none" ? (
                        <Badge
                          variant={
                            u.courierStatus === "approved" ? "success"
                            : u.courierStatus === "rejected" ? "muted"
                            : "warning"
                          }
                        >
                          {u.courierStatus}
                        </Badge>
                      ) : (
                        <span className="text-xs text-muted-foreground">—</span>
                      )}
                    </TableCell>
                    <TableCell className="text-right">{u.ordersCount ?? 0}</TableCell>
                    <TableCell>{u.lastSeenAt ? dateRuShort(u.lastSeenAt) : "—"}</TableCell>
                    <TableCell className="text-right">
                      <Button size="sm" variant="ghost" asChild>
                        <Link href={`/users/${u.id}`}>View</Link>
                      </Button>
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
