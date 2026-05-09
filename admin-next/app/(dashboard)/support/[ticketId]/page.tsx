"use client";

import { useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { toast } from "sonner";
import {
  useSupportTicket,
  useAssignTicket,
  useUpdateTicket,
  useCloseTicket,
  useReplyTicket,
  useUsers,
  useUploadBannerImage,
} from "@/lib/queries";
import { useAuth } from "@/lib/auth";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { StatusBadge } from "@/components/status-badge";
import { PriorityBadge } from "@/components/priority-badge";
import { RelativeTime } from "@/components/relative-time";
import { dateRu } from "@/lib/formatters";
import { API_URL } from "@/lib/api";

const STATUSES = ["open", "in_progress", "awaiting_user", "resolved", "closed"];
const PRIORITIES = ["low", "normal", "high", "urgent"];

function attachmentUrl(url: string) {
  if (!url) return "";
  if (url.startsWith("http")) return url;
  return `${API_URL}${url}`;
}

export default function TicketDetailPage() {
  const params = useParams<{ ticketId: string }>();
  const router = useRouter();
  const id = params?.ticketId;

  const { user: me } = useAuth();
  const { data: ticketResp, isLoading, error } = useSupportTicket(id);
  const ticket = ticketResp?.ticket;
  const { data: adminsResp } = useUsers({ role: "admin", limit: 100 });
  const admins = adminsResp?.users ?? [];

  const assign = useAssignTicket();
  const update = useUpdateTicket();
  const close = useCloseTicket();
  const reply = useReplyTicket();
  // Reuse banners' upload endpoint as a generic image upload (best-effort).
  const upload = useUploadBannerImage();

  const [draft, setDraft] = useState("");
  const [attachments, setAttachments] = useState<
    Array<{ url: string; filename?: string; size?: number }>
  >([]);

  if (!id) {
    return <div className="p-8 text-sm text-muted-foreground">Invalid ticket</div>;
  }

  if (isLoading) {
    return <div className="p-8 text-sm text-muted-foreground">Loading...</div>;
  }

  if (error || !ticket) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
        {(error as Error)?.message || "Ticket not found"}
      </div>
    );
  }

  async function onChangeStatus(next: string) {
    if (!ticket) return;
    try {
      await update.mutateAsync({ id: ticket.id, body: { status: next } });
      toast.success("Status updated");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onChangePriority(next: string) {
    if (!ticket) return;
    try {
      await update.mutateAsync({ id: ticket.id, body: { priority: next } });
      toast.success("Priority updated");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onAssign(assigneeId: string) {
    if (!ticket) return;
    try {
      await assign.mutateAsync({
        id: ticket.id,
        assigneeId: assigneeId || null,
      });
      toast.success("Assignee updated");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onAssignToMe() {
    if (!me?.id || !ticket) {
      toast.error("Not signed in");
      return;
    }
    await onAssign(me.id);
  }

  async function onClose() {
    if (!ticket) return;
    if (!confirm("Close this ticket?")) return;
    try {
      await close.mutateAsync(ticket.id);
      toast.success("Ticket closed");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onUpload(file: File) {
    try {
      const r = await upload.mutateAsync(file);
      setAttachments((a) => [
        ...a,
        { url: r.url, filename: r.filename, size: r.size },
      ]);
      toast.success("Attachment uploaded");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onSendReply(e: React.FormEvent) {
    e.preventDefault();
    if (!ticket) return;
    if (!draft.trim()) return;
    try {
      await reply.mutateAsync({
        id: ticket.id,
        body: draft.trim(),
        attachments: attachments.length ? attachments : undefined,
      });
      setDraft("");
      setAttachments([]);
      toast.success("Reply sent");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  const messages = ticket.messages ?? [];

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Link href="/support" className="hover:underline">
          Support
        </Link>
        <span>/</span>
        <span className="text-foreground">{ticket.subject}</span>
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
        <div className="space-y-4">
          <Card>
            <CardContent className="space-y-1 pt-6">
              <div className="flex items-start justify-between gap-3">
                <h1 className="text-xl font-semibold">{ticket.subject}</h1>
                <div className="flex shrink-0 items-center gap-2">
                  <PriorityBadge priority={ticket.priority} />
                  <StatusBadge status={ticket.status} />
                </div>
              </div>
              <div className="text-xs text-muted-foreground">
                Author: {ticket.author?.name || "—"}{" "}
                {ticket.author?.phone ? `(${ticket.author.phone})` : ""} ·
                Created {dateRu(ticket.createdAt)}
              </div>
              {ticket.category && (
                <div className="pt-1">
                  <Badge variant="outline">{ticket.category}</Badge>
                </div>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardContent className="space-y-3 pt-6">
              {messages.length === 0 ? (
                <div className="p-6 text-center text-sm text-muted-foreground">
                  No messages yet
                </div>
              ) : (
                messages.map((m) => {
                  const isAdmin =
                    m.senderRole === "admin" ||
                    m.senderRole === "support" ||
                    (me?.id && m.senderId === me.id);
                  return (
                    <div
                      key={m.id}
                      className={
                        "flex flex-col gap-1 " +
                        (isAdmin ? "items-end" : "items-start")
                      }
                    >
                      <div
                        className={
                          "max-w-[80%] rounded-lg border px-3 py-2 text-sm " +
                          (isAdmin
                            ? "bg-primary/10 border-primary/30"
                            : "bg-muted")
                        }
                      >
                        <div className="mb-1 flex items-center gap-2 text-xs text-muted-foreground">
                          <Badge variant={isAdmin ? "default" : "secondary"}>
                            {m.senderRole || (isAdmin ? "admin" : "user")}
                          </Badge>
                          <span>
                            {m.sender?.name || m.sender?.phone || "—"}
                          </span>
                          <span>·</span>
                          <RelativeTime value={m.createdAt} />
                        </div>
                        <div className="whitespace-pre-wrap">{m.body}</div>
                        {m.attachments && m.attachments.length > 0 && (
                          <div className="mt-2 flex flex-wrap gap-2">
                            {m.attachments.map((a, i) => (
                              <a
                                key={i}
                                href={attachmentUrl(a.url)}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="text-xs underline"
                              >
                                {a.filename || `attachment ${i + 1}`}
                              </a>
                            ))}
                          </div>
                        )}
                      </div>
                    </div>
                  );
                })
              )}
            </CardContent>
          </Card>

          {ticket.status !== "closed" && (
            <Card>
              <CardContent className="space-y-3 pt-6">
                <form onSubmit={onSendReply} className="space-y-3">
                  <div className="grid gap-2">
                    <Label htmlFor="reply">Reply</Label>
                    <Textarea
                      id="reply"
                      value={draft}
                      onChange={(e) => setDraft(e.target.value)}
                      rows={4}
                      placeholder="Write a reply..."
                      required
                    />
                  </div>
                  <div className="grid gap-2">
                    <Label htmlFor="attach">Attachments</Label>
                    <Input
                      id="attach"
                      type="file"
                      accept="image/jpeg,image/png,image/webp"
                      onChange={(e) => {
                        const f = e.target.files?.[0];
                        if (f) onUpload(f);
                        e.currentTarget.value = "";
                      }}
                    />
                    {attachments.length > 0 && (
                      <div className="flex flex-wrap gap-2 text-xs">
                        {attachments.map((a, i) => (
                          <span
                            key={i}
                            className="flex items-center gap-1 rounded border px-2 py-1"
                          >
                            {a.filename || `file ${i + 1}`}
                            <button
                              type="button"
                              className="text-muted-foreground hover:text-destructive"
                              onClick={() =>
                                setAttachments((arr) =>
                                  arr.filter((_, idx) => idx !== i)
                                )
                              }
                            >
                              ×
                            </button>
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                  <div className="flex justify-end">
                    <Button
                      type="submit"
                      disabled={
                        reply.isPending || upload.isPending || !draft.trim()
                      }
                    >
                      Send reply
                    </Button>
                  </div>
                </form>
              </CardContent>
            </Card>
          )}
        </div>

        <div className="space-y-3">
          <Card>
            <CardContent className="space-y-3 pt-6">
              <div className="grid gap-2">
                <Label htmlFor="status">Status</Label>
                <Select
                  id="status"
                  value={ticket.status}
                  disabled={update.isPending}
                  onChange={(e) => onChangeStatus(e.target.value)}
                >
                  {STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </Select>
              </div>
              <div className="grid gap-2">
                <Label htmlFor="priority">Priority</Label>
                <Select
                  id="priority"
                  value={ticket.priority}
                  disabled={update.isPending}
                  onChange={(e) => onChangePriority(e.target.value)}
                >
                  {PRIORITIES.map((p) => (
                    <option key={p} value={p}>
                      {p}
                    </option>
                  ))}
                </Select>
              </div>
              <div className="grid gap-2">
                <Label htmlFor="assignee">Assignee</Label>
                <Select
                  id="assignee"
                  value={ticket.assigneeId ?? ""}
                  disabled={assign.isPending}
                  onChange={(e) => onAssign(e.target.value)}
                >
                  <option value="">Unassigned</option>
                  {admins.map((u) => (
                    <option key={u.id} value={u.id}>
                      {u.name || u.phone || u.id}
                    </option>
                  ))}
                </Select>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  disabled={assign.isPending || !me?.id}
                  onClick={onAssignToMe}
                >
                  Assign to me
                </Button>
              </div>
              <div className="border-t pt-3">
                <Button
                  type="button"
                  variant="destructive"
                  className="w-full"
                  disabled={close.isPending || ticket.status === "closed"}
                  onClick={onClose}
                >
                  Close ticket
                </Button>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="space-y-1 pt-6 text-xs">
              <div className="font-medium">Author</div>
              <div>{ticket.author?.name || "—"}</div>
              <div className="text-muted-foreground">
                {ticket.author?.phone || "—"}
              </div>
              {ticket.author?.id && (
                <Link
                  href={`/users/${ticket.author.id}`}
                  className="text-primary underline"
                >
                  View profile
                </Link>
              )}
            </CardContent>
          </Card>

          <Button variant="outline" onClick={() => router.back()}>
            Back
          </Button>
        </div>
      </div>
    </div>
  );
}
