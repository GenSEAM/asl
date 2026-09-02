import React from 'react';

/**
 * CosmicLandscapeBackground
 * Clean, uncluttered international aerospace & cybernetic blueprint:
 * 1. Fixed schematic chameleon mascot perched on a cyber-vine that starts low at y=160,
 *    passes DEAD-CENTER through the circular spiral eye of the tail (x=52, y=95),
 *    and sweeps UPWARDS to the top header/navbar.
 * 2. Strict Gutters-Only Placement: All drawings and Easter eggs are placed strictly in the
 *    Left Margin (x <= 200) and Right Margin (x >= 1220), leaving the entire center column
 *    (x: 210..1210) 100% clean and unobstructed for maximum content readability.
 * 3. 18+ Veiled International Easter Eggs across 3-4 scrolling screens (repeating into footer):
 *    - Left: Conway's Glider, Sputnik-1, 12AX7 Vacuum Triode, Turing Machine Tape,
 *            Planetary Scanner Dome, 3.5" Diskette, Token Fuel Gauge, Curiosity Wheel Morse Track,
 *            Glider Squadron.
 *    - Right: Apollo 11 Lunar Module, Voyager Golden Record, JWST 18-Hex Mirror,
 *             Hollerith 80-Col Card, Paperclip Wire Retainer, Ringed Planet OPS.RTA,
 *             8-bit Chrome Dino Runner, HAL-9000 Optical Turret, Bio-Mechanical Gears.
 * 4. Microscopic text annotations only (fontSize 6.5-7px, muted opacity, 100% English / ASL Nano).
 */
export const CosmicLandscapeBackground: React.FC = () => (
  <div className="pointer-events-none select-none" aria-hidden="true">
    {/* 1. Fixed Viewport: Ambient Glow & Perched Chameleon with Vine Sweeping to Header */}
    <div className="fixed inset-0 pointer-events-none overflow-hidden z-0">
      {/* Soft atmospheric lighting auras */}
      <div className="absolute top-6 left-6 w-[550px] h-[550px] bg-purple-600/12 dark:bg-purple-900/20 blur-[150px] rounded-full" />
      <div className="absolute top-1/3 right-8 w-[650px] h-[650px] bg-indigo-600/10 dark:bg-indigo-950/15 blur-[160px] rounded-full" />
      <div className="absolute bottom-16 left-1/4 w-[700px] h-[550px] bg-purple-900/12 blur-[160px] rounded-full" />

      {/* 
        CHAMELEON & CYBER-VINE PERCH (Top-Left):
        Starts low at y=160, threads DEAD-CENTER through the tail's spiral eye at (52, 95),
        then sweeps UPWARDS between the chameleon and satellite right to the top header!
      */}
      <div className="fixed top-12 sm:top-14 left-2 sm:left-6 lg:left-10 w-72 sm:w-84 lg:w-[440px] h-auto opacity-35 dark:opacity-40 transition-all z-10">
        <svg
          viewBox="0 0 260 160"
          className="w-full h-auto text-signal overflow-visible"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <defs>
            <linearGradient id="vineBranchGrad" x1="0%" y1="100%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#7e22ce" />
              <stop offset="45%" stopColor="#a855f7" />
              <stop offset="100%" stopColor="#c084fc" />
            </linearGradient>
            <linearGradient id="chameleonGradFixed" x1="20%" y1="0%" x2="80%" y2="100%">
              <stop offset="0%" stopColor="rgb(var(--signal-soft))" />
              <stop offset="70%" stopColor="rgb(var(--signal))" />
              <stop offset="100%" stopColor="#9333ea" />
            </linearGradient>
            <filter id="fixedAmbientGlow" x="-30%" y="-30%" width="160%" height="160%">
              <feGaussianBlur stdDeviation="3" result="glow" />
              <feComposite in="SourceGraphic" in2="glow" operator="over" />
            </filter>
          </defs>

          <g filter="url(#fixedAmbientGlow)">
            {/* 
              THE CYBER-VINE:
              Starts low on left edge at (-30, 160), passes directly through the tail's circular spiral eye at (52, 95),
              cradles under the belly at (95, 78), and sweeps UPWARDS to the top header (-50)!
            */}
            <path
              d="M -30,160 C 2,142 24,118 52,95 C 78,74 104,72 134,54 C 168,34 202,0 234,-48"
              stroke="url(#vineBranchGrad)"
              strokeWidth="3.4"
              strokeLinecap="round"
            />
            <path
              d="M -30,165 C 2,147 24,123 52,100 C 78,79 104,77 134,59 C 168,39 202,5 234,-43"
              stroke="url(#vineBranchGrad)"
              strokeWidth="1.2"
              strokeDasharray="3 3"
              opacity="0.55"
            />

            {/* Sprouting cyber-leaves climbing up to header */}
            <g transform="translate(138, 72) rotate(-42)">
              <path d="M 0,0 Q 14,-9 28,0 Q 14,9 0,0" fill="#a855f7" fillOpacity="0.2" stroke="url(#vineBranchGrad)" strokeWidth="1.2" />
              <line x1="0" y1="0" x2="28" y2="0" stroke="url(#vineBranchGrad)" strokeWidth="0.8" />
            </g>
            <g transform="translate(178, 36) rotate(-60)">
              <path d="M 0,0 Q 12,-8 24,0 Q 12,8 0,0" fill="#a855f7" fillOpacity="0.2" stroke="url(#vineBranchGrad)" strokeWidth="1.2" />
              <line x1="0" y1="0" x2="24" y2="0" stroke="url(#vineBranchGrad)" strokeWidth="0.8" />
            </g>
            <g transform="translate(216, -8) rotate(-75)">
              <path d="M 0,0 Q 10,-7 20,0 Q 10,7 0,0" fill="#a855f7" fillOpacity="0.2" stroke="url(#vineBranchGrad)" strokeWidth="1.2" />
              <line x1="0" y1="0" x2="20" y2="0" stroke="url(#vineBranchGrad)" strokeWidth="0.8" />
            </g>

            {/* Spiral tendril curling near header */}
            <path
              d="M 232,-35 Q 244,-47 240,-56 Q 234,-62 225,-58 Q 220,-52 225,-47"
              stroke="url(#vineBranchGrad)"
              strokeWidth="1.4"
            />

            {/* 
              THE SCHEMATIC CHAMELEON:
              Tail wraps tightly around the branch, with the branch passing through the spiral eye.
            */}
            <g transform="translate(5, 0)">
              {/* Spine and outer tail curve */}
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
                stroke="url(#chameleonGradFixed)"
                strokeWidth="2.2"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
              {/* Snout & Head Arc */}
              <path
                d="M 68 20 
                   C 85 24, 102 36, 98 52 
                   C 94 62, 80 65, 68 64"
                stroke="url(#chameleonGradFixed)"
                strokeWidth="2.2"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
              {/* Eye circular aperture */}
              <circle cx="82" cy="40" r="9" stroke="url(#chameleonGradFixed)" strokeWidth="2.2" />
              <circle cx="82" cy="40" r="3" fill="rgb(var(--signal-soft))" opacity="0.9" />

              {/* Underside / Belly Line */}
              <path
                d="M 68 64 
                   C 52 64, 40 68, 32 78 
                   C 25 87, 26 96, 30 102"
                stroke="url(#chameleonGradFixed)"
                strokeWidth="1.8"
                strokeLinecap="round"
              />

              {/* Coordinate reference nodes */}
              <circle cx="53" cy="14" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.7" />
              <circle cx="98" cy="52" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.7" />
              <circle cx="38" cy="122" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.7" />

              {/* Inner tail wrap stroke: explicitly curls in front of the branch passing through it */}
              <path
                d="M 44 86 C 37 94, 44 104, 53 102 C 59 100, 59 93, 54 91"
                stroke="url(#chameleonGradFixed)"
                strokeWidth="2.6"
                strokeLinecap="round"
              />
            </g>
          </g>
        </svg>
      </div>
    </div>

    {/* 2. Full-Document Scrolling Blueprint Landscape (Strictly in Left & Right Gutters) */}
    <div className="absolute inset-0 w-full h-full pointer-events-none overflow-hidden z-0">
      <svg
        className="w-full h-full text-purple-400/35 dark:text-purple-300/30"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 1440 3400"
        preserveAspectRatio="xMidYMin slice"
        fill="none"
      >
        <defs>
          {/* Blueprint Millimetric Grid Pattern */}
          <pattern id="blueprintGridPattern" width="40" height="40" patternUnits="userSpaceOnUse">
            <path d="M 40 0 L 0 0 0 40" fill="none" stroke="currentColor" strokeWidth="0.5" opacity="0.3" />
            <path d="M 200 0 L 0 0 0 200" fill="none" stroke="currentColor" strokeWidth="1.0" opacity="0.45" />
          </pattern>

          {/* Line Gradients */}
          <linearGradient id="bioLineGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#c084fc" stopOpacity="0.7" />
            <stop offset="60%" stopColor="#a855f7" stopOpacity="0.45" />
            <stop offset="100%" stopColor="#7e22ce" stopOpacity="0.25" />
          </linearGradient>

          <linearGradient id="leafFacetGrad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stopColor="#a855f7" stopOpacity="0.16" />
            <stop offset="100%" stopColor="#581c87" stopOpacity="0.04" />
          </linearGradient>

          <linearGradient id="amberGlow" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#fbbf24" stopOpacity="0.65" />
            <stop offset="100%" stopColor="#d97706" stopOpacity="0.25" />
          </linearGradient>
        </defs>

        {/* Technical Blueprint Grid Base */}
        <rect width="100%" height="100%" fill="url(#blueprintGridPattern)" />

        {/* ========================================================================= */}
        {/* LEFT GUTTER (x <= 200): Screen 1 (y: 0 - 1000)                             */}
        {/* ========================================================================= */}

        {/* 1. Conway's Game of Life Glider (Left Gutter, x: 90, y: 320) */}
        <g transform="translate(90, 320)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <rect x="12" y="0" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="24" y="12" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="0" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="12" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="24" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <line x1="32" y1="32" x2="52" y2="52" strokeDasharray="2 2" opacity="0.6" />
        </g>

        {/* 2. Sputnik-1 (Left Gutter, x: 80, y: 560, rotate -35) */}
        <g transform="translate(80, 560) rotate(-35)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="10" fill="#3b0764" fillOpacity="0.3" strokeWidth="1.5" />
          <ellipse cx="0" cy="0" rx="10" ry="3" strokeDasharray="2 2" opacity="0.5" />
          <line x1="-7" y1="-7" x2="-52" y2="-30" strokeWidth="1.1" />
          <line x1="-7" y1="7" x2="-55" y2="24" strokeWidth="1.1" />
          <line x1="7" y1="-7" x2="46" y2="-38" strokeWidth="1.0" strokeDasharray="2 1" opacity="0.6" />
          <line x1="7" y1="7" x2="50" y2="30" strokeWidth="1.0" strokeDasharray="2 1" opacity="0.6" />
          <circle cx="0" cy="0" r="18" strokeDasharray="2 2" opacity="0.4" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6" transform="rotate(35)">
            <text x="14" y="-10">PS-01</text>
          </g>
        </g>

        {/* 3. Vacuum Triode 12AX7 (Left Gutter, x: 75, y: 840, rotate -15) */}
        <g transform="translate(75, 840) rotate(-15)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <path d="M 0,50 L 0,22 C 0,7 32,7 32,22 L 32,50 Z" fill="#4a044e" fillOpacity="0.2" />
          <line x1="8" y1="18" x2="24" y2="18" strokeWidth="1.6" />
          <line x1="16" y1="7" x2="16" y2="18" />
          <path d="M 10,26 L 13,29 L 16,26 L 19,29 L 22,26" strokeWidth="1.1" strokeDasharray="1 1" />
          <path d="M 11,36 L 21,36" stroke="url(#amberGlow)" strokeWidth="1.6" />
          <line x1="7" y1="50" x2="7" y2="58" />
          <line x1="16" y1="50" x2="16" y2="60" />
          <line x1="25" y1="50" x2="25" y2="58" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.55">
            <text x="36" y="28">V-12</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* LEFT GUTTER (x <= 200): Screen 2 (y: 1000 - 2000)                          */}
        {/* ========================================================================= */}

        {/* 4. Turing Machine Tape (Left Gutter, x: 50, y: 1160) */}
        <g transform="translate(50, 1160)" stroke="url(#bioLineGrad)" strokeWidth="1.1">
          <rect x="0" y="0" width="110" height="22" rx="2" fill="#3b0764" fillOpacity="0.2" />
          <line x1="22" y1="0" x2="22" y2="22" />
          <line x1="44" y1="0" x2="44" y2="22" />
          <line x1="66" y1="0" x2="66" y2="22" />
          <line x1="88" y1="0" x2="88" y2="22" />
          {/* Read/Write head pointer */}
          <path d="M 55,-10 L 55,-2 M 52,-5 L 55,-2 L 58,-5" strokeWidth="1.4" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.8">
            <text x="8" y="15">1</text>
            <text x="30" y="15">0</text>
            <text x="52" y="15" fill="#4ade80">1</text>
            <text x="74" y="15">1</text>
            <text x="96" y="15">0</text>
          </g>
        </g>

        {/* 5. Planetary Scanner Dome & Astrolabe Dial (Left Gutter, x: 70, y: 1440) */}
        <g transform="translate(70, 1440)" stroke="url(#bioLineGrad)" strokeWidth="1.3">
          <circle cx="0" cy="0" r="90" strokeDasharray="6 5" opacity="0.35" />
          <circle cx="0" cy="0" r="55" strokeWidth="1.8" />
          <path d="M -48,-16 A 50 50 0 0 1 48,-16" strokeWidth="2.2" fill="#3b0764" fillOpacity="0.2" />
          <line x1="-48" y1="-16" x2="48" y2="-16" />
          <line x1="0" y1="-45" x2="0" y2="-70" strokeWidth="2.0" />
          <circle cx="0" cy="-70" r="3" fill="currentColor" />
          <path d="M -35,10 L -70,50 L -80,95" strokeWidth="2.2" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.75">
            <text x="18" y="45" fill="#4ade80">0.038ms</text>
          </g>
        </g>

        {/* 6. 3.5" Diskette Avionics ROM (Left Gutter, x: 75, y: 1780, rotate -28) */}
        <g transform="translate(75, 1780) rotate(-28)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <polygon points="0,0 65,0 72,7 72,76 0,76" fill="#3b0764" fillOpacity="0.25" />
          <rect x="13" y="0" width="34" height="28" rx="2" fill="#581c87" fillOpacity="0.35" />
          <rect x="19" y="5" width="7" height="17" rx="1" fill="currentColor" fillOpacity="0.75" />
          <circle cx="36" cy="46" r="12" strokeDasharray="2 2" opacity="0.5" />
          <circle cx="36" cy="46" r="4" fill="currentColor" opacity="0.5" />
          <rect x="62" y="66" width="5" height="4" fill="currentColor" opacity="0.75" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
            <text x="10" y="68">ROM-144</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* LEFT GUTTER (x <= 200): Screen 3 & 4 (y: 2000 - 3400)                      */}
        {/* ========================================================================= */}

        {/* 7. Token Fuel Gauge (Left Gutter, x: 65, y: 2120) */}
        <g transform="translate(65, 2120)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <circle cx="36" cy="36" r="32" strokeDasharray="4 3" opacity="0.5" />
          <path d="M 36,36 L 54,19" stroke="#4ade80" strokeWidth="2.0" />
          <circle cx="36" cy="36" r="3" fill="#4ade80" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.8">
            <text x="75" y="32" fill="#4ade80">-80% TOKENS</text>
            <text x="75" y="44" fill="#c084fc">0 RETRIES</text>
          </g>
        </g>

        {/* 8. Curiosity Rover Wheel Morse Code Tread (Left Gutter, x: 60, y: 2460) */}
        <g transform="translate(60, 2460)" stroke="url(#bioLineGrad)" strokeWidth="1.3">
          <rect x="0" y="0" width="85" height="16" rx="2" fill="#3b0764" fillOpacity="0.2" />
          {/* Morse: .--- (J) .--. (P) .-.. (L) */}
          <circle cx="10" cy="8" r="1.5" fill="currentColor" />
          <line x1="16" y1="8" x2="24" y2="8" strokeWidth="2" />
          <line x1="28" y1="8" x2="36" y2="8" strokeWidth="2" />
          <circle cx="44" cy="8" r="1.5" fill="currentColor" />
          <line x1="50" y1="8" x2="58" y2="8" strokeWidth="2" />
          <circle cx="66" cy="8" r="1.5" fill="currentColor" />
          <line x1="72" y1="8" x2="78" y2="8" strokeWidth="2" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.5">
            <text x="92" y="11">JPL-TR</text>
          </g>
        </g>

        {/* 9. Glider Squadron Repeat (Left Gutter, x: 80, y: 2820) */}
        <g transform="translate(80, 2820)" stroke="url(#bioLineGrad)" strokeWidth="1.1">
          <rect x="10" y="0" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="20" y="10" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="0" y="20" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="10" y="20" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="20" y="20" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
        </g>

        {/* ========================================================================= */}
        {/* RIGHT GUTTER (x >= 1220): Screen 1 (y: 0 - 1000)                           */}
        {/* ========================================================================= */}

        {/* 10. Apollo 11 Lunar Module Descent Stage (Right Gutter, x: 1260, y: 240, rotate 12) */}
        <g transform="translate(1260, 240) rotate(12)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <polygon points="7,0 23,0 30,7 30,20 23,27 7,27 0,20 0,7" fill="#3b0764" fillOpacity="0.3" />
          <path d="M 11,27 L 9,34 L 21,34 L 19,27 Z" fill="#581c87" fillOpacity="0.35" />
          <line x1="4" y1="21" x2="-10" y2="38" strokeWidth="1.3" />
          <ellipse cx="-10" cy="38" rx="3.5" ry="1.2" strokeWidth="1.1" />
          <line x1="26" y1="21" x2="40" y2="38" strokeWidth="1.3" />
          <ellipse cx="40" cy="38" rx="3.5" ry="1.2" strokeWidth="1.1" />
          <line x1="-7" y1="25" x2="-5" y2="26" strokeWidth="0.8" />
          <line x1="-9" y1="30" x2="-7" y2="31" strokeWidth="0.8" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6" transform="rotate(-12)">
            <text x="36" y="22">TRANQ-11</text>
          </g>
        </g>

        {/* 11. Voyager Golden Record Pulsar Map (Right Gutter, x: 1290, y: 520) */}
        <g transform="translate(1290, 520)" stroke="url(#bioLineGrad)" strokeWidth="1.0" opacity="0.6">
          <circle cx="0" cy="0" r="24" />
          <circle cx="0" cy="0" r="12" strokeDasharray="2 2" />
          <circle cx="0" cy="0" r="3" fill="currentColor" />
          <line x1="0" y1="0" x2="-20" y2="-10" />
          <line x1="0" y1="0" x2="18" y2="-14" />
          <line x1="0" y1="0" x2="-8" y2="20" />
          <line x1="0" y1="0" x2="16" y2="18" />
          <line x1="0" y1="0" x2="-22" y2="7" strokeDasharray="2 1" />
          <line x1="0" y1="0" x2="22" y2="5" strokeDasharray="2 1" />
        </g>

        {/* 12. JWST 18-Hexagon Mirror Array (Right Gutter, x: 1270, y: 780) */}
        <g transform="translate(1270, 780)" stroke="url(#bioLineGrad)" strokeWidth="1.1">
          {/* Hexagonal grid tile function */}
          {[
            { x: 0, y: 0 }, { x: 15, y: -9 }, { x: 15, y: 9 }, { x: 0, y: 18 }, { x: -15, y: 9 }, { x: -15, y: -9 }, { x: 0, y: -18 },
            { x: 30, y: 0 }, { x: 30, y: -18 }, { x: 30, y: 18 }, { x: -30, y: 0 }, { x: -30, y: -18 }, { x: -30, y: 18 }
          ].map((h, i) => (
            <polygon
              key={i}
              points={`${h.x},${h.y-8} ${h.x+7},${h.y-4} ${h.x+7},${h.y+4} ${h.x},${h.y+8} ${h.x-7},${h.y+4} ${h.x-7},${h.y-4}`}
              fill="#fbbf24"
              fillOpacity="0.08"
            />
          ))}
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
            <text x="36" y="24">L2-HEX</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* RIGHT GUTTER (x >= 1220): Screen 2 (y: 1000 - 2000)                          */}
        {/* ========================================================================= */}

        {/* 13. Hollerith 80-Column Punched Card (Right Gutter, x: 1250, y: 1080, rotate 20) */}
        <g transform="translate(1250, 1080) rotate(20)" stroke="url(#bioLineGrad)" strokeWidth="1.1">
          <polygon points="10,0 120,0 120,60 0,60 0,10" fill="#3b0764" fillOpacity="0.2" />
          <line x1="0" y1="12" x2="120" y2="12" strokeWidth="0.6" opacity="0.5" />
          <g fill="currentColor" opacity="0.75">
            <rect x="14" y="18" width="2" height="4" />
            <rect x="14" y="32" width="2" height="4" />
            <rect x="24" y="25" width="2" height="4" />
            <rect x="36" y="18" width="2" height="4" />
            <rect x="36" y="40" width="2" height="4" />
            <rect x="50" y="46" width="2" height="4" />
            <rect x="64" y="25" width="2" height="4" />
            <rect x="78" y="18" width="2" height="4" />
            <rect x="92" y="32" width="2" height="4" />
            <rect x="105" y="40" width="2" height="4" />
          </g>
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.55">
            <text x="12" y="9">MASK-80</text>
          </g>
        </g>

        {/* 14. Paperclip Wire Cable Retainer (Right Gutter, x: 1280, y: 1380, rotate 54) */}
        <g transform="translate(1280, 1380) rotate(54)" stroke="url(#bioLineGrad)" strokeWidth="1.5">
          <path
            d="M 10,38 L 10,13 C 10,5 24,5 24,13 L 24,42 C 24,52 5,52 5,42 L 5,18 C 5,11 17,11 17,18 L 17,38"
            fill="none"
            strokeLinecap="round"
          />
          <circle cx="14" cy="27" r="18" strokeDasharray="3 2" opacity="0.35" strokeWidth="0.8" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.55">
            <text x="28" y="28">CLIP-MAX</text>
          </g>
        </g>

        {/* 15. Saturnian Ringed Planet OPS.RTA (Right Gutter, x: 1300, y: 1680) */}
        <g transform="translate(1300, 1680)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="42" fill="#4a044e" fillOpacity="0.25" />
          <path d="M -34,-10 Q 0,-20 34,-10" strokeDasharray="2 3" opacity="0.5" />
          <ellipse cx="0" cy="0" rx="100" ry="30" strokeWidth="1.8" transform="rotate(-18)" />
          <ellipse cx="0" cy="0" rx="85" ry="24" strokeDasharray="5 3" transform="rotate(-18)" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.75">
            <text x="-22" y="60">OPS.RTA</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* RIGHT GUTTER (x >= 1220): Screen 3 & 4 (y: 2000 - 3400)                     */}
        {/* ========================================================================= */}

        {/* 16. Chrome Offline 8-Bit Dino Runner (Right Gutter, x: 1280, y: 2040) */}
        <g transform="translate(1280, 2040)" stroke="none" fill="currentColor" opacity="0.6">
          {/* Ground baseline */}
          <rect x="-10" y="26" width="60" height="1.5" />
          {/* Head & Snout */}
          <rect x="18" y="0" width="16" height="10" />
          <rect x="22" y="2" width="2" height="2" fill="#000" />
          {/* Neck & Body */}
          <rect x="14" y="8" width="10" height="12" />
          <rect x="8" y="12" width="16" height="8" />
          {/* Tiny Arms */}
          <rect x="24" y="12" width="4" height="2" />
          {/* Tail */}
          <rect x="2" y="10" width="6" height="6" />
          {/* Running Legs */}
          <rect x="10" y="20" width="3" height="6" />
          <rect x="18" y="20" width="3" height="4" />
          <rect x="21" y="24" width="3" height="2" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.7">
            <text x="36" y="16">0-LAG</text>
          </g>
        </g>

        {/* 17. HAL 9000 Eye Turret (Right Gutter, x: 1290, y: 2380) */}
        <g transform="translate(1290, 2380)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <rect x="-16" y="-24" width="32" height="48" rx="4" fill="#3b0764" fillOpacity="0.3" />
          <circle cx="0" cy="0" r="12" strokeWidth="1.6" />
          <circle cx="0" cy="0" r="7" fill="#ef4444" fillOpacity="0.8" stroke="#f87171" strokeWidth="1.2" />
          <circle cx="2" cy="-2" r="2" fill="#fff" opacity="0.9" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
            <text x="-14" y="32">HAL-9K</text>
          </g>
        </g>

        {/* 18. Bio-Mechanical Gear Drive & Chill Frame (Right Gutter, x: 1280, y: 2740) */}
        <g transform="translate(1280, 2740)" stroke="url(#bioLineGrad)" strokeWidth="1.3">
          <circle cx="0" cy="0" r="40" strokeDasharray="4 3" fill="#3b0764" fillOpacity="0.2" />
          <circle cx="0" cy="0" r="16" />
          {[0, 45, 90, 135, 180, 225, 270, 315].map((deg) => (
            <line
              key={deg}
              x1={Math.cos((deg * Math.PI) / 180) * 40}
              y1={Math.sin((deg * Math.PI) / 180) * 40}
              x2={Math.cos((deg * Math.PI) / 180) * 50}
              y2={Math.sin((deg * Math.PI) / 180) * 50}
              strokeWidth="2.5"
            />
          ))}
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.8">
            <text x="-28" y="65" fill="#4ade80">(mt s ((:on) (! run)))</text>
          </g>
        </g>

        {/* 19. Repeating Voyager & Apollo Relay for Screen 4 (Right Gutter, x: 1290, y: 3120) */}
        <g transform="translate(1290, 3120)" stroke="url(#bioLineGrad)" strokeWidth="1.1" opacity="0.65">
          <circle cx="0" cy="0" r="22" strokeDasharray="3 2" />
          <circle cx="0" cy="0" r="8" fill="currentColor" />
          <line x1="-18" y1="-9" x2="18" y2="9" />
          <line x1="-9" y1="18" x2="9" y2="-18" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor">
            <text x="26" y="5">END-OF-FILE</text>
          </g>
        </g>

        {/* Bottom Ambient Chill Frame */}
        <g transform="translate(1120, 3320)" stroke="url(#bioLineGrad)" strokeWidth="1">
          <text x="0" y="0" fontFamily="monospace" fontSize="7.5" fill="#4ade80">
            (! agent/vibe :chill true :parens :balanced)
          </text>
        </g>
      </svg>
    </div>
  </div>
);
