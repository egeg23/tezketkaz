import type { Config } from "tailwindcss";

/**
 * TezKetKaz marketing site theme.
 *
 * Brand palette anchors on the "Pin+Lightning" logo (Phase 13.1.3):
 *   - navy gradient (1A237E → 3F51B5) for hero backgrounds
 *   - gold/amber (FFD600 → FFA000) for the lightning accent + CTAs
 *
 * Aesthetic target: clean, generous whitespace (Wolt-like), not the busy
 * yellow density of Glovo.
 */
const config: Config = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./lib/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        navy: {
          50: "#EEF0F9",
          100: "#D6DAEF",
          500: "#5C6BC0",
          700: "#3F51B5",
          900: "#1A237E",
        },
        brand: {
          gold: "#FFD600",
          amber: "#FFA000",
        },
      },
      fontFamily: {
        sans: [
          "var(--font-inter)",
          "ui-sans-serif",
          "system-ui",
          "-apple-system",
          "Segoe UI",
          "Roboto",
          "sans-serif",
        ],
      },
      backgroundImage: {
        "hero-gradient":
          "linear-gradient(135deg, #1A237E 0%, #3F51B5 100%)",
        "gold-gradient":
          "linear-gradient(180deg, #FFD600 0%, #FFA000 100%)",
      },
      boxShadow: {
        soft: "0 8px 30px rgba(26, 35, 126, 0.08)",
        lift: "0 18px 50px -10px rgba(26, 35, 126, 0.25)",
      },
      keyframes: {
        "fade-up": {
          "0%": { opacity: "0", transform: "translateY(16px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        "pulse-bolt": {
          "0%, 100%": { transform: "scale(1)", opacity: "1" },
          "50%": { transform: "scale(1.05)", opacity: "0.85" },
        },
      },
      animation: {
        "fade-up": "fade-up 0.6s ease-out both",
        "pulse-bolt": "pulse-bolt 2.4s ease-in-out infinite",
      },
    },
  },
  plugins: [],
};

export default config;
