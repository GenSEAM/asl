import React from 'react';
import { ChameleonSchematic } from './ui/Logo';

/**
 * CosmicLandscapeBackground
 * Universal fixed viewport background featuring:
 * 1. Fixed schematic chameleon watermark in the top-left (below floating navbar) that persists on scroll
 * 2. Isometric 3D wireframe cubes, terrain contour lines, and circuit traces matching the original design mockup
 * 3. Ambient cosmic violet light auras and blueprint grid
 */
export const CosmicLandscapeBackground: React.FC = () => (
  <div
    className="fixed inset-0 pointer-events-none select-none overflow-hidden z-0"
    aria-hidden="true"
  >
    {/* Ambient radial lighting auras */}
    <div className="absolute top-16 left-12 w-[500px] h-[500px] bg-purple-600/15 dark:bg-purple-900/25 blur-[140px] rounded-full" />
    <div className="absolute top-1/3 right-10 w-[600px] h-[600px] bg-indigo-600/10 dark:bg-indigo-950/20 blur-[160px] rounded-full" />
    <div className="absolute bottom-10 left-1/4 w-[700px] h-[450px] bg-purple-900/10 blur-[150px] rounded-full" />

    {/* Fixed Schematic Chameleon Watermark in Upper-Left (below floating navbar) */}
    <div className="fixed top-20 left-2 sm:left-6 lg:left-10 w-72 sm:w-84 lg:w-[440px] h-auto opacity-20 dark:opacity-25 transition-all">
      <ChameleonSchematic
        className="w-full h-auto text-signal"
        strokeWidth={2.0}
        glow={true}
      />
    </div>

    {/* Isometric 3D Blueprint Landscape & Circuit Mesh (from reference mockup) */}
    <svg
      className="absolute inset-0 w-full h-full text-purple-500/20"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 1440 960"
      preserveAspectRatio="xMidYMid slice"
      fill="none"
    >
      <defs>
        <linearGradient id="landscapeGrad" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#c084fc" stopOpacity="0.4" />
          <stop offset="50%" stopColor="#a855f7" stopOpacity="0.2" />
          <stop offset="100%" stopColor="#6b21a8" stopOpacity="0.05" />
        </linearGradient>

        <linearGradient id="cubeFaceGrad" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stopColor="#a855f7" stopOpacity="0.08" />
          <stop offset="100%" stopColor="#4c1d95" stopOpacity="0.02" />
        </linearGradient>
      </defs>

      {/* 3D Isometric Wireframe Cube Cluster in Upper-Right (matching original mockup) */}
      <g stroke="url(#landscapeGrad)" strokeWidth="1.2">
        {/* Large Central Cube */}
        <g transform="translate(1080, 160)">
          {/* Top Face */}
          <polygon points="0,-40 69,-80 0,-120 -69,-80" fill="url(#cubeFaceGrad)" />
          {/* Left Face */}
          <polygon points="-69,-80 0,-40 0,40 -69,0" fill="url(#cubeFaceGrad)" />
          {/* Right Face */}
          <polygon points="0,-40 69,-80 69,0 0,40" fill="url(#cubeFaceGrad)" />
          {/* Internal Wireframe Lines */}
          <line x1="0" y1="-40" x2="0" y2="40" strokeDasharray="3 3" />
        </g>

        {/* Medium Upper Cube */}
        <g transform="translate(1200, 80)">
          <polygon points="0,-25 43,-50 0,-75 -43,-50" fill="url(#cubeFaceGrad)" />
          <polygon points="-43,-50 0,-25 0,25 -43,0" fill="url(#cubeFaceGrad)" />
          <polygon points="0,-25 43,-50 43,0 0,25" fill="url(#cubeFaceGrad)" />
        </g>

        {/* Small Lower Cube */}
        <g transform="translate(960, 240)">
          <polygon points="0,-20 35,-40 0,-60 -35,-40" fill="url(#cubeFaceGrad)" />
          <polygon points="-35,-40 0,-20 0,20 -35,0" fill="url(#cubeFaceGrad)" />
          <polygon points="0,-20 35,-40 35,0 0,20" fill="url(#cubeFaceGrad)" />
        </g>
      </g>

      {/* Isometric Perspective Grid Rays & Horizontal Horizon Arcs */}
      <g stroke="currentColor" strokeWidth="1" strokeDasharray="3 6" opacity="0.6">
        <line x1="720" y1="180" x2="0" y2="960" />
        <line x1="720" y1="180" x2="360" y2="960" />
        <line x1="720" y1="180" x2="720" y2="960" />
        <line x1="720" y1="180" x2="1080" y2="960" />
        <line x1="720" y1="180" x2="1440" y2="960" />

        {/* Organic Contour / Elevation Iso-curves flowing across the landscape */}
        <path d="M 0,480 Q 360,400 720,440 T 1440,380" strokeDasharray="4 6" />
        <path d="M 0,640 Q 360,560 720,600 T 1440,540" strokeDasharray="4 6" />
        <path d="M 0,800 Q 360,720 720,760 T 1440,700" strokeDasharray="4 6" />
      </g>

      {/* Neon Circuit Traces Connecting the Nodes */}
      <g stroke="#a855f7" strokeWidth="1.5" opacity="0.4">
        <polyline points="540,180 620,180 700,240 840,240" />
        <polyline points="960,240 1020,280 1140,280 1200,340" />
        <polyline points="280,520 380,520 440,580 560,580" />
      </g>

      {/* Blueprint Coordinate Crosshairs and Coordinate Badges */}
      <g fill="#c084fc" opacity="0.7">
        <circle cx="620" cy="180" r="2.5" />
        <circle cx="700" cy="240" r="3" />
        <circle cx="1020" cy="280" r="3" />
        <circle cx="1140" cy="280" r="2.5" />
        <circle cx="380" cy="520" r="2.5" />
        <circle cx="440" cy="580" r="3" />
      </g>

      {/* Technical Drafting Labels in Blueprint Style */}
      <g font-family="monospace" font-size="9" fill="#a855f7" opacity="0.35">
        <text x="1080" y="80">+14.28 / ASL-GEO</text>
        <text x="140" y="320">ISO-ELEV-01 // 440m</text>
        <text x="1240" y="580">MESH-VECTORS // 0x4F</text>
      </g>
    </svg>
  </div>
);
