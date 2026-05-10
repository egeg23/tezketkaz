"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import {
  useCampaigns,
  useCreateCampaign,
  useSendCampaign,
  useCancelCampaign,
  useDeleteCampaign,
  type PushCampaign,
} from "@/lib/queries";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { dateRu } from "@/lib/formatters";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

const STATUSES = [
  "",
  "draft",
  "scheduled",
  "sending",
  "sent",
  "failed",
  "cancelled",
];

const STATUS_VARIANT: Record<
  string,
  "default" | "secondary" | "destructive" | "outline" | "success" | "warning" | "info" | "muted"
> = {
  draft: "muted",
  scheduled: "info",
  sending: "warning",
  sent: "success",
  failed: "destructive",
  cancelled: "muted",
};

export default function PushCampaignsPage() {
  const router = useRouter();
  const [status, setStatus] = useState("");
  const [createOpen, setCreateOpen] = useState(false);
  const [titleRu, setTitleRu] = useState("");

  const { data, isLoading, error } = useCampaigns({
    status: status || undefined,
    limit: 50,
  });
  const create = useCreateCampaign();
  const send = useSendCampaign();
  const cancel = useCancelCampaign();
  const remove = useDeleteCampaign();

  const list: PushCampaign[] = data?.campaigns ?? [];

  async function onCreate(e: React.FormEvent) {
    e.preventDefault();
    try {
      const c = await create.mutateAsync({
        titleRu,
        status: "draft",
      });
      toast.success("Campaign created");
      setCreateOpen(false);
      setTitleRu("");
      if (c?.id) router.push(`/push-campaigns/${c.id}`);
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onSend(c: PushCampaign) {
    if (!confirm(`Send campaign "${c.titleRu || c.titleUz || c.id}" now?`)) return;
    try {
      await send.mutateAsync(c.id);
      toast.success("Send started");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onCancel(c: PushCampaign) {
    if (!confirm("Cancel this campaign?")) return;
    try {
      await cancel.mutateAsync(c.id);
      toast.success("Cancelled");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onDelete(c: PushCampaign) {
    if (!confirm("Delete this campaign?")) return;
    try {
      await remove.mutateAsync(c.id);
      toast.success("Deleted");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Push campaigns</h1>
        <Button onClick={() => setCreateOpen(true)}>+ New campaign</Button>
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
          ) : list.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              No campaigns
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Title (RU)</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Scheduled / Sent</TableHead>
                  <TableHead>Recipients</TableHead>
                  <TableHead>Success / Fail / Open</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {list.map((c) => (
                  <TableRow
                    key={c.id}
                    className="cursor-pointer"
                    onClick={() => router.push(`/push-campaigns/${c.id}`)}
                  >
                    <TableCell className="font-medium">
                      {c.titleRu || c.titleUz || c.titleEn || c.titleKk || "—"}
                    </TableCell>
                    <TableCell>
                      <Badge variant={STATUS_VARIANT[c.status] ?? "secondary"}>
                        {c.status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-xs">
                      {c.sentAt
                        ? dateRu(c.sentAt)
                        : c.scheduledFor
                          ? dateRu(c.scheduledFor)
                          : "—"}
                    </TableCell>
                    <TableCell>{c.recipientCount ?? 0}</TableCell>
                    <TableCell className="text-xs">
                      {(c.successCount ?? 0)} / {(c.failureCount ?? 0)} /{" "}
                      {(c.openCount ?? 0)}
                    </TableCell>
                    <TableCell
                      className="text-right"
                      onClick={(e) => e.stopPropagation()}
                    >
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button size="sm" variant="ghost">
                            ...
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          {c.status === "draft" && (
                            <>
                              <DropdownMenuItem
                                onSelect={() =>
                                  router.push(`/push-campaigns/${c.id}`)
                                }
                              >
                                Edit
                              </DropdownMenuItem>
                              <DropdownMenuItem onSelect={() => onSend(c)}>
                                Send now
                              </DropdownMenuItem>
                              <DropdownMenuItem onSelect={() => onDelete(c)}>
                                Delete
                              </DropdownMenuItem>
                            </>
                          )}
                          {c.status === "scheduled" && (
                            <>
                              <DropdownMenuItem
                                onSelect={() =>
                                  router.push(`/push-campaigns/${c.id}`)
                                }
                              >
                                Edit
                              </DropdownMenuItem>
                              <DropdownMenuItem onSelect={() => onCancel(c)}>
                                Cancel
                              </DropdownMenuItem>
                            </>
                          )}
                          {c.status === "sending" && (
                            <DropdownMenuItem onSelect={() => onCancel(c)}>
                              Cancel
                            </DropdownMenuItem>
                          )}
                          {(c.status === "sent" ||
                            c.status === "failed" ||
                            c.status === "cancelled") && (
                            <DropdownMenuItem
                              onSelect={() =>
                                router.push(`/push-campaigns/${c.id}`)
                              }
                            >
                              View
                            </DropdownMenuItem>
                          )}
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

      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>New push campaign</DialogTitle>
          </DialogHeader>
          <form onSubmit={onCreate} className="space-y-3">
            <div className="grid gap-2">
              <Label htmlFor="titleRu">Title (RU)</Label>
              <Input
                id="titleRu"
                value={titleRu}
                onChange={(e) => setTitleRu(e.target.value)}
                required
                placeholder="Большая распродажа в эту субботу!"
              />
              <p className="text-xs text-muted-foreground">
                You can fill the other locales and audience query on the next
                screen.
              </p>
            </div>
            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => setCreateOpen(false)}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={create.isPending}>
                Create draft
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
