"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";
import { Sidebar } from "@/components/sidebar";

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const { accessToken, user } = useAuth();

  useEffect(() => {
    if (!accessToken || !user?.isAdmin) {
      router.replace("/login");
    }
  }, [accessToken, user, router]);

  if (!accessToken || !user?.isAdmin) {
    return (
      <div className="flex min-h-screen items-center justify-center text-sm text-muted-foreground">
        Redirecting...
      </div>
    );
  }

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 overflow-auto bg-muted/30 p-6">{children}</main>
    </div>
  );
}
