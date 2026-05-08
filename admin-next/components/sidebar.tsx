"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  BarChart3,
  Package,
  Store,
  Truck,
  Users,
  Tag,
  Settings,
  Wallet,
  AlertCircle,
  LogOut,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useAuth } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { useStats } from "@/lib/queries";

const NAV: { href: string; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { href: "/dashboard", label: "Dashboard", icon: BarChart3 },
  { href: "/orders", label: "Orders", icon: Package },
  { href: "/shops", label: "Shops", icon: Store },
  { href: "/couriers", label: "Couriers", icon: Truck },
  { href: "/users", label: "Users", icon: Users },
  { href: "/coupons", label: "Coupons", icon: Tag },
  { href: "/pricing-rules", label: "Pricing", icon: Settings },
  { href: "/finance", label: "Finance", icon: Wallet },
  { href: "/disputes", label: "Disputes", icon: AlertCircle },
];

export function Sidebar() {
  const pathname = usePathname();
  const router = useRouter();
  const { user, clear } = useAuth();
  const { data: stats } = useStats();
  const openDisputes = stats?.openDisputes ?? 0;

  return (
    <aside className="flex h-screen w-60 flex-col border-r bg-card">
      <div className="border-b p-4">
        <div className="text-lg font-semibold">TezKetKaz</div>
        <div className="text-xs text-muted-foreground">Admin panel</div>
      </div>
      <nav className="flex-1 space-y-1 p-2">
        {NAV.map((item) => {
          const active = pathname === item.href || pathname?.startsWith(item.href + "/");
          const Icon = item.icon;
          const isDisputes = item.href === "/disputes";
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center justify-between gap-2 rounded-md px-3 py-2 text-sm transition-colors hover:bg-accent",
                active && "bg-accent font-medium"
              )}
            >
              <span className="flex items-center gap-2">
                <Icon className="h-4 w-4" />
                {item.label}
              </span>
              {isDisputes && openDisputes > 0 && (
                <Badge variant="destructive">{openDisputes}</Badge>
              )}
            </Link>
          );
        })}
      </nav>
      <div className="border-t p-3">
        <div className="mb-2 text-xs">
          <div className="font-medium">{user?.name || "Admin"}</div>
          <div className="text-muted-foreground">{user?.phone}</div>
        </div>
        <button
          type="button"
          onClick={() => {
            clear();
            router.push("/login");
          }}
          className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm hover:bg-accent"
        >
          <LogOut className="h-4 w-4" />
          Logout
        </button>
      </div>
    </aside>
  );
}
