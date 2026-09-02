import React from 'react';
import { ChameleonSchematic } from './ui/Logo';

/**
 * CosmicLandscapeBackground
 * Comprehensive multi-screen technical blueprint canvas celebrating the evolution of computing to AI agents:
 * 1. Fixed schematic chameleon mascot perched on a graceful cyber-vine in the upper-left.
 * 2. Unobtrusive authentic AgentScript Nano code snippets embedded as blueprint technical annotations.
 * 3. Continuous blueprint canvas framing the page with:
 *    - The Cyber-Vine branch running under the chameleon across the canopy.
 *    - The Evolution of Computing Timeline:
 *      * Era 1: 1950s Hollerith 80-Column Punch Card (IBM-029) & Vacuum Tube Triode (12AX7)
 *      * Era 2: 1980s 3.5" Floppy Disk ("1.44 MB // ENTIRE ASL RUNTIME FITS HERE")
 *      * Era 3: 2000s Paperclip Maximizer Meme ("Status: Converted to AgentScript, saving tokens instead")
 *      * Era 4: 2026+ WebAssembly Reactor Core & Autonomous Swarm Relay (0.038ms latency, chilling on vine)
 *    - Orbital satellites, planetary scanner dome, gears, and constellations.
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
      <div className="fixed top-20 left-2 sm:left-6 lg:left-10 w-72 sm:w-84 lg:w-[440px] h-auto opacity-30 dark:opacity-35 transition-all z-10">
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
            <stop offset="0%" stopColor="#fbbf24" stopOpacity="0.8" />
            <stop offset="100%" stopColor="#d97706" stopOpacity="0.4" />
          </linearGradient>
        </defs>

        {/* Technical Blueprint Grid Base */}
        <rect width="100%" height="100%" fill="url(#blueprintGridPattern)" />

        {/* ========================================================================= */}
        {/* THE LIVING CYBER-VINE BRANCH: Running under the Chameleon (y: 180 - 450)  */}
        {/* ========================================================================= */}
        <g stroke="url(#bioLineGrad)" strokeWidth="1.8" fill="none">
          {/* Main Horizontal Branch under chameleon's perching feet */}
          <path
            d="M 0,220 C 100,215 220,245 360,225 C 480,205 580,240 700,210 C 780,190 850,220 940,205"
            strokeWidth="3.2"
          />
          <path
            d="M 0,226 C 100,221 220,251 360,231 C 480,211 580,246 700,216"
            strokeDasharray="4 4"
            opacity="0.6"
          />
          {/* Branch Tendril Curving Down Left */}
          <path d="M 180,238 C 220,290 190,360 230,410 C 250,435 280,445 300,430" strokeWidth="1.8" />
          {/* Little Sprouting Cyber-Leaves on Branch */}
          <g transform="translate(120, 218) rotate(-25)">
            <path d="M 0,0 Q 25,-18 50,0 Q 25,18 0,0" fill="url(#leafFacetGrad)" strokeWidth="1.2" />
            <line x1="0" y1="0" x2="50" y2="0" strokeWidth="1" />
          </g>
          <g transform="translate(280, 230) rotate(15)">
            <path d="M 0,0 Q 20,-15 40,0 Q 20,15 0,0" fill="url(#leafFacetGrad)" strokeWidth="1.2" />
            <line x1="0" y1="0" x2="40" y2="0" strokeWidth="1" />
          </g>
          <g transform="translate(420, 212) rotate(-10)">
            <path d="M 0,0 Q 22,-14 45,0 Q 22,14 0,0" fill="url(#leafFacetGrad)" strokeWidth="1.2" />
            <line x1="0" y1="0" x2="45" y2="0" strokeWidth="1" />
          </g>
          
          {/* NANO-CODE SNIPPET 1: Chameleon Perch Telemetry Vector */}
          <g transform="translate(50, 250)" strokeWidth="1">
            <rect x="0" y="0" width="225" height="34" rx="4" fill="#3b0764" fillOpacity="0.25" strokeDasharray="3 3" />
            <text x="8" y="15" fontFamily="monospace" fontSize="7.5" fill="#a855f7">
              ;; Telemetry Vector: balanced
            </text>
            <text x="8" y="27" fontFamily="monospace" fontSize="8" fill="#4ade80">
              (! cam:perch :target "vine-01" :mode :balanced)
            </text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* EVOLUTION OF COMPUTING — ERA 1: 1950s PUNCH CARD & VACUUM TUBE            */}
        {/* ========================================================================= */}

        {/* 1. Hollerith 80-Column Punched Card (Upper Right Margin, x: 1140, y: 120) */}
        <g transform="translate(1140, 120)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <polygon
            points="18,0 260,0 260,130 0,130 0,18"
            fill="#3b0764"
            fillOpacity="0.3"
          />
          <line x1="0" y1="24" x2="260" y2="24" stroke="currentColor" strokeWidth="0.8" opacity="0.7" />
          
          <g fill="currentColor" opacity="0.9">
            <rect x="25" y="36" width="3.5" height="7" />
            <rect x="25" y="60" width="3.5" height="7" />
            <rect x="45" y="48" width="3.5" height="7" />
            <rect x="65" y="36" width="3.5" height="7" />
            <rect x="65" y="72" width="3.5" height="7" />
            <rect x="85" y="84" width="3.5" height="7" />
            <rect x="105" y="48" width="3.5" height="7" />
            <rect x="125" y="36" width="3.5" height="7" />
            <rect x="125" y="96" width="3.5" height="7" />
            <rect x="145" y="60" width="3.5" height="7" />
            <rect x="165" y="72" width="3.5" height="7" />
            <rect x="185" y="48" width="3.5" height="7" />
            <rect x="205" y="36" width="3.5" height="7" />
            <rect x="225" y="84" width="3.5" height="7" />
            <rect x="240" y="60" width="3.5" height="7" />
          </g>

          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.9">
            <text x="25" y="16" fontWeight="bold" fill="#c084fc">IBM-029 // HOLLERITH CARD</text>
            <text x="18" y="120" fill="#a855f7">1956: FORTRAN · 80 COLUMNS OF PAIN</text>
          </g>
        </g>

        {/* 2. Vacuum Tube Triode 12AX7 (Upper Right Margin, x: 1220, y: 280) */}
        <g transform="translate(1220, 280)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <path d="M 0,90 L 0,40 C 0,10 60,10 60,40 L 60,90 Z" fill="#4a044e" fillOpacity="0.25" />
          
          <line x1="15" y1="35" x2="45" y2="35" strokeWidth="2" />
          <line x1="30" y1="15" x2="30" y2="35" />

          <path d="M 18,50 L 22,54 L 26,50 L 30,54 L 34,50 L 38,54 L 42,50" strokeWidth="1.5" strokeDasharray="1 1" />
          <line x1="18" y1="50" x2="10" y2="85" />

          <path d="M 22,65 L 38,65" strokeWidth="2" stroke="url(#amberGlow)" />
          <path d="M 26,75 L 30,68 L 34,75" strokeWidth="1.2" stroke="url(#amberGlow)" />
          
          <line x1="12" y1="90" x2="12" y2="102" strokeWidth="2" />
          <line x1="24" y1="90" x2="24" y2="102" strokeWidth="2" />
          <line x1="36" y1="90" x2="36" y2="102" strokeWidth="2" />
          <line x1="48" y1="90" x2="48" y2="102" strokeWidth="2" />

          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.85">
            <text x="70" y="45">TRIODE 12AX7</text>
            <text x="70" y="60" fill="#fbbf24">HEATER: 6.3V</text>
            <text x="70" y="75">FIRST BYTES EMITTED</text>
          </g>
        </g>

        {/* NANO-CODE SNIPPET 2: Orbital Mesh Function (Right Margin, x: 1100, y: 440) */}
        <g transform="translate(1100, 440)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <rect x="0" y="0" width="280" height="60" rx="6" fill="#3b0764" fillOpacity="0.3" strokeDasharray="4 3" />
          <g fontFamily="monospace" fontSize="8" fill="currentColor">
            <text x="12" y="18" fill="#c084fc">;; Mesh Satellite Handshake</text>
            <text x="12" y="32" fill="#4ade80">(df orbit-sync [(sat String) (band Int64)] -&gt; Bool</text>
            <text x="24" y="48" fill="#4ade80">  (! mesh/ping sat :hz band :timeout 40))</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* EVOLUTION OF COMPUTING — ERA 2: 1980s FLOPPY DISK & SILICON               */}
        {/* ========================================================================= */}

        {/* 3. 3.5" Floppy Disk (Left Margin, x: 60, y: 720) */}
        <g transform="translate(60, 720)" stroke="url(#bioLineGrad)" strokeWidth="1.3">
          <polygon
            points="0,0 125,0 135,10 135,140 0,140"
            fill="#3b0764"
            fillOpacity="0.3"
          />
          <rect x="25" y="0" width="65" height="50" rx="3" fill="#581c87" fillOpacity="0.4" />
          <rect x="35" y="10" width="12" height="30" rx="1" fill="currentColor" fillOpacity="0.8" />
          
          <circle cx="67" cy="85" r="22" strokeDasharray="3 3" opacity="0.7" />
          <circle cx="67" cy="85" r="8" fill="currentColor" opacity="0.6" />

          <rect x="118" y="125" width="10" height="8" fill="currentColor" opacity="0.9" />

          <rect x="15" y="102" width="105" height="28" rx="2" stroke="currentColor" strokeWidth="0.8" fill="#1e1b4b" fillOpacity="0.5" />
          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.95">
            <text x="20" y="114" fill="#4ade80">1.44 MB DISKETTE</text>
            <text x="20" y="124" fill="#c084fc">ASL RUNTIME FITS HERE</text>
          </g>
        </g>

        {/* NANO-CODE SNIPPET 3: In-Memory Vector Recall (Left Margin, x: 50, y: 900) */}
        <g transform="translate(50, 900)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <rect x="0" y="0" width="270" height="58" rx="6" fill="#3b0764" fillOpacity="0.25" strokeDasharray="3 3" />
          <g fontFamily="monospace" fontSize="8" fill="currentColor">
            <text x="10" y="18" fill="#c084fc">;; In-Memory Vector Recall (0.038ms)</text>
            <text x="10" y="32" fill="#4ade80">(dfmem recall [(q String)] -&gt; (List Node)</text>
            <text x="20" y="48" fill="#4ade80">  (! mem/search (embed q) :k 5 :max-ms 0.05))</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* EVOLUTION OF COMPUTING — ERA 3: SYNTAX DARK AGES & CLIPPY MEME            */}
        {/* ========================================================================= */}

        {/* 4. The Paperclip Maximizer Meme (Right Margin, x: 1210, y: 840) */}
        <g transform="translate(1210, 840)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          <path
            d="M 20,70 L 20,25 C 20,10 45,10 45,25 L 45,80 C 45,100 10,100 10,80 L 10,35 C 10,22 32,22 32,35 L 32,70"
            strokeWidth="2.2"
            fill="none"
          />
          <circle cx="28" cy="50" r="35" strokeDasharray="4 3" opacity="0.5" />
          <line x1="-15" y1="50" x2="70" y2="50" strokeDasharray="2 2" opacity="0.4" />
          
          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.9">
            <text x="-70" y="20" fill="#c084fc">[ENTITY: CLIPPY / MAXIMIZER]</text>
            <text x="-70" y="32" fill="#ef4444">STATUS: ABORTED</text>
            <text x="-70" y="44" fill="#4ade80">REASON: DISCOVERED ASL</text>
            <text x="-70" y="56" fill="#a855f7">SAVING TOKENS INSTEAD</text>
          </g>
        </g>

        {/* NANO-CODE SNIPPET 4: Pure ASL Pipeline (Left Margin, x: 50, y: 1120) */}
        <g transform="translate(50, 1120)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <rect x="0" y="0" width="270" height="70" rx="6" fill="#3b0764" fillOpacity="0.25" strokeDasharray="5 3" />
          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.9">
            <text x="10" y="16" fill="#c084fc">;; Pure Verified Pipeline (0 Syntax Retries)</text>
            <text x="10" y="32" fill="#4ade80">(! pipe [</text>
            <text x="20" y="46" fill="#4ade80">  (read "src/core.asl") (check :pure) (emit :wasm)])</text>
            <text x="10" y="60" fill="#a855f7">;; Result: 0 repair loops · -80% tokens</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* ERA 4: 2026+ WEBASSEMBLY & AI AGENT SWARM RUNTIME                         */}
        {/* ========================================================================= */}

        {/* Large Planetary Station / Scanner Dome (Left Margin, x: 80, y: 1480) */}
        <g transform="translate(80, 1480)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          <circle cx="0" cy="0" r="140" strokeDasharray="8 6" opacity="0.4" />
          <circle cx="0" cy="0" r="110" strokeDasharray="4 4" opacity="0.6" />
          <circle cx="0" cy="0" r="80" strokeWidth="2" />

          <path d="M -70,-25 A 75 75 0 0 1 70,-25" strokeWidth="2.5" fill="#3b0764" fillOpacity="0.2" />
          <line x1="-70" y1="-25" x2="70" y2="-25" />

          <path d="M -30,-25 L -16,-65 L 16,-65 L 30,-25 Z" strokeWidth="2" fill="#581c87" fillOpacity="0.3" />
          <line x1="0" y1="-65" x2="0" y2="-100" strokeWidth="2.5" />
          <circle cx="0" cy="-100" r="4" fill="currentColor" />

          <path d="M -50,15 L -100,65 L -120,130" strokeWidth="3" />
          <path d="M -30,25 L -75,90 L -85,150" strokeWidth="2" strokeDasharray="4 4" />

          <g fontFamily="monospace" fontSize="8.5" fill="currentColor" opacity="0.85">
            <text x="65" y="-50">ПЛАНЕТАРНЫЙ ПОРТ</text>
            <line x1="20" y1="-55" x2="60" y2="-55" stroke="currentColor" strokeWidth="0.8" />
            <text x="-35" y="15" transform="rotate(45 -35 15)">ПОРТ А</text>
            <text x="55" y="110">WASM REACTOR // 0.038ms</text>
          </g>
        </g>

        {/* NANO-CODE SNIPPET 5: Typed Wasm Reactor Schema (Left Margin, x: 70, y: 1680) */}
        <g transform="translate(70, 1680)" stroke="url(#bioLineGrad)" strokeWidth="1.2">
          <rect x="0" y="0" width="240" height="74" rx="6" fill="#3b0764" fillOpacity="0.25" strokeDasharray="4 3" />
          <g fontFamily="monospace" fontSize="8" fill="currentColor">
            <text x="10" y="16" fill="#c084fc">;; Schema: Zero-Leak Wasm Core</text>
            <text x="10" y="32" fill="#4ade80">(dfs WasmNode</text>
            <text x="20" y="46" fill="#4ade80">  (:f id String) (:f ms Float64)</text>
            <text x="20" y="60" fill="#4ade80">  (:f cap (Option Keyword)))</text>
          </g>
        </g>

        {/* Saturnian Ringed Planet (OPS.RTA) in Right Margin (x: 1240, y: 1520) */}
        <g transform="translate(1240, 1520)" stroke="url(#bioLineGrad)" strokeWidth="1.3">
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

        {/* Cable Bundles (Right Margin, x: 1140, y: 1750) */}
        <g transform="translate(1140, 1750)" stroke="url(#bioLineGrad)" strokeWidth="1.4">
          <path d="M 0,0 C 40,30 80,20 120,70" strokeWidth="2" />
          <path d="M 20,-10 C 60,10 90,40 140,50" />
          <path d="M 40,-20 C 70,-10 110,10 160,20" />
          <circle cx="120" cy="70" r="4" fill="currentColor" />
          <circle cx="140" cy="50" r="4" fill="currentColor" />
          <circle cx="160" cy="20" r="4" fill="currentColor" />
          <g fontFamily="monospace" fontSize="8" fill="currentColor" opacity="0.85">
            <text x="-40" y="30">ДАТЧИК-1</text>
            <text x="130" y="10">ПОРТ-А</text>
          </g>
        </g>

        {/* ========================================================================= */}
        {/* LOWER BLUEPRINT MATRIX & BIO-MECHANICAL GEARS (y: 2100 - 3200)            */}
        {/* ========================================================================= */}

        {/* Token Fuel Gauge (Left Margin, x: 70, y: 2240) */}
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
              <text x="-25" y="80">ШЕСТЕРЕНЧАТЫЙ БЛОК</text>
            </g>
          </g>

          {/* NANO-CODE SNIPPET 6: Gear State Pattern Matching (Right Margin, x: -60, y: 440) */}
          <g transform="translate(-60, 440)" stroke="url(#bioLineGrad)" strokeWidth="1">
            <rect x="0" y="0" width="220" height="54" rx="4" fill="#3b0764" fillOpacity="0.25" strokeDasharray="3 3" />
            <g fontFamily="monospace" fontSize="7.5" fill="currentColor">
              <text x="8" y="14" fill="#c084fc">;; Exhaustive Pattern Match</text>
              <text x="8" y="27" fill="#4ade80">(mt gear-state</text>
              <text x="16" y="38" fill="#4ade80">  ((:running r) (! throttle r)))</text>
            </g>
          </g>

          {/* Agent Vibe Secret S-Expression Frame */}
          <g transform="translate(-80, 520)" stroke="url(#bioLineGrad)" strokeWidth="1">
            <rect x="0" y="0" width="230" height="38" rx="6" fill="#3b0764" fillOpacity="0.3" strokeDasharray="3 3" />
            <text x="10" y="24" fontFamily="monospace" fontSize="8" fill="#4ade80">
              (! agent/vibe :chill true :parens :balanced)
            </text>
          </g>
        </g>
      </svg>
    </div>
  </div>
);
