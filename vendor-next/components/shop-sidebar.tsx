"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  BarChart3,
  Package,
  ShoppingBag,
  Clock,
  Tag,
  Star,
  Settings,
  LogOut,
  Store,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useAuth } from "@/lib/auth";
import { useCurrentShop } from "@/lib/shop-context";

const NAV: { href: string; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { href: "/dashboard", label: "Dashboard", icon: BarChart3 },
  { href: "/orders", label: "Orders", icon: Package },
  { href: "/products", label: "Products", icon: ShoppingBag },
  { href: "/working-hours", label: "Working hours", icon: Clock },
  { href: "/promotions", label: "Promotions", icon: Tag },
  { href: "/reviews", label: "Reviews", icon: Star },
  { href: "/settings", label: "Settings", icon: Settings },
];

export function ShopSidebar() {
  const pathname = usePathname();
  const router = useRouter();
  const { user, clear, currentShopId, setCurrentShopId } = useAuth();
  const { shop } = useCurrentShop();

  const shops = user?.shops ?? [];

  return (
    <aside className="flex h-screen w-60 flex-col border-r bg-card">
      <div className="border-b p-4">
        <div className="text-lg font-semibold">TezKetKaz</div>
        <div className="text-xs text-muted-foreground">Vendor portal</div>
      </div>

      {shops.length > 0 && (
        <div className="border-b p-3">
          <div className="mb-1 flex items-center gap-2 text-xs font-medium text-muted-foreground">
            <Store className="h-3.5 w-3.5" />
            Shop
          </div>
          {shops.length === 1 ? (
            <div className="text-sm font-medium">{shop?.name || shops[0]?.name}</div>
          ) : (
            <select
              value={currentShopId || ""}
              onChange={(e) => setCurrentShopId(e.target.value || null)}
              className="w-full rounded-md border border-input bg-background px-2 py-1 text-sm"
            >
              {shops.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
          )}
        </div>
      )}

      <nav className="flex-1 space-y-1 p-2">
        {NAV.map((item) => {
          const active = pathname === item.href || pathname?.startsWith(item.href + "/");
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center gap-2 rounded-md px-3 py-2 text-sm transition-colors hover:bg-accent",
                active && "bg-accent font-medium"
              )}
            >
              <Icon className="h-4 w-4" />
              {item.label}
            </Link>
          );
        })}
      </nav>
      <div className="border-t p-3">
        <div className="mb-2 text-xs">
          <div className="font-medium">{user?.name || "Vendor"}</div>
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
