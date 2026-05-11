import Link from "next/link";

interface LogoProps {
  variant?: "light" | "dark";
  size?: number;
  showWordmark?: boolean;
}

/**
 * Brand mark = navy rounded square + white pin + gold lightning bolt.
 * Matches `design/logo-concepts/concept-3-pin-bolt.svg` (Phase 13.1.3).
 *
 * Rendered inline as SVG so it crisply scales for retina displays and
 * does not require a network fetch.
 */
export function Logo({
  variant = "dark",
  size = 36,
  showWordmark = true,
}: LogoProps) {
  const textColor =
    variant === "light" ? "text-white" : "text-navy-900";

  return (
    <Link
      href="/"
      aria-label="TezKetKaz — на главную"
      className="inline-flex items-center gap-2.5"
    >
      <svg
        width={size}
        height={size}
        viewBox="0 0 1024 1024"
        xmlns="http://www.w3.org/2000/svg"
        aria-hidden="true"
        className="shrink-0"
      >
        <defs>
          <linearGradient id="lgNavy" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#1A237E" />
            <stop offset="100%" stopColor="#3F51B5" />
          </linearGradient>
          <linearGradient id="lgGold" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stopColor="#FFD600" />
            <stop offset="100%" stopColor="#FFA000" />
          </linearGradient>
        </defs>
        <rect width="1024" height="1024" rx="224" ry="224" fill="url(#lgNavy)" />
        <path
          d="M 512 192 C 350 192, 224 318, 224 480 C 224 624, 416 800, 512 880 C 608 800, 800 624, 800 480 C 800 318, 674 192, 512 192 Z"
          fill="white"
        />
        <path
          d="M 560 320 L 432 528 L 528 528 L 464 720 L 592 480 L 496 480 Z"
          fill="url(#lgGold)"
        />
      </svg>
      {showWordmark && (
        <span
          className={`text-lg font-bold tracking-tight ${textColor}`}
        >
          TezKetKaz
        </span>
      )}
    </Link>
  );
}
