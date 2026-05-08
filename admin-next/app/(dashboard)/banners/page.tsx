"use client";

import { useState } from "react";
import { toast } from "sonner";
import {
  useBanners,
  useCreateBanner,
  useUpdateBanner,
  useDeleteBanner,
  useBannerStats,
  useUploadBannerImage,
  type Banner,
} from "@/lib/queries";
import { API_URL } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { dateRuShort } from "@/lib/formatters";
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

const COUNTRY_FLAGS: Record<string, string> = {
  UZ: "🇺🇿",
  KZ: "🇰🇿",
  KG: "🇰🇬",
};

const EMPTY: Partial<Banner> = {
  titleUz: "",
  titleRu: "",
  titleEn: "",
  subtitleUz: "",
  subtitleRu: "",
  imageUrl: "",
  deepLink: "",
  vertical: "all",
  country: null,
  priority: 0,
  isActive: true,
};

function imgSrc(url: string | undefined | null) {
  if (!url) return "";
  if (url.startsWith("http")) return url;
  return `${API_URL}${url}`;
}

export default function BannersPage() {
  const { data, isLoading } = useBanners();
  const create = useCreateBanner();
  const update = useUpdateBanner();
  const remove = useDeleteBanner();
  const upload = useUploadBannerImage();

  const list = data?.banners ?? [];

  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<Banner | null>(null);
  const [form, setForm] = useState<Partial<Banner>>(EMPTY);
  const [statsOpen, setStatsOpen] = useState(false);
  const [statsBanner, setStatsBanner] = useState<Banner | null>(null);

  function openCreate() {
    setEditing(null);
    setForm(EMPTY);
    setOpen(true);
  }
  function openEdit(b: Banner) {
    setEditing(b);
    setForm({
      titleUz: b.titleUz,
      titleRu: b.titleRu,
      titleEn: b.titleEn ?? "",
      subtitleUz: b.subtitleUz ?? "",
      subtitleRu: b.subtitleRu ?? "",
      imageUrl: b.imageUrl,
      deepLink: b.deepLink ?? "",
      vertical: b.vertical,
      country: b.country ?? null,
      priority: b.priority,
      isActive: b.isActive,
      validFrom: b.validFrom ?? null,
      validUntil: b.validUntil ?? null,
    });
    setOpen(true);
  }

  async function onUpload(file: File) {
    try {
      const r = await upload.mutateAsync(file);
      setForm((f) => ({ ...f, imageUrl: r.url }));
      toast.success("Image uploaded");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    try {
      const payload: Partial<Banner> = {
        ...form,
        priority: Number(form.priority ?? 0),
        country: form.country || null,
      };
      if (editing) {
        await update.mutateAsync({ id: editing.id, body: payload });
        toast.success("Banner updated");
      } else {
        await create.mutateAsync(payload);
        toast.success("Banner created");
      }
      setOpen(false);
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onDelete(b: Banner) {
    if (!confirm(`Delete banner "${b.titleRu}"?`)) return;
    try {
      await remove.mutateAsync(b.id);
      toast.success("Deleted");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onToggleActive(b: Banner) {
    try {
      await update.mutateAsync({ id: b.id, body: { isActive: !b.isActive } });
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  function openStats(b: Banner) {
    setStatsBanner(b);
    setStatsOpen(true);
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Banners</h1>
        <Button onClick={openCreate}>Create banner</Button>
      </div>

      <Card>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="p-8 text-center text-sm text-muted-foreground">Loading...</div>
          ) : list.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">No banners</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Image</TableHead>
                  <TableHead>Title</TableHead>
                  <TableHead>Vertical</TableHead>
                  <TableHead>Country</TableHead>
                  <TableHead>Priority</TableHead>
                  <TableHead>Active</TableHead>
                  <TableHead>Validity</TableHead>
                  <TableHead>Views / Clicks</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {list.map((b) => (
                  <TableRow key={b.id}>
                    <TableCell>
                      {b.imageUrl && (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={imgSrc(b.imageUrl)}
                          alt={b.titleRu}
                          className="h-10 w-16 rounded object-cover"
                        />
                      )}
                    </TableCell>
                    <TableCell className="font-medium">{b.titleRu}</TableCell>
                    <TableCell>
                      <Badge variant="outline">{b.vertical}</Badge>
                    </TableCell>
                    <TableCell>
                      {b.country ? `${COUNTRY_FLAGS[b.country] || ""} ${b.country}` : "—"}
                    </TableCell>
                    <TableCell>{b.priority}</TableCell>
                    <TableCell>
                      <button
                        type="button"
                        onClick={() => onToggleActive(b)}
                        className="cursor-pointer"
                      >
                        <Badge variant={b.isActive ? "default" : "secondary"}>
                          {b.isActive ? "On" : "Off"}
                        </Badge>
                      </button>
                    </TableCell>
                    <TableCell className="text-xs">
                      {b.validFrom ? dateRuShort(b.validFrom) : "—"} →{" "}
                      {b.validUntil ? dateRuShort(b.validUntil) : "—"}
                    </TableCell>
                    <TableCell>
                      {b.viewsCount ?? 0} / {b.clicksCount ?? 0}
                    </TableCell>
                    <TableCell className="text-right">
                      <Button size="sm" variant="ghost" onClick={() => openStats(b)}>
                        Stats
                      </Button>
                      <Button size="sm" variant="ghost" onClick={() => openEdit(b)}>
                        Edit
                      </Button>
                      <Button size="sm" variant="ghost" onClick={() => onDelete(b)}>
                        Delete
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>{editing ? "Edit banner" : "Create banner"}</DialogTitle>
          </DialogHeader>
          <form onSubmit={submit} className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div className="grid gap-2">
                <Label htmlFor="titleRu">Title (RU)</Label>
                <Input
                  id="titleRu"
                  value={form.titleRu ?? ""}
                  onChange={(e) => setForm((f) => ({ ...f, titleRu: e.target.value }))}
                  required
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="titleUz">Title (UZ)</Label>
                <Input
                  id="titleUz"
                  value={form.titleUz ?? ""}
                  onChange={(e) => setForm((f) => ({ ...f, titleUz: e.target.value }))}
                  required
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="grid gap-2">
                <Label htmlFor="subtitleRu">Subtitle (RU)</Label>
                <Textarea
                  id="subtitleRu"
                  value={form.subtitleRu ?? ""}
                  onChange={(e) => setForm((f) => ({ ...f, subtitleRu: e.target.value }))}
                  rows={2}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="subtitleUz">Subtitle (UZ)</Label>
                <Textarea
                  id="subtitleUz"
                  value={form.subtitleUz ?? ""}
                  onChange={(e) => setForm((f) => ({ ...f, subtitleUz: e.target.value }))}
                  rows={2}
                />
              </div>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="image">Image</Label>
              <div className="flex items-center gap-3">
                {form.imageUrl && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={imgSrc(form.imageUrl)}
                    alt="banner"
                    className="h-12 w-20 rounded object-cover"
                  />
                )}
                <Input
                  id="image"
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  onChange={(e) => {
                    const file = e.target.files?.[0];
                    if (file) onUpload(file);
                  }}
                />
              </div>
              <Input
                placeholder="…or paste image URL"
                value={form.imageUrl ?? ""}
                onChange={(e) => setForm((f) => ({ ...f, imageUrl: e.target.value }))}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="deepLink">Deep link (optional)</Label>
              <Input
                id="deepLink"
                value={form.deepLink ?? ""}
                onChange={(e) => setForm((f) => ({ ...f, deepLink: e.target.value }))}
                placeholder="/buyer/shops?vertical=restaurant"
              />
            </div>
            <div className="grid grid-cols-3 gap-3">
              <div className="grid gap-2">
                <Label htmlFor="vertical">Vertical</Label>
                <Select
                  id="vertical"
                  value={form.vertical ?? "all"}
                  onChange={(e) => setForm((f) => ({ ...f, vertical: e.target.value }))}
                >
                  <option value="all">all</option>
                  <option value="grocery">grocery</option>
                  <option value="restaurant">restaurant</option>
                  <option value="pharmacy">pharmacy</option>
                  <option value="electronics">electronics</option>
                </Select>
              </div>
              <div className="grid gap-2">
                <Label htmlFor="country">Country</Label>
                <Select
                  id="country"
                  value={form.country ?? ""}
                  onChange={(e) =>
                    setForm((f) => ({ ...f, country: e.target.value || null }))
                  }
                >
                  <option value="">All</option>
                  <option value="UZ">UZ</option>
                  <option value="KZ">KZ</option>
                  <option value="KG">KG</option>
                </Select>
              </div>
              <div className="grid gap-2">
                <Label htmlFor="priority">Priority</Label>
                <Input
                  id="priority"
                  type="number"
                  value={form.priority ?? 0}
                  onChange={(e) => setForm((f) => ({ ...f, priority: Number(e.target.value) }))}
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="grid gap-2">
                <Label htmlFor="vf">Valid from</Label>
                <Input
                  id="vf"
                  type="date"
                  value={form.validFrom ? String(form.validFrom).slice(0, 10) : ""}
                  onChange={(e) =>
                    setForm((f) => ({ ...f, validFrom: e.target.value || null }))
                  }
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="vu">Valid until</Label>
                <Input
                  id="vu"
                  type="date"
                  value={form.validUntil ? String(form.validUntil).slice(0, 10) : ""}
                  onChange={(e) =>
                    setForm((f) => ({ ...f, validUntil: e.target.value || null }))
                  }
                />
              </div>
            </div>
            <div className="flex items-center gap-2">
              <input
                id="isActive"
                type="checkbox"
                checked={!!form.isActive}
                onChange={(e) => setForm((f) => ({ ...f, isActive: e.target.checked }))}
              />
              <Label htmlFor="isActive">Active</Label>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={create.isPending || update.isPending || upload.isPending}
              >
                {editing ? "Save" : "Create"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      <BannerStatsDialog
        open={statsOpen}
        onOpenChange={setStatsOpen}
        banner={statsBanner}
      />
    </div>
  );
}

function BannerStatsDialog({
  open,
  onOpenChange,
  banner,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  banner: Banner | null;
}) {
  const { data, isLoading } = useBannerStats(open && banner ? banner.id : undefined);

  const max = data?.last30dayDailyViews?.reduce((m, d) => Math.max(m, d.count), 0) ?? 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <DialogTitle>{banner ? `Stats — ${banner.titleRu}` : "Stats"}</DialogTitle>
        </DialogHeader>
        {isLoading ? (
          <div className="p-6 text-sm text-muted-foreground">Loading...</div>
        ) : data ? (
          <div className="space-y-4">
            <div className="grid grid-cols-3 gap-3">
              <div className="rounded-md border p-3">
                <div className="text-xs text-muted-foreground">Views</div>
                <div className="text-2xl font-semibold">{data.views}</div>
              </div>
              <div className="rounded-md border p-3">
                <div className="text-xs text-muted-foreground">Clicks</div>
                <div className="text-2xl font-semibold">{data.clicks}</div>
              </div>
              <div className="rounded-md border p-3">
                <div className="text-xs text-muted-foreground">CTR</div>
                <div className="text-2xl font-semibold">
                  {(data.ctr * 100).toFixed(1)}%
                </div>
              </div>
            </div>
            <div>
              <div className="mb-2 text-xs text-muted-foreground">
                Last 30 days — daily views
              </div>
              <div className="flex h-32 items-end gap-1">
                {data.last30dayDailyViews.map((d) => (
                  <div
                    key={d.day}
                    className="flex-1 rounded-t bg-primary/70"
                    style={{
                      height: max > 0 ? `${(d.count / max) * 100}%` : "0%",
                    }}
                    title={`${d.day}: ${d.count}`}
                  />
                ))}
                {data.last30dayDailyViews.length === 0 && (
                  <div className="text-xs text-muted-foreground">No data yet</div>
                )}
              </div>
            </div>
          </div>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}
