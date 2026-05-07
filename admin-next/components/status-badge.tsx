import { Badge } from "@/components/ui/badge";

const MAP: Record<string, "default" | "secondary" | "destructive" | "outline" | "success" | "warning" | "info" | "muted"> = {
  PENDING: "warning",
  PLACED: "info",
  CONFIRMED: "info",
  PREPARING: "info",
  READY: "info",
  PICKED_UP: "info",
  EN_ROUTE: "info",
  DELIVERED: "success",
  COMPLETED: "success",
  CANCELLED: "muted",
  CANCELED: "muted",
  REFUNDED: "destructive",
  FAILED: "destructive",
  PAID: "success",
  OPEN: "warning",
  RESOLVED: "success",
  REJECTED: "muted",
  ACTIVE: "success",
  INACTIVE: "muted",
};

export function StatusBadge({ status }: { status?: string | null }) {
  if (!status) return <Badge variant="muted">—</Badge>;
  const variant = MAP[status.toUpperCase()] ?? "secondary";
  return <Badge variant={variant}>{status}</Badge>;
}
