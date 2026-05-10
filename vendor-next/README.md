# tezketkaz-vendor

Vendor portal for TezKetKaz shop owners. Mirrors the shape of `admin-next/`
but with shop-owner auth and shop-scoped endpoints.

## Stack

- Next.js 15 (App Router) + TypeScript strict
- Tailwind + hand-written shadcn-style components
- @tanstack/react-query + zustand + recharts + jose

## Scripts

```
npm run dev        # next dev -p 3001
npm run build
npm run start      # next start -p 3001
npm run lint
npm run typecheck
```

## Environment

Copy `.env.example` to `.env.local` and set `NEXT_PUBLIC_API_URL` to your
backend (`http://localhost:3000` by default).

## Auth

OTP login via `POST /api/auth/send-otp` and `POST /api/auth/verify-otp`. The
returned user must have `isShop === true`; non-shop accounts are rejected at
the login screen. The active shop comes from `/api/auth/me`'s `shops[]`. If
the user manages multiple shops the sidebar lets them switch.
