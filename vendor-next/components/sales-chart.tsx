"use client";

import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
} from "recharts";
import { uzs } from "@/lib/formatters";

interface SalesChartProps {
  data: { date: string; orders: number; gmv: number }[];
  height?: number;
}

export function SalesChart({ data, height = 260 }: SalesChartProps) {
  if (!data || data.length === 0) {
    return (
      <div
        className="flex items-center justify-center text-sm text-muted-foreground"
        style={{ height }}
      >
        No sales yet
      </div>
    );
  }
  return (
    <ResponsiveContainer width="100%" height={height}>
      <AreaChart data={data} margin={{ top: 10, right: 12, left: 0, bottom: 0 }}>
        <defs>
          <linearGradient id="gmvFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#16a34a" stopOpacity={0.4} />
            <stop offset="100%" stopColor="#16a34a" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
        <XAxis dataKey="date" tick={{ fontSize: 11 }} tickFormatter={(d) => d.slice(5)} />
        <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => `${Math.round(Number(v) / 1000)}k`} />
        <Tooltip
          formatter={(value: unknown, name: string) =>
            name === "gmv" ? [uzs(Number(value)), "GMV"] : [String(value), name]
          }
        />
        <Area type="monotone" dataKey="gmv" stroke="#16a34a" strokeWidth={2} fill="url(#gmvFill)" />
      </AreaChart>
    </ResponsiveContainer>
  );
}
