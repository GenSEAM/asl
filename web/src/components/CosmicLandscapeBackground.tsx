import React from 'react';

/**
 * CosmicLandscapeBackground
 * Guaranteed-Visibility Dual-Gutter Blueprint Architecture:
 * 1. Fixed Chameleon Perch (Top-Left): Curled tail wrapped around vine that passes through the spiral eye.
 * 2. Full-Screen Background Grid: Fixed millimetric technical blueprint grid pattern.
 * 3. Dedicated Left Gutter Stream (pinned to left edge):
 *    - Conway's Glider, Sputnik-1, 12AX7 Vacuum Triode, Turing Machine Tape,
 *      Planetary Scanner Dome, 3.5" Diskette, Token Fuel Gauge, Curiosity Wheel Morse Track,
 *      Glider Squadron Repeat.
 * 4. Dedicated Right Gutter Stream (pinned to right edge):
 *    - Apollo 11 Lunar Module, Voyager Golden Record, JWST 18-Hex Mirror,
 *      Hollerith 80-Col Card, Paperclip Wire Retainer, Ringed Planet OPS.RTA,
 *      8-bit Chrome Dino Runner, HAL-9000 Optical Turret, Bio-Mechanical Gears.
 * 
 * Crucial Fix: By separating into independent left and right gutter SVGs pinned to the viewport
 * edges, no aspect-ratio zoom/crop can ever push elements off-screen. They are 100% visible
 * across mobile, laptop, desktop, and ultrawide displays without touching center text.
 */
export const CosmicLandscapeBackground: React.FC = () => (
  <div className="pointer-events-none select-none" aria-hidden="true">
    {/* 1. Ambient Lighting Auras */}
    <div className="fixed inset-0 pointer-events-none overflow-hidden z-0">
      <div className="absolute top-6 left-6 w-[550px] h-[550px] bg-purple-600/12 dark:bg-purple-900/20 blur-[150px] rounded-full" />
      <div className="absolute top-1/3 right-8 w-[650px] h-[650px] bg-indigo-600/10 dark:bg-indigo-950/15 blur-[160px] rounded-full" />
      <div className="absolute bottom-16 left-1/4 w-[700px] h-[550px] bg-purple-900/12 blur-[160px] rounded-full" />

      {/* Blueprint Base Grid Pattern (Always Crisp & Visible) */}
      <svg className="w-full h-full opacity-25 dark:opacity-20 text-purple-400 dark:text-purple-300" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <pattern id="fixedBlueprintGrid" width="40" height="40" patternUnits="userSpaceOnUse">
            <path d="M 40 0 L 0 0 0 40" fill="none" stroke="currentColor" strokeWidth="0.5" opacity="0.4" />
            <path d="M 200 0 L 0 0 0 200" fill="none" stroke="currentColor" strokeWidth="1.0" opacity="0.6" />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#fixedBlueprintGrid)" />
      </svg>

      {/* 
        CHAMELEON & CYBER-VINE PERCH (Top-Left):
        Starts low at y=160, threads DEAD-CENTER through the tail's spiral eye at (52, 95),
        then sweeps UPWARDS between the chameleon and satellite right to the top header!
      */}
      <div className="fixed top-12 sm:top-14 left-2 sm:left-6 lg:left-10 w-72 sm:w-84 lg:w-[440px] h-auto opacity-40 dark:opacity-45 transition-all z-10">
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
            {/* The Vine passing directly through the spiral eye at (52, 95) */}
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

            {/* The Schematic Chameleon */}
            <g transform="translate(5, 0)">
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
              <path
                d="M 68 20 
                   C 85 24, 102 36, 98 52 
                   C 94 62, 80 65, 68 64"
                stroke="url(#chameleonGradFixed)"
                strokeWidth="2.2"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
              <circle cx="82" cy="40" r="9" stroke="url(#chameleonGradFixed)" strokeWidth="2.2" />
              <circle cx="82" cy="40" r="3" fill="rgb(var(--signal-soft))" opacity="0.9" />

              <path
                d="M 68 64 
                   C 52 64, 40 68, 32 78 
                   C 25 87, 26 96, 30 102"
                stroke="url(#chameleonGradFixed)"
                strokeWidth="1.8"
                strokeLinecap="round"
              />

              <circle cx="53" cy="14" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.7" />
              <circle cx="98" cy="52" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.7" />
              <circle cx="38" cy="122" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.7" />

              {/* Inner tail wrap stroke explicitly on top of branch */}
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

    {/* 2. DEDICATED LEFT GUTTER STREAM (Always Visible at Left Screen Margin) */}
    <div className="absolute top-0 left-0 w-28 sm:w-36 md:w-44 lg:w-52 h-[3400px] pointer-events-none z-0 overflow-visible">
      <svg
        className="w-full h-full text-purple-400/40 dark:text-purple-300/35"
        viewBox="0 0 160 3400"
        preserveAspectRatio="xMidYMin meet"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <linearGradient id="leftBioGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#c084fc" stopOpacity="0.8" />
            <stop offset="60%" stopColor="#a855f7" stopOpacity="0.5" />
            <stop offset="100%" stopColor="#7e22ce" stopOpacity="0.3" />
          </linearGradient>
          <linearGradient id="amberGlowL" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#fbbf24" stopOpacity="0.75" />
            <stop offset="100%" stopColor="#d97706" stopOpacity="0.3" />
          </linearGradient>
        </defs>

        {/* 1. Conway's Glider (y: 320) */}
        <g transform="translate(60, 320)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <rect x="12" y="0" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="24" y="12" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="0" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="12" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="24" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <line x1="32" y1="32" x2="52" y2="52" strokeDasharray="2 2" opacity="0.6" />
        </g>

        {/* 2. Sputnik-1 (y: 560, rotate -35) */}
        <g transform="translate(55, 560) rotate(-35)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="10" fill="#3b0764" fillOpacity="0.3" strokeWidth="1.5" />
          <ellipse cx="0" cy="0" rx="10" ry="3" strokeDasharray="2 2" opacity="0.5" />
          <line x1="-7" y1="-7" x2="-52" y2="-30" strokeWidth="1.1" />
          <line x1="-7" y1="7" x2="-55" y2="24" strokeWidth="1.1" />
          <line x1="7" y1="-7" x2="46" y2="-38" strokeWidth="1.0" strokeDasharray="2 1" opacity="0.6" />
          <line x1="7" y1="7" x2="50" y2="30" strokeWidth="1.0" strokeDasharray="2 1" opacity="0.6" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6" transform="rotate(35)">
            <text x="14" y="-10">PS-01</text>
          </g>
        </g>

        {/* 3. Vacuum Triode 12AX7 (y: 840) */}
        <g transform="translate(45, 840) rotate(-15)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <path d="M 0,50 L 0,22 C 0,7 32,7 32,22 L 32,50 Z" fill="#4a044e" fillOpacity="0.2" />
          <line x1="8" y1="18" x2="24" y2="18" strokeWidth="1.6" />
          <line x1="16" y1="7" x2="16" y2="18" />
          <path d="M 10,26 L 13,29 L 16,26 L 19,29 L 22,26" strokeWidth="1.1" strokeDasharray="1 1" />
          <path d="M 11,36 L 21,36" stroke="url(#amberGlowL)" strokeWidth="1.6" />
          <line x1="7" y1="50" x2="7" y2="58" />
          <line x1="16" y1="50" x2="16" y2="60" />
          <line x1="25" y1="50" x2="25" y2="58" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.55">
            <text x="36" y="28">V-12</text>
          </g>
        </g>

        {/* 4. Turing Machine Tape (y: 1160) */}
        <g transform="translate(25, 1160)" stroke="url(#leftBioGrad)" strokeWidth="1.1">
          <rect x="0" y="0" width="110" height="22" rx="2" fill="#3b0764" fillOpacity="0.2" />
          <line x1="22" y1="0" x2="22" y2="22" />
          <line x1="44" y1="0" x2="44" y2="22" />
          <line x1="66" y1="0" x2="66" y2="22" />
          <line x1="88" y1="0" x2="88" y2="22" />
          <path d="M 55,-10 L 55,-2 M 52,-5 L 55,-2 L 58,-5" strokeWidth="1.4" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.8">
            <text x="8" y="15">1</text>
            <text x="30" y="15">0</text>
            <text x="52" y="15" fill="#4ade80">1</text>
            <text x="74" y="15">1</text>
            <text x="96" y="15">0</text>
          </g>
        </g>

        {/* 5. Planetary Scanner Dome (y: 1440) */}
        <g transform="translate(50, 1440)" stroke="url(#leftBioGrad)" strokeWidth="1.3">
          <circle cx="0" cy="0" r="48" strokeDasharray="5 4" opacity="0.35" />
          <path d="M -38,-12 A 40 40 0 0 1 38,-12" strokeWidth="2" fill="#3b0764" fillOpacity="0.2" />
          <line x1="-38" y1="-12" x2="38" y2="-12" />
          <line x1="0" y1="-38" x2="0" y2="-55" strokeWidth="2.0" />
          <circle cx="0" cy="-55" r="3" fill="currentColor" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.75">
            <text x="12" y="32" fill="#4ade80">0.038ms</text>
          </g>
        </g>

        {/* 6. 3.5" Diskette Avionics ROM (y: 1780) */}
        <g transform="translate(45, 1780) rotate(-28)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <polygon points="0,0 60,0 66,6 66,70 0,70" fill="#3b0764" fillOpacity="0.25" />
          <rect x="12" y="0" width="30" height="26" rx="2" fill="#581c87" fillOpacity="0.35" />
          <rect x="17" y="5" width="6" height="15" rx="1" fill="currentColor" fillOpacity="0.75" />
          <circle cx="33" cy="42" r="10" strokeDasharray="2 2" opacity="0.5" />
          <circle cx="33" cy="42" r="3.5" fill="currentColor" opacity="0.5" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
            <text x="8" y="62">ROM-144</text>
          </g>
        </g>

        {/* 7. Token Fuel Gauge (y: 2120) */}
        <g transform="translate(35, 2120)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <circle cx="30" cy="30" r="26" strokeDasharray="4 3" opacity="0.5" />
          <path d="M 30,30 L 46,16" stroke="#4ade80" strokeWidth="2.0" />
          <circle cx="30" cy="30" r="3" fill="#4ade80" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.8">
            <text x="64" y="26" fill="#4ade80">-80% TOK</text>
            <text x="64" y="38" fill="#c084fc">0 RETRY</text>
          </g>
        </g>

        {/* 8. Curiosity Rover Wheel Morse Track (y: 2460) */}
        <g transform="translate(30, 2460)" stroke="url(#leftBioGrad)" strokeWidth="1.3">
          <rect x="0" y="0" width="85" height="16" rx="2" fill="#3b0764" fillOpacity="0.2" />
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

        {/* 9. Glider Squadron Repeat (y: 2820) */}
        <g transform="translate(50, 2820)" stroke="url(#leftBioGrad)" strokeWidth="1.1">
          <rect x="10" y="0" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="20" y="10" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="0" y="20" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="10" y="20" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="20" y="20" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
        </g>
      </svg>
    </div>

    {/* 3. DEDICATED RIGHT GUTTER STREAM (Always Visible at Right Screen Margin) */}
    <div className="absolute top-0 right-0 w-28 sm:w-36 md:w-44 lg:w-52 h-[3400px] pointer-events-none z-0 overflow-visible">
      <svg
        className="w-full h-full text-purple-400/40 dark:text-purple-300/35"
        viewBox="0 0 160 3400"
        preserveAspectRatio="xMidYMin meet"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <linearGradient id="rightBioGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#c084fc" stopOpacity="0.8" />
            <stop offset="60%" stopColor="#a855f7" stopOpacity="0.5" />
            <stop offset="100%" stopColor="#7e22ce" stopOpacity="0.3" />
          </linearGradient>
        </defs>

        {/* 10. Apollo 11 Lunar Module (y: 240) */}
        <g transform="translate(50, 240) rotate(12)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <polygon points="7,0 23,0 30,7 30,20 23,27 7,27 0,20 0,7" fill="#3b0764" fillOpacity="0.3" />
          <path d="M 11,27 L 9,34 L 21,34 L 19,27 Z" fill="#581c87" fillOpacity="0.35" />
          <line x1="4" y1="21" x2="-10" y2="38" strokeWidth="1.3" />
          <ellipse cx="-10" cy="38" rx="3.5" ry="1.2" strokeWidth="1.1" />
          <line x1="26" y1="21" x2="40" y2="38" strokeWidth="1.3" />
          <ellipse cx="40" cy="38" rx="3.5" ry="1.2" strokeWidth="1.1" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6" transform="rotate(-12)">
            <text x="36" y="22">TRANQ-11</text>
          </g>
        </g>

        {/* 11. Voyager Golden Record Pulsar Map (y: 520) */}
        <g transform="translate(70, 520)" stroke="url(#rightBioGrad)" strokeWidth="1.0" opacity="0.6">
          <circle cx="0" cy="0" r="22" />
          <circle cx="0" cy="0" r="11" strokeDasharray="2 2" />
          <circle cx="0" cy="0" r="3" fill="currentColor" />
          <line x1="0" y1="0" x2="-18" y2="-9" />
          <line x1="0" y1="0" x2="16" y2="-12" />
          <line x1="0" y1="0" x2="-7" y2="18" />
          <line x1="0" y1="0" x2="14" y2="16" />
        </g>

        {/* 12. JWST 18-Hex Mirror Array (y: 780) */}
        <g transform="translate(60, 780)" stroke="url(#rightBioGrad)" strokeWidth="1.1">
          {[
            { x: 0, y: 0 }, { x: 14, y: -8 }, { x: 14, y: 8 }, { x: 0, y: 16 }, { x: -14, y: 8 }, { x: -14, y: -8 }, { x: 0, y: -16 }
          ].map((h, i) => (
            <polygon
              key={i}
              points={`${h.x},${h.y-7} ${h.x+6},${h.y-3.5} ${h.x+6},${h.y+3.5} ${h.x},${h.y+7} ${h.x-6},${h.y+3.5} ${h.x-6},${h.y-3.5}`}
              fill="#fbbf24"
              fillOpacity="0.1"
            />
          ))}
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
            <text x="26" y="20">L2-HEX</text>
          </g>
        </g>

        {/* 13. Hollerith 80-Column Punched Card (y: 1080) */}
        <g transform="translate(30, 1080) rotate(18)" stroke="url(#rightBioGrad)" strokeWidth="1.1">
          <polygon points="10,0 110,0 110,54 0,54 0,10" fill="#3b0764" fillOpacity="0.2" />
          <line x1="0" y1="11" x2="110" y2="11" strokeWidth="0.6" opacity="0.5" />
          <g fill="currentColor" opacity="0.75">
            <rect x="12" y="16" width="2" height="4" />
            <rect x="12" y="28" width="2" height="4" />
            <rect x="22" y="22" width="2" height="4" />
            <rect x="32" y="16" width="2" height="4" />
            <rect x="44" y="34" width="2" height="4" />
            <rect x="58" y="22" width="2" height="4" />
            <rect x="70" y="16" width="2" height="4" />
            <rect x="82" y="28" width="2" height="4" />
          </g>
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.55">
            <text x="10" y="8">MASK-80</text>
          </g>
        </g>

        {/* 14. Paperclip Wire Cable Retainer (y: 1380) */}
        <g transform="translate(60, 1380) rotate(54)" stroke="url(#rightBioGrad)" strokeWidth="1.5">
          <path
            d="M 10,38 L 10,13 C 10,5 24,5 24,13 L 24,42 C 24,52 5,52 5,42 L 5,18 C 5,11 17,11 17,18 L 17,38"
            fill="none"
            strokeLinecap="round"
          />
          <circle cx="14" cy="27" r="16" strokeDasharray="3 2" opacity="0.35" strokeWidth="0.8" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.55">
            <text x="24" y="26">CLIP-MAX</text>
          </g>
        </g>

        {/* 15. Saturnian Ringed Planet (y: 1680) */}
        <g transform="translate(70, 1680)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="34" fill="#4a044e" fillOpacity="0.25" />
          <ellipse cx="0" cy="0" rx="80" ry="24" strokeWidth="1.6" transform="rotate(-18)" />
          <ellipse cx="0" cy="0" rx="68" ry="19" strokeDasharray="4 3" transform="rotate(-18)" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.75">
            <text x="-20" y="48">OPS.RTA</text>
          </g>
        </g>

        {/* 16. Chrome 8-Bit Offline Dino Runner (y: 2040) */}
        <g transform="translate(50, 2040)" stroke="none" fill="currentColor" opacity="0.6">
          <rect x="-8" y="24" width="50" height="1.5" />
          <rect x="16" y="0" width="14" height="9" />
          <rect x="20" y="2" width="2" height="2" fill="#000" />
          <rect x="12" y="7" width="9" height="10" />
          <rect x="7" y="11" width="14" height="7" />
          <rect x="21" y="11" width="3" height="2" />
          <rect x="2" y="9" width="5" height="5" />
          <rect x="9" y="18" width="3" height="6" />
          <rect x="16" y="18" width="3" height="4" />
          <rect x="19" y="22" width="3" height="2" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.7">
            <text x="32" y="14">0-LAG</text>
          </g>
        </g>

        {/* 17. HAL 9000 Eye Turret (y: 2380) */}
        <g transform="translate(65, 2380)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <rect x="-14" y="-22" width="28" height="44" rx="4" fill="#3b0764" fillOpacity="0.3" />
          <circle cx="0" cy="0" r="11" strokeWidth="1.5" />
          <circle cx="0" cy="0" r="6" fill="#ef4444" fillOpacity="0.8" stroke="#f87171" strokeWidth="1.1" />
          <circle cx="2" cy="-2" r="1.5" fill="#fff" opacity="0.9" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
            <text x="-12" y="30">HAL-9K</text>
          </g>
        </g>

        {/* 18. Bio-Mechanical Gear Drive (y: 2740) */}
        <g transform="translate(60, 2740)" stroke="url(#rightBioGrad)" strokeWidth="1.3">
          <circle cx="0" cy="0" r="32" strokeDasharray="4 3" fill="#3b0764" fillOpacity="0.2" />
          <circle cx="0" cy="0" r="13" />
          {[0, 45, 90, 135, 180, 225, 270, 315].map((deg) => (
            <line
              key={deg}
              x1={Math.cos((deg * Math.PI) / 180) * 32}
              y1={Math.sin((deg * Math.PI) / 180) * 32}
              x2={Math.cos((deg * Math.PI) / 180) * 40}
              y2={Math.sin((deg * Math.PI) / 180) * 40}
              strokeWidth="2.2"
            />
          ))}
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.8">
            <text x="-24" y="52" fill="#4ade80">(! run)</text>
          </g>
        </g>

        {/* 19. Repeating Voyager Relay (y: 3120) */}
        <g transform="translate(65, 3120)" stroke="url(#rightBioGrad)" strokeWidth="1.1" opacity="0.65">
          <circle cx="0" cy="0" r="18" strokeDasharray="3 2" />
          <circle cx="0" cy="0" r="6" fill="currentColor" />
          <line x1="-15" y1="-7" x2="15" y2="7" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor">
            <text x="22" y="4">EOF</text>
          </g>
        </g>
      </svg>
    </div>
  </div>
);
