import React from 'react';
import { ChameleonSchematic } from './ui/Logo';

/**
 * CosmicLandscapeBackground
 * Comprehensive multi-screen blueprint canvas inspired by the technical drawing mockup:
 * 1. Fixed schematic chameleon mascot perched in the top-left (stays fixed on scroll)
 * 2. Multi-screen continuous blueprint scroll spanning the entire document:
 *    - Screen 1 (Hero & Ecosystem): Constellations, Satellites, Upper Canopy Monstera & Palm Fronds, Chameleon Handprint
 *    - Screen 2 (Capabilities & The Agent Way): Orbital Planetary Scanner Station, Ringed Planet OPS.RTA, Eye Crosshairs, Cable Bundles (ДАТЧИК-1, ПОРТ-А)
 *    - Screen 3 (Protocol, Harness & Architecture): Bio-Mechanical Gears (ШЕСТЕРЕНЧАТЫЙ ПРИВОД, C=150кп), Satellite Probes, Lower Cyber-Flora
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

        {/* Constellation Alpha-1 (Upper Left / Center) */}
        <g stroke="currentColor" strokeWidth="1.2" opacity="0.65">
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

        {/* Constellation Beta-2 (Left Side) */}
        <g stroke="currentColor" strokeWidth="1.2" opacity="0.6">
          <line x1="320" y1="310" x2="330" y2="365" />
          <line x1="330" y1="365" x2="250" y2="440" />
          <line x1="330" y1="365" x2="365" y2="410" />
          <line x1="250" y1="440" x2="280" y2="510" />
          <line x1="365" y1="410" x2="365" y2="480" />
          <line x1="280" y1="510" x2="365" y2="480" />

          <path d="M 316,310 H 324 M 320,306 V 314" />
          <path d="M 326,365 H 334 M 330,361 V 369" />
          <path d="M 246,440 H 254 M 250,436 V 444" />
          <path d="M 361,410 H 369 M 365,406 V 414" />
          <path d="M 276,510 H 284 M 280,506 V 514" />
          <path d="M 361,480 H 369 M 365,476 V 484" />

          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.7">
            <text x="330" y="318">+R</text>
            <text x="340" y="375">A</text>
            <text x="280" y="525">A</text>
            <text x="375" y="485">B</text>
          </g>
        </g>

        {/* Satellite Probe 1 (Upper Left, with solar arrays and label) */}
        <g transform="translate(100, 390) rotate(-35)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
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

        {/* Central Space Satellite (Center, angled, with broadcast waves) */}
        <g transform="translate(850, 480) rotate(42)" stroke="url(#bioLineGrad)" strokeWidth="1.3">
          <rect x="-20" y="-30" width="40" height="60" rx="4" fill="#581c87" fillOpacity="0.2" />
          <circle cx="0" cy="0" r="10" strokeDasharray="3 3" />

          {/* Solar Arrays */}
          <rect x="-80" y="-16" width="55" height="32" fill="#581c87" fillOpacity="0.25" />
          <line x1="-62" y1="-16" x2="-62" y2="16" />
          <line x1="-44" y1="-16" x2="-44" y2="16" />

          <rect x="25" y="-16" width="55" height="32" fill="#581c87" fillOpacity="0.25" />
          <line x1="43" y1="-16" x2="43" y2="16" />
          <line x1="61" y1="-16" x2="61" y2="16" />

          {/* Dish with signal waves */}
          <path d="M 0,30 Q -16,48 0,56 Q 16,48 0,30" />
          <path d="M 12,62 Q 24,70 18,82" strokeDasharray="2 3" />
          <path d="M 18,58 Q 32,68 26,88" strokeDasharray="2 3" />
        </g>

        {/* Upper-Right Bio-Digital Jungle Canopy (Lush Monstera, Vines, Spiral Tendrils) */}
        <g transform="translate(980, 0)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          {/* Main Canopy Cyber-Vine Arch */}
          <path
            d="M 460,0 C 380,40 320,120 330,220 C 340,320 420,380 460,480"
            fill="none"
          />
          <path
            d="M 475,0 C 395,45 335,125 345,225 C 355,325 435,385 475,485"
            strokeDasharray="4 4"
            opacity="0.5"
            fill="none"
          />

          {/* Big Monstera Leaf 1 (Upper Right) */}
          <g transform="translate(280, 40) rotate(-15)">
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
          <g transform="translate(360, 190) rotate(25)">
            <path
              d="M 0,0 C 35,-45 95,-50 130,-15 C 150,15 140,65 110,95 C 80,125 25,120 -5,80 Z"
              fill="url(#leafFacetGrad)"
            />
            <ellipse cx="50" cy="-5" rx="12" ry="4" transform="rotate(-25 50 -5)" />
            <ellipse cx="80" cy="20" rx="14" ry="5" transform="rotate(5 80 20)" />
            <line x1="0" y1="0" x2="110" y2="95" strokeWidth="1.8" />
          </g>

          {/* Tropical Palm Fronds Cluster */}
          <g transform="translate(180, 80) rotate(45)">
            <path d="M 0,0 Q 60,-30 140,-10 Q 70,20 0,0" fill="url(#leafFacetGrad)" />
            <path d="M 0,0 Q 70,-10 155,20 Q 80,40 0,0" fill="url(#leafFacetGrad)" />
            <path d="M 0,0 Q 60,10 140,50 Q 65,55 0,0" fill="url(#leafFacetGrad)" />
          </g>

          {/* Chameleon Palm Handprint Icon with Spiral in Upper-Right */}
          <g transform="translate(230, 210)" stroke="currentColor" strokeWidth="1.4" opacity="0.8">
            <path d="M 0,20 C -5,12 -12,8 -10,0 C -8,-6 2,-6 5,0 C 7,8 8,14 10,20" />
            <path d="M 12,20 C 14,10 12,2 18,-2 C 24,-6 28,0 26,8 C 24,14 20,18 18,24" />
            <path d="M 22,24 C 28,16 32,8 38,8 C 44,8 44,16 38,22 C 32,28 26,30 22,32" />
            {/* Spiral Palm Center */}
            <path
              d="M 10,32 C 8,36 12,40 16,38 C 20,36 20,30 16,28 C 13,26 10,28 10,30"
              strokeWidth="1.2"
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

        {/* Observation Eye Crosshair Sensor (Upper Center) */}
        <g transform="translate(740, 200)" stroke="currentColor" strokeWidth="1.2" opacity="0.7">
          {/* Target Reticle Frame */}
          <rect x="-35" y="-25" width="70" height="50" strokeDasharray="3 3" fill="#3b0764" fillOpacity="0.15" />
          <line x1="-45" y1="0" x2="45" y2="0" strokeDasharray="2 2" />
          <line x1="0" y1="-32" x2="0" y2="32" strokeDasharray="2 2" />
          {/* Eye Outline */}
          <path d="M -25,0 Q 0,-18 25,0 Q 0,18 -25,0 Z" />
          <circle cx="0" cy="0" r="7" />
          <circle cx="0" cy="0" r="3" fill="currentColor" />
        </g>

        {/* Right Border Bio-Mechanical Gears Cluster */}
        <g transform="translate(1380, 680)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          {/* Large Gear */}
          <g transform="translate(-40, 0)">
            <circle cx="0" cy="0" r="75" strokeDasharray="6 4" fill="#3b0764" fillOpacity="0.2" />
            <circle cx="0" cy="0" r="30" />
            <circle cx="0" cy="0" r="10" fill="currentColor" />
            {/* Gear Teeth */}
            {[0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330].map((deg) => (
              <line
                key={deg}
                x1={Math.cos((deg * Math.PI) / 180) * 75}
                y1={Math.sin((deg * Math.PI) / 180) * 75}
                x2={Math.cos((deg * Math.PI) / 180) * 90}
                y2={Math.sin((deg * Math.PI) / 180) * 90}
                strokeWidth="4"
              />
            ))}
          </g>

          {/* Medium Gear with Callout */}
          <g transform="translate(-130, 80)">
            <circle cx="0" cy="0" r="45" strokeDasharray="4 3" fill="#3b0764" fillOpacity="0.2" />
            <circle cx="0" cy="0" r="18" />
            {[0, 45, 90, 135, 180, 225, 270, 315].map((deg) => (
              <line
                key={deg}
                x1={Math.cos((deg * Math.PI) / 180) * 45}
                y1={Math.sin((deg * Math.PI) / 180) * 45}
                x2={Math.cos((deg * Math.PI) / 180) * 55}
                y2={Math.sin((deg * Math.PI) / 180) * 55}
                strokeWidth="3.5"
              />
            ))}
            <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.8">
              <text x="-16" y="3">C=150кп</text>
              <text x="-40" y="70">БИО-КОМПОНЕНТ</text>
            </g>
          </g>

          {/* Small Interlocking Gear */}
          <g transform="translate(-80, 160)">
            <circle cx="0" cy="0" r="28" strokeDasharray="3 3" />
            <circle cx="0" cy="0" r="10" />
            <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.8">
              <text x="25" y="-5">ШЕСТЕРЕНЧАТЫЙ</text>
              <text x="25" y="5">ПРИВОД</text>
            </g>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* SCREEN 2: MID SCANNER DOME & PLANETARY VORTEX (y: 1000 - 2100)            */}
        {/* ========================================================================= */}

        {/* Large Orbital Planetary Station / Scanner Dome (Lower-Left / Mid) */}
        <g transform="translate(100, 1280)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          {/* Outer Targeting Rings */}
          <circle cx="0" cy="0" r="160" strokeDasharray="8 6" opacity="0.4" />
          <circle cx="0" cy="0" r="130" strokeDasharray="4 4" opacity="0.6" />
          <circle cx="0" cy="0" r="95" strokeWidth="2" />

          {/* Station Hemisphere Dome */}
          <path d="M -80,-30 A 85 85 0 0 1 80,-30" strokeWidth="2.5" fill="#3b0764" fillOpacity="0.2" />
          <line x1="-80" y1="-30" x2="80" y2="-30" />

          {/* Segmented Optical Sensor Head */}
          <path d="M -35,-30 L -20,-75 L 20,-75 L 35,-30 Z" strokeWidth="2" fill="#581c87" fillOpacity="0.3" />
          <line x1="0" y1="-75" x2="0" y2="-120" strokeWidth="2.5" />
          <circle cx="0" cy="-120" r="5" fill="currentColor" />

          {/* Hydraulic Conduits and Pipe Feeds */}
          <path d="M -60,20 L -120,80 L -140,160" strokeWidth="3" />
          <path d="M -40,30 L -90,110 L -100,180" strokeWidth="2" strokeDasharray="4 4" />

          {/* Technical Station Callouts */}
          <g fontFamily="monospace" fontSize="9" fill="currentColor" opacity="0.85">
            <text x="75" y="-60">ПЛАНЕТАРНЫЙ ПОРТ</text>
            <line x1="25" y1="-65" x2="70" y2="-65" stroke="currentColor" strokeWidth="0.8" />
            <text x="-40" y="20" transform="rotate(45 -40 20)">ПОРТ А</text>
            <text x="-15" y="55" transform="rotate(45 -15 55)">ЛИНИЯ Б</text>
            <text x="65" y="140">ПОРТ-СИСТЕМЫ // 0x8F</text>
            <line x1="0" y1="135" x2="60" y2="135" stroke="currentColor" strokeWidth="0.8" />
          </g>
        </g>

        {/* Saturnian Ringed Planet (OPS.RTA) in Mid-Field */}
        <g transform="translate(480, 1340)" stroke="url(#bioLineGrad)" strokeWidth="1.3">
          {/* Planet Sphere */}
          <circle cx="0" cy="0" r="55" fill="#4a044e" fillOpacity="0.3" />
          <path d="M -45,-15 Q 0,-30 45,-15" strokeDasharray="2 3" opacity="0.6" />
          <path d="M -52,10 Q 0,-5 52,10" strokeDasharray="2 3" opacity="0.6" />

          {/* Concentric Accretion Rings */}
          <ellipse cx="0" cy="0" rx="140" ry="42" strokeWidth="2" transform="rotate(-18)" />
          <ellipse cx="0" cy="0" rx="125" ry="36" strokeDasharray="6 4" transform="rotate(-18)" />
          <ellipse cx="0" cy="0" rx="110" ry="30" strokeDasharray="3 3" transform="rotate(-18)" />
          <ellipse cx="0" cy="0" rx="85" ry="22" strokeWidth="1.5" transform="rotate(-18)" />

          {/* Technical Badge */}
          <g fontFamily="monospace" fontSize="9" fill="currentColor" opacity="0.85">
            <rect x="130" y="20" width="60" height="18" stroke="currentColor" strokeWidth="0.8" />
            <text x="138" y="33">OPS.RTA</text>
          </g>
        </g>

        {/* Second Sensor Eye Target (Mid Screen) */}
        <g transform="translate(780, 1380)" stroke="currentColor" strokeWidth="1.2" opacity="0.7">
          <rect x="-35" y="-25" width="70" height="50" strokeDasharray="3 3" fill="#3b0764" fillOpacity="0.15" />
          <line x1="-45" y1="0" x2="45" y2="0" strokeDasharray="2 2" />
          <line x1="0" y1="-32" x2="0" y2="32" strokeDasharray="2 2" />
          <path d="M -25,0 Q 0,-18 25,0 Q 0,18 -25,0 Z" />
          <circle cx="0" cy="0" r="7" />
          <circle cx="0" cy="0" r="3" fill="currentColor" />
        </g>

        {/* Cable Bundles and Sensor Probes (ДАТЧИК-1, ПОРТ-А, ПОРТ 46) */}
        <g transform="translate(860, 1460)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
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
            <text x="130" y="90">ПОРТ-А</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* SCREEN 3: LOWER BLUEPRINT MATRIX & HARNESS GROUND (y: 2100 - 3200)        */}
        {/* ========================================================================= */}

        {/* Extended Constellation Gamma (Lower Field) */}
        <g stroke="currentColor" strokeWidth="1.2" opacity="0.65" transform="translate(200, 2300)">
          <line x1="120" y1="100" x2="240" y2="60" />
          <line x1="240" y1="60" x2="380" y2="120" />
          <line x1="240" y1="60" x2="220" y2="180" />
          <line x1="380" y1="120" x2="480" y2="80" />
          <line x1="220" y1="180" x2="320" y2="240" />

          <path d="M 116,100 H 124 M 120,96 V 104" />
          <path d="M 236,60 H 244 M 240,56 V 64" />
          <path d="M 376,120 H 384 M 380,116 V 124" />
          <path d="M 216,180 H 224 M 220,176 V 184" />
          <path d="M 476,80 H 484 M 480,76 V 84" />
          <path d="M 316,240 H 324 M 320,236 V 244" />

          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.75">
            <text x="248" y="65">G</text>
            <text x="390" y="125">B</text>
            <text x="490" y="85">A</text>
            <text x="210" y="195">B</text>
            <text x="330" y="255">+R</text>
          </g>
        </g>

        {/* Lower Right Cyber-Canopy Roots & Tropical Fronds */}
        <g transform="translate(1120, 2450)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
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
          <g transform="translate(140, 360)">
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
        </g>
      </svg>
    </div>
  </div>
);
