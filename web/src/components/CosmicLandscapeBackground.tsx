import React from 'react';

/**
 * CosmicLandscapeBackground
 * Full-Document Scattered & Tilted Aerospace Blueprint Architecture:
 * 1. Fixed Chameleon Perch (Top-Left): Curled tail wrapped around vine that passes through the spiral eye.
 * 2. Full-Screen Background Grid: Fixed millimetric technical blueprint grid pattern.
 * 3. 7800px Extended Gutter Streams (Left & Right):
 *    - Extends all the way down to 7800px so Easter eggs NEVER stop or disappear when scrolling through all sections.
 *    - Organically scattered positions (x wanders between 30 and 150) and tilted rotations (-60° to +65°).
 *    - 40+ cult engineering & space exploration Easter eggs:
 *      * Left: Conway Glider, Sputnik-1, 12AX7 Tube, Turing Tape, Astrolabe Scanner, 3.5" Diskette,
 *              Token Fuel Gauge, Curiosity Morse Track, Wasm Matrix, Cassette Spool, Transistor TO-92,
 *              Fiber Optic Ferrule, Radar Sweep, Silicon Wafer Die, Repeating Glider Fleet...
 *      * Right: Apollo 11 Lunar Module, Voyager Golden Record, JWST 18-Hex Mirror, Hollerith 80-Col Card,
 *               Clippy Wire Retainer, Saturnian Planet, Chrome 8-bit Dino, HAL-9000 Eye, Bio Gears,
 *               Ferrite Core Memory, Shuttle Heat Tiles, 555 Timer IC, Oscilloscope Waveform, Resistor Bands...
 * 4. Pinned to viewport edges: 100% visible on any resolution without colliding with center text.
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

    {/* 2. DEDICATED LEFT GUTTER STREAM (Scattered & Tilted across 7800px) */}
    <div className="absolute top-0 left-0 w-32 sm:w-44 md:w-52 lg:w-60 h-[7800px] pointer-events-none z-0 overflow-visible">
      <svg
        className="w-full h-full text-purple-400/40 dark:text-purple-300/35"
        viewBox="0 0 180 7800"
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

        {/* 1. Conway's Glider (y: 280, x: 75, rotate -24) */}
        <g transform="translate(75, 280) rotate(-24)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <rect x="12" y="0" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="24" y="12" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="0" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="12" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <rect x="24" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
          <line x1="32" y1="32" x2="52" y2="52" strokeDasharray="2 2" opacity="0.6" />
        </g>

        {/* 2. Sputnik-1 (y: 580, x: 130, rotate 42) */}
        <g transform="translate(130, 580) rotate(42)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="10" fill="#3b0764" fillOpacity="0.3" strokeWidth="1.5" />
          <ellipse cx="0" cy="0" rx="10" ry="3" strokeDasharray="2 2" opacity="0.5" />
          <line x1="-7" y1="-7" x2="-48" y2="-28" strokeWidth="1.1" />
          <line x1="-7" y1="7" x2="-52" y2="22" strokeWidth="1.1" />
          <line x1="7" y1="-7" x2="42" y2="-36" strokeWidth="1.0" strokeDasharray="2 1" opacity="0.6" />
          <line x1="7" y1="7" x2="46" y2="28" strokeWidth="1.0" strokeDasharray="2 1" opacity="0.6" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6" transform="rotate(-42)">
            <text x="14" y="-10">PS-01</text>
          </g>
        </g>

        {/* 3. Vacuum Triode 12AX7 (y: 920, x: 45, rotate -18) */}
        <g transform="translate(45, 920) rotate(-18)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
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

        {/* 4. Turing Machine Tape (y: 1240, x: 110, rotate 12) */}
        <g transform="translate(110, 1240) rotate(12)" stroke="url(#leftBioGrad)" strokeWidth="1.1">
          <rect x="-55" y="-11" width="110" height="22" rx="2" fill="#3b0764" fillOpacity="0.2" />
          <line x1="-33" y1="-11" x2="-33" y2="11" />
          <line x1="-11" y1="-11" x2="-11" y2="11" />
          <line x1="11" y1="-11" x2="11" y2="11" />
          <line x1="33" y1="-11" x2="33" y2="11" />
          <path d="M 0,-18 L 0,-11 M -3,-14 L 0,-11 L 3,-14" strokeWidth="1.4" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.8">
            <text x="-48" y="4">1</text>
            <text x="-26" y="4">0</text>
            <text x="-4" y="4" fill="#4ade80">1</text>
            <text x="18" y="4">1</text>
            <text x="40" y="4">0</text>
          </g>
        </g>

        {/* 5. Planetary Scanner Dome (y: 1560, x: 50, rotate -45) */}
        <g transform="translate(50, 1560) rotate(-45)" stroke="url(#leftBioGrad)" strokeWidth="1.3">
          <circle cx="0" cy="0" r="44" strokeDasharray="5 4" opacity="0.35" />
          <path d="M -34,-10 A 36 36 0 0 1 34,-10" strokeWidth="2" fill="#3b0764" fillOpacity="0.2" />
          <line x1="-34" y1="-10" x2="34" y2="-10" />
          <line x1="0" y1="-34" x2="0" y2="-50" strokeWidth="2.0" />
          <circle cx="0" cy="-50" r="3" fill="currentColor" />
        </g>

        {/* 6. 3.5" Diskette Avionics ROM (y: 1880, x: 135, rotate 32) */}
        <g transform="translate(135, 1880) rotate(32)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <polygon points="0,0 55,0 60,5 60,65 0,65" fill="#3b0764" fillOpacity="0.25" />
          <rect x="11" y="0" width="28" height="24" rx="2" fill="#581c87" fillOpacity="0.35" />
          <rect x="16" y="4" width="5" height="14" rx="1" fill="currentColor" fillOpacity="0.75" />
          <circle cx="30" cy="38" r="9" strokeDasharray="2 2" opacity="0.5" />
          <circle cx="30" cy="38" r="3" fill="currentColor" opacity="0.5" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
            <text x="8" y="58">ROM-144</text>
          </g>
        </g>

        {/* 7. Token Fuel Gauge (y: 2200, x: 60, rotate -12) */}
        <g transform="translate(60, 2200) rotate(-12)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="26" strokeDasharray="4 3" opacity="0.5" />
          <path d="M 0,0 L 16,-14" stroke="#4ade80" strokeWidth="2.0" />
          <circle cx="0" cy="0" r="3" fill="#4ade80" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.8">
            <text x="32" y="-4" fill="#4ade80">-80% TOK</text>
          </g>
        </g>

        {/* 8. Curiosity Rover Wheel Morse Track (y: 2540, x: 120, rotate -28) */}
        <g transform="translate(120, 2540) rotate(-28)" stroke="url(#leftBioGrad)" strokeWidth="1.3">
          <rect x="-42" y="-8" width="85" height="16" rx="2" fill="#3b0764" fillOpacity="0.2" />
          <circle cx="-32" cy="0" r="1.5" fill="currentColor" />
          <line x1="-26" y1="0" x2="-18" y2="0" strokeWidth="2" />
          <line x1="-14" y1="0" x2="-6" y2="0" strokeWidth="2" />
          <circle cx="2" cy="0" r="1.5" fill="currentColor" />
          <line x1="8" y1="0" x2="16" y2="0" strokeWidth="2" />
          <circle cx="24" cy="0" r="1.5" fill="currentColor" />
          <line x1="30" y1="0" x2="36" y2="0" strokeWidth="2" />
        </g>

        {/* 9. Wasm Bytecode Hexagon Node (y: 2860, x: 40, rotate 55) */}
        <g transform="translate(40, 2860) rotate(55)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <polygon points="0,-24 20,-12 20,12 0,24 -20,12 -20,-12" fill="#3b0764" fillOpacity="0.25" />
          <circle cx="0" cy="0" r="8" strokeDasharray="2 2" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.7">
            <text x="-12" y="3">WASM</text>
          </g>
        </g>

        {/* 10. Dipole Antenna Array (y: 3200, x: 115, rotate -38) */}
        <g transform="translate(115, 3200) rotate(-38)" stroke="url(#leftBioGrad)" strokeWidth="1.3">
          <line x1="-35" y1="0" x2="35" y2="0" strokeWidth="1.8" />
          <line x1="0" y1="0" x2="0" y2="45" />
          <circle cx="0" cy="0" r="3" fill="currentColor" />
          <path d="M -20,12 Q 0,22 20,12" strokeDasharray="2 2" opacity="0.6" />
          <path d="M -30,22 Q 0,36 30,22" strokeDasharray="2 2" opacity="0.4" />
        </g>

        {/* 11. Retro Audio Cassette Tape Spool (y: 3550, x: 55, rotate 22) */}
        <g transform="translate(55, 3550) rotate(22)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <rect x="-35" y="-22" width="70" height="44" rx="4" fill="#3b0764" fillOpacity="0.2" />
          <circle cx="-16" cy="0" r="8" />
          <circle cx="16" cy="0" r="8" />
          <line x1="-16" y1="8" x2="16" y2="8" strokeDasharray="2 2" />
        </g>

        {/* 12. Secondary Glider Fleet (y: 3900, x: 130, rotate -60) */}
        <g transform="translate(130, 3900) rotate(-60)" stroke="url(#leftBioGrad)" strokeWidth="1.1">
          <rect x="8" y="0" width="6" height="6" fill="#c084fc" fillOpacity="0.4" />
          <rect x="16" y="8" width="6" height="6" fill="#c084fc" fillOpacity="0.4" />
          <rect x="0" y="16" width="6" height="6" fill="#c084fc" fillOpacity="0.4" />
          <rect x="8" y="16" width="6" height="6" fill="#c084fc" fillOpacity="0.4" />
          <rect x="16" y="16" width="6" height="6" fill="#c084fc" fillOpacity="0.4" />
        </g>

        {/* 13. Hydraulic Servo Valve (y: 4250, x: 65, rotate 15) */}
        <g transform="translate(65, 4250) rotate(15)" stroke="url(#leftBioGrad)" strokeWidth="1.3">
          <rect x="-18" y="-18" width="36" height="36" rx="3" fill="#3b0764" fillOpacity="0.25" />
          <circle cx="0" cy="0" r="8" />
          <line x1="-28" y1="0" x2="-18" y2="0" strokeWidth="2" />
          <line x1="18" y1="0" x2="28" y2="0" strokeWidth="2" />
          <line x1="0" y1="-28" x2="0" y2="-18" strokeWidth="2" />
        </g>

        {/* 14. Transistor TO-92 (y: 4600, x: 125, rotate -25) */}
        <g transform="translate(125, 4600) rotate(-25)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <path d="M -14,0 A 14 14 0 0 1 14,0 Z" fill="#3b0764" fillOpacity="0.3" strokeWidth="1.5" />
          <line x1="-8" y1="0" x2="-8" y2="28" />
          <line x1="0" y1="0" x2="0" y2="32" />
          <line x1="8" y1="0" x2="8" y2="28" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
            <text x="18" y="12">2N3904</text>
          </g>
        </g>

        {/* 15. Orbital Radar Sweep Arc (y: 4950, x: 50, rotate 40) */}
        <g transform="translate(50, 4950) rotate(40)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="32" strokeDasharray="3 3" opacity="0.4" />
          <circle cx="0" cy="0" r="18" strokeDasharray="2 2" opacity="0.6" />
          <circle cx="0" cy="0" r="3" fill="currentColor" />
          <line x1="0" y1="0" x2="28" y2="-16" stroke="#4ade80" strokeWidth="1.8" />
        </g>

        {/* 16. Silicon Die Test Pads (y: 5300, x: 110, rotate -15) */}
        <g transform="translate(110, 5300) rotate(-15)" stroke="url(#leftBioGrad)" strokeWidth="1.1">
          <rect x="-24" y="-24" width="48" height="48" fill="#3b0764" fillOpacity="0.2" />
          <rect x="-18" y="-18" width="10" height="10" fill="currentColor" fillOpacity="0.4" />
          <rect x="8" y="-18" width="10" height="10" fill="currentColor" fillOpacity="0.4" />
          <rect x="-18" y="8" width="10" height="10" fill="currentColor" fillOpacity="0.4" />
          <rect x="8" y="8" width="10" height="10" fill="currentColor" fillOpacity="0.4" />
        </g>

        {/* 17. Fiber Optic Connector Ferrule (y: 5680, x: 45, rotate 30) */}
        <g transform="translate(45, 5680) rotate(30)" stroke="url(#leftBioGrad)" strokeWidth="1.3">
          <rect x="-8" y="-25" width="16" height="50" rx="3" fill="#3b0764" fillOpacity="0.3" />
          <circle cx="0" cy="0" r="2.5" fill="#4ade80" />
          <line x1="0" y1="-35" x2="0" y2="35" strokeDasharray="4 2" stroke="#4ade80" opacity="0.7" />
        </g>

        {/* 18. Repeating Sputnik Probe (y: 6050, x: 135, rotate -48) */}
        <g transform="translate(135, 6050) rotate(-48)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="9" fill="#3b0764" fillOpacity="0.3" />
          <line x1="-6" y1="-6" x2="-40" y2="-22" strokeWidth="1.1" />
          <line x1="-6" y1="6" x2="-44" y2="18" strokeWidth="1.1" />
          <line x1="6" y1="-6" x2="36" y2="-30" strokeWidth="1.0" strokeDasharray="2 1" opacity="0.6" />
        </g>

        {/* 19. Astrolabe Coordinate Ring (y: 6450, x: 60, rotate 18) */}
        <g transform="translate(60, 6450) rotate(18)" stroke="url(#leftBioGrad)" strokeWidth="1.1">
          <circle cx="0" cy="0" r="28" strokeDasharray="4 3" />
          <circle cx="0" cy="0" r="14" />
          <line x1="-32" y1="0" x2="32" y2="0" />
          <line x1="0" y1="-32" x2="0" y2="32" />
        </g>

        {/* 20. Glider Cruising to Footer (y: 6850, x: 120, rotate -35) */}
        <g transform="translate(120, 6850) rotate(-35)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
          <rect x="10" y="0" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="20" y="10" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="0" y="20" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="10" y="20" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
          <rect x="20" y="20" width="7" height="7" fill="#c084fc" fillOpacity="0.4" />
        </g>
      </svg>
    </div>

    {/* 3. DEDICATED RIGHT GUTTER STREAM (Scattered & Tilted across 7800px) */}
    <div className="absolute top-0 right-0 w-32 sm:w-44 md:w-52 lg:w-60 h-[7800px] pointer-events-none z-0 overflow-visible">
      <svg
        className="w-full h-full text-purple-400/40 dark:text-purple-300/35"
        viewBox="0 0 180 7800"
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

        {/* 1. Apollo 11 Lunar Module (y: 220, x: 120, rotate 14) */}
        <g transform="translate(120, 220) rotate(14)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <polygon points="7,0 23,0 30,7 30,20 23,27 7,27 0,20 0,7" fill="#3b0764" fillOpacity="0.3" />
          <path d="M 11,27 L 9,34 L 21,34 L 19,27 Z" fill="#581c87" fillOpacity="0.35" />
          <line x1="4" y1="21" x2="-10" y2="38" strokeWidth="1.3" />
          <ellipse cx="-10" cy="38" rx="3.5" ry="1.2" strokeWidth="1.1" />
          <line x1="26" y1="21" x2="40" y2="38" strokeWidth="1.3" />
          <ellipse cx="40" cy="38" rx="3.5" ry="1.2" strokeWidth="1.1" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6" transform="rotate(-14)">
            <text x="36" y="22">TRANQ-11</text>
          </g>
        </g>

        {/* 2. Voyager Golden Record Pulsar Map (y: 520, x: 50, rotate -32) */}
        <g transform="translate(50, 520) rotate(-32)" stroke="url(#rightBioGrad)" strokeWidth="1.0" opacity="0.65">
          <circle cx="0" cy="0" r="22" />
          <circle cx="0" cy="0" r="11" strokeDasharray="2 2" />
          <circle cx="0" cy="0" r="3" fill="currentColor" />
          <line x1="0" y1="0" x2="-18" y2="-9" />
          <line x1="0" y1="0" x2="16" y2="-12" />
          <line x1="0" y1="0" x2="-7" y2="18" />
          <line x1="0" y1="0" x2="14" y2="16" />
        </g>

        {/* 3. JWST 18-Hex Mirror Array (y: 840, x: 130, rotate 48) */}
        <g transform="translate(130, 840) rotate(48)" stroke="url(#rightBioGrad)" strokeWidth="1.1">
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

        {/* 4. Hollerith 80-Column Punched Card (y: 1160, x: 40, rotate -22) */}
        <g transform="translate(40, 1160) rotate(-22)" stroke="url(#rightBioGrad)" strokeWidth="1.1">
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

        {/* 5. Paperclip Wire Cable Retainer (y: 1480, x: 125, rotate 62) */}
        <g transform="translate(125, 1480) rotate(62)" stroke="url(#rightBioGrad)" strokeWidth="1.5">
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

        {/* 6. Saturnian Ringed Planet (y: 1800, x: 55, rotate -16) */}
        <g transform="translate(55, 1800) rotate(-16)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="34" fill="#4a044e" fillOpacity="0.25" />
          <ellipse cx="0" cy="0" rx="80" ry="24" strokeWidth="1.6" transform="rotate(-18)" />
          <ellipse cx="0" cy="0" rx="68" ry="19" strokeDasharray="4 3" transform="rotate(-18)" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.75">
            <text x="-20" y="48">OPS.RTA</text>
          </g>
        </g>

        {/* 7. Chrome 8-Bit Offline Dino Runner (y: 2140, x: 115, rotate 8) */}
        <g transform="translate(115, 2140) rotate(8)" stroke="none" fill="currentColor" opacity="0.6">
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

        {/* 8. HAL 9000 Eye Turret (y: 2480, x: 45, rotate -28) */}
        <g transform="translate(45, 2480) rotate(-28)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <rect x="-14" y="-22" width="28" height="44" rx="4" fill="#3b0764" fillOpacity="0.3" />
          <circle cx="0" cy="0" r="11" strokeWidth="1.5" />
          <circle cx="0" cy="0" r="6" fill="#ef4444" fillOpacity="0.8" stroke="#f87171" strokeWidth="1.1" />
          <circle cx="2" cy="-2" r="1.5" fill="#fff" opacity="0.9" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
            <text x="-12" y="30">HAL-9K</text>
          </g>
        </g>

        {/* 9. Bio-Mechanical Gear Drive (y: 2820, x: 130, rotate 45) */}
        <g transform="translate(130, 2820) rotate(45)" stroke="url(#rightBioGrad)" strokeWidth="1.3">
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

        {/* 10. Ferrite Core Memory Matrix (y: 3160, x: 60, rotate -50) */}
        <g transform="translate(60, 3160) rotate(-50)" stroke="url(#rightBioGrad)" strokeWidth="1.1">
          <rect x="-24" y="-24" width="48" height="48" fill="#3b0764" fillOpacity="0.2" />
          {[-12, 0, 12].map((gx) =>
            [-12, 0, 12].map((gy) => (
              <ellipse key={`${gx}-${gy}`} cx={gx} cy={gy} rx="4" ry="2" strokeWidth="1.2" transform={`rotate(45 ${gx} ${gy})`} />
            ))
          )}
          <line x1="-28" y1="-28" x2="28" y2="28" strokeDasharray="2 2" stroke="#4ade80" opacity="0.6" />
        </g>

        {/* 11. Shuttle Thermal Shield Tile Grid (y: 3500, x: 125, rotate 24) */}
        <g transform="translate(125, 3500) rotate(24)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <rect x="-28" y="-20" width="56" height="40" fill="#3b0764" fillOpacity="0.25" />
          <line x1="-28" y1="0" x2="28" y2="0" strokeWidth="1.4" />
          <line x1="0" y1="-20" x2="0" y2="20" strokeWidth="1.4" />
          <g fontFamily="monospace" fontSize="6" fill="currentColor" opacity="0.6">
            <text x="-22" y="-6">VT-04</text>
            <text x="6" y="14">VT-05</text>
          </g>
        </g>

        {/* 12. Lunar Rover Wireframe Chassis (y: 3850, x: 45, rotate -35) */}
        <g transform="translate(45, 3850) rotate(-35)" stroke="url(#rightBioGrad)" strokeWidth="1.3">
          <circle cx="-18" cy="12" r="9" strokeDasharray="2 2" />
          <circle cx="18" cy="12" r="9" strokeDasharray="2 2" />
          <line x1="-18" y1="12" x2="18" y2="12" strokeWidth="1.8" />
          <line x1="-10" y1="12" x2="0" y2="-8" />
          <line x1="10" y1="12" x2="0" y2="-8" />
          <line x1="0" y1="-8" x2="8" y2="-18" />
        </g>

        {/* 13. NE555 Timer IC Pinout (y: 4200, x: 120, rotate 52) */}
        <g transform="translate(120, 4200) rotate(52)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <rect x="-18" y="-25" width="36" height="50" rx="3" fill="#3b0764" fillOpacity="0.3" />
          <circle cx="0" cy="-25" r="4" fill="none" />
          {[-15, -5, 5, 15].map((py) => (
            <React.Fragment key={py}>
              <line x1="-26" y1={py} x2="-18" y2={py} strokeWidth="1.5" />
              <line x1="18" y1={py} x2="26" y2={py} strokeWidth="1.5" />
            </React.Fragment>
          ))}
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.7">
            <text x="-12" y="2">NE555</text>
          </g>
        </g>

        {/* 14. Solar Sail Rigging (y: 4550, x: 55, rotate -14) */}
        <g transform="translate(55, 4550) rotate(-14)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <polygon points="0,-35 35,0 0,35 -35,0" fill="#3b0764" fillOpacity="0.2" />
          <line x1="-35" y1="0" x2="35" y2="0" strokeWidth="1.6" />
          <line x1="0" y1="-35" x2="0" y2="35" strokeWidth="1.6" />
          <line x1="-25" y1="-25" x2="25" y2="25" strokeDasharray="2 2" opacity="0.5" />
        </g>

        {/* 15. CRT Oscilloscope Raster Sine Wave (y: 4900, x: 135, rotate 38) */}
        <g transform="translate(135, 4900) rotate(38)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="28" fill="#3b0764" fillOpacity="0.25" />
          <path d="M -22,0 Q -11,-16 0,0 Q 11,16 22,0" stroke="#4ade80" strokeWidth="1.8" />
        </g>

        {/* 16. Radio Telescope Parabolic Array (y: 5260, x: 50, rotate -42) */}
        <g transform="translate(50, 5260) rotate(-42)" stroke="url(#rightBioGrad)" strokeWidth="1.3">
          <path d="M -25,18 Q 0,-15 25,18" strokeWidth="2.0" />
          <line x1="0" y1="0" x2="0" y2="-22" strokeWidth="1.5" />
          <circle cx="0" cy="-22" r="2.5" fill="currentColor" />
          <line x1="-8" y1="18" x2="0" y2="32" />
          <line x1="8" y1="18" x2="0" y2="32" />
        </g>

        {/* 17. Resistor Color Band Code (y: 5640, x: 125, rotate 16) */}
        <g transform="translate(125, 5640) rotate(16)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <line x1="-35" y1="0" x2="35" y2="0" strokeWidth="1.6" />
          <rect x="-18" y="-7" width="36" height="14" rx="4" fill="#3b0764" fillOpacity="0.3" />
          <line x1="-9" y1="-7" x2="-9" y2="7" stroke="#fbbf24" strokeWidth="2" />
          <line x1="-3" y1="-7" x2="-3" y2="7" stroke="#c084fc" strokeWidth="2" />
          <line x1="3" y1="-7" x2="3" y2="7" stroke="#ef4444" strokeWidth="2" />
          <line x1="10" y1="-7" x2="10" y2="7" stroke="#fbbf24" strokeWidth="1.5" strokeDasharray="1 1" />
        </g>

        {/* 18. Secondary Apollo Module on Perimeter (y: 6020, x: 60, rotate -30) */}
        <g transform="translate(60, 6020) rotate(-30)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
          <polygon points="5,0 17,0 22,5 22,15 17,20 5,20 0,15 0,5" fill="#3b0764" fillOpacity="0.3" />
          <line x1="3" y1="15" x2="-8" y2="28" strokeWidth="1.2" />
          <line x1="19" y1="15" x2="30" y2="28" strokeWidth="1.2" />
        </g>

        {/* 19. Repeating Clippy Conduit Retainer (y: 6420, x: 130, rotate 65) */}
        <g transform="translate(130, 6420) rotate(65)" stroke="url(#rightBioGrad)" strokeWidth="1.4">
          <path
            d="M 8,32 L 8,10 C 8,4 20,4 20,10 L 20,35 C 20,44 4,44 4,35 L 4,15 C 4,9 14,9 14,15 L 14,32"
            fill="none"
            strokeLinecap="round"
          />
        </g>

        {/* 20. Hydrogen Spin Transition Symbol (y: 6820, x: 70, rotate -12) */}
        <g transform="translate(70, 6820) rotate(-12)" stroke="url(#rightBioGrad)" strokeWidth="1.1" opacity="0.7">
          <circle cx="-16" cy="0" r="7" />
          <circle cx="16" cy="0" r="7" />
          <line x1="-9" y1="0" x2="9" y2="0" />
          <line x1="-16" y1="-7" x2="-16" y2="-12" strokeWidth="1.5" />
          <line x1="16" y1="7" x2="16" y2="12" strokeWidth="1.5" />
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor">
            <text x="28" y="3">1420-MHZ</text>
          </g>
        </g>
      </svg>
    </div>
  </div>
);
