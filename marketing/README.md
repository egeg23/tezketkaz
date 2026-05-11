# TezKetKaz marketing site (`tezketkaz.uz`)

Static Next.js 15 app deployed to **Cloudflare Pages**. The site is fully
pre-rendered (`output: "export"`) — no Node runtime is required to serve it.

## Pages

| Path        | Purpose                                                                    |
| ----------- | -------------------------------------------------------------------------- |
| `/`         | Homepage: hero, verticals, features, stats, partner & courier CTAs        |
| `/couriers` | Courier acquisition page with application form + FAQ                       |
| `/partners` | Shop-partner acquisition page with application form, "how it works", FAQ  |
| `/privacy`  | Stub linking to backend `/api/legal/privacy?locale=…`                     |
| `/terms`    | Stub linking to backend `/api/legal/terms?locale=…`                       |

## Local development

```bash
cd marketing
npm install
npm run dev          # http://localhost:3002
```

The marketing site uses port `3002` so it can run side-by-side with
`admin-next` (3001) and the future `vendor-next` portal.

## Build (Cloudflare Pages compatible)

```bash
cd marketing
npm install
npm run build        # produces `marketing/out/`
```

The static export lands in `marketing/out/`. Cloudflare Pages serves this
directory directly. To preview locally:

```bash
npx serve out -p 3002
```

## Environment

```
# .env.local
NEXT_PUBLIC_API_BASE=https://api.tezketkaz.uz
```

`NEXT_PUBLIC_API_BASE` is used by:
- the courier/partner application forms (`POST /api/couriers/apply`,
  `POST /api/partners/apply`),
- the privacy/terms pages (deep links to `/api/legal/{privacy,terms}`).

If unset, forms log the payload to the browser console with a
"TODO: wire to backend" hint and still show the success state — operators
receive applications through the email gateway in the interim.

## Deploy

CI workflow at `.github/workflows/deploy-marketing.yml` builds and deploys
on every push to `main` that touches `marketing/**`.

Required GitHub Action secrets:

| Secret                  | Where to find it                                      |
| ----------------------- | ----------------------------------------------------- |
| `CLOUDFLARE_API_TOKEN`  | Cloudflare → My Profile → API Tokens (Pages: Edit)    |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard → right sidebar of your account  |

Setup steps live in `docs/runbooks/marketing-deploy.md`.

## Design system

| Token         | Value      | Usage                            |
| ------------- | ---------- | -------------------------------- |
| `navy-900`    | `#1A237E`  | Hero gradient start, brand text  |
| `navy-700`    | `#3F51B5`  | Hero gradient end, accents       |
| `brand-gold`  | `#FFD600`  | CTAs, lightning bolt, highlights |
| `brand-amber` | `#FFA000`  | Gold gradient end                |
| `Inter`       | (Google)   | All typography                   |

The aesthetic target is "Wolt-clean" — generous whitespace, restrained use
of colour, photography only where it adds atmosphere.

## Tech

- Next.js 15 (App Router) — static export
- TypeScript strict mode
- Tailwind CSS 3.4
- No client-state library, no UI kit — components are inline shadcn-style

Client components (require JS): `LanguageSwitcher`, `DownloadCTA`,
`CourierApplyForm`, `PartnerApplyForm`. Everything else is a server
component.
