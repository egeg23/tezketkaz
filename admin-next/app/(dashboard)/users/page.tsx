import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export default function UsersPage() {
  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Users</h1>
      <Card>
        <CardHeader>
          <CardTitle>Coming in next iteration</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm text-muted-foreground">
          <p>User management UI is not yet implemented.</p>
          <p>
            For now, list users via the API:{" "}
            <code className="rounded bg-muted px-1.5 py-0.5">GET /api/admin/users</code>
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
