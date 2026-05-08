"use client";

import { useState } from "react";
import { toast } from "sonner";
import {
  downloadPayoutsCsv,
  useGeneratePayouts,
  usePayouts,
} from "@/lib/queries";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { PayoutsTable } from "@/components/payouts-table";

export default function FinancePage() {
  const [recipientType, setRecipientType] = useState("");
  const [status, setStatus] = useState("");
  const [periodStart, setPeriodStart] = useState("");
  const [weekStart, setWeekStart] = useState("");
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [history, setHistory] = useState<(string | undefined)[]>([undefined]);
  const [genResult, setGenResult] = useState<unknown>(null);

  const { data, isLoading } = usePayouts({
    recipientType: recipientType || undefined,
    status: status || undefined,
    periodStart: periodStart || undefined,
    cursor,
    limit: 25,
  });
  const generate = useGeneratePayouts();

  async function onGenerate() {
    try {
      const r = await generate.mutateAsync({ weekStart: weekStart || undefined });
      setGenResult(r);
      toast.success("Payouts generated");
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  async function onExport() {
    if (!periodStart) {
      toast.error("Pick a periodStart filter to export");
      return;
    }
    try {
      await downloadPayoutsCsv(periodStart);
    } catch (err) {
      toast.error((err as Error).message);
    }
  }

  const payouts = data?.data ?? [];

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Finance</h1>

      <Card>
        <CardHeader>
          <CardTitle>Generate weekly payouts</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap items-end gap-3">
          <div className="grid gap-1">
            <Label htmlFor="ws">Week start (Mon)</Label>
            <Input
              id="ws"
              type="date"
              value={weekStart}
              onChange={(e) => setWeekStart(e.target.value)}
            />
          </div>
          <Button onClick={onGenerate} disabled={generate.isPending}>
            {generate.isPending ? "Generating..." : "Generate"}
          </Button>
          <Button variant="outline" onClick={onExport}>
            Export CSV
          </Button>
          {genResult ? (
            <pre className="ml-auto max-w-xl overflow-x-auto rounded bg-muted p-2 text-xs">
              {JSON.stringify(genResult, null, 2)}
            </pre>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="flex flex-wrap items-end gap-3 pt-6">
          <div className="grid gap-1">
            <Label>Recipient type</Label>
            <Select value={recipientType} onChange={(e) => setRecipientType(e.target.value)}>
              <option value="">All</option>
              <option value="SHOP">SHOP</option>
              <option value="COURIER">COURIER</option>
            </Select>
          </div>
          <div className="grid gap-1">
            <Label>Status</Label>
            <Select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">All</option>
              <option value="PENDING">PENDING</option>
              <option value="PAID">PAID</option>
              <option value="FAILED">FAILED</option>
            </Select>
          </div>
          <div className="grid gap-1">
            <Label>Period start</Label>
            <Input type="date" value={periodStart} onChange={(e) => setPeriodStart(e.target.value)} />
          </div>
          <Button
            variant="outline"
            onClick={() => {
              setCursor(undefined);
              setHistory([undefined]);
            }}
          >
            Reset
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="p-8 text-center text-sm text-muted-foreground">Loading...</div>
          ) : (
            <PayoutsTable payouts={payouts} />
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
