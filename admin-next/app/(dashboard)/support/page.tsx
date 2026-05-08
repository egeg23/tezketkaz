"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  useSupportTickets,
  useSupportStats,
  useUsers,
  type SupportTicket,
} from "@/lib/queries";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { KpiCard } from "@/components/kpi-card";
import { StatusBadge } from "@/components/status-badge";
import { PriorityBadge } from "@/components/priority-badge";
import { RelativeTime } from "@/components/relative-time";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

const STATUSES = [
  "",
  "open",
  "in_progress",
  "awaiting_user",
  "resolved",
  "closed",
];

const PRIORITIES = ["", "low", "normal", "high", "urgent"];

export default function SupportPage() {
  const router = useRouter();
  const [status, setStatus] = useState("");
  const [priority, setPriority] = useState("");
  const [assigneeId, setAssigneeId] = useState("");
  const [q, setQ] = useState("");
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [history, setHistory] = useState<(string | undefined)[]>([undefined]);

  const { data: stats } = useSupportStats();
  const { data: adminsResp } = useUsers({ role: "admin", limit: 100 });
  const admins = adminsResp?.users ?? [];

  const { data, isLoading, error } = useSupportTickets({
    status: status || undefined,
    priority: priority || undefined,
    assigneeId: assigneeId || undefined,
    q: q || undefined,
    cursor,
    limit: 25,
  });

  const tickets: SupportTicket[] = data?.data ?? [];

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Support inbox</h1>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        <KpiCard label="Open" value={String(stats?.open ?? 0)} />
        <KpiCard label="In progress" value={String(stats?.in_progress ?? 0)} />
        <KpiCard label="Awaiting user" value={String(stats?.awaiting_user ?? 0)} />
        <KpiCard label="Resolved today" value={String(stats?.resolved_today ?? 0)} />
        <KpiCard label="Closed today" value={String(stats?.closed_today ?? 0)} />
      </div>

      <Card>
        <CardContent className="flex flex-wrap items-end gap-3 pt-6">
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Status</label>
            <Select value={status} onChange={(e) => setStatus(e.target.value)}>
              {STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s || "All"}
                </option>
              ))}
            </Select>
          </div>
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Priority</label>
            <Select value={priority} onChange={(e) => setPriority(e.target.value)}>
              {PRIORITIES.map((p) => (
                <option key={p} value={p}>
                  {p || "All"}
                </option>
              ))}
            </Select>
          </div>
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Assignee</label>
            <Select
              value={assigneeId}
              onChange={(e) => setAssigneeId(e.target.value)}
            >
              <option value="">All</option>
              <option value="unassigned">Unassigned</option>
              {admins.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.name || u.phone || u.id}
                </option>
              ))}
            </Select>
          </div>
          <div className="grid gap-1">
            <label className="text-xs text-muted-foreground">Search</label>
            <Input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Subject, phone, body..."
            />
          </div>
          <Button
            variant="outline"
            onClick={() => {
              setStatus("");
              setPriority("");
              setAssigneeId("");
              setQ("");
              setCursor(undefined);
              setHistory([undefined]);
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
            <div className="p-8 text-center text-sm text-muted-foreground">
              Loading...
            </div>
          ) : tickets.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              No tickets
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Subject</TableHead>
                  <TableHead>Author</TableHead>
                  <TableHead>Category</TableHead>
                  <TableHead>Priority</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Assignee</TableHead>
                  <TableHead>Last reply</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {tickets.map((t) => (
                  <TableRow
                    key={t.id}
                    className="cursor-pointer"
                    onClick={() => router.push(`/support/${t.id}`)}
                  >
                    <TableCell className="font-medium">
                      <div className="flex items-center gap-2">
                        {t.unreplied && (
                          <span
                            className="h-2 w-2 rounded-full bg-blue-500"
                            title="Unreplied"
                          />
                        )}
                        <span className="line-clamp-1">{t.subject}</span>
                      </div>
                    </TableCell>
                    <TableCell className="text-xs">
                      <div className="font-medium">
                        {t.author?.name || "—"}
                      </div>
                      <div className="text-muted-foreground">
                        {t.author?.phone || "—"}
                      </div>
                    </TableCell>
                    <TableCell>
                      {t.category ? (
                        <Badge variant="outline">{t.category}</Badge>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </TableCell>
                    <TableCell>
                      <PriorityBadge priority={t.priority} />
                    </TableCell>
                    <TableCell>
                      <StatusBadge status={t.status} />
                    </TableCell>
                    <TableCell className="text-xs">
                      {t.assignee?.name || t.assignee?.phone || (
                        <span className="text-muted-foreground">Unassigned</span>
                      )}
                    </TableCell>
                    <TableCell className="text-xs text-muted-foreground">
                      <RelativeTime value={t.lastReplyAt ?? t.updatedAt ?? t.createdAt} />
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
