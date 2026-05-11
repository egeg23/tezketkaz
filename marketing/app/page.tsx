import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { Verticals } from "@/components/Verticals";
import { Features } from "@/components/Features";
import { Stats } from "@/components/Stats";
import { PartnersSection } from "@/components/PartnersSection";
import { CouriersSection } from "@/components/CouriersSection";
import { Footer } from "@/components/Footer";

/**
 * tezketkaz.uz homepage.
 *
 * Section order (per Phase 13.3.5 spec):
 *   1. Hero (navy gradient + Download CTAs)
 *   2. Verticals — 4 categories
 *   3. Features — 3 columns
 *   4. Stats — trust numbers strip
 *   5. PartnersSection — link to /partners
 *   6. CouriersSection — link to /couriers
 *   7. Footer
 */
export default function HomePage() {
  return (
    <>
      <Nav variant="light" />
      <main>
        <Hero />
        <Verticals />
        <Features />
        <Stats />
        <PartnersSection />
        <CouriersSection />
      </main>
      <Footer />
    </>
  );
}
