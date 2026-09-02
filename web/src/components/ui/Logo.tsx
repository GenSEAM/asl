import React from 'react';

/**
 * ASL Curled 'a' Chameleon Mark
 * Solid filled signature glyph matching the exact chameleon tail spiral geometry from the design concept.
 */
export const ChameleonALogo: React.FC<{ className?: string; title?: string }> = ({
  className = 'w-8 h-8',
  title = 'ASL Chameleon Logo',
}) => (
  <svg
    viewBox="0 0 100 100"
    className={className}
    role="img"
    aria-label={title}
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
  >
    <defs>
      <linearGradient id="chameleonTailGrad" x1="15%" y1="10%" x2="85%" y2="90%">
        <stop offset="0%" stopColor="#d8b4fe" />
        <stop offset="35%" stopColor="#c084fc" />
        <stop offset="70%" stopColor="#a855f7" />
        <stop offset="100%" stopColor="#7c3aed" />
      </linearGradient>
      <linearGradient id="chameleonTailStrokeGrad" x1="10%" y1="5%" x2="90%" y2="95%">
        <stop offset="0%" stopColor="#f3e8ff" stopOpacity="0.8" />
        <stop offset="50%" stopColor="#c084fc" stopOpacity="0.4" />
        <stop offset="100%" stopColor="#581c87" stopOpacity="0.6" />
      </linearGradient>
      <filter id="chameleonTailGlow" x="-20%" y="-20%" width="140%" height="140%">
        <feGaussianBlur stdDeviation="3" result="blur" />
        <feComposite in="SourceGraphic" in2="blur" operator="over" />
      </filter>
    </defs>

    {/* Chameleon Tail Spiral 'a' Solid Glyph */}
    <path
      d="M 78,82 C 83,72 84,48 81,32 C 77,16 64,8 46,8 C 26,8 13,19 8,36 C 4,52 7,72 18,84 C 28,94 44,95 56,88 C 64,82 68,70 67,58 C 66,44 57,35 44,35 C 32,35 25,44 25,54 C 25,62 31,67 38,67 C 43,67 46,63 46,58 C 46,53 41,52 38,55 C 36,57 34,55 34,52 C 34,46 40,41 46,41 C 53,41 57,48 57,57 C 57,67 50,75 42,76 C 31,77 21,70 17,60 C 14,48 16,36 24,26 C 33,16 46,15 56,19 C 66,24 70,35 70,50 L 70,82 C 70,86 77,86 78,82 Z"
      fill="url(#chameleonTailGrad)"
      stroke="url(#chameleonTailStrokeGrad)"
      strokeWidth="1.2"
      strokeLinejoin="round"
      filter="url(#chameleonTailGlow)"
    />
  </svg>
);

/**
 * Standard Logo Component (aliases ChameleonALogo)
 */
export const Logo = ChameleonALogo;

/**
 * Refined Schematic Chameleon (Full Vector Mascot / Identity Mark)
 * Built strictly according to the reference schema with:
 * 1. Cleaned-up head & crest: removed redundant vertical bridge divider
 * 2. Elegant spiral tail matching the 'a' tail spiral curvature
 * 3. Consistent stroke weight, precision blueprint line-art
 */
export const ChameleonSchematic: React.FC<{
  className?: string;
  strokeWidth?: number;
  glow?: boolean;
}> = ({ className = 'w-48 h-48', strokeWidth = 2.4, glow = true }) => (
  <svg
    viewBox="0 0 120 140"
    className={className}
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    role="img"
    aria-label="Schematic Chameleon"
  >
    <defs>
      <linearGradient id="chameleonLineGrad" x1="20%" y1="0%" x2="80%" y2="100%">
        <stop offset="0%" stopColor="rgb(var(--signal-soft))" />
        <stop offset="70%" stopColor="rgb(var(--signal))" />
        <stop offset="100%" stopColor="#9333ea" />
      </linearGradient>
      {glow && (
        <filter id="chameleonAmbientGlow" x="-30%" y="-30%" width="160%" height="160%">
          <feGaussianBlur stdDeviation="3" result="glow" />
          <feComposite in="SourceGraphic" in2="glow" operator="over" />
        </filter>
      )}
    </defs>

    <g filter={glow ? 'url(#chameleonAmbientGlow)' : undefined}>
      {/* 
        Main Body & Spine Curve:
        Forehead curves up to crest (crest divider removed for clean continuity),
        smooth arch down the spine into the inward-curling spiral tail.
      */}
      <path
        d="M 68 20 
           C 62 13, 56 12, 53 14 
           C 49 16, 49 22, 53 25
           C 35 28, 16 46, 12 70 
           C 8 95, 18 116, 38 122 
           C 56 127, 72 116, 70 96 
           C 68 81, 52 76, 44 86 
           C 37 94, 44 104, 53 102 
           C 59 100, 59 93, 54 91"
        stroke="url(#chameleonLineGrad)"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
      />

      {/* 
        Snout & Head Arc:
        Curved front snout connecting to upper forehead line.
      */}
      <path
        d="M 68 20 
           C 85 24, 102 36, 98 52 
           C 94 62, 80 65, 68 64"
        stroke="url(#chameleonLineGrad)"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
      />

      {/* 
        Eye:
        Crisp circular aperture situated in head.
      */}
      <circle
        cx="82"
        cy="40"
        r="9"
        stroke="url(#chameleonLineGrad)"
        strokeWidth={strokeWidth}
      />
      <circle
        cx="82"
        cy="40"
        r="3"
        fill="rgb(var(--signal-soft))"
        opacity="0.9"
      />

      {/* 
        Belly & Chest Guideline:
        Curving gently along the underside into the tail base.
      */}
      <path
        d="M 68 64 
           C 52 64, 40 68, 32 78 
           C 25 87, 26 96, 30 102"
        stroke="url(#chameleonLineGrad)"
        strokeWidth={strokeWidth * 0.9}
        strokeLinecap="round"
      />

      {/* Subtle blueprint coordinate nodes for schematic aesthetic */}
      <circle cx="53" cy="14" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.6" />
      <circle cx="98" cy="52" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.6" />
      <circle cx="38" cy="122" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.6" />
    </g>
  </svg>
);

/**
 * Large Ambient Blueprint Watermark for Hero Background
 */
export const ChameleonWatermark: React.FC<{ className?: string }> = ({
  className = 'w-96 h-96 opacity-20 pointer-events-none',
}) => (
  <div className={`relative ${className}`}>
    <ChameleonSchematic className="w-full h-full" strokeWidth={1.8} glow={false} />
  </div>
);

/**
 * High-Density Brand Emblem / Visual Seal for Hero & Showcase
 */
export const Emblem: React.FC<{ className?: string }> = ({ className = 'w-24 h-24' }) => (
  <div className={`relative flex items-center justify-center ${className}`}>
    <div className="absolute inset-0 rounded-full bg-signal/15 blur-xl" />
    <ChameleonALogo className="w-full h-full relative z-10" />
  </div>
);

/**
 * Brand Wordmark with Logo and Clean Typography
 */
export const Wordmark: React.FC<{ className?: string }> = ({ className = '' }) => (
  <span className={`inline-flex items-center gap-2.5 ${className}`}>
    <ChameleonALogo className="w-7 h-7 text-signal shrink-0" />
    <span className="font-sans font-semibold tracking-tight text-ink text-brand text-lg">
      aslang<span className="text-signal">.dev</span>
    </span>
  </span>
);
