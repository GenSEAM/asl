import React from 'react';

/**
 * CosmicLandscapeBackground
 * Full-Document Cyclic Scattered & Tilted Aerospace Blueprint Architecture:
 * 1. Fixed Chameleon Perch (Top-Left): Curled tail wrapped around vine passing through spiral eye.
 * 2. Full-Screen Background Grid: Fixed technical blueprint grid pattern.
 * 3. 14,400px Cyclic Gutter Streams (Left & Right):
 *    - Modular 1800px cycle containing 13 cult aerospace & engineering Easter eggs per gutter.
 *    - Seamlessly loops 8 times (0px to 14,400px) so the stream NEVER ends or leaves empty space when scrolling.
 *    - Organically scattered x-coordinates (zig-zagging between 38px and 135px) and varied tilts (-50° to +60°).
 *    - Reappearance guarantee: when one scroll finishes, the next cycle begins immediately with the same cult artifacts!
 */

// Left Gutter 1800px Cycle Template
const LeftGutterCycle: React.FC = () => (
  <>
    {/* 1. Conway's Glider (y: 80, x: 50, rotate -28) */}
    <g transform="translate(50, 80) rotate(-28)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
      <rect x="12" y="0" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
      <rect x="24" y="12" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
      <rect x="0" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
      <rect x="12" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
      <rect x="24" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
      <line x1="32" y1="32" x2="52" y2="52" strokeDasharray="2 2" opacity="0.6" />
    </g>

    {/* 2. Sputnik-1 (y: 220, x: 130, rotate 42) */}
    <g transform="translate(130, 220) rotate(42)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
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

    {/* 3. Vacuum Triode 12AX7 (y: 360, x: 38, rotate -18) */}
    <g transform="translate(38, 360) rotate(-18)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
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

    {/* 4. Turing Machine Tape (y: 500, x: 115, rotate 15) */}
    <g transform="translate(115, 500) rotate(15)" stroke="url(#leftBioGrad)" strokeWidth="1.1">
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

    {/* 5. Astrolabe Coordinate Scanner (y: 640, x: 42, rotate -45) */}
    <g transform="translate(42, 640) rotate(-45)" stroke="url(#leftBioGrad)" strokeWidth="1.3">
      <circle cx="0" cy="0" r="44" strokeDasharray="5 4" opacity="0.35" />
      <path d="M -34,-10 A 36 36 0 0 1 34,-10" strokeWidth="2" fill="#3b0764" fillOpacity="0.2" />
      <line x1="-34" y1="-10" x2="34" y2="-10" />
      <line x1="0" y1="-34" x2="0" y2="-50" strokeWidth="2.0" />
      <circle cx="0" cy="-50" r="3" fill="currentColor" />
    </g>

    {/* 6. 3.5" Diskette Avionics ROM (y: 780, x: 135, rotate 32) */}
    <g transform="translate(135, 780) rotate(32)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
      <polygon points="0,0 55,0 60,5 60,65 0,65" fill="#3b0764" fillOpacity="0.25" />
      <rect x="11" y="0" width="28" height="24" rx="2" fill="#581c87" fillOpacity="0.35" />
      <rect x="16" y="4" width="5" height="14" rx="1" fill="currentColor" fillOpacity="0.75" />
      <circle cx="30" cy="38" r="9" strokeDasharray="2 2" opacity="0.5" />
      <circle cx="30" cy="38" r="3" fill="currentColor" opacity="0.5" />
      <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
        <text x="8" y="58">ROM-144</text>
      </g>
    </g>

    {/* 7. Token Fuel Gauge (y: 920, x: 50, rotate -12) */}
    <g transform="translate(50, 920) rotate(-12)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
      <circle cx="0" cy="0" r="26" strokeDasharray="4 3" opacity="0.5" />
      <path d="M 0,0 L 16,-14" stroke="#4ade80" strokeWidth="2.0" />
      <circle cx="0" cy="0" r="3" fill="#4ade80" />
      <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.8">
        <text x="32" y="-4" fill="#4ade80">-80% TOK</text>
      </g>
    </g>

    {/* 8. Curiosity Rover Morse Track (y: 1060, x: 125, rotate -28) */}
    <g transform="translate(125, 1060) rotate(-28)" stroke="url(#leftBioGrad)" strokeWidth="1.3">
      <rect x="-42" y="-8" width="85" height="16" rx="2" fill="#3b0764" fillOpacity="0.2" />
      <circle cx="-32" cy="0" r="1.5" fill="currentColor" />
      <line x1="-26" y1="0" x2="-18" y2="0" strokeWidth="2" />
      <line x1="-14" y1="0" x2="-6" y2="0" strokeWidth="2" />
      <circle cx="2" cy="0" r="1.5" fill="currentColor" />
      <line x1="8" y1="0" x2="16" y2="0" strokeWidth="2" />
      <circle cx="24" cy="0" r="1.5" fill="currentColor" />
      <line x1="30" y1="0" x2="36" y2="0" strokeWidth="2" />
    </g>

    {/* 9. Wasm Bytecode Hexagon Node (y: 1200, x: 38, rotate 55) */}
    <g transform="translate(38, 1200) rotate(55)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
      <polygon points="0,-24 20,-12 20,12 0,24 -20,12 -20,-12" fill="#3b0764" fillOpacity="0.25" />
      <circle cx="0" cy="0" r="8" strokeDasharray="2 2" />
      <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.7">
        <text x="-12" y="3">WASM</text>
      </g>
    </g>

    {/* 10. Retro Audio Cassette Tape Spool (y: 1340, x: 128, rotate -35) */}
    <g transform="translate(128, 1340) rotate(-35)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
      <rect x="-35" y="-22" width="70" height="44" rx="4" fill="#3b0764" fillOpacity="0.2" />
      <circle cx="-16" cy="0" r="8" />
      <circle cx="16" cy="0" r="8" />
      <line x1="-16" y1="8" x2="16" y2="8" strokeDasharray="2 2" />
    </g>

    {/* 11. Transistor TO-92 (y: 1480, x: 48, rotate 24) */}
    <g transform="translate(48, 1480) rotate(24)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
      <path d="M -14,0 A 14 14 0 0 1 14,0 Z" fill="#3b0764" fillOpacity="0.3" strokeWidth="1.5" />
      <line x1="-8" y1="0" x2="-8" y2="28" />
      <line x1="0" y1="0" x2="0" y2="32" />
      <line x1="8" y1="0" x2="8" y2="28" />
      <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
        <text x="18" y="12">2N3904</text>
      </g>
    </g>

    {/* 12. Orbital Radar Sweep Arc (y: 1620, x: 122, rotate -50) */}
    <g transform="translate(122, 1620) rotate(-50)" stroke="url(#leftBioGrad)" strokeWidth="1.2">
      <circle cx="0" cy="0" r="32" strokeDasharray="3 3" opacity="0.4" />
      <circle cx="0" cy="0" r="18" strokeDasharray="2 2" opacity="0.6" />
      <circle cx="0" cy="0" r="3" fill="currentColor" />
      <line x1="0" y1="0" x2="28" y2="-16" stroke="#4ade80" strokeWidth="1.8" />
    </g>

    {/* 13. Fiber Optic Connector Ferrule (y: 1740, x: 44, rotate 18) */}
    <g transform="translate(44, 1740) rotate(18)" stroke="url(#leftBioGrad)" strokeWidth="1.3">
      <rect x="-8" y="-25" width="16" height="50" rx="3" fill="#3b0764" fillOpacity="0.3" />
      <circle cx="0" cy="0" r="2.5" fill="#4ade80" />
      <line x1="0" y1="-35" x2="0" y2="35" strokeDasharray="4 2" stroke="#4ade80" opacity="0.7" />
    </g>
  </>
);

// Right Gutter 1800px Cycle Template
const RightGutterCycle: React.FC = () => (
  <>
    {/* 1. Apollo 11 Lunar Module (y: 70, x: 125, rotate 16) */}
    <g transform="translate(125, 70) rotate(16)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
      <polygon points="7,0 23,0 30,7 30,20 23,27 7,27 0,20 0,7" fill="#3b0764" fillOpacity="0.3" />
      <path d="M 11,27 L 9,34 L 21,34 L 19,27 Z" fill="#581c87" fillOpacity="0.35" />
      <line x1="4" y1="21" x2="-10" y2="38" strokeWidth="1.3" />
      <ellipse cx="-10" cy="38" rx="3.5" ry="1.2" strokeWidth="1.1" />
      <line x1="26" y1="21" x2="40" y2="38" strokeWidth="1.3" />
      <ellipse cx="40" cy="38" rx="3.5" ry="1.2" strokeWidth="1.1" />
      <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6" transform="rotate(-16)">
        <text x="36" y="22">TRANQ-11</text>
      </g>
    </g>

    {/* 2. Voyager Golden Record Pulsar Map (y: 210, x: 45, rotate -30) */}
    <g transform="translate(45, 210) rotate(-30)" stroke="url(#rightBioGrad)" strokeWidth="1.0" opacity="0.65">
      <circle cx="0" cy="0" r="22" />
      <circle cx="0" cy="0" r="11" strokeDasharray="2 2" />
      <circle cx="0" cy="0" r="3" fill="currentColor" />
      <line x1="0" y1="0" x2="-18" y2="-9" />
      <line x1="0" y1="0" x2="16" y2="-12" />
      <line x1="0" y1="0" x2="-7" y2="18" />
      <line x1="0" y1="0" x2="14" y2="16" />
    </g>

    {/* 3. JWST 18-Hex Mirror Array (y: 350, x: 130, rotate 48) */}
    <g transform="translate(130, 350) rotate(48)" stroke="url(#rightBioGrad)" strokeWidth="1.1">
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

    {/* 4. Hollerith 80-Column Punched Card (y: 490, x: 38, rotate -22) */}
    <g transform="translate(38, 490) rotate(-22)" stroke="url(#rightBioGrad)" strokeWidth="1.1">
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

    {/* 5. Paperclip Wire Cable Retainer (y: 630, x: 125, rotate 60) */}
    <g transform="translate(125, 630) rotate(60)" stroke="url(#rightBioGrad)" strokeWidth="1.5">
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

    {/* 6. Saturnian Ringed Planet (y: 770, x: 45, rotate -16) */}
    <g transform="translate(45, 770) rotate(-16)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
      <circle cx="0" cy="0" r="34" fill="#4a044e" fillOpacity="0.25" />
      <ellipse cx="0" cy="0" rx="80" ry="24" strokeWidth="1.6" transform="rotate(-18)" />
      <ellipse cx="0" cy="0" rx="68" ry="19" strokeDasharray="4 3" transform="rotate(-18)" />
      <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.75">
        <text x="-20" y="48">OPS.RTA</text>
      </g>
    </g>

    {/* 7. Chrome 8-Bit Offline Dino Runner (y: 910, x: 120, rotate 8) */}
    <g transform="translate(120, 910) rotate(8)" stroke="none" fill="currentColor" opacity="0.6">
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

    {/* 8. HAL 9000 Eye Turret (y: 1050, x: 40, rotate -26) */}
    <g transform="translate(40, 1050) rotate(-26)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
      <rect x="-14" y="-22" width="28" height="44" rx="4" fill="#3b0764" fillOpacity="0.3" />
      <circle cx="0" cy="0" r="11" strokeWidth="1.5" />
      <circle cx="0" cy="0" r="6" fill="#ef4444" fillOpacity="0.8" stroke="#f87171" strokeWidth="1.1" />
      <circle cx="2" cy="-2" r="1.5" fill="#fff" opacity="0.9" />
      <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
        <text x="-12" y="30">HAL-9K</text>
      </g>
    </g>

    {/* 9. Bio-Mechanical Gear Drive (y: 1190, x: 130, rotate 45) */}
    <g transform="translate(130, 1190) rotate(45)" stroke="url(#rightBioGrad)" strokeWidth="1.3">
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

    {/* 10. Ferrite Core Memory Matrix (y: 1330, x: 48, rotate -48) */}
    <g transform="translate(48, 1330) rotate(-48)" stroke="url(#rightBioGrad)" strokeWidth="1.1">
      <rect x="-24" y="-24" width="48" height="48" fill="#3b0764" fillOpacity="0.2" />
      {[-12, 0, 12].map((gx) =>
        [-12, 0, 12].map((gy) => (
          <ellipse key={`${gx}-${gy}`} cx={gx} cy={gy} rx="4" ry="2" strokeWidth="1.2" transform={`rotate(45 ${gx} ${gy})`} />
        ))
      )}
      <line x1="-28" y1="-28" x2="28" y2="28" strokeDasharray="2 2" stroke="#4ade80" opacity="0.6" />
    </g>

    {/* 11. Shuttle Thermal Shield Tile Grid (y: 1470, x: 125, rotate 24) */}
    <g transform="translate(125, 1470) rotate(24)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
      <rect x="-28" y="-20" width="56" height="40" fill="#3b0764" fillOpacity="0.25" />
      <line x1="-28" y1="0" x2="28" y2="0" strokeWidth="1.4" />
      <line x1="0" y1="-20" x2="0" y2="20" strokeWidth="1.4" />
      <g fontFamily="monospace" fontSize="6" fill="currentColor" opacity="0.6">
        <text x="-22" y="-6">VT-04</text>
        <text x="6" y="14">VT-05</text>
      </g>
    </g>

    {/* 12. NE555 Timer IC Pinout (y: 1610, x: 42, rotate -35) */}
    <g transform="translate(42, 1610) rotate(-35)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
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

    {/* 13. CRT Oscilloscope Raster Sine Wave (y: 1740, x: 120, rotate 45) */}
    <g transform="translate(120, 1740) rotate(45)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
      <circle cx="0" cy="0" r="28" fill="#3b0764" fillOpacity="0.25" />
      <path d="M -22,0 Q -11,-16 0,0 Q 11,16 22,0" stroke="#4ade80" strokeWidth="1.8" />
    </g>
  </>
);

export const CosmicLandscapeBackground: React.FC = () => {
  // 8 cycles of 1800px = 14,400px continuous coverage
  const CYCLES = [0, 1, 2, 3, 4, 5, 6, 7];
  const CYCLE_HEIGHT = 1800;

  return (
    <div className="pointer-events-none select-none" aria-hidden="true">
      {/* 1. Ambient Lighting Auras & Grid */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden z-0">
        <div className="absolute top-6 left-6 w-[550px] h-[550px] bg-purple-600/12 dark:bg-purple-900/20 blur-[150px] rounded-full" />
        <div className="absolute top-1/3 right-8 w-[650px] h-[650px] bg-indigo-600/10 dark:bg-indigo-950/15 blur-[160px] rounded-full" />
        <div className="absolute bottom-16 left-1/4 w-[700px] h-[550px] bg-purple-900/12 blur-[160px] rounded-full" />

        {/* Blueprint Base Grid Pattern */}
        <svg className="w-full h-full opacity-25 dark:opacity-20 text-purple-400 dark:text-purple-300" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <pattern id="fixedBlueprintGrid" width="40" height="40" patternUnits="userSpaceOnUse">
              <path d="M 40 0 L 0 0 0 40" fill="none" stroke="currentColor" strokeWidth="0.5" opacity="0.4" />
              <path d="M 200 0 L 0 0 0 200" fill="none" stroke="currentColor" strokeWidth="1.0" opacity="0.6" />
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="url(#fixedBlueprintGrid)" />
        </svg>

        {/* Chameleon Perch (Top-Left) */}
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
              {/* 
                THE CYBER-VINE:
                Starts low at (-30, 145), passes right through the curled tail which wraps around it,
                cradles the belly, and sweeps UPWARDS between chameleon & satellite to the header!
              */}
              <path
                d="M -30,145 C 5,140 25,128 48,121 C 72,114 96,106 122,96 C 152,84 178,58 198,28 C 218,-2 232,-24 246,-45"
                stroke="url(#vineBranchGrad)"
                strokeWidth="3.4"
                strokeLinecap="round"
              />
              <path
                d="M -30,150 C 5,145 25,133 48,126 C 72,119 96,111 122,101 C 152,89 178,63 198,33 C 218,3 232,-19 246,-40"
                stroke="url(#vineBranchGrad)"
                strokeWidth="1.2"
                strokeDasharray="3 3"
                opacity="0.6"
              />

              {/* Delicate sprouting cyber-leaves climbing up towards header */}
              <g transform="translate(142, 80) rotate(-40)">
                <path d="M 0,0 Q 14,-9 28,0 Q 14,9 0,0" fill="#a855f7" fillOpacity="0.2" stroke="url(#vineBranchGrad)" strokeWidth="1.2" />
                <line x1="0" y1="0" x2="28" y2="0" stroke="url(#vineBranchGrad)" strokeWidth="0.8" />
              </g>
              <g transform="translate(182, 42) rotate(-58)">
                <path d="M 0,0 Q 12,-8 24,0 Q 12,8 0,0" fill="#a855f7" fillOpacity="0.2" stroke="url(#vineBranchGrad)" strokeWidth="1.2" />
                <line x1="0" y1="0" x2="24" y2="0" stroke="url(#vineBranchGrad)" strokeWidth="0.8" />
              </g>
              <g transform="translate(222, -4) rotate(-72)">
                <path d="M 0,0 Q 10,-7 20,0 Q 10,7 0,0" fill="#a855f7" fillOpacity="0.2" stroke="url(#vineBranchGrad)" strokeWidth="1.2" />
                <line x1="0" y1="0" x2="20" y2="0" stroke="url(#vineBranchGrad)" strokeWidth="0.8" />
              </g>

              {/* Spiral tendril curling near header */}
              <path
                d="M 238,-28 Q 250,-40 246,-50 Q 240,-56 230,-52 Q 225,-47 230,-42"
                stroke="url(#vineBranchGrad)"
                strokeWidth="1.4"
              />

              {/* 
                THE SCHEMATIC CHAMELEON:
                Perched securely on the horizontal section of the branch.
              */}
              <g transform="translate(5, 0)">
                {/* Spine and inward-spiraling tail */}
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

                {/* Front tail curl stroke: physically wraps in front of the branch */}
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

      {/* 2. DEDICATED LEFT CYCLIC GUTTER STREAM (14,400px continuous repeating loop) */}
      <div
        className="absolute top-0 left-0 w-32 sm:w-44 md:w-52 lg:w-60 pointer-events-none z-0 overflow-visible"
        style={{ height: `${CYCLES.length * CYCLE_HEIGHT}px` }}
      >
        <svg
          className="w-full h-full text-purple-400/40 dark:text-purple-300/35"
          viewBox={`0 0 180 ${CYCLES.length * CYCLE_HEIGHT}`}
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

          {/* 8 seamlessly repeating cycles down the left gutter */}
          {CYCLES.map((cycleIdx) => (
            <g key={cycleIdx} transform={`translate(0, ${cycleIdx * CYCLE_HEIGHT})`}>
              <LeftGutterCycle />
            </g>
          ))}
        </svg>
      </div>

      {/* 3. DEDICATED RIGHT CYCLIC GUTTER STREAM (14,400px continuous repeating loop) */}
      <div
        className="absolute top-0 right-0 w-32 sm:w-44 md:w-52 lg:w-60 pointer-events-none z-0 overflow-visible"
        style={{ height: `${CYCLES.length * CYCLE_HEIGHT}px` }}
      >
        <svg
          className="w-full h-full text-purple-400/40 dark:text-purple-300/35"
          viewBox={`0 0 180 ${CYCLES.length * CYCLE_HEIGHT}`}
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

          {/* 8 seamlessly repeating cycles down the right gutter */}
          {CYCLES.map((cycleIdx) => (
            <g key={cycleIdx} transform={`translate(0, ${cycleIdx * CYCLE_HEIGHT})`}>
              <RightGutterCycle />
            </g>
          ))}
        </svg>
      </div>
    </div>
  );
};
