import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export default function PricingRulesPage() {
  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Pricing rules</h1>
      <Card>
        <CardHeader>
          <CardTitle>Coming in next iteration</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm text-muted-foreground">
          <p>Pricing-rule management UI is not yet implemented.</p>
          <p>
            For now, list rules via the API:{" "}
            <code className="rounded bg-muted px-1.5 py-0.5">GET /api/admin/pricing-rules</code>
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
