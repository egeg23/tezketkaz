import type { MetadataRoute } from "next";

// Required for `output: "export"` — see sitemap.ts.
export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{ userAgent: "*", allow: "/" }],
    sitemap: "https://tezketkaz.uz/sitemap.xml",
    host: "https://tezketkaz.uz",
  };
}
