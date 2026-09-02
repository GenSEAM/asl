import React from 'react';
import { ChameleonSchematic } from './ui/Logo';

/**
 * BioDigitalJungleBackground
 * Merges deep cosmic violet blueprint styling with a vibrant Cybernetic Jungle (Цифровые Джунгли):
 * 1. Fixed schematic chameleon resting naturally on a cyber-canopy branch in the upper-left
 * 2. Winding bio-digital circuit vines with Fibonacci spiral tendrils
 * 3. Stylized geometric tropical wireframe foliage (monstera & fern fronds) with bio-luminescent capillary nodes
 * 4. Drifting firefly data spores and atmospheric cosmic violet-emerald lighting
 */
export const CosmicLandscapeBackground: React.FC = () => (
  <div
    className="fixed inset-0 pointer-events-none select-none overflow-hidden z-0"
    aria-hidden="true"
  >
    {/* Atmospheric Bioluminescent Lighting Auras */}
    <div className="absolute top-12 left-10 w-[550px] h-[550px] bg-purple-600/15 dark:bg-purple-900/25 blur-[150px] rounded-full" />
    <div className="absolute top-1/4 right-8 w-[650px] h-[650px] bg-indigo-600/12 dark:bg-indigo-950/20 blur-[160px] rounded-full" />
    <div className="absolute bottom-12 left-1/3 w-[600px] h-[500px] bg-emerald-950/10 dark:bg-purple-950/20 blur-[150px] rounded-full" />

    {/* Fixed Schematic Chameleon Mascot in Upper-Left (perched on canopy branch) */}
    <div className="fixed top-20 left-2 sm:left-6 lg:left-10 w-72 sm:w-84 lg:w-[440px] h-auto opacity-22 dark:opacity-28 transition-all z-10">
      <ChameleonSchematic
        className="w-full h-auto text-signal"
        strokeWidth={2.0}
        glow={true}
      />
    </div>

    {/* Cybernetic Digital Jungle Vector SVG */}
    <svg
      className="absolute inset-0 w-full h-full text-purple-400/25"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 1440 960"
      preserveAspectRatio="xMidYMid slice"
      fill="none"
    >
      <defs>
        {/* Vine Circuit Gradient */}
        <linearGradient id="cyberVineGrad" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#c084fc" stopOpacity="0.45" />
          <stop offset="40%" stopColor="#a855f7" stopOpacity="0.3" />
          <stop offset="80%" stopColor="#38bdf8" stopOpacity="0.2" />
          <stop offset="100%" stopColor="#34d399" stopOpacity="0.15" />
        </linearGradient>

        {/* Bio-Digital Leaf Facet Gradient */}
        <linearGradient id="cyberLeafGrad" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stopColor="#a855f7" stopOpacity="0.1" />
          <stop offset="60%" stopColor="#6366f1" stopOpacity="0.05" />
          <stop offset="100%" stopColor="#10b981" stopOpacity="0.02" />
        </linearGradient>

        <linearGradient id="tendrilGlow" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stopColor="#d8b4fe" stopOpacity="0.5" />
          <stop offset="100%" stopColor="#a855f7" stopOpacity="0.1" />
        </linearGradient>
      </defs>

      {/* 1. Main Cyber-Canopy Perch Branch (Anchors the Chameleon's paws & tail) */}
      <g stroke="url(#cyberVineGrad)" strokeWidth="1.8">
        {/* Primary supportive canopy branch sweeping under chameleon */}
        <path
          d="M -40,310 C 80,310 180,330 320,315 C 440,300 520,230 640,210 C 760,190 890,230 1020,180 C 1150,130 1280,140 1480,90"
        />
        {/* Parallel secondary circuit vine */}
        <path
          d="M -40,324 C 80,324 175,342 315,327 C 430,312 515,242 635,222 C 755,202 885,242 1015,192 C 1145,142 1275,152 1480,102"
          strokeDasharray="4 6"
          opacity="0.6"
        />
      </g>

      {/* 2. Fibonacci Spiral Tendrils (echoing chameleon tail and curled 'a') */}
      <g stroke="url(#tendrilGlow)" strokeWidth="1.4" fill="none">
        {/* Tendril curling near chameleon tail */}
        <path
          d="M 190,328 C 170,360 140,380 110,370 C 80,360 70,320 90,295 C 110,270 145,280 150,305 C 155,330 135,340 125,335 C 115,330 118,318 126,318"
        />
        {/* Tendril in mid canopy */}
        <path
          d="M 640,210 C 670,240 680,280 660,305 C 640,330 600,330 580,305 C 560,280 575,250 600,245 C 625,240 635,260 625,270 C 615,280 605,275 605,265"
        />
        {/* Tendril in upper right canopy */}
        <path
          d="M 1150,142 C 1180,170 1185,210 1160,235 C 1135,260 1095,255 1080,230 C 1065,205 1085,180 1110,178 C 1135,176 1142,195 1132,205"
        />
      </g>

      {/* 3. Geometric Wireframe Jungle Foliage (Monstera & Palm Fronds in Blueprint) */}
      {/* Upper-Right Canopy Tropical Leaf Cluster */}
      <g transform="translate(1180, 180) rotate(-25)" stroke="#a855f7" strokeWidth="1.2">
        {/* Central Spine */}
        <line x1="0" y1="0" x2="160" y2="120" stroke="url(#cyberVineGrad)" strokeWidth="2" />
        {/* Leaf Facets & Ribs */}
        <polygon points="0,0 40,10 70,-15 50,20 100,25 130,5 110,45 160,120 90,75 50,85 70,45 20,40" fill="url(#cyberLeafGrad)" />
        <line x1="40" y1="10" x2="70" y2="-15" />
        <line x1="50" y1="20" x2="100" y2="25" />
        <line x1="70" y1="45" x2="130" y2="5" />
        <line x1="90" y1="75" x2="110" y2="45" />
        <line x1="20" y1="40" x2="50" y2="85" />
      </g>

      {/* Mid-Right Fern Frond Leaf */}
      <g transform="translate(1280, 420) rotate(-65)" stroke="#818cf8" strokeWidth="1">
        <line x1="0" y1="0" x2="200" y2="80" stroke="url(#cyberVineGrad)" strokeWidth="1.8" />
        {/* Segmented Frond Pinnae */}
        <polygon points="20,8 45,-25 35,14" fill="url(#cyberLeafGrad)" />
        <polygon points="50,20 85,-20 65,26" fill="url(#cyberLeafGrad)" />
        <polygon points="80,32 125,-10 95,38" fill="url(#cyberLeafGrad)" />
        <polygon points="110,44 155,10 125,50" fill="url(#cyberLeafGrad)" />
        <polygon points="140,56 185,30 155,62" fill="url(#cyberLeafGrad)" />
        <polygon points="35,14 50,45 50,20" fill="url(#cyberLeafGrad)" />
        <polygon points="65,26 90,65 80,32" fill="url(#cyberLeafGrad)" />
        <polygon points="95,38 130,75 110,44" fill="url(#cyberLeafGrad)" />
      </g>

      {/* Lower-Left Cyber-Flora Accent */}
      <g transform="translate(40, 760) rotate(35)" stroke="#a855f7" strokeWidth="1.1">
        <line x1="0" y1="0" x2="150" y2="-90" stroke="url(#cyberVineGrad)" strokeWidth="1.8" />
        <polygon points="0,0 35,-10 60,-45 45,-15 90,-35 115,-70 95,-45 150,-90 85,-65 40,-50 60,-25 15,-15" fill="url(#cyberLeafGrad)" />
        <circle cx="60" cy="-45" r="2.5" fill="#34d399" />
        <circle cx="115" cy="-70" r="3" fill="#c084fc" />
      </g>

      {/* 4. Cross-Landscape Canopy Horizon Vines (Descending through lower view) */}
      <g stroke="currentColor" strokeWidth="1" strokeDasharray="3 6" opacity="0.45">
        <path d="M -20,540 Q 380,480 740,520 T 1460,460" />
        <path d="M -20,720 Q 380,660 740,700 T 1460,640" />
        <path d="M -20,880 Q 380,820 740,860 T 1460,800" />
      </g>

      {/* 5. Bioluminescent Firefly Data Spores (Pulsing nodes along the cyber jungle) */}
      <g fill="#c084fc">
        <circle cx="320" cy="315" r="3.5" className="animate-pulse" />
        <circle cx="520" cy="230" r="3" />
        <circle cx="640" cy="210" r="4" fill="#e9d5ff" className="animate-pulse" />
        <circle cx="890" cy="230" r="3" />
        <circle cx="1020" cy="180" r="3.5" fill="#a855f7" className="animate-pulse" />
        <circle cx="1200" cy="165" r="2.5" fill="#34d399" />
        <circle cx="1320" cy="260" r="3" className="animate-pulse" />
        <circle cx="740" cy="520" r="3" fill="#818cf8" />
        <circle cx="980" cy="480" r="2.5" className="animate-pulse" />
        <circle cx="480" cy="680" r="3" fill="#34d399" className="animate-pulse" />
      </g>

      {/* Technical Blueprint Canopy Annotations */}
      <g fontFamily="monospace" fontSize="9" fill="#a855f7" opacity="0.4">
        <text x="340" y="340">CANOPY-PERCH // 315m-ASL</text>
        <text x="650" y="195">FIBONACCI-TENDRIL [φ 1.618]</text>
        <text x="1100" y="115">CYBER-FLORA // TROPIC-VINE</text>
        <text x="760" y="540">BIO-MESH BUS // &lt;0.04ms</text>
      </g>
    </svg>
  </div>
);
