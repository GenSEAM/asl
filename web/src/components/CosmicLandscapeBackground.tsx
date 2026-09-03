import React from 'react';

/**
 * CosmicLandscapeBackground
 * Full-Document Cyclic Scattered & Tilted Aerospace Blueprint Architecture:
 * 1. Fixed Chameleon Perch (Top-Left): Curled tail wrapped around vine passing through spiral eye.
 * 2. Full-Screen Background Grid: Fixed technical blueprint grid pattern.
 * 3. Left Deflecting Stream:
 *    - Items scroll up normally, but as they approach the chameleon (y <= 480 in viewport),
 *      they smoothly veer off to the left (X -> -220px) and bank into a turn, disappearing off-screen!
 *    - Zero collision with the chameleon!
 * 4. Right Gutter Stream:
 *    - Strictly bounded to document height with ~280px generous spacing.
 */

const CYCLE_HEIGHT = 2800;
const CYCLES = [0, 1, 2, 3, 4]; // 5 * 2800 = 14,000px continuous coverage

// Definition of Left Gutter Easter Eggs
const LEFT_ITEMS = [
  {
    baseX: 130,
    baseRot: 40,
    render: () => (
      <>
        {/* Sputnik-1 */}
        <circle cx="0" cy="0" r="10" fill="#3b0764" fillOpacity="0.3" strokeWidth="1.5" />
        <ellipse cx="0" cy="0" rx="10" ry="3" strokeDasharray="2 2" opacity="0.5" />
        <line x1="-7" y1="-7" x2="-48" y2="-28" strokeWidth="1.1" />
        <line x1="-7" y1="7" x2="-52" y2="22" strokeWidth="1.1" />
        <line x1="7" y1="-7" x2="42" y2="-36" strokeWidth="1.0" strokeDasharray="2 1" opacity="0.6" />
        <line x1="7" y1="7" x2="46" y2="28" strokeWidth="1.0" strokeDasharray="2 1" opacity="0.6" />
        <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6" transform="rotate(-40)">
          <text x="14" y="-10">PS-01</text>
        </g>
      </>
    ),
  },
  {
    baseX: 40,
    baseRot: -18,
    render: () => (
      <>
        {/* Vacuum Triode 12AX7 */}
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
      </>
    ),
  },
  {
    baseX: 120,
    baseRot: 15,
    render: () => (
      <>
        {/* Turing Machine Tape */}
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
      </>
    ),
  },
  {
    baseX: 45,
    baseRot: -45,
    render: () => (
      <>
        {/* Astrolabe */}
        <circle cx="0" cy="0" r="44" strokeDasharray="5 4" opacity="0.35" />
        <path d="M -34,-10 A 36 36 0 0 1 34,-10" strokeWidth="2" fill="#3b0764" fillOpacity="0.2" />
        <line x1="-34" y1="-10" x2="34" y2="-10" />
        <line x1="0" y1="-34" x2="0" y2="-50" strokeWidth="2.0" />
        <circle cx="0" cy="-50" r="3" fill="currentColor" />
      </>
    ),
  },
  {
    baseX: 135,
    baseRot: 30,
    render: () => (
      <>
        {/* 3.5" Diskette */}
        <polygon points="0,0 55,0 60,5 60,65 0,65" fill="#3b0764" fillOpacity="0.25" />
        <rect x="11" y="0" width="28" height="24" rx="2" fill="#581c87" fillOpacity="0.35" />
        <rect x="16" y="4" width="5" height="14" rx="1" fill="currentColor" fillOpacity="0.75" />
        <circle cx="30" cy="38" r="9" strokeDasharray="2 2" opacity="0.5" />
        <circle cx="30" cy="38" r="3" fill="currentColor" opacity="0.5" />
        <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
          <text x="8" y="58">ROM-144</text>
        </g>
      </>
    ),
  },
  {
    baseX: 50,
    baseRot: -12,
    render: () => (
      <>
        {/* Fuel Gauge */}
        <circle cx="0" cy="0" r="26" strokeDasharray="4 3" opacity="0.5" />
        <path d="M 0,0 L 16,-14" stroke="#4ade80" strokeWidth="2.0" />
        <circle cx="0" cy="0" r="3" fill="#4ade80" />
        <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.8">
          <text x="32" y="-4" fill="#4ade80">-80% TOK</text>
        </g>
      </>
    ),
  },
  {
    baseX: 125,
    baseRot: -26,
    render: () => (
      <>
        {/* Curiosity Rover Track */}
        <rect x="-42" y="-8" width="85" height="16" rx="2" fill="#3b0764" fillOpacity="0.2" />
        <circle cx="-32" cy="0" r="1.5" fill="currentColor" />
        <line x1="-26" y1="0" x2="-18" y2="0" strokeWidth="2" />
        <line x1="-14" y1="0" x2="-6" y2="0" strokeWidth="2" />
        <circle cx="2" cy="0" r="1.5" fill="currentColor" />
        <line x1="8" y1="0" x2="16" y2="0" strokeWidth="2" />
        <circle cx="24" cy="0" r="1.5" fill="currentColor" />
        <line x1="30" y1="0" x2="36" y2="0" strokeWidth="2" />
      </>
    ),
  },
  {
    baseX: 40,
    baseRot: 50,
    render: () => (
      <>
        {/* Wasm Hexagon */}
        <polygon points="0,-24 20,-12 20,12 0,24 -20,12 -20,-12" fill="#3b0764" fillOpacity="0.25" />
        <circle cx="0" cy="0" r="8" strokeDasharray="2 2" />
        <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.7">
          <text x="-12" y="3">WASM</text>
        </g>
      </>
    ),
  },
  {
    baseX: 125,
    baseRot: -25,
    render: () => (
      <>
        {/* 2N3904 Transistor */}
        <path d="M -14,0 A 14 14 0 0 1 14,0 Z" fill="#3b0764" fillOpacity="0.3" strokeWidth="1.5" />
        <line x1="-8" y1="0" x2="-8" y2="28" />
        <line x1="0" y1="0" x2="0" y2="32" />
        <line x1="8" y1="0" x2="8" y2="28" />
        <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
          <text x="18" y="12">2N3904</text>
        </g>
      </>
    ),
  },
  {
    baseX: 50,
    baseRot: -28,
    render: () => (
      <>
        {/* Conway Glider */}
        <rect x="12" y="0" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
        <rect x="24" y="12" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
        <rect x="0" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
        <rect x="12" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
        <rect x="24" y="24" width="8" height="8" fill="#c084fc" fillOpacity="0.45" />
        <line x1="32" y1="32" x2="52" y2="52" strokeDasharray="2 2" opacity="0.6" />
      </>
    ),
  },
];

// Left Stream with Smooth Deflection veering to the left before reaching chameleon
const LeftDeflectingGutterStream: React.FC = () => {
  const [scrollY, setScrollY] = React.useState(0);
  const [viewportH, setViewportH] = React.useState(typeof window !== 'undefined' ? window.innerHeight : 900);
  const [docH, setDocH] = React.useState(typeof document !== 'undefined' ? document.documentElement.scrollHeight : 12000);

  React.useEffect(() => {
    let ticking = false;
    const update = () => {
      setScrollY(window.scrollY);
      setViewportH(window.innerHeight);
      setDocH(document.documentElement.scrollHeight);
      ticking = false;
    };

    const onScroll = () => {
      if (!ticking) {
        window.requestAnimationFrame(update);
        ticking = true;
      }
    };

    update();
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
    };
  }, []);

  const STEP = 280;
  const START_Y = 520;
  const maxK = Math.max(0, Math.floor((docH - START_Y - 200) / STEP));
  const minK = Math.max(0, Math.floor((scrollY - 100 - START_Y) / STEP));
  const endK = Math.min(maxK, Math.ceil((scrollY + viewportH + 100 - START_Y) / STEP));

  const visibleItems = [];
  for (let k = minK; k <= endK; k++) {
    const docY = START_Y + k * STEP;
    const viewY = docY - scrollY;
    if (viewY < -100 || viewY > viewportH + 100) continue;

    const itemDef = LEFT_ITEMS[k % LEFT_ITEMS.length];

    // Smooth deflection to the left when approaching chameleon (viewY <= 480)
    let xOff = 0;
    let extraRot = 0;
    let opacity = 0.85;

    if (viewY <= 480) {
      // t ranges from 0 (at 480px) to 1 (at 120px)
      const t = Math.max(0, Math.min(1, (480 - viewY) / 360));
      // Ease curve: veers smoothly to the left
      const ease = Math.pow(t, 1.7);
      xOff = -ease * 240; // Drifts 240px to the left (off-screen)
      extraRot = -ease * 35; // Banks 35 degrees into the turn
      opacity = Math.max(0, 0.85 * (1 - ease * 1.2));
    }

    visibleItems.push({
      key: k,
      x: itemDef.baseX + xOff,
      y: viewY,
      rot: itemDef.baseRot + extraRot,
      opacity,
      render: itemDef.render,
    });
  }

  return (
    <div className="fixed top-0 bottom-0 left-0 w-32 sm:w-44 md:w-52 lg:w-60 pointer-events-none z-0 overflow-visible">
      <svg
        className="w-full h-full text-purple-400/40 dark:text-purple-300/35 overflow-visible"
        viewBox={`0 0 180 ${viewportH}`}
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

        {/* Blueprint dashed guideline showing the diversion trajectory out to the left */}
        <path
          d="M 120,480 C 110,380 50,260 -60,140"
          stroke="url(#leftBioGrad)"
          strokeWidth="1.2"
          strokeDasharray="4 4"
          opacity="0.25"
        />

        {visibleItems.map(({ key, x, y, rot, opacity, render }) => (
          <g
            key={key}
            transform={`translate(${x}, ${y}) rotate(${rot})`}
            stroke="url(#leftBioGrad)"
            strokeWidth="1.2"
            opacity={opacity}
          >
            {render()}
          </g>
        ))}
      </svg>
    </div>
  );
};

// Right Gutter 2800px Cycle (10 elements spaced by 280px)
const RightGutterCycle: React.FC = () => (
  <>
    {/* 1. Apollo 11 Lunar Module (y: 200, x: 125, rotate 16) */}
    <g transform="translate(125, 200) rotate(16)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
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

    {/* 2. Voyager Golden Record Pulsar Map (y: 480, x: 45, rotate -30) */}
    <g transform="translate(45, 480) rotate(-30)" stroke="url(#rightBioGrad)" strokeWidth="1.0" opacity="0.65">
      <circle cx="0" cy="0" r="22" />
      <circle cx="0" cy="0" r="11" strokeDasharray="2 2" />
      <circle cx="0" cy="0" r="3" fill="currentColor" />
      <line x1="0" y1="0" x2="-18" y2="-9" />
      <line x1="0" y1="0" x2="16" y2="-12" />
      <line x1="0" y1="0" x2="-7" y2="18" />
      <line x1="0" y1="0" x2="14" y2="16" />
    </g>

    {/* 3. JWST 18-Hex Mirror Array (y: 760, x: 130, rotate 45) */}
    <g transform="translate(130, 760) rotate(45)" stroke="url(#rightBioGrad)" strokeWidth="1.1">
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

    {/* 4. Hollerith 80-Column Punched Card (y: 1040, x: 40, rotate -22) */}
    <g transform="translate(40, 1040) rotate(-22)" stroke="url(#rightBioGrad)" strokeWidth="1.1">
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

    {/* 5. Paperclip Wire Cable Retainer (y: 1320, x: 125, rotate 55) */}
    <g transform="translate(125, 1320) rotate(55)" stroke="url(#rightBioGrad)" strokeWidth="1.5">
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

    {/* 6. Saturnian Ringed Planet (y: 1600, x: 45, rotate -16) */}
    <g transform="translate(45, 1600) rotate(-16)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
      <circle cx="0" cy="0" r="34" fill="#4a044e" fillOpacity="0.25" />
      <ellipse cx="0" cy="0" rx="80" ry="24" strokeWidth="1.6" transform="rotate(-18)" />
      <ellipse cx="0" cy="0" rx="68" ry="19" strokeDasharray="4 3" transform="rotate(-18)" />
      <g fontFamily="monospace" fontSize="7" fill="currentColor" opacity="0.75">
        <text x="-20" y="48">OPS.RTA</text>
      </g>
    </g>

    {/* 7. Chrome 8-Bit Offline Dino Runner (y: 1880, x: 120, rotate 8) */}
    <g transform="translate(120, 1880) rotate(8)" stroke="none" fill="currentColor" opacity="0.6">
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

    {/* 8. HAL 9000 Eye Turret (y: 2160, x: 40, rotate -26) */}
    <g transform="translate(40, 2160) rotate(-26)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
      <rect x="-14" y="-22" width="28" height="44" rx="4" fill="#3b0764" fillOpacity="0.3" />
      <circle cx="0" cy="0" r="11" strokeWidth="1.5" />
      <circle cx="0" cy="0" r="6" fill="#ef4444" fillOpacity="0.8" stroke="#f87171" strokeWidth="1.1" />
      <circle cx="2" cy="-2" r="1.5" fill="#fff" opacity="0.9" />
      <g fontFamily="monospace" fontSize="6.5" fill="currentColor" opacity="0.6">
        <text x="-12" y="30">HAL-9K</text>
      </g>
    </g>

    {/* 9. Bio-Mechanical Gear Drive (y: 2440, x: 130, rotate 45) */}
    <g transform="translate(130, 2440) rotate(45)" stroke="url(#rightBioGrad)" strokeWidth="1.3">
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

    {/* 10. NE555 Timer IC Pinout (y: 2720, x: 45, rotate -35) */}
    <g transform="translate(45, 2720) rotate(-35)" stroke="url(#rightBioGrad)" strokeWidth="1.2">
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
  </>
);

export const CosmicLandscapeBackground: React.FC = () => {
  return (
    <div className="absolute inset-0 pointer-events-none select-none overflow-hidden z-0" aria-hidden="true">
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
                Starts low on left edge at (-30, 160), passes directly through the tail's circular spiral eye at (52, 95),
                cradles under the belly at (95, 74), and sweeps UPWARDS to the top header (-50)!
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

      {/* 2. DEDICATED LEFT DEFLECTING GUTTER STREAM (Smoothly veers left before chameleon) */}
      <LeftDeflectingGutterStream />

      {/* 3. DEDICATED RIGHT CYCLIC GUTTER STREAM (Strictly bounded to page height) */}
      <div className="absolute top-0 bottom-0 right-0 w-32 sm:w-44 md:w-52 lg:w-60 pointer-events-none overflow-hidden">
        <svg
          className="w-full h-full text-purple-400/40 dark:text-purple-300/35"
          viewBox={`0 0 180 ${CYCLES.length * CYCLE_HEIGHT}`}
          preserveAspectRatio="xMidYMin slice"
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

          {/* Seamlessly repeating cycles down the right gutter */}
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
