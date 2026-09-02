import React from 'react';
import { ChameleonSchematic } from './ui/Logo';

/**
 * CosmicLandscapeBackground
 * Comprehensive multi-screen blueprint canvas inspired by the technical drawing mockup:
 * 1. Fixed schematic chameleon mascot perched in the top-left (stays fixed on scroll)
 * 2. Multi-screen continuous blueprint scroll framing the page with:
 *    - Constellations Alpha/Beta/Gamma & Orbital Satellites with solar arrays
 *    - Lush Cyber-Canopy: Monstera leaves with vein cutouts & tropical palm fronds
 *    - Planetary Port Dome, Cable connectors (ДАТЧИК-1, ПОРТ-А) & Accretion Vortex
 *    - Bio-Mechanical Gears (ШЕСТЕРЕНЧАТЫЙ ПРИВОД, C=150кп)
 *    - Developer & Agent Easter Eggs:
 *      * "TAB-ERROR CONTAINMENT UNIT: PURGED BY BALANCED S-EXPRESSIONS"
 *      * "CHAMELEON INTERCEPT RADAR: MACH 3.2 TONGUE · 0 BUGS REMAIN"
 *      * "TOKEN FUEL GAUGE: JSON BLOAT EMPTY · -80% PROMPT TOKENS"
 *      * "(! agent/vibe :chill true :parens :balanced :target :wasm32)"
 */
export const CosmicLandscapeBackground: React.FC = () => (
  <div className="pointer-events-none select-none" aria-hidden="true">
    {/* 1. Fixed Viewport Elements: Ambient Glow & Fixed Chameleon Mascot */}
    <div className="fixed inset-0 pointer-events-none overflow-hidden z-0">
      {/* Atmospheric bioluminescent lighting auras */}
      <div className="absolute top-12 left-8 w-[550px] h-[550px] bg-purple-600/15 dark:bg-purple-900/25 blur-[150px] rounded-full" />
      <div className="absolute top-1/3 right-8 w-[650px] h-[650px] bg-indigo-600/12 dark:bg-indigo-950/20 blur-[160px] rounded-full" />
      <div className="absolute bottom-16 left-1/4 w-[700px] h-[550px] bg-purple-900/15 blur-[160px] rounded-full" />

      {/* Fixed Schematic Chameleon Watermark in Upper-Left (perched under floating navbar) */}
      <div className="fixed top-20 left-2 sm:left-6 lg:left-10 w-72 sm:w-84 lg:w-[440px] h-auto opacity-20 dark:opacity-25 transition-all z-10">
        <ChameleonSchematic
          className="w-full h-auto text-signal"
          strokeWidth={2.0}
          glow={true}
        />
      </div>
    </div>

    {/* 2. Full-Document Scrolling Blueprint Landscape (Multi-Screen Continuous Canvas) */}
    <div className="absolute inset-0 w-full h-full pointer-events-none overflow-hidden z-0">
      <svg
        className="w-full h-full text-purple-400/25 dark:text-purple-300/20"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 1440 3200"
        preserveAspectRatio="xMidYMin slice"
        fill="none"
      >
        <defs>
          {/* Blueprint Millimetric Grid Pattern */}
          <pattern id="blueprintGridPattern" width="40" height="40" patternUnits="userSpaceOnUse">
            <path d="M 40 0 L 0 0 0 40" fill="none" stroke="currentColor" strokeWidth="0.5" opacity="0.3" />
            <path d="M 200 0 L 0 0 0 200" fill="none" stroke="currentColor" strokeWidth="1.0" opacity="0.5" />
          </pattern>

          {/* Line Gradients */}
          <linearGradient id="bioLineGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#c084fc" stopOpacity="0.6" />
            <stop offset="60%" stopColor="#a855f7" stopOpacity="0.4" />
            <stop offset="100%" stopColor="#7e22ce" stopOpacity="0.2" />
          </linearGradient>

          <linearGradient id="leafFacetGrad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stopColor="#a855f7" stopOpacity="0.12" />
            <stop offset="100%" stopColor="#581c87" stopOpacity="0.03" />
          </linearGradient>
        </defs>

        {/* Technical Blueprint Grid Base */}
        <rect width="100%" height="100%" fill="url(#blueprintGridPattern)" />

        {/* ========================================================================= */}
        {/* SCREEN 1: UPPER CANOPY & COSMIC SPACE (y: 0 - 1000)                        */}
        {/* ========================================================================= */}

        {/* Constellation Alpha-1 (Upper Left) */}
        <g stroke="currentColor" strokeWidth="1.2" opacity="0.65" transform="translate(40, 20)">
          <line x1="340" y1="110" x2="470" y2="70" />
          <line x1="470" y1="70" x2="510" y2="40" />
          <line x1="470" y1="70" x2="400" y2="190" />
          <line x1="400" y1="190" x2="480" y2="200" />
          <line x1="400" y1="190" x2="440" y2="260" />
          <line x1="480" y1="200" x2="495" y2="235" />
          <line x1="440" y1="260" x2="475" y2="310" />

          {/* Star Node Crosshairs */}
          <g fill="currentColor">
            <path d="M 336,110 H 344 M 340,106 V 114" />
            <path d="M 466,70 H 474 M 470,66 V 74" />
            <path d="M 506,40 H 514 M 510,36 V 44" />
            <path d="M 396,190 H 404 M 400,186 V 194" />
            <path d="M 476,200 H 484 M 480,196 V 204" />
            <path d="M 436,260 H 444 M 440,256 V 264" />
            <path d="M 471,310 H 479 M 475,306 V 314" />
          </g>

          {/* Star Identifier Labels */}
          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.7">
            <text x="478" y="78">A</text>
            <text x="460" y="130">B</text>
            <text x="390" y="200">A</text>
            <text x="502" y="240">g</text>
            <text x="478" y="320">G*</text>
          </g>
        </g>

        {/* Constellation Beta-2 (Left Side Margin) */}
        <g stroke="currentColor" strokeWidth="1.2" opacity="0.6" transform="translate(10, 50)">
          <line x1="220" y1="310" x2="230" y2="365" />
          <line x1="230" y1="365" x2="150" y2="440" />
          <line x1="230" y1="365" x2="265" y2="410" />
          <line x1="150" y1="440" x2="180" y2="510" />
          <line x1="265" y1="410" x2="265" y2="480" />
          <line x1="180" y1="510" x2="265" y2="480" />

          <path d="M 216,310 H 224 M 220,306 V 314" />
          <path d="M 226,365 H 234 M 230,361 V 369" />
          <path d="M 146,440 H 154 M 150,436 V 444" />
          <path d="M 261,410 H 269 M 265,406 V 414" />
          <path d="M 176,510 H 184 M 180,506 V 514" />
          <path d="M 261,480 H 269 M 265,476 V 484" />

          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.7">
            <text x="230" y="318">+R</text>
            <text x="240" y="375">A</text>
            <text x="180" y="525">A</text>
            <text x="275" y="485">B</text>
          </g>
        </g>

        {/* Satellite Probe 1 (Upper Left Margin, with solar arrays and label) */}
        <g transform="translate(90, 420) rotate(-35)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          {/* Satellite Central Chassis */}
          <rect x="-15" y="-25" width="30" height="50" rx="3" fill="#3b0764" fillOpacity="0.2" />
          <line x1="-15" y1="-10" x2="15" y2="-10" strokeDasharray="2 2" />
          <line x1="-15" y1="10" x2="15" y2="10" strokeDasharray="2 2" />

          {/* Solar Panel Wing Left */}
          <rect x="-65" y="-12" width="45" height="24" fill="#3b0764" fillOpacity="0.3" />
          <line x1="-50" y1="-12" x2="-50" y2="12" />
          <line x1="-35" y1="-12" x2="-35" y2="12" />

          {/* Solar Panel Wing Right */}
          <rect x="20" y="-12" width="45" height="24" fill="#3b0764" fillOpacity="0.3" />
          <line x1="35" y1="-12" x2="35" y2="12" />
          <line x1="50" y1="-12" x2="50" y2="12" />

          {/* Antenna Dish */}
          <path d="M 0,25 Q -12,40 0,48 Q 12,40 0,25" />
          <line x1="0" y1="48" x2="0" y2="58" />

          {/* Technical Label */}
          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.8" transform="rotate(35)">
            <text x="45" y="-10">САТЕЛЛИТ-1</text>
            <line x1="35" y1="-13" x2="10" y2="-20" stroke="currentColor" strokeWidth="0.8" />
          </g>
        </g>

        {/* Upper-Right Bio-Digital Jungle Canopy (Lush Monstera, Vines, Spiral Tendrils) */}
        <g transform="translate(1020, 0)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          {/* Main Canopy Cyber-Vine Arch */}
          <path
            d="M 420,0 C 340,40 280,120 290,220 C 300,320 380,380 420,480"
            fill="none"
          />
          <path
            d="M 435,0 C 355,45 295,125 305,225 C 315,325 395,385 435,485"
            strokeDasharray="4 4"
            opacity="0.5"
            fill="none"
          />

          {/* Big Monstera Leaf 1 (Upper Right) */}
          <g transform="translate(240, 40) rotate(-15)">
            <path
              d="M 0,0 C 40,-60 120,-70 160,-20 C 190,20 180,90 140,130 C 100,170 30,160 -10,110 C -40,70 -30,20 0,0 Z"
              fill="url(#leafFacetGrad)"
            />
            {/* Monstera Cutouts / Fenestrations */}
            <ellipse cx="60" cy="-10" rx="14" ry="5" transform="rotate(-30 60 -10)" />
            <ellipse cx="100" cy="20" rx="18" ry="6" transform="rotate(-15 100 20)" />
            <ellipse cx="90" cy="70" rx="16" ry="6" transform="rotate(20 90 70)" />
            <ellipse cx="40" cy="90" rx="14" ry="5" transform="rotate(45 40 90)" />
            {/* Rib Veins */}
            <line x1="0" y1="0" x2="140" y2="130" strokeWidth="2" />
            <line x1="40" y1="35" x2="90" y2="0" strokeDasharray="3 3" />
            <line x1="70" y1="65" x2="130" y2="40" strokeDasharray="3 3" />
            <line x1="95" y1="90" x2="140" y2="90" strokeDasharray="3 3" />
          </g>

          {/* Monstera Leaf 2 (Hanging Edge) */}
          <g transform="translate(320, 190) rotate(25)">
            <path
              d="M 0,0 C 35,-45 95,-50 130,-15 C 150,15 140,65 110,95 C 80,125 25,120 -5,80 Z"
              fill="url(#leafFacetGrad)"
            />
            <ellipse cx="50" cy="-5" rx="12" ry="4" transform="rotate(-25 50 -5)" />
            <ellipse cx="80" cy="20" rx="14" ry="5" transform="rotate(5 80 20)" />
            <line x1="0" y1="0" x2="110" y2="95" strokeWidth="1.8" />
          </g>

          {/* Tropical Palm Fronds Cluster */}
          <g transform="translate(150, 80) rotate(45)">
            <path d="M 0,0 Q 60,-30 140,-10 Q 70,20 0,0" fill="url(#leafFacetGrad)" />
            <path d="M 0,0 Q 70,-10 155,20 Q 80,40 0,0" fill="url(#leafFacetGrad)" />
            <path d="M 0,0 Q 60,10 140,50 Q 65,55 0,0" fill="url(#leafFacetGrad)" />
          </g>

          {/* Chameleon Handprint Icon with Spiral Palm */}
          <g transform="translate(80, 240) rotate(-20)" stroke="url(#bioLineGrad)" strokeWidth="1.5">
            <path d="M 0,0 C 15,-20 30,-15 25,10 C 20,30 5,35 0,0" fill="url(#leafFacetGrad)" />
            <path d="M -15,-10 C -5,-30 10,-25 5,-5" fill="url(#leafFacetGrad)" />
            <path d="M 20,-5 C 35,-25 50,-15 35,5" fill="url(#leafFacetGrad)" />
            <path
              d="M 12,8 A 6 6 0 0 1 18,14 A 8 8 0 0 1 10,22 A 12 12 0 0 1 -2,10"
              strokeDasharray="2 2"
              fill="none"
            />
            {/* Technical Labels */}
            <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.8">
              <text x="-60" y="-10">ПЛАНЕТАРНЫЙ ПОРТ</text>
              <line x1="25" y1="-13" x2="45" y2="-13" stroke="currentColor" strokeWidth="0.8" />
              <text x="25" y="55">БИО-КОМПОНЕНТ</text>
            </g>
          </g>
        </g>

        {/* EASTER EGG 1: TAB-ERROR CONTAINMENT UNIT (Upper Right Margin, x: 1160, y: 440) */}
        <g transform="translate(1160, 440)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          {/* Blueprint Containment Grid Box */}
          <rect x="0" y="0" width="250" height="110" rx="8" fill="#3b0764" fillOpacity="0.25" strokeDasharray="6 3" />
          <line x1="0" y1="24" x2="250" y2="24" stroke="currentColor" strokeWidth="0.8" />
          
          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.9">
            <text x="12" y="16" fontWeight="bold" fill="#c084fc">CONTAINMENT: TAB-ERROR-04</text>
            <text x="12" y="42" fill="#ef4444">def hallucinate():</text>
            <text x="24" y="56" fill="#ef4444">  TabError: 4 spaces != 1 tab</text>
            <line x1="10" y1="64" x2="240" y2="64" stroke="currentColor" strokeWidth="0.6" strokeDasharray="2 2" />
            <text x="12" y="80" fill="#4ade80">STATUS: PURGED BY BALANCED PARENS</text>
            <text x="12" y="96" fill="#a855f7">AGENT RETRIES SAVED: 100%</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* SCREEN 2: MID SCANNER DOME & PLANETARY VORTEX (y: 1000 - 2100)            */}
        {/* ========================================================================= */}

        {/* Large Orbital Planetary Station / Scanner Dome (Left Margin, x: 80, y: 1280) */}
        <g transform="translate(80, 1280)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          {/* Outer Targeting Rings */}
          <circle cx="0" cy="0" r="140" strokeDasharray="8 6" opacity="0.4" />
          <circle cx="0" cy="0" r="110" strokeDasharray="4 4" opacity="0.6" />
          <circle cx="0" cy="0" r="80" strokeWidth="2" />

          {/* Station Hemisphere Dome */}
          <path d="M -70,-25 A 75 75 0 0 1 70,-25" strokeWidth="2.5" fill="#3b0764" fillOpacity="0.2" />
          <line x1="-70" y1="-25" x2="70" y2="-25" />

          {/* Segmented Optical Sensor Head */}
          <path d="M -30,-25 L -16,-65 L 16,-65 L 30,-25 Z" strokeWidth="2" fill="#581c87" fillOpacity="0.3" />
          <line x1="0" y1="-65" x2="0" y2="-100" strokeWidth="2.5" />
          <circle cx="0" cy="-100" r="4" fill="currentColor" />

          {/* Hydraulic Conduits and Pipe Feeds */}
          <path d="M -50,15 L -100,65 L -120,130" strokeWidth="3" />
          <path d="M -30,25 L -75,90 L -85,150" strokeWidth="2" strokeDasharray="4 4" />

          {/* Technical Station Callouts */}
          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.85">
            <text x="65" y="-50">ПЛАНЕТАРНЫЙ ПОРТ</text>
            <line x1="20" y1="-55" x2="60" y2="-55" stroke="currentColor" strokeWidth="0.8" />
            <text x="-35" y="15" transform="rotate(45 -35 15)">ПОРТ А</text>
            <text x="-10" y="45" transform="rotate(45 -10 45)">ЛИНИЯ Б</text>
            <text x="55" y="110">ПОРТ-СИСТЕМЫ // 0x8F</text>
          </g>
        </g>

        {/* EASTER EGG 2: CHAMELEON TONGUE BUG RADAR (Left Margin, x: 220, y: 1550) */}
        <g transform="translate(220, 1550)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <circle cx="0" cy="0" r="45" strokeDasharray="3 3" opacity="0.5" />
          <circle cx="0" cy="0" r="30" opacity="0.7" />
          <line x1="-50" y1="0" x2="50" y2="0" strokeDasharray="2 2" />
          <line x1="0" y1="-50" x2="0" y2="50" strokeDasharray="2 2" />
          {/* Chameleon Tongue Vector Zap */}
          <path d="M -20,20 Q 0,0 35,-15" stroke="#4ade80" strokeWidth="2" />
          <circle cx="35" cy="-15" r="3" fill="#4ade80" />
          
          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.85">
            <text x="-55" y="65">RADAR: BUG-INTERCEPT</text>
            <text x="-55" y="78" fill="#4ade80">TONGUE SPEED: MACH 3.2</text>
            <text x="-55" y="91">BUGS CAUGHT: (catch! :all)</text>
          </g>
        </g>

        {/* Saturnian Ringed Planet (OPS.RTA) in Right Margin (x: 1240, y: 1380) */}
        <g transform="translate(1240, 1380)" stroke="url(#bioLineGrad)" strokeWidth="1.3">
          {/* Planet Sphere */}
          <circle cx="0" cy="0" r="50" fill="#4a044e" fillOpacity="0.3" />
          <path d="M -40,-12 Q 0,-25 40,-12" strokeDasharray="2 3" opacity="0.6" />
          <path d="M -45,8 Q 0,-5 45,8" strokeDasharray="2 3" opacity="0.6" />

          {/* Concentric Accretion Rings */}
          <ellipse cx="0" cy="0" rx="120" ry="36" strokeWidth="2" transform="rotate(-18)" />
          <ellipse cx="0" cy="0" rx="105" ry="30" strokeDasharray="6 4" transform="rotate(-18)" />
          <ellipse cx="0" cy="0" rx="90" ry="25" strokeDasharray="3 3" transform="rotate(-18)" />

          {/* Technical Badge */}
          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.85">
            <rect x="-35" y="65" width="70" height="18" stroke="currentColor" strokeWidth="0.8" rx="3" fill="#3b0764" fillOpacity="0.3" />
            <text x="-25" y="78">OPS.RTA</text>
          </g>
        </g>

        {/* Cable Bundles and Sensor Probes (ДАТЧИК-1, ПОРТ-А, ПОРТ 46) (Right Margin, x: 1140, y: 1600) */}
        <g transform="translate(1140, 1600)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          {/* Bundled Wires */}
          <path d="M 0,0 C 40,30 80,20 120,70" strokeWidth="2" />
          <path d="M 20,-10 C 60,10 90,40 140,50" />
          <path d="M 40,-20 C 70,-10 110,10 160,20" />

          {/* Connectors & Terminals */}
          <circle cx="120" cy="70" r="4" fill="currentColor" />
          <circle cx="140" cy="50" r="4" fill="currentColor" />
          <circle cx="160" cy="20" r="4" fill="currentColor" />

          {/* Callout Labels */}
          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.85">
            <text x="-40" y="30">ДАТЧИК-1</text>
            <text x="-35" y="70">ПОРТ 46</text>
            <text x="130" y="10">ПОРТ-А</text>
            <text x="150" y="45">ПОРТ-А</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* SCREEN 3: LOWER BLUEPRINT MATRIX & HARNESS GROUND (y: 2100 - 3200)        */}
        {/* ========================================================================= */}

        {/* EASTER EGG 3: TOKEN BURN FUEL GAUGE (Left Margin, x: 70, y: 2240) */}
        <g transform="translate(70, 2240)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <rect x="0" y="0" width="220" height="95" rx="8" fill="#3b0764" fillOpacity="0.25" strokeDasharray="5 3" />
          <line x1="0" y1="22" x2="220" y2="22" stroke="currentColor" strokeWidth="0.8" />
          
          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.9">
            <text x="10" y="15" fontWeight="bold" fill="#c084fc">GAUGE: TOKEN CONSUMPTION</text>
            <text x="10" y="40">JSON BLOAT : [E----|----F] (0%)</text>
            <text x="10" y="55" fill="#4ade80">ASL SAVINGS: [████████--] (-80%)</text>
            <line x1="10" y1="64" x2="210" y2="64" stroke="currentColor" strokeWidth="0.6" strokeDasharray="2 2" />
            <text x="10" y="80" fill="#a855f7">COGNITIVE OVERHEAD: 0.00%</text>
          </g>
        </g>

        {/* Extended Constellation Gamma (Lower Left, x: 50, y: 2420) */}
        <g stroke="currentColor" strokeWidth="1.2" opacity="0.65" transform="translate(50, 2420)">
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
            <text x="215" y="195">+R</text>
          </g>
        </g>

        {/* Lower Right Cyber-Canopy Roots, Gears & Tropical Fronds (x: 1140, y: 2450) */}
        <g transform="translate(1140, 2450)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          <path
            d="M 200,0 C 120,80 40,160 80,260 C 120,360 220,440 260,540"
            fill="none"
          />
          <path
            d="M 220,0 C 140,85 60,165 100,265 C 140,365 240,445 280,545"
            strokeDasharray="4 6"
            fill="none"
            opacity="0.5"
          />

          {/* Deep Palm Fan Fronds */}
          <g transform="translate(60, 160) rotate(-45)">
            <polygon points="0,0 80,-40 180,-30 90,10" fill="url(#leafFacetGrad)" />
            <polygon points="0,0 90,10 190,40 75,45" fill="url(#leafFacetGrad)" />
            <polygon points="0,0 75,45 160,95 50,70" fill="url(#leafFacetGrad)" />
            <polygon points="0,0 50,70 120,140 25,85" fill="url(#leafFacetGrad)" />
          </g>

          {/* Gear Drive Accent in Lower Roots */}
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
              <text x="-25" y="80">ШЕСТЕРЕНЧАТЫЙ БЛОК</text>
            </g>
          </g>

          {/* EASTER EGG 4: PURE ASL SECRET VIBE (Lower Margin) */}
          <g transform="translate(-100, 480)" stroke="url(#bioLineGrad)" strokeWidth="1">
            <rect x="0" y="0" width="220" height="38" rx="6" fill="#3b0764" fillOpacity="0.3" strokeDasharray="3 3" />
            <text x="10" y="24" fontFamily="monospace" fontSize="8" fill="#4ade80">
              (! agent/vibe :chill true :parens :balanced)
            </text>
          </g>
        </g>
      </svg>
    </div>
  </div>
);
