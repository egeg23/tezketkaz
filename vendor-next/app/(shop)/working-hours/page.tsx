"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useWorkingHours, useSaveWorkingHours } from "@/lib/queries";
import type { WorkingHoursRow } from "@/lib/queries";
import { useCurrentShop } from "@/lib/shop-context";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

const DAYS: { dow: number; label: string }[] = [
  { dow: 0, label: "Sunday" },
  { dow: 1, label: "Monday" },
  { dow: 2, label: "Tuesday" },
  { dow: 3, label: "Wednesday" },
  { dow: 4, label: "Thursday" },
  { dow: 5, label: "Friday" },
  { dow: 6, label: "Saturday" },
];

interface DayDraft {
  isClosed: boolean;
  startsAt: string;
  endsAt: string;
}

function rowsToDrafts(rows: WorkingHoursRow[]): Record<number, DayDraft> {
  const out: Record<number, DayDraft> = {};
  for (const d of DAYS) {
    out[d.dow] = { isClosed: true, startsAt: "09:00", endsAt: "21:00" };
  }
  // Take the first row per day (the simple grid editor doesn't support split shifts).
  for (const r of rows) {
    if (out[r.dayOfWeek]?.isClosed) {
      out[r.dayOfWeek] = {
        isClosed: r.isClosed,
        startsAt: r.startsAt,
        endsAt: r.endsAt,
      };
    }
  }
  return out;
}

export default function WorkingHoursPage() {
  const { shopId } = useCurrentShop();
  const { data, isLoading, error } = useWorkingHours(shopId);
  const save = useSaveWorkingHours();
  const [drafts, setDrafts] = useState<Record<number, DayDraft>>(() =>
    rowsToDrafts([])
  );

  useEffect(() => {
    if (data?.items) {
      setDrafts(rowsToDrafts(data.items));
    }
  }, [data]);

  function update(dow: number, patch: Partial<DayDraft>) {
    setDrafts((prev) => ({
      ...prev,
      [dow]: { ...(prev[dow] ?? { isClosed: true, startsAt: "09:00", endsAt: "21:00" }), ...patch },
    }));
  }

  async function onSave() {
    if (!shopId) return;
    const items: WorkingHoursRow[] = DAYS.map((d) => {
      const draft = drafts[d.dow] ?? { isClosed: true, startsAt: "09:00", endsAt: "21:00" };
      return {
        dayOfWeek: d.dow,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
        isClosed: draft.isClosed,
      };
    });
    try {
      await save.mutateAsync({ shopId, items });
      toast.success("Schedule saved");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Working hours</h1>

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          {(error as Error).message}
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Weekly schedule</CardTitle>
          <CardDescription>
            Times are in 24h format. Customers cannot place orders outside these
            hours. Split shifts are not supported in this editor — call the API
            directly for advanced setups.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {isLoading ? (
            <div className="text-sm text-muted-foreground">Loading...</div>
          ) : (
            DAYS.map((d) => {
              const draft = drafts[d.dow] ?? {
                isClosed: true,
                startsAt: "09:00",
                endsAt: "21:00",
              };
              return (
                <div
                  key={d.dow}
                  className="grid grid-cols-1 items-center gap-3 border-b pb-3 last:border-0 md:grid-cols-[120px_120px_1fr_1fr]"
                >
                  <div className="font-medium">{d.label}</div>
                  <label className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={!draft.isClosed}
                      onChange={(e) =>
                        update(d.dow, { isClosed: !e.target.checked })
                      }
                      className="h-4 w-4 rounded border-input"
                    />
                    Open
                  </label>
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-muted-foreground">From</span>
                    <Input
                      type="time"
                      value={draft.startsAt}
                      onChange={(e) =>
                        update(d.dow, { startsAt: e.target.value })
                      }
                      disabled={draft.isClosed}
                    />
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-muted-foreground">To</span>
                    <Input
                      type="time"
                      value={draft.endsAt}
                      onChange={(e) =>
                        update(d.dow, { endsAt: e.target.value })
                      }
                      disabled={draft.isClosed}
                    />
                  </div>
                </div>
              );
            })
          )}

          <div className="flex justify-end pt-2">
            <Button onClick={onSave} disabled={save.isPending}>
              {save.isPending ? "Saving..." : "Save schedule"}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
