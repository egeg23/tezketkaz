# Marketing site deployment — `tezketkaz.uz`

How to provision `tezketkaz.uz` on Cloudflare Pages and wire up CI deploys
from this repository.

> Target audience: operations engineer with access to the company GoDaddy /
> Hosting.uz account, the Cloudflare org, and GitHub repo settings.

## 1. Buy the domain

Register `tezketkaz.uz` through one of the official `.uz` registrars (the
TLD cannot be bought through generic registrars):

- **Hosting.uz** (https://hosting.uz/) — fastest if you already have a
  legal entity in Uzbekistan.
- **UZINFOCOM** (https://uzinfocom.uz/) — direct from the TLD operator.

The registration form asks for the legal owner's INN/PINFL. Set the
contact email to `domains@tezketkaz.uz`.

## 2. Add the domain to Cloudflare

1. Log in to https://dash.cloudflare.com → **Add a site** → enter
   `tezketkaz.uz` → choose the **Free** plan.
2. Cloudflare scans the existing DNS and gives you two nameservers, e.g.
   `dana.ns.cloudflare.com`, `arnold.ns.cloudflare.com`.
3. Open the registrar control panel and replace the existing nameservers
   with the Cloudflare pair. Propagation usually finishes in 15–60 minutes
   for `.uz`.
4. Wait for the **Active** banner on the Cloudflare overview page.

## 3. Create the Pages project

1. Cloudflare dashboard → **Workers & Pages** → **Create application** →
   **Pages** → **Connect to Git**.
2. Sign in with GitHub, authorise the **Cloudflare Pages** app, and select
   the `tezketkaz` repo.
3. Name the project **`tezketkaz-marketing`** (must match
   `.github/workflows/deploy-marketing.yml`).
4. Build settings:

   | Field                | Value                                      |
   | -------------------- | ------------------------------------------ |
   | Framework preset     | Next.js (Static HTML Export)               |
   | Build command        | `cd marketing && npm install && npm run build` |
   | Build output dir     | `marketing/out`                            |
   | Root directory       | (leave blank — repo root)                  |
   | Production branch    | `main`                                     |

   Environment variables (Production):

   | Key                     | Value                          |
   | ----------------------- | ------------------------------ |
   | `NEXT_PUBLIC_API_BASE`  | `https://api.tezketkaz.uz`     |
   | `NODE_VERSION`          | `20`                           |

5. Click **Save and deploy**. The first build takes ~2 minutes.

## 4. Wire GitHub Actions (optional but recommended)

The repo already ships `.github/workflows/deploy-marketing.yml`. To enable
it:

1. Cloudflare dashboard → right sidebar → copy **Account ID**.
2. Cloudflare dashboard → top-right avatar → **My Profile** → **API
   Tokens** → **Create Token** → **Create Custom Token**:
   - Permissions: `Account → Cloudflare Pages → Edit`.
   - Account resources: `Include → <your account>`.
   - TTL: leave default (no expiry).
3. GitHub repo → **Settings** → **Secrets and variables** → **Actions** →
   **New repository secret**. Add:
   - `CLOUDFLARE_API_TOKEN` ← the token from step 2.
   - `CLOUDFLARE_ACCOUNT_ID` ← the ID from step 1.
4. Push a commit that touches `marketing/**` to trigger the workflow.

## 5. Custom domains

Cloudflare Pages → **tezketkaz-marketing** → **Custom domains** → **Set up
a custom domain**.

Add both:
- `tezketkaz.uz` (apex)
- `www.tezketkaz.uz`

Cloudflare creates the CNAME/AAAA records automatically because the zone
is already managed by Cloudflare. SSL certificates issue within a minute.

## 6. Smoke test

```bash
curl -I https://tezketkaz.uz/
curl -I https://tezketkaz.uz/couriers/
curl -I https://tezketkaz.uz/partners/
curl -s https://tezketkaz.uz/sitemap.xml | head
```

Expect HTTP `200` for the page URLs and a valid XML document from
`/sitemap.xml`.

## 7. Rollback

Cloudflare keeps every deployment. To roll back: **Pages → project →
Deployments → … → Rollback**. This is instant and does not require a
rebuild.
