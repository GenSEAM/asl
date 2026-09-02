import React from 'react';

/**
 * CosmicLandscapeBackground
 * Comprehensive multi-screen technical blueprint canvas celebrating the Industrial Cosmos & Cyber-Canopy:
 * 1. Fixed schematic chameleon mascot perched directly on an integrated cyber-vine branch in the top-left.
 * 2. Grand Industrial Cosmos at the top:
 *    - Prominent Satellite Probe 1 with multi-cell solar arrays, dish, and radio signal waves.
 *    - Deep-Space Satellite 2 with angled solar wings and telemetry mesh links.
 *    - Deep-space constellations with star crosshairs, drafting arcs, and Greek-letter coordinate nodes.
 *    - Architectural Monstera canopy foliage and tropical palm fronds along the right margin.
 * 3. Planetary Scanner Port & Saturnian Ringed Planet (OPS.RTA) in the mid-range.
 * 4. Bio-Mechanical Gear Drive (ШЕСТЕРЕНЧАТЫЙ ПРИВОД) and root conduits in the lower section.
 * 5. Veiled, uncaptioned Easter eggs scattered naturally across the blueprint:
 *    - Perforated 80-column optical calibration mask (Hollerith punch card) tilted in upper orbit.
 *    - Inline glass-dome miniature vacuum triode amplifying the satellite downlink feed.
 *    - 3.5" avionics ROM cartridge tilted along the hydraulic conduit bus.
 *    - Structural wire retaining bracket shaped like a paperclip holding cable conduits together.
 */
export const CosmicLandscapeBackground: React.FC = () => (
  <div className="pointer-events-none select-none" aria-hidden="true">
    {/* 1. Fixed Viewport Elements: Ambient Lighting Glow & Perched Chameleon on Cyber-Vine */}
    <div className="fixed inset-0 pointer-events-none overflow-hidden z-0">
      {/* Atmospheric bioluminescent lighting auras */}
      <div className="absolute top-8 left-6 w-[550px] h-[550px] bg-purple-600/15 dark:bg-purple-900/25 blur-[150px] rounded-full" />
      <div className="absolute top-1/4 right-8 w-[650px] h-[650px] bg-indigo-600/12 dark:bg-indigo-950/20 blur-[160px] rounded-full" />
      <div className="absolute bottom-16 left-1/4 w-[700px] h-[550px] bg-purple-900/15 blur-[160px] rounded-full" />

      {/* 
        Fixed Schematic Chameleon PERCHED DIRECTLY ON CYBER-VINE (Top-Left)
        Integrated SVG ensures the branch always runs directly under the chameleon's paws and belly,
        curling out from the screen edge and leading smoothly towards the right.
      */}
      <div className="fixed top-16 sm:top-20 left-2 sm:left-6 lg:left-10 w-72 sm:w-84 lg:w-[420px] h-auto opacity-35 dark:opacity-40 transition-all z-10">
        <svg
          viewBox="0 0 240 160"
          className="w-full h-auto text-signal overflow-visible"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <defs>
            <linearGradient id="vineBranchGrad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#c084fc" />
              <stop offset="60%" stopColor="#a855f7" />
              <stop offset="100%" stopColor="#7e22ce" />
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
              THE CYBER-VINE BRANCH (Physical perch under the chameleon):
              Starts from off-screen left at y=108, passes right under feet and tail,
              then extends out to the right with sprouts and leaf nodes.
            */}
            <path
              d="M -30,108 C 20,104 60,112 105,108 C 145,104 185,116 230,110 C 270,105 310,120 360,114"
              stroke="url(#vineBranchGrad)"
              strokeWidth="3.2"
              strokeLinecap="round"
            />
            <path
              d="M -30,113 C 20,109 60,117 105,113 C 145,109 185,121 230,115"
              stroke="url(#vineBranchGrad)"
              strokeWidth="1.2"
              strokeDasharray="3 3"
              opacity="0.6"
            />

            {/* Small Sprouting Cyber-Leaves along the vine */}
            <g transform="translate(140, 108) rotate(20)">
              <path d="M 0,0 Q 15,-10 30,0 Q 15,10 0,0" fill="#a855f7" fillOpacity="0.2" stroke="url(#vineBranchGrad)" strokeWidth="1.2" />
              <line x1="0" y1="0" x2="30" y2="0" stroke="url(#vineBranchGrad)" strokeWidth="0.8" />
            </g>
            <g transform="translate(195, 112) rotate(-15)">
              <path d="M 0,0 Q 14,-8 26,0 Q 14,8 0,0" fill="#a855f7" fillOpacity="0.2" stroke="url(#vineBranchGrad)" strokeWidth="1.2" />
              <line x1="0" y1="0" x2="26" y2="0" stroke="url(#vineBranchGrad)" strokeWidth="0.8" />
            </g>
            {/* Spiral Tendril on Branch */}
            <path
              d="M 230,110 Q 245,125 240,135 Q 235,142 225,140 Q 220,135 225,130"
              stroke="url(#vineBranchGrad)"
              strokeWidth="1.4"
            />

            {/* Technical Perch Annotation */}
            <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.85">
              <text x="5" y="128">КИБЕР-ЛИАНА // ПЕРХ-01</text>
              <line x1="0" y1="120" x2="75" y2="120" stroke="currentColor" strokeWidth="0.6" strokeDasharray="2 2" />
            </g>

            {/* 
              THE SCHEMATIC CHAMELEON (Scale 1:1 onto the perch):
              Positioned so paws grasp the branch at y=108 and tail curls gracefully around it.
            */}
            <g transform="translate(5, 0)">
              {/* Spine and Tail Curl */}
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
              {/* Eye Circular Aperture */}
              <circle cx="82" cy="40" r="9" stroke="url(#chameleonGradFixed)" strokeWidth="2.2" />
              <circle cx="82" cy="40" r="3" fill="rgb(var(--signal-soft))" opacity="0.9" />

              {/* Belly & Underside Line */}
              <path
                d="M 68 64 
                   C 52 64, 40 68, 32 78 
                   C 25 87, 26 96, 30 102"
                stroke="url(#chameleonGradFixed)"
                strokeWidth="1.8"
                strokeLinecap="round"
              />

              {/* Blueprint coordinate nodes */}
              <circle cx="53" cy="14" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.7" />
              <circle cx="98" cy="52" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.7" />
              <circle cx="38" cy="122" r="1.5" fill="rgb(var(--signal-soft))" opacity="0.7" />
            </g>
          </g>
        </svg>
      </div>
    </div>

    {/* 2. Full-Document Scrolling Blueprint Landscape (Multi-Screen Continuous Canvas) */}
    <div className="absolute inset-0 w-full h-full pointer-events-none overflow-hidden z-0">
      <svg
        className="w-full h-full text-purple-400/35 dark:text-purple-300/30"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 1440 3200"
        preserveAspectRatio="xMidYMin slice"
        fill="none"
      >
        <defs>
          {/* Blueprint Millimetric Grid Pattern */}
          <pattern id="blueprintGridPattern" width="40" height="40" patternUnits="userSpaceOnUse">
            <path d="M 40 0 L 0 0 0 40" fill="none" stroke="currentColor" strokeWidth="0.5" opacity="0.35" />
            <path d="M 200 0 L 0 0 0 200" fill="none" stroke="currentColor" strokeWidth="1.0" opacity="0.55" />
          </pattern>

          {/* Line Gradients */}
          <linearGradient id="bioLineGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#c084fc" stopOpacity="0.75" />
            <stop offset="60%" stopColor="#a855f7" stopOpacity="0.5" />
            <stop offset="100%" stopColor="#7e22ce" stopOpacity="0.3" />
          </linearGradient>

          <linearGradient id="leafFacetGrad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stopColor="#a855f7" stopOpacity="0.18" />
            <stop offset="100%" stopColor="#581c87" stopOpacity="0.05" />
          </linearGradient>

          <linearGradient id="amberGlow" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#fbbf24" stopOpacity="0.7" />
            <stop offset="100%" stopColor="#d97706" stopOpacity="0.3" />
          </linearGradient>
        </defs>

        {/* Technical Blueprint Grid Base */}
        <rect width="100%" height="100%" fill="url(#blueprintGridPattern)" />

        {/* ========================================================================= */}
        {/* SCREEN 1: THE GRAND INDUSTRIAL COSMOS & CYBER-CANOPY (y: 0 - 1000)        */}
        {/* ========================================================================= */}

        {/* 1. INDUSTRIAL SATELLITE PROBE 1 (Upper Left-Center, x: 380, y: 190, rotate -25) */}
        <g transform="translate(380, 190) rotate(-25)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          {/* Central Satellite Chassis */}
          <rect x="-20" y="-35" width="40" height="70" rx="4" fill="#3b0764" fillOpacity="0.25" />
          <line x1="-20" y1="-15" x2="20" y2="-15" strokeDasharray="3 3" />
          <line x1="-20" y1="15" x2="20" y2="15" strokeDasharray="3 3" />
          <circle cx="0" cy="0" r="10" strokeDasharray="2 2" />

          {/* Large Solar Array Wing Left (3 segmented cells) */}
          <rect x="-95" y="-18" width="70" height="36" fill="#581c87" fillOpacity="0.3" />
          <line x1="-72" y1="-18" x2="-72" y2="18" />
          <line x1="-49" y1="-18" x2="-49" y2="18" />
          <line x1="-95" y1="0" x2="-25" y2="0" strokeDasharray="2 2" />

          {/* Large Solar Array Wing Right (3 segmented cells) */}
          <rect x="25" y="-18" width="70" height="36" fill="#581c87" fillOpacity="0.3" />
          <line x1="48" y1="-18" x2="48" y2="18" />
          <line x1="71" y1="-18" x2="71" y2="18" />
          <line x1="25" y1="0" x2="95" y2="0" strokeDasharray="2 2" />

          {/* Parabolic Antenna Dish with Feed Horn */}
          <path d="M 0,35 Q -18,58 0,68 Q 18,58 0,35" strokeWidth="1.8" />
          <line x1="0" y1="68" x2="0" y2="82" strokeWidth="2" />
          <circle cx="0" cy="82" r="3" fill="currentColor" />

          {/* Radio Signal Wave Fronts */}
          <path d="M -16,92 Q 0,105 16,92" strokeDasharray="3 3" opacity="0.8" />
          <path d="M -26,104 Q 0,122 26,104" strokeDasharray="3 3" opacity="0.6" />
          <path d="M -36,116 Q 0,138 36,116" strokeDasharray="3 3" opacity="0.4" />

          {/* Technical Leader Callout */}
          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.9" transform="rotate(25)">
            <text x="85" y="-20">САТЕЛЛИТ-1 // Ku-BAND</text>
            <line x1="15" y1="-23" x2="80" y2="-23" stroke="currentColor" strokeWidth="0.8" />
            <text x="85" y="-8" fill="#4ade80">(! mesh/ping "sat-01" 40)</text>
          </g>
        </g>

        {/* 
          VEILED EASTER EGG 1: Glass Vacuum Triode (Inline RF Preamplifier)
          Tilted -20° and wired directly into the satellite antenna downlink.
        */}
        <g transform="translate(530, 310) rotate(-20)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          {/* Glass Dome Envelope */}
          <path d="M 0,55 L 0,25 C 0,8 36,8 36,25 L 36,55 Z" fill="#4a044e" fillOpacity="0.2" />
          {/* Anode Plate */}
          <line x1="9" y1="20" x2="27" y2="20" strokeWidth="1.8" />
          <line x1="18" y1="8" x2="18" y2="20" />
          {/* Zig-Zag Grid */}
          <path d="M 11,30 L 14,33 L 18,30 L 21,33 L 25,30" strokeWidth="1.2" strokeDasharray="1 1" />
          {/* Glowing Heater Cathode */}
          <path d="M 13,40 L 23,40" stroke="url(#amberGlow)" strokeWidth="1.8" />
          <path d="M 16,46 L 18,42 L 20,46" stroke="url(#amberGlow)" strokeWidth="1.2" />
          {/* Pin leads connecting to coaxial bus */}
          <line x1="8" y1="55" x2="8" y2="65" />
          <line x1="18" y1="55" x2="18" y2="68" />
          <line x1="28" y1="55" x2="28" y2="65" />
          <line x1="18" y1="68" x2="-40" y2="68" strokeDasharray="2 2" />
          <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.75">
            <text x="42" y="32">AMP: V-12 // 6.3V</text>
          </g>
        </g>

        {/* 2. CENTRAL INDUSTRIAL SATELLITE RELAY (Upper Right-Center, x: 920, y: 320, rotate 35) */}
        <g transform="translate(920, 320) rotate(35)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          <rect x="-25" y="-30" width="50" height="60" rx="4" fill="#3b0764" fillOpacity="0.25" />
          <circle cx="0" cy="0" r="14" strokeWidth="1.8" />
          <circle cx="0" cy="0" r="5" fill="currentColor" />

          {/* Extended Solar Panels */}
          <rect x="-110" y="-16" width="80" height="32" fill="#581c87" fillOpacity="0.3" />
          <line x1="-84" y1="-16" x2="-84" y2="16" />
          <line x1="-58" y1="-16" x2="-58" y2="16" />

          <rect x="30" y="-16" width="80" height="32" fill="#581c87" fillOpacity="0.3" />
          <line x1="56" y1="-16" x2="56" y2="16" />
          <line x1="82" y1="-16" x2="82" y2="16" />

          {/* High-Gain Dish */}
          <path d="M 0,30 Q -20,52 0,62 Q 20,52 0,30" strokeWidth="1.8" />
          <line x1="0" y1="62" x2="0" y2="76" strokeWidth="2" />
          <circle cx="0" cy="76" r="3.5" fill="currentColor" />

          {/* Concentric Telemetry Radio Arcs */}
          <path d="M 14,84 Q 28,96 20,112" strokeDasharray="3 3" opacity="0.8" />
          <path d="M 22,80 Q 40,94 32,120" strokeDasharray="3 3" opacity="0.6" />

          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.9" transform="rotate(-35)">
            <text x="35" y="-45">ОРБИТАЛЬНЫЙ РЕЛЕЙ</text>
            <line x1="0" y1="-48" x2="30" y2="-48" stroke="currentColor" strokeWidth="0.8" />
            <text x="35" y="-32" fill="#c084fc">СВЯЗЬ: 0.038ms // MESH</text>
          </g>
        </g>

        {/* 
          VEILED EASTER EGG 2: Perforated Calibration Mask (Hollerith 80-Column Card)
          Tilted 22° in deep space, woven into orbit telemetry grid without loud caption.
        */}
        <g transform="translate(680, 110) rotate(22)" stroke="url(#bioLineGrad)" strokeWidth="1.1">
          {/* Outline with the unmistakable diagonal corner notch */}
          <polygon
            points="12,0 145,0 145,72 0,72 0,12"
            fill="#3b0764"
            fillOpacity="0.2"
          />
          <line x1="0" y1="14" x2="145" y2="14" strokeWidth="0.6" opacity="0.6" />
          {/* Subtle punched rectangular apertures */}
          <g fill="currentColor" opacity="0.85">
            <rect x="16" y="22" width="2.5" height="5" />
            <rect x="16" y="38" width="2.5" height="5" />
            <rect x="28" y="30" width="2.5" height="5" />
            <rect x="42" y="22" width="2.5" height="5" />
            <rect x="42" y="46" width="2.5" height="5" />
            <rect x="58" y="54" width="2.5" height="5" />
            <rect x="74" y="30" width="2.5" height="5" />
            <rect x="90" y="22" width="2.5" height="5" />
            <rect x="90" y="60" width="2.5" height="5" />
            <rect x="106" y="38" width="2.5" height="5" />
            <rect x="122" y="46" width="2.5" height="5" />
            <rect x="134" y="30" width="2.5" height="5" />
          </g>
          {/* Cryptic engineering mark */}
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.7">
            <text x="14" y="10">MASK-80 // CAL-A</text>
          </g>
        </g>

        {/* 3. DEEP-SPACE CONSTELLATIONS ALPHA & BETA (Upper Skies) */}
        <g stroke="currentColor" strokeWidth="1.2" opacity="0.75" transform="translate(180, 60)">
          {/* Alpha Web */}
          <line x1="220" y1="90" x2="340" y2="50" />
          <line x1="340" y1="50" x2="390" y2="20" />
          <line x1="340" y1="50" x2="300" y2="150" />
          <line x1="300" y1="150" x2="380" y2="170" />
          <line x1="380" y1="170" x2="430" y2="130" />
          <line x1="300" y1="150" x2="340" y2="230" />

          {/* Precision Star Crosshairs */}
          <g fill="currentColor">
            <path d="M 216,90 H 224 M 220,86 V 94" />
            <path d="M 336,50 H 344 M 340,46 V 54" />
            <path d="M 386,20 H 394 M 390,16 V 24" />
            <path d="M 296,150 H 304 M 300,146 V 154" />
            <path d="M 376,170 H 384 M 380,166 V 174" />
            <path d="M 426,130 H 434 M 430,126 V 134" />
            <path d="M 336,230 H 344 M 340,226 V 234" />
          </g>

          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.8">
            <text x="348" y="56">α-ASL</text>
            <text x="398" y="26">β-COORD</text>
            <text x="290" y="162">γ-WASM</text>
            <text x="388" y="178">δ-SWARM</text>
          </g>
        </g>

        {/* 
          VEILED EASTER EGG 5: Sputnik-1 (First Artificial Satellite, 1957)
          Polished sphere with 4 swept whip antennas, traversing upper cosmic vacuum.
        */}
        <g transform="translate(340, 470) rotate(-42)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          {/* Spherical Body */}
          <circle cx="0" cy="0" r="12" fill="#3b0764" fillOpacity="0.3" strokeWidth="1.6" />
          <ellipse cx="0" cy="0" rx="12" ry="4" strokeDasharray="2 2" opacity="0.6" />
          
          {/* 4 Swept Whip Antennas (Pair 1 and Pair 2) */}
          <line x1="-8" y1="-8" x2="-60" y2="-36" strokeWidth="1.3" />
          <line x1="-8" y1="8" x2="-64" y2="28" strokeWidth="1.3" />
          <line x1="8" y1="-8" x2="52" y2="-44" strokeWidth="1.1" strokeDasharray="3 1" opacity="0.7" />
          <line x1="8" y1="8" x2="58" y2="34" strokeWidth="1.1" strokeDasharray="3 1" opacity="0.7" />

          {/* Spherical Pulse Waves */}
          <circle cx="0" cy="0" r="22" strokeDasharray="2 3" opacity="0.5" />
          <circle cx="0" cy="0" r="34" strokeDasharray="1 4" opacity="0.3" />

          {/* Cryptic Frequency Mark */}
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.7" transform="rotate(42)">
            <text x="18" y="-14">PS-01 // 20.005 MHz</text>
          </g>
        </g>

        {/* 4. UPPER-RIGHT CYBER-MONSTERA CANOPY (Natural, uncrowded architectural foliage) */}
        <g transform="translate(1080, 0)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          {/* Graceful Canopy Arch */}
          <path d="M 360,0 C 280,60 220,150 240,260 C 260,370 340,430 360,540" fill="none" />
          <path d="M 375,0 C 295,65 235,155 255,265 C 275,375 355,435 375,545" strokeDasharray="4 4" opacity="0.5" fill="none" />

          {/* Large Architectural Monstera Leaf with Precision Cutouts */}
          <g transform="translate(180, 60) rotate(-15)">
            <path
              d="M 0,0 C 50,-70 130,-80 170,-30 C 200,20 190,90 150,140 C 110,180 30,170 -10,120 C -40,80 -30,30 0,0 Z"
              fill="url(#leafFacetGrad)"
            />
            {/* Fenestrations / Cutouts */}
            <ellipse cx="60" cy="-15" rx="15" ry="6" transform="rotate(-30 60 -15)" />
            <ellipse cx="105" cy="20" rx="18" ry="7" transform="rotate(-15 105 20)" />
            <ellipse cx="95" cy="75" rx="16" ry="6" transform="rotate(20 95 75)" />
            <ellipse cx="45" cy="95" rx="14" ry="5" transform="rotate(45 45 95)" />
            <line x1="0" y1="0" x2="150" y2="140" strokeWidth="2.2" />
          </g>

          {/* Tropical Palm Fronds Fan */}
          <g transform="translate(80, 160) rotate(35)">
            <path d="M 0,0 Q 60,-35 150,-15 Q 80,20 0,0" fill="url(#leafFacetGrad)" />
            <path d="M 0,0 Q 75,-15 165,15 Q 90,40 0,0" fill="url(#leafFacetGrad)" />
            <path d="M 0,0 Q 60,10 145,50 Q 70,55 0,0" fill="url(#leafFacetGrad)" />
          </g>

          {/* Chameleon Palm Mark */}
          <g transform="translate(40, 320) rotate(-20)" strokeWidth="1.5">
            <path d="M 0,0 C 15,-20 30,-15 25,10 C 20,30 5,35 0,0" fill="url(#leafFacetGrad)" />
            <path d="M -15,-10 C -5,-30 10,-25 5,-5" fill="url(#leafFacetGrad)" />
            <path d="M 20,-5 C 35,-25 50,-15 35,5" fill="url(#leafFacetGrad)" />
            <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.85">
              <text x="35" y="10">БИО-КОМПОНЕНТ</text>
              <line x1="0" y1="15" x2="30" y2="15" stroke="currentColor" strokeWidth="0.8" />
            </g>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* SCREEN 2: MID SCANNER DOME & PLANETARY VORTEX (y: 1000 - 2100)            */}
        {/* ========================================================================= */}

        {/* Planetary Scanner Station Dome (Left Margin, x: 80, y: 1380) */}
        <g transform="translate(80, 1380)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          <circle cx="0" cy="0" r="140" strokeDasharray="8 6" opacity="0.4" />
          <circle cx="0" cy="0" r="110" strokeDasharray="4 4" opacity="0.6" />
          <circle cx="0" cy="0" r="80" strokeWidth="2" />

          {/* Hemisphere Dome */}
          <path d="M -70,-25 A 75 75 0 0 1 70,-25" strokeWidth="2.5" fill="#3b0764" fillOpacity="0.2" />
          <line x1="-70" y1="-25" x2="70" y2="-25" />

          {/* Optical Scanner Head */}
          <path d="M -30,-25 L -16,-65 L 16,-65 L 30,-25 Z" strokeWidth="2" fill="#581c87" fillOpacity="0.3" />
          <line x1="0" y1="-65" x2="0" y2="-100" strokeWidth="2.5" />
          <circle cx="0" cy="-100" r="4" fill="currentColor" />

          {/* Hydraulic Conduits */}
          <path d="M -50,15 L -100,65 L -120,130" strokeWidth="3" />
          <path d="M -30,25 L -75,90 L -85,150" strokeWidth="2" strokeDasharray="4 4" />

          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.9">
            <text x="65" y="-50">ПЛАНЕТАРНЫЙ ПОРТ</text>
            <line x1="20" y1="-55" x2="60" y2="-55" stroke="currentColor" strokeWidth="0.8" />
            <text x="-35" y="15" transform="rotate(45 -35 15)">ПОРТ А</text>
            <text x="55" y="105" fill="#4ade80">WASM REACTOR // 0.038ms</text>
            <text x="55" y="118" fill="#c084fc">(dfs WasmNode (:f id Str) (:f ms F64))</text>
          </g>
        </g>

        {/* 
          VEILED EASTER EGG 3: 3.5" Avionics Memory Cartridge (Floppy Disk)
          Tilted -34° near hydraulic bus, looking like a modular avionics sub-unit.
        */}
        <g transform="translate(180, 1680) rotate(-34)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          {/* Chassis with bevel corner */}
          <polygon
            points="0,0 75,0 82,7 82,88 0,88"
            fill="#3b0764"
            fillOpacity="0.25"
          />
          {/* Metal Shutter Slider with Rectangular Read Window */}
          <rect x="15" y="0" width="40" height="32" rx="2" fill="#581c87" fillOpacity="0.35" />
          <rect x="22" y="6" width="8" height="20" rx="1" fill="currentColor" fillOpacity="0.8" />
          {/* Center Drive Hub */}
          <circle cx="41" cy="54" r="14" strokeDasharray="2 2" opacity="0.6" />
          <circle cx="41" cy="54" r="5" fill="currentColor" opacity="0.5" />
          {/* Write-protect slider notch */}
          <rect x="71" y="77" width="6" height="5" fill="currentColor" opacity="0.8" />
          {/* Cryptic technical part mark */}
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.75">
            <text x="12" y="78">ROM-144 // ASL</text>
          </g>
        </g>

        {/* Saturnian Ringed Planet (OPS.RTA) in Right Margin (x: 1240, y: 1440) */}
        <g transform="translate(1240, 1440)" stroke="url(#bioLineGrad)" strokeWidth="1.3">
          <circle cx="0" cy="0" r="50" fill="#4a044e" fillOpacity="0.3" />
          <path d="M -40,-12 Q 0,-25 40,-12" strokeDasharray="2 3" opacity="0.6" />
          <path d="M -45,8 Q 0,-5 45,8" strokeDasharray="2 3" opacity="0.6" />

          <ellipse cx="0" cy="0" rx="120" ry="36" strokeWidth="2" transform="rotate(-18)" />
          <ellipse cx="0" cy="0" rx="105" ry="30" strokeDasharray="6 4" transform="rotate(-18)" />
          <ellipse cx="0" cy="0" rx="90" ry="25" strokeDasharray="3 3" transform="rotate(-18)" />

          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.85">
            <rect x="-35" y="65" width="70" height="18" stroke="currentColor" strokeWidth="0.8" rx="3" fill="#3b0764" fillOpacity="0.3" />
            <text x="-25" y="78">OPS.RTA</text>
          </g>
        </g>

        {/* 
          VEILED EASTER EGG 6: Lunar Module Descent Stage (1969 Apollo 11 "Eagle")
          Tilted 14° resting gracefully along the orbital station perimeter ring.
        */}
        <g transform="translate(1060, 1460) rotate(14)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          {/* Octagonal Descent Stage Chassis */}
          <polygon
            points="8,0 26,0 34,8 34,22 26,30 8,30 0,22 0,8"
            fill="#3b0764"
            fillOpacity="0.35"
          />
          {/* Central Descent Engine Bell */}
          <path d="M 13,30 L 11,38 L 23,38 L 21,30 Z" fill="#581c87" fillOpacity="0.4" />
          
          {/* Outrigger Landing Struts & Footpads */}
          <line x1="4" y1="24" x2="-12" y2="42" strokeWidth="1.4" />
          <ellipse cx="-12" cy="42" rx="4" ry="1.5" strokeWidth="1.2" />
          
          <line x1="30" y1="24" x2="46" y2="42" strokeWidth="1.4" />
          <ellipse cx="46" cy="42" rx="4" ry="1.5" strokeWidth="1.2" />
          
          {/* Miniature Egress Ladder on Forward Strut */}
          <line x1="-8" y1="28" x2="-6" y2="29" strokeWidth="0.8" />
          <line x1="-10" y1="33" x2="-8" y2="34" strokeWidth="0.8" />
          <line x1="-12" y1="38" x2="-10" y2="39" strokeWidth="0.8" />

          {/* Cryptic Site Callout */}
          <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.75" transform="rotate(-14)">
            <text x="42" y="24">SITE: TRANQ-11</text>
          </g>
        </g>

        {/* Cable Bundles and Sensor Terminals (Right Margin, x: 1140, y: 1680) */}
        <g transform="translate(1140, 1680)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          <path d="M 0,0 C 40,30 80,20 120,70" strokeWidth="2" />
          <path d="M 20,-10 C 60,10 90,40 140,50" />
          <path d="M 40,-20 C 70,-10 110,10 160,20" />
          <circle cx="120" cy="70" r="4" fill="currentColor" />
          <circle cx="140" cy="50" r="4" fill="currentColor" />
          <circle cx="160" cy="20" r="4" fill="currentColor" />

          {/* 
            VEILED EASTER EGG 4: The Paperclip Wire Retainer
            Tilted 58° clipping the two hydraulic cable conduits together!
            No loud signs: just an authentic curved wire bracket that engineers spot.
          */}
          <g transform="translate(55, 20) rotate(58)" stroke="url(#bioLineGrad)" strokeWidth="1.6">
            <path
              d="M 12,42 L 12,15 C 12,6 27,6 27,15 L 27,48 C 27,60 6,60 6,48 L 6,21 C 6,13 20,13 20,21 L 20,42"
              fill="none"
              strokeLinecap="round"
            />
            <circle cx="16" cy="30" r="22" strokeDasharray="3 2" opacity="0.4" strokeWidth="0.8" />
            <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.7">
              <text x="32" y="32">CLIP-MAX</text>
            </g>
          </g>

          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.85">
            <text x="-40" y="30">ДАТЧИК-1</text>
            <text x="130" y="10">ПОРТ-А</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* SCREEN 3: LOWER BLUEPRINT MATRIX & BIO-MECHANICAL GEARS (y: 2100 - 3200)  */}
        {/* ========================================================================= */}

        {/* Token Fuel Gauge Callout (Left Margin, x: 70, y: 2240) */}
        <g transform="translate(70, 2240)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <circle cx="45" cy="45" r="40" strokeDasharray="4 3" opacity="0.6" />
          <path d="M 45,45 L 68,24" stroke="#4ade80" strokeWidth="2.2" />
          <circle cx="45" cy="45" r="4" fill="#4ade80" />
          
          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.9">
            <text x="100" y="32" fontWeight="bold" fill="#c084fc">GAUGE: TOKEN FUEL</text>
            <text x="100" y="46" fill="#4ade80">ASL SAVINGS: -80% BLOAT</text>
            <text x="100" y="60">COGNITIVE LOAD: 0.00%</text>
            <line x1="85" y1="38" x2="96" y2="38" stroke="currentColor" strokeWidth="0.8" />
          </g>
        </g>

        {/* Extended Constellation Gamma (Lower Left, x: 50, y: 2460) */}
        <g stroke="currentColor" strokeWidth="1.2" opacity="0.65" transform="translate(50, 2460)">
          <line x1="60" y1="60" x2="160" y2="30" />
          <line x1="160" y1="30" x2="240" y2="80" />
          <line x1="160" y1="30" x2="140" y2="130" />
          <line x1="240" y1="80" x2="310" y2="50" />
          <line x1="140" y1="130" x2="210" y2="180" />

          <path d="M 56,60 H 64 M 60,56 V 64" />
          <path d="M 156,30 H 164 M 160,26 V 34" />
          <path d="M 236,80 H 244 M 240,76 V 84" />
          <path d="M 136,130 H 144 M 140,126 V 134" />
          <path d="M 306,50 H 314 M 310,46 V 54" />
          <path d="M 206,180 H 214 M 210,176 V 184" />

          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.75">
            <text x="165" y="35">G</text>
            <text x="245" y="85">B</text>
            <text x="315" y="55">A</text>
            <text x="130" y="140">B</text>
          </g>
        </g>

        {/* Lower Right Cyber-Canopy Roots & Bio-Mechanical Gears (x: 1140, y: 2450) */}
        <g transform="translate(1140, 2450)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          <path d="M 200,0 C 120,80 40,160 80,260 C 120,360 220,440 260,540" fill="none" />
          <path d="M 220,0 C 140,85 60,165 100,265 C 140,365 240,445 280,545" strokeDasharray="4 6" fill="none" opacity="0.5" />

          {/* Tropical Fan Leaves */}
          <g transform="translate(60, 160) rotate(-45)">
            <polygon points="0,0 80,-40 180,-30 90,10" fill="url(#leafFacetGrad)" />
            <polygon points="0,0 90,10 190,40 75,45" fill="url(#leafFacetGrad)" />
            <polygon points="0,0 75,45 160,95 50,70" fill="url(#leafFacetGrad)" />
          </g>

          {/* Bio-Mechanical Gear Drive */}
          <g transform="translate(120, 360)">
            <circle cx="0" cy="0" r="50" strokeDasharray="5 4" fill="#3b0764" fillOpacity="0.25" />
            <circle cx="0" cy="0" r="20" />
            {[0, 45, 90, 135, 180, 225, 270, 315].map((deg) => (
              <line
                key={deg}
                x1={Math.cos((deg * Math.PI) / 180) * 50}
                y1={Math.sin((deg * Math.PI) / 180) * 50}
                x2={Math.cos((deg * Math.PI) / 180) * 62}
                y2={Math.sin((deg * Math.PI) / 180) * 62}
                strokeWidth="3"
              />
            ))}
            <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.8">
              <text x="-35" y="80">ШЕСТЕРЕНЧАТЫЙ БЛОК</text>
              <text x="-35" y="92" fill="#4ade80">(mt state ((:on) (! run)))</text>
            </g>
          </g>

          {/* Agent Vibe Secret S-Expression Frame */}
          <g transform="translate(-100, 520)" stroke="url(#bioLineGrad)" strokeWidth="1">
            <line x1="0" y1="12" x2="230" y2="12" strokeDasharray="3 3" opacity="0.5" />
            <text x="10" y="26" fontFamily="monospace" fontSize="8" fill="#4ade80">
              (! agent/vibe :chill true :parens :balanced)
            </text>
          </g>
        </g>
      </svg>
    </div>
  </div>
);
