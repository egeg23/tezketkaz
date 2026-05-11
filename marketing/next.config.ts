import type { NextConfig } from "next";

/**
 * Marketing site for tezketkaz.uz — deployed to Cloudflare Pages.
 *
 * Uses Next.js static export (`output: 'export'`) so the build output in
 * `out/` can be deployed to any static host (Cloudflare Pages, S3, GitHub
 * Pages). The marketing site does not need a Node runtime — all forms POST
 * directly to the backend API on a different origin.
 */
const nextConfig: NextConfig = {
  output: "export",
  reactStrictMode: true,
  trailingSlash: true,
  images: {
    // Static export does not support the Next.js image optimizer; use the
    // unoptimized path so <Image /> still works for hero photos.
    unoptimized: true,
  },
};

export default nextConfig;
