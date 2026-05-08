"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { toast } from "sonner";
import {
  useCampaign,
  useUpdateCampaign,
  useSendCampaign,
  useCancelCampaign,
  useDeleteCampaign,
  useCampaignStats,
  usePreviewAudience,
  type PushCampaign,
} from "@/lib/queries";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { AudienceQueryEditor } from "@/components/audience-query-editor";
import { dateRu } from "@/lib/formatters";

type Locale = "ru" | "uz" | "en" | "kk";
const LOCALES: Locale[] = ["ru", "uz", "en", "kk"];

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

interface FormState {
  titleRu: string;
  titleUz: string;
  titleEn: string;
  titleKk: string;
  bodyRu: string;
  bodyUz: string;
  bodyEn: string;
  bodyKk: string;
  deepLink: string;
  audienceQuery: Record<string, unknown> | null;
  scheduledFor: string; // datetime-local
}

function emptyForm(): FormState {
  return {
    titleRu: "",
    titleUz: "",
    titleEn: "",
    titleKk: "",
    bodyRu: "",
    bodyUz: "",
    bodyEn: "",
    bodyKk: "",
    deepLink: "",
    audienceQuery: null,
    scheduledFor: "",
  };
}

function fromCampaign(c: PushCampaign): FormState {
  return {
    titleRu: c.titleRu ?? "",
    titleUz: c.titleUz ?? "",
    titleEn: c.titleEn ?? "",
    titleKk: c.titleKk ?? "",
    bodyRu: c.bodyRu ?? "",
    bodyUz: c.bodyUz ?? "",
    bodyEn: c.bodyEn ?? "",
    bodyKk: c.bodyKk ?? "",
    deepLink: c.deepLink ?? "",
    audienceQuery: c.audienceQuery ?? null,
    scheduledFor: c.scheduledFor
      ? new Date(c.scheduledFor).toISOString().slice(0, 16)
      : "",
  };
}

export default function PushCampaignDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const id = params?.id;

  const { data: campaign, isLoading, error } = useCampaign(id);
  const update = useUpdateCampaign();
  const send = useSendCampaign();
  const cancel = useCancelCampaign();
  const remove = useDeleteCampaign();
  const preview = usePreviewAudience();

  const [locale, setLocale] = useState<Locale>("ru");
  const [form, setForm] = useState<FormState>(emptyForm());
  const [previewCount, setPreviewCount] = useState<number | null>(null);

  useEffect(() => {
    if (campaign) setForm(fromCampaign(campaign));
  }, [campaign]);

  const isReadOnly = useMemo(() => {
    if (!campaign) return true;
    return campaign.status !== "draft" && campaign.status !== "scheduled";
  }, [campaign]);

  const isSent = campaign?.status === "sent" || campaign?.status === "failed";

  if (!id) return <div className="p-8 text-sm">Invalid campaign</div>;

  if (isLoading) {
    return <div className="p-8 text-sm text-muted-foreground">Loading...</div>;
  }

  if (error || !campaign) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
        {(error as Error)?.message || "Campaign not found"}
      </div>
    );
  }

  function buildBody(): Partial<PushCampaign> {
    return {
      titleRu: form.titleRu || null,
      titleUz: form.titleUz || null,
      titleEn: form.titleEn || null,
      titleKk: form.titleKk || null,
      bodyRu: form.bodyRu || null,
      bodyUz: form.bodyUz || null,
      bodyEn: form.bodyEn || null,
      bodyKk: form.bodyKk || null,
      deepLink: form.deepLink || null,
      audienceQuery: form.audienceQuery,
    };
  }

  async function onSave() {
    if (!campaign) return;
    try {
      await update.mutateAsync({ id: campaign.id, body: buildBody() });
      toast.success("Saved");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onPreview() {
    if (!form.audienceQuery) {
      toast.error("Audience query is empty or invalid");
      return;
    }
    try {
      const r = await preview.mutateAsync(form.audienceQuery);
      setPreviewCount(r.recipientCount);
      toast.success(`Audience: ${r.recipientCount.toLocaleString("ru-RU")}`);
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onSendNow() {
    if (!campaign) return;
    if (!confirm("Send this campaign now?")) return;
    try {
      // Save first to ensure latest content is on the server.
      await update.mutateAsync({ id: campaign.id, body: buildBody() });
      await send.mutateAsync(campaign.id);
      toast.success("Send started");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onSchedule() {
    if (!campaign) return;
    if (!form.scheduledFor) {
      toast.error("Pick a date/time first");
      return;
    }
    try {
      const iso = new Date(form.scheduledFor).toISOString();
      await update.mutateAsync({
        id: campaign.id,
        body: { ...buildBody(), scheduledFor: iso, status: "scheduled" },
      });
      toast.success("Scheduled");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onCancel() {
    if (!campaign) return;
    if (!confirm("Cancel this campaign?")) return;
    try {
      await cancel.mutateAsync(campaign.id);
      toast.success("Cancelled");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onDelete() {
    if (!campaign) return;
    if (!confirm("Delete this campaign?")) return;
    try {
      await remove.mutateAsync(campaign.id);
      toast.success("Deleted");
      router.push("/push-campaigns");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  type StringField = "titleRu" | "titleUz" | "titleEn" | "titleKk" | "bodyRu" | "bodyUz" | "bodyEn" | "bodyKk";
  const cap = (locale.charAt(0).toUpperCase() + locale.slice(1)) as "Ru" | "Uz" | "En" | "Kk";
  const titleField = (`title${cap}`) as StringField;
  const bodyField = (`body${cap}`) as StringField;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Link href="/push-campaigns" className="hover:underline">
          Push campaigns
        </Link>
        <span>/</span>
        <span className="text-foreground">{form.titleRu || campaign.id}</span>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl font-semibold">
          {form.titleRu || "Untitled campaign"}
        </h1>
        <Badge variant={STATUS_VARIANT[campaign.status] ?? "secondary"}>
          {campaign.status}
        </Badge>
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
        <div className="space-y-4">
          <Card>
            <CardContent className="space-y-3 pt-6">
              <div className="flex flex-wrap gap-1">
                {LOCALES.map((l) => (
                  <button
                    key={l}
                    type="button"
                    onClick={() => setLocale(l)}
                    className={
                      "rounded-md border px-3 py-1 text-xs uppercase " +
                      (locale === l
                        ? "border-primary bg-primary/10"
                        : "border-input")
                    }
                  >
                    {l}
                  </button>
                ))}
              </div>

              <div className="grid gap-2">
                <Label htmlFor="title">Title ({locale.toUpperCase()})</Label>
                <Input
                  id="title"
                  disabled={isReadOnly}
                  value={form[titleField] ?? ""}
                  onChange={(e) => {
                    const v = e.target.value;
                    setForm((f) => ({ ...f, [titleField]: v }) as FormState);
                  }}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="body">Body ({locale.toUpperCase()})</Label>
                <Textarea
                  id="body"
                  rows={4}
                  disabled={isReadOnly}
                  value={form[bodyField] ?? ""}
                  onChange={(e) => {
                    const v = e.target.value;
                    setForm((f) => ({ ...f, [bodyField]: v }) as FormState);
                  }}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="deepLink">Deep link</Label>
                <Input
                  id="deepLink"
                  disabled={isReadOnly}
                  value={form.deepLink}
                  onChange={(e) =>
                    setForm((f) => ({ ...f, deepLink: e.target.value }))
                  }
                  placeholder="/buyer/shops?vertical=restaurant"
                />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="space-y-3 pt-6">
              <AudienceQueryEditor
                value={form.audienceQuery}
                disabled={isReadOnly}
                onChange={(v) =>
                  setForm((f) => ({ ...f, audienceQuery: v }))
                }
              />
              <div className="flex items-center gap-3">
                <Button
                  type="button"
                  variant="outline"
                  disabled={preview.isPending || isReadOnly || !form.audienceQuery}
                  onClick={onPreview}
                >
                  Preview audience
                </Button>
                {previewCount !== null && (
                  <div className="rounded-md border bg-muted px-3 py-1 text-sm">
                    Recipients:{" "}
                    <span className="font-semibold">
                      {previewCount.toLocaleString("ru-RU")}
                    </span>
                  </div>
                )}
              </div>
            </CardContent>
          </Card>

          {isSent && <CampaignStatsCard id={campaign.id} />}
        </div>

        <div className="space-y-3">
          <Card>
            <CardContent className="space-y-3 pt-6 text-sm">
              <div>
                <div className="text-xs text-muted-foreground">Created</div>
                <div>{dateRu(campaign.createdAt)}</div>
              </div>
              {campaign.scheduledFor && (
                <div>
                  <div className="text-xs text-muted-foreground">Scheduled for</div>
                  <div>{dateRu(campaign.scheduledFor)}</div>
                </div>
              )}
              {campaign.sentAt && (
                <div>
                  <div className="text-xs text-muted-foreground">Sent at</div>
                  <div>{dateRu(campaign.sentAt)}</div>
                </div>
              )}
              <div className="grid grid-cols-2 gap-2 border-t pt-3 text-xs">
                <div>
                  <div className="text-muted-foreground">Recipients</div>
                  <div className="text-base font-semibold">
                    {campaign.recipientCount ?? 0}
                  </div>
                </div>
                <div>
                  <div className="text-muted-foreground">Success</div>
                  <div className="text-base font-semibold">
                    {campaign.successCount ?? 0}
                  </div>
                </div>
                <div>
                  <div className="text-muted-foreground">Failed</div>
                  <div className="text-base font-semibold">
                    {campaign.failureCount ?? 0}
                  </div>
                </div>
                <div>
                  <div className="text-muted-foreground">Opened</div>
                  <div className="text-base font-semibold">
                    {campaign.openCount ?? 0}
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>

          {!isReadOnly && (
            <Card>
              <CardContent className="space-y-3 pt-6">
                <Button
                  type="button"
                  className="w-full"
                  onClick={onSave}
                  disabled={update.isPending}
                >
                  Save draft
                </Button>
                <Button
                  type="button"
                  className="w-full"
                  variant="default"
                  onClick={onSendNow}
                  disabled={send.isPending || update.isPending}
                >
                  Send now
                </Button>
                <div className="grid gap-2">
                  <Label htmlFor="schedule">Schedule for</Label>
                  <Input
                    id="schedule"
                    type="datetime-local"
                    value={form.scheduledFor}
                    onChange={(e) =>
                      setForm((f) => ({ ...f, scheduledFor: e.target.value }))
                    }
                  />
                  <Button
                    type="button"
                    variant="outline"
                    onClick={onSchedule}
                    disabled={update.isPending || !form.scheduledFor}
                  >
                    Schedule
                  </Button>
                </div>
                {campaign.status === "scheduled" && (
                  <Button
                    type="button"
                    variant="destructive"
                    className="w-full"
                    onClick={onCancel}
                    disabled={cancel.isPending}
                  >
                    Cancel campaign
                  </Button>
                )}
                {campaign.status === "draft" && (
                  <Button
                    type="button"
                    variant="ghost"
                    className="w-full"
                    onClick={onDelete}
                    disabled={remove.isPending}
                  >
                    Delete draft
                  </Button>
                )}
              </CardContent>
            </Card>
          )}

          {campaign.status === "sending" && (
            <Card>
              <CardContent className="space-y-2 pt-6">
                <Button
                  type="button"
                  variant="destructive"
                  className="w-full"
                  onClick={onCancel}
                  disabled={cancel.isPending}
                >
                  Cancel send
                </Button>
              </CardContent>
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}

function CampaignStatsCard({ id }: { id: string }) {
  const { data, isLoading } = useCampaignStats(id);

  if (isLoading) {
    return (
      <Card>
        <CardContent className="p-6 text-sm text-muted-foreground">
          Loading stats...
        </CardContent>
      </Card>
    );
  }
  if (!data) return null;

  const total = data.recipientCount || 1;
  const successPct = (data.successCount / total) * 100;
  const failPct = (data.failureCount / total) * 100;
  const openPct = (data.openCount / total) * 100;

  return (
    <Card>
      <CardContent className="space-y-4 pt-6">
        <div className="text-sm font-medium">Delivery stats</div>
        <div className="grid grid-cols-4 gap-3 text-sm">
          <div className="rounded-md border p-3">
            <div className="text-xs text-muted-foreground">Recipients</div>
            <div className="text-xl font-semibold">{data.recipientCount}</div>
          </div>
          <div className="rounded-md border p-3">
            <div className="text-xs text-muted-foreground">Success</div>
            <div className="text-xl font-semibold text-green-700">
              {data.successCount}
            </div>
          </div>
          <div className="rounded-md border p-3">
            <div className="text-xs text-muted-foreground">Failed</div>
            <div className="text-xl font-semibold text-red-700">
              {data.failureCount}
            </div>
          </div>
          <div className="rounded-md border p-3">
            <div className="text-xs text-muted-foreground">Opened</div>
            <div className="text-xl font-semibold text-blue-700">
              {data.openCount}
            </div>
          </div>
        </div>
        <div className="space-y-2">
          <Bar label="Success" value={successPct} color="bg-green-500" />
          <Bar label="Failed" value={failPct} color="bg-red-500" />
          <Bar label="Opened" value={openPct} color="bg-blue-500" />
        </div>
      </CardContent>
    </Card>
  );
}

function Bar({
  label,
  value,
  color,
}: {
  label: string;
  value: number;
  color: string;
}) {
  return (
    <div className="text-xs">
      <div className="mb-1 flex justify-between">
        <span>{label}</span>
        <span>{value.toFixed(1)}%</span>
      </div>
      <div className="h-2 overflow-hidden rounded bg-muted">
        <div
          className={`h-full ${color}`}
          style={{ width: `${Math.min(100, Math.max(0, value))}%` }}
        />
      </div>
    </div>
  );
}
