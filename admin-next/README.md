# TezKetKaz Admin (Next.js)

Phase 4 admin panel: login + dashboard + orders + finance/payouts + coupons + disputes.

## Setup

```bash
cp .env.example .env.local
npm install
npm run dev
```

Open http://localhost:3001.

## Stack

- Next.js 15 (App Router) + TypeScript strict
- Tailwind CSS + hand-written shadcn-style components in `components/ui/`
- @tanstack/react-query for server state
- recharts for charts
- zustand for auth state
- jose for JWT decoding

## Backend

Set `NEXT_PUBLIC_API_URL` to the TezKetKaz backend (default `http://localhost:3000`).
Login uses `/api/auth/send-otp` then `/api/auth/verify-otp`. Only users with `isAdmin=true` can sign in.

## Pages

- `/login` — phone + OTP
- `/dashboard` — KPIs + charts
- `/orders`, `/orders/[id]` — list + detail with refund
- `/coupons` — full CRUD
- `/finance`, `/finance/[id]` — payouts + generate + CSV
- `/disputes` — list + resolve modal
- `/shops`, `/couriers`, `/users`, `/pricing-rules` — stubs
