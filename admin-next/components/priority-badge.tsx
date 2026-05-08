import { Badge } from "@/components/ui/badge";

const MAP: Record<
  string,
  "default" | "secondary" | "destructive" | "outline" | "success" | "warning" | "info" | "muted"
> = {
  low: "muted",
  normal: "info",
  high: "warning",
  urgent: "destructive",
};

export function PriorityBadge({ priority }: { priority?: string | null }) {
  if (!priority) return <Badge variant="muted">—</Badge>;
  const variant = MAP[priority.toLowerCase()] ?? "secondary";
  return <Badge variant={variant}>{priority}</Badge>;
}
