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
}> = ({ className = 'w-48 h-48', strokeWidth = 2.0, glow = false }) => (
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
        <stop offset="0%" stopColor="#d8b4fe" />
        <stop offset="50%" stopColor="#c084fc" />
        <stop offset="100%" stopColor="#818cf8" />
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
        Head Crest & Snout Profile:
        Starts at apex of crest, curves down brow/snout, around the mouth to throat.
      */}
      <path
        d="M 52 14
           C 62 16, 78 26, 84 38
           C 88 47, 85 54, 76 56
           C 66 58, 54 54, 48 46"
        stroke="url(#chameleonLineGrad)"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
      />

      {/* 
        Crest Back to Spine & Inward Spiral Tail:
        Continuous majestic curve from crest apex, down the spine, 
        swooping into the iconic curled spiral tail.
      */}
      <path
        d="M 52 14
           C 44 14, 38 22, 42 30
           C 30 36, 16 52, 14 74
           C 11 98, 22 118, 42 124
           C 62 130, 80 118, 78 96
           C 75 80, 58 74, 46 84
           C 38 92, 44 104, 54 102
           C 60 100, 60 92, 54 90
           C 50 89, 47 92, 49 95"
        stroke="url(#chameleonLineGrad)"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
      />

      {/* 
        Concentric Focal Eye (Characteristic Chameleon Turret):
      */}
      <circle
        cx="72"
        cy="40"
        r="11"
        stroke="url(#chameleonLineGrad)"
        strokeWidth={strokeWidth}
      />
      <circle
        cx="72"
        cy="40"
        r="4.5"
        stroke="url(#chameleonLineGrad)"
        strokeWidth={strokeWidth * 0.9}
        fill="rgba(216, 180, 254, 0.25)"
      />

      {/* 
        Throat to Chest Contour:
      */}
      <path
        d="M 48 46
           C 56 52, 60 62, 54 72
           C 48 80, 38 82, 34 88"
        stroke="url(#chameleonLineGrad)"
        strokeWidth={strokeWidth * 0.8}
        strokeLinecap="round"
      />

      {/* Subtle blueprint coordinate nodes */}
      <circle cx="52" cy="14" r="1.5" fill="#d8b4fe" opacity="0.8" />
      <circle cx="84" cy="38" r="1.5" fill="#d8b4fe" opacity="0.8" />
      <circle cx="42" cy="124" r="1.5" fill="#d8b4fe" opacity="0.8" />
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
