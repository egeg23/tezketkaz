import type { MetadataRoute } from "next";

const SITE = "https://tezketkaz.uz";

// Required for `output: "export"` — Next refuses to pre-render dynamic
// metadata routes by default, but our sitemap is fully static.
export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  return [
    { url: `${SITE}/`, lastModified: now, changeFrequency: "weekly", priority: 1.0 },
    { url: `${SITE}/couriers/`, lastModified: now, changeFrequency: "weekly", priority: 0.85 },
    { url: `${SITE}/partners/`, lastModified: now, changeFrequency: "weekly", priority: 0.85 },
    { url: `${SITE}/privacy/`, lastModified: now, changeFrequency: "monthly", priority: 0.4 },
    { url: `${SITE}/terms/`, lastModified: now, changeFrequency: "monthly", priority: 0.4 },
  ];
}
