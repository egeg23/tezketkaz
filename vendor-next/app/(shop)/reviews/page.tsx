"use client";

import { useState } from "react";
import { useShopReviews } from "@/lib/queries";
import { useCurrentShop } from "@/lib/shop-context";
import { dateRu } from "@/lib/formatters";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";

export default function ReviewsPage() {
  const { shopId } = useCurrentShop();
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [history, setHistory] = useState<(string | undefined)[]>([undefined]);
  const { data, isLoading, error } = useShopReviews(shopId, cursor, 20);

  const reviews = data?.reviews ?? [];

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Reviews</h1>

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          {(error as Error).message}
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Customer feedback</CardTitle>
          <CardDescription>
            Most recent first. Replying to reviews is not yet available — the
            backend doesn't expose a shop-side reply endpoint.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {isLoading ? (
            <div className="text-sm text-muted-foreground">Loading...</div>
          ) : reviews.length === 0 ? (
            <div className="text-sm text-muted-foreground">No reviews yet.</div>
          ) : (
            reviews.map((r) => (
              <div key={r.id} className="border-b pb-3 last:border-0">
                <div className="flex items-center justify-between">
                  <div className="font-medium">{r.reviewerName || "—"}</div>
                  <div className="text-sm text-yellow-700">
                    {"★".repeat(Math.max(0, Math.min(5, r.rating)))}
                    <span className="ml-1 text-muted-foreground">
                      {r.rating.toFixed(1)}
                    </span>
                  </div>
                </div>
                {r.text && <div className="mt-1 text-sm">{r.text}</div>}
                <div className="mt-1 text-xs text-muted-foreground">
                  {dateRu(r.createdAt)}
                </div>
              </div>
            ))
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
