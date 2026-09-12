(module asl-web/CosmicLandscapeBackground
  :d "Full-Document Cyclic Scattered & Tilted Aerospace Blueprint Background in pure ASL."
  :x [render-blueprint-grid render-chameleon-perch render-left-deflecting-stream render-right-cyclic-stream render-cosmic-background cosmic-landscape-background]
  :i [(asl-text/string :a s)])

(df render-blueprint-grid ()
  :d "Fixed technical blueprint grid pattern."
  "<svg class=\"w-full h-full opacity-25 dark:opacity-20 text-purple-400 dark:text-purple-300\" xmlns=\"http://www.w3.org/2000/svg\"><defs><pattern id=\"fixedBlueprintGrid\" width=\"40\" height=\"40\" patternUnits=\"userSpaceOnUse\"><path d=\"M 40 0 L 0 0 0 40\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"0.5\" opacity=\"0.4\" /><path d=\"M 200 0 L 0 0 0 200\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.0\" opacity=\"0.6\" /></pattern></defs><rect width=\"100%\" height=\"100%\" fill=\"url(#fixedBlueprintGrid)\" /></svg>")

(df render-chameleon-perch ()
  :d "Top-left schematic chameleon perched on cyber-vine with glowing SVG filters."
  "<div class=\"fixed top-12 sm:top-14 left-2 sm:left-6 lg:left-10 w-72 sm:w-84 lg:w-[440px] h-auto opacity-40 dark:opacity-45 transition-all z-10\"><svg viewBox=\"0 0 260 160\" class=\"w-full h-auto text-signal overflow-visible\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><defs><linearGradient id=\"vineBranchGrad\" x1=\"0%\" y1=\"100%\" x2=\"100%\" y2=\"0%\"><stop offset=\"0%\" stop-color=\"#7e22ce\" /><stop offset=\"45%\" stop-color=\"#a855f7\" /><stop offset=\"100%\" stop-color=\"#c084fc\" /></linearGradient><linearGradient id=\"chameleonGradFixed\" x1=\"20%\" y1=\"0%\" x2=\"80%\" y2=\"100%\"><stop offset=\"0%\" stop-color=\"rgb(var(--signal-soft))\" /><stop offset=\"70%\" stop-color=\"rgb(var(--signal))\" /><stop offset=\"100%\" stop-color=\"#9333ea\" /></linearGradient><filter id=\"fixedAmbientGlow\" x=\"-30%\" y=\"-30%\" width=\"160%\" height=\"160%\"><feGaussianBlur stdDeviation=\"3\" result=\"glow\" /><feComposite in=\"SourceGraphic\" in2=\"glow\" operator=\"over\" /></filter></defs><g filter=\"url(#fixedAmbientGlow)\"><path d=\"M -30,160 C 2,142 24,118 52,95 C 78,74 104,72 134,54 C 168,34 202,0 234,-48\" stroke=\"url(#vineBranchGrad)\" stroke-width=\"3.4\" stroke-linecap=\"round\" /><path d=\"M -30,165 C 2,147 24,123 52,100 C 78,79 104,77 134,59 C 168,39 202,5 234,-43\" stroke=\"url(#vineBranchGrad)\" stroke-width=\"1.2\" stroke-dasharray=\"3 3\" opacity=\"0.55\" /><g transform=\"translate(138, 72) rotate(-42)\"><path d=\"M 0,0 Q 14,-9 28,0 Q 14,9 0,0\" fill=\"#a855f7\" fill-opacity=\"0.2\" stroke=\"url(#vineBranchGrad)\" stroke-width=\"1.2\" /><line x1=\"0\" y1=\"0\" x2=\"28\" y2=\"0\" stroke=\"url(#vineBranchGrad)\" stroke-width=\"0.8\" /></g><g transform=\"translate(178, 36) rotate(-60)\"><path d=\"M 0,0 Q 12,-8 24,0 Q 12,8 0,0\" fill=\"#a855f7\" fill-opacity=\"0.2\" stroke=\"url(#vineBranchGrad)\" stroke-width=\"1.2\" /><line x1=\"0\" y1=\"0\" x2=\"24\" y2=\"0\" stroke=\"url(#vineBranchGrad)\" stroke-width=\"0.8\" /></g><g transform=\"translate(216, -8) rotate(-75)\"><path d=\"M 0,0 Q 10,-7 20,0 Q 10,7 0,0\" fill=\"#a855f7\" fill-opacity=\"0.2\" stroke=\"url(#vineBranchGrad)\" stroke-width=\"1.2\" /><line x1=\"0\" y1=\"0\" x2=\"20\" y2=\"0\" stroke=\"url(#vineBranchGrad)\" stroke-width=\"0.8\" /></g><path d=\"M 232,-35 Q 244,-47 240,-56 Q 234,-62 225,-58 Q 220,-52 225,-47\" stroke=\"url(#vineBranchGrad)\" stroke-width=\"1.4\" /><g transform=\"translate(5, 0)\"><path d=\"M 68 20 C 62 13, 56 12, 53 14 C 49 16, 49 22, 53 25 C 35 28, 16 46, 12 70 C 8 95, 18 116, 38 122 C 56 127, 72 116, 70 96 C 68 81, 52 76, 44 86 C 37 94, 44 104, 53 102 C 59 100, 59 93, 54 91\" stroke=\"url(#chameleonGradFixed)\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" /><path d=\"M 68 20 C 85 24, 102 36, 98 52 C 94 62, 80 65, 68 64\" stroke=\"url(#chameleonGradFixed)\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" /><circle cx=\"82\" cy=\"40\" r=\"9\" stroke=\"url(#chameleonGradFixed)\" stroke-width=\"2.2\" /><circle cx=\"82\" cy=\"40\" r=\"3\" fill=\"rgb(var(--signal-soft))\" opacity=\"0.9\" /><path d=\"M 68 64 C 52 64, 40 68, 32 78 C 25 87, 26 96, 30 102\" stroke=\"url(#chameleonGradFixed)\" stroke-width=\"1.8\" stroke-linecap=\"round\" /><circle cx=\"53\" cy=\"14\" r=\"1.5\" fill=\"rgb(var(--signal-soft))\" opacity=\"0.7\" /><circle cx=\"98\" cy=\"52\" r=\"1.5\" fill=\"rgb(var(--signal-soft))\" opacity=\"0.7\" /><circle cx=\"38\" cy=\"122\" r=\"1.5\" fill=\"rgb(var(--signal-soft))\" opacity=\"0.7\" /><path d=\"M 44 86 C 37 94, 44 104, 53 102 C 59 100, 59 93, 54 91\" stroke=\"url(#chameleonGradFixed)\" stroke-width=\"2.6\" stroke-linecap=\"round\" /></g></g></svg></div>")

(df render-left-deflecting-stream ()
  :d "Left Gutter stream deflecting smoothly out along diversion arc away from the perched chameleon on scroll."
  "<div class=\"fixed top-0 bottom-0 left-0 w-32 sm:w-44 md:w-52 lg:w-60 pointer-events-none z-0 overflow-visible\"><svg id=\"left-deflecting-svg\" class=\"w-full h-full text-purple-400/40 dark:text-purple-300/35 overflow-visible\" viewBox=\"0 0 180 900\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><defs><linearGradient id=\"leftBioGrad\" x1=\"0%\" y1=\"0%\" x2=\"100%\" y2=\"100%\"><stop offset=\"0%\" stop-color=\"#c084fc\" stop-opacity=\"0.8\" /><stop offset=\"60%\" stop-color=\"#a855f7\" stop-opacity=\"0.5\" /><stop offset=\"100%\" stop-color=\"#7e22ce\" stop-opacity=\"0.3\" /></linearGradient><linearGradient id=\"amberGlowL\" x1=\"0%\" y1=\"0%\" x2=\"100%\" y2=\"100%\"><stop offset=\"0%\" stop-color=\"#fbbf24\" stop-opacity=\"0.75\" /><stop offset=\"100%\" stop-color=\"#d97706\" stop-opacity=\"0.3\" /></linearGradient></defs><path d=\"M 125,560 C 115,440 60,300 -80,180\" stroke=\"url(#leftBioGrad)\" stroke-width=\"1.4\" stroke-dasharray=\"5 3\" opacity=\"0.35\" /><g font-family=\"monospace\" font-size=\"6\" fill=\"#c084fc\" opacity=\"0.35\" transform=\"translate(16, 290) rotate(-38)\"><text x=\"0\" y=\"0\">&lt;&lt; DIVERSION-ARC &lt;&lt;</text></g><g id=\"left-stream-items\"></g></svg>
<script>
(function() {
  var items = [
  { bx: 130, br: 40, svg: \"<circle cx='0' cy='0' r='10' fill='#3b0764' fill-opacity='0.3' stroke-width='1.5' /><ellipse cx='0' cy='0' rx='10' ry='3' stroke-dasharray='2 2' opacity='0.5' /><line x1='-7' y1='-7' x2='-48' y2='-28' stroke-width='1.1' /><line x1='-7' y1='7' x2='-52' y2='22' stroke-width='1.1' /><line x1='7' y1='-7' x2='42' y2='-36' stroke-width='1.0' stroke-dasharray='2 1' opacity='0.6' /><line x1='7' y1='7' x2='46' y2='28' stroke-width='1.0' stroke-dasharray='2 1' opacity='0.6' /><g font-family='monospace' font-size='6.5' fill='currentColor' opacity='0.6' transform='rotate(-40)'><text x='14' y='-10'>PS-01</text></g>\" },
  { bx: 40, br: -18, svg: \"<path d='M 0,50 L 0,22 C 0,7 32,7 32,22 L 32,50 Z' fill='#4a044e' fill-opacity='0.2' /><line x1='8' y1='18' x2='24' y2='18' stroke-width='1.6' /><line x1='16' y1='7' x2='16' y2='18' /><path d='M 10,26 L 13,29 L 16,26 L 19,29 L 22,26' stroke-width='1.1' stroke-dasharray='1 1' /><path d='M 11,36 L 21,36' stroke='url(#amberGlowL)' stroke-width='1.6' /><line x1='7' y1='50' x2='7' y2='58' /><line x1='16' y1='50' x2='16' y2='60' /><line x1='25' y1='50' x2='25' y2='58' /><g font-family='monospace' font-size='6.5' fill='currentColor' opacity='0.55'><text x='36' y='28'>V-12</text></g>\" },
  { bx: 120, br: 15, svg: \"<rect x='-55' y='-11' width='110' height='22' rx='2' fill='#3b0764' fill-opacity='0.2' /><line x1='-33' y1='-11' x2='-33' y2='11' /><line x1='-11' y1='-11' x2='-11' y2='11' /><line x1='11' y1='-11' x2='11' y2='11' /><line x1='33' y1='-11' x2='33' y2='11' /><path d='M 0,-18 L 0,-11 M -3,-14 L 0,-11 L 3,-14' stroke-width='1.4' /><g font-family='monospace' font-size='7' fill='currentColor' opacity='0.8'><text x='-48' y='4'>1</text><text x='-26' y='4'>0</text><text x='-4' y='4' fill='#4ade80'>1</text><text x='18' y='4'>1</text><text x='40' y='4'>0</text></g>\" },
  { bx: 45, br: -45, svg: \"<circle cx='0' cy='0' r='44' stroke-dasharray='5 4' opacity='0.35' /><path d='M -34,-10 A 36 36 0 0 1 34,-10' stroke-width='2' fill='#3b0764' fill-opacity='0.2' /><line x1='-34' y1='-10' x2='34' y2='-10' /><line x1='0' y1='-34' x2='0' y2='-50' stroke-width='2.0' /><circle cx='0' cy='-50' r='3' fill='currentColor' />\" },
  { bx: 135, br: 30, svg: \"<polygon points='0,0 55,0 60,5 60,65 0,65' fill='#3b0764' fill-opacity='0.25' /><rect x='11' y='0' width='28' height='24' rx='2' fill='#581c87' fill-opacity='0.35' /><rect x='16' y='4' width='5' height='14' rx='1' fill='currentColor' fill-opacity='0.75' /><circle cx='30' cy='38' r='9' stroke-dasharray='2 2' opacity='0.5' /><circle cx='30' cy='38' r='3' fill='currentColor' opacity='0.5' /><g font-family='monospace' font-size='6.5' fill='currentColor' opacity='0.6'><text x='8' y='58'>ROM-144</text></g>\" },
  { bx: 50, br: -12, svg: \"<circle cx='0' cy='0' r='26' stroke-dasharray='4 3' opacity='0.5' /><path d='M 0,0 L 16,-14' stroke='#4ade80' stroke-width='2.0' /><circle cx='0' cy='0' r='3' fill='#4ade80' /><g font-family='monospace' font-size='7' fill='currentColor' opacity='0.8'><text x='32' y='-4' fill='#4ade80'>-80% TOK</text></g>\" },
  { bx: 125, br: -26, svg: \"<rect x='-42' y='-8' width='85' height='16' rx='2' fill='#3b0764' fill-opacity='0.2' /><circle cx='-32' cy='0' r='1.5' fill='currentColor' /><line x1='-26' y1='0' x2='-18' y2='0' stroke-width='2' /><line x1='-14' y1='0' x2='-6' y2='0' stroke-width='2' /><circle cx='2' cy='0' r='1.5' fill='currentColor' /><line x1='8' y1='0' x2='16' y2='0' stroke-width='2' /><circle cx='24' cy='0' r='1.5' fill='currentColor' /><line x1='30' y1='0' x2='36' y2='0' stroke-width='2' />\" },
  { bx: 40, br: 50, svg: \"<polygon points='0,-24 20,-12 20,12 0,24 -20,12 -20,-12' fill='#3b0764' fill-opacity='0.25' /><circle cx='0' cy='0' r='8' stroke-dasharray='2 2' /><g font-family='monospace' font-size='6.5' fill='currentColor' opacity='0.7'><text x='-12' y='3'>WASM</text></g>\" },
  { bx: 125, br: -25, svg: \"<path d='M -14,0 A 14 14 0 0 1 14,0 Z' fill='#3b0764' fill-opacity='0.3' stroke-width='1.5' /><line x1='-8' y1='0' x2='-8' y2='28' /><line x1='0' y1='0' x2='0' y2='32' /><line x1='8' y1='0' x2='8' y2='28' /><g font-family='monospace' font-size='6.5' fill='currentColor' opacity='0.6'><text x='18' y='12'>2N3904</text></g>\" },
  { bx: 50, br: -28, svg: \"<rect x='12' y='0' width='8' height='8' fill='#c084fc' fill-opacity='0.45' /><rect x='24' y='12' width='8' height='8' fill='#c084fc' fill-opacity='0.45' /><rect x='0' y='24' width='8' height='8' fill='#c084fc' fill-opacity='0.45' /><rect x='12' y='24' width='8' height='8' fill='#c084fc' fill-opacity='0.45' /><rect x='24' y='24' width='8' height='8' fill='#c084fc' fill-opacity='0.45' /><line x1='32' y1='32' x2='52' y2='52' stroke-dasharray='2 2' opacity='0.6' />\" }
];
  var container = document.getElementById('left-stream-items');
  var svg = document.getElementById('left-deflecting-svg');
  if (!container || !svg) return;

  var ticking = false;
  function update() {
    ticking = false;
    var scrollY = window.scrollY || window.pageYOffset || 0;
    var vh = window.innerHeight || 900;
    var docH = document.documentElement.scrollHeight || 12000;
    svg.setAttribute('viewBox', '0 0 180 ' + vh);

    var STEP = 280;
    var START_Y = 520;
    var maxK = Math.max(0, Math.floor((docH - START_Y - 200) / STEP));
    var minK = Math.max(0, Math.floor((scrollY - 100 - START_Y) / STEP));
    var endK = Math.min(maxK, Math.ceil((scrollY + vh + 100 - START_Y) / STEP));

    var html = '';
    for (var k = minK; k <= endK; k++) {
      var docY = START_Y + k * STEP;
      var viewY = docY - scrollY;
      if (viewY < -100 || viewY > vh + 100) continue;

      var item = items[k % items.length];
      var xOff = 0;
      var extraRot = 0;
      var opacity = 0.85;

      if (viewY <= 560) {
        var t = Math.max(0, Math.min(1, (560 - viewY) / 420));
        var ease = t * t * (3 - 2 * t);
        xOff = -ease * 260;
        extraRot = -ease * 42;
        opacity = Math.max(0, 0.85 * (1 - Math.pow(t, 1.3)));
      }

      var x = item.bx + xOff;
      var rot = item.br + extraRot;
      html += '<g transform=\"translate(' + x.toFixed(1) + ', ' + viewY.toFixed(1) + ') rotate(' + rot.toFixed(1) + ')\" stroke=\"url(#leftBioGrad)\" stroke-width=\"1.2\" opacity=\"' + opacity.toFixed(3) + '\" style=\"transition:transform 0.08s ease-out,opacity 0.08s ease-out\">' + item.svg + '</g>';
    }
    container.innerHTML = html;
  }

  window.addEventListener('scroll', function() {
    if (!ticking) {
      window.requestAnimationFrame(update);
      ticking = true;
    }
  }, { passive: true });
  window.addEventListener('resize', function() {
    if (!ticking) {
      window.requestAnimationFrame(update);
      ticking = true;
    }
  }, { passive: true });
  update();
})();
</script>
</div>")

(df render-right-cyclic-stream ()
  :d "Right Gutter cyclic aerospace relics stream bounded to page."
  "<div class=\"absolute top-0 bottom-0 right-0 w-32 sm:w-44 md:w-52 lg:w-60 pointer-events-none overflow-hidden\"><svg class=\"w-full h-full text-purple-400/40 dark:text-purple-300/35\" viewBox=\"0 0 180 14000\" preserveAspectRatio=\"xMidYMin slice\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><defs><linearGradient id=\"rightBioGrad\" x1=\"0%\" y1=\"0%\" x2=\"100%\" y2=\"100%\"><stop offset=\"0%\" stop-color=\"#c084fc\" stop-opacity=\"0.8\" /><stop offset=\"60%\" stop-color=\"#a855f7\" stroke-opacity=\"0.5\" /><stop offset=\"100%\" stop-color=\"#7e22ce\" stop-opacity=\"0.3\" /></linearGradient><g id=\"rightGutterCycle\">
    <g transform=\"translate(125, 200) rotate(16)\" stroke=\"url(#rightBioGrad)\" stroke-width=\"1.2\">
      <polygon points=\"7,0 23,0 30,7 30,20 23,27 7,27 0,20 0,7\" fill=\"#3b0764\" fill-opacity=\"0.3\" />
      <path d=\"M 11,27 L 9,34 L 21,34 L 19,27 Z\" fill=\"#581c87\" fill-opacity=\"0.35\" />
      <line x1=\"4\" y1=\"21\" x2=\"-10\" y2=\"38\" stroke-width=\"1.3\" />
      <ellipse cx=\"-10\" cy=\"38\" rx=\"3.5\" ry=\"1.2\" stroke-width=\"1.1\" />
      <line x1=\"26\" y1=\"21\" x2=\"40\" y2=\"38\" stroke-width=\"1.3\" />
      <ellipse cx=\"40\" cy=\"38\" rx=\"3.5\" ry=\"1.2\" stroke-width=\"1.1\" />
      <g font-family=\"monospace\" font-size=\"6.5\" fill=\"currentColor\" opacity=\"0.6\" transform=\"rotate(-16)\">
        <text x=\"36\" y=\"22\">TRANQ-11</text>
      </g>
    </g>

    <g transform=\"translate(45, 480) rotate(-30)\" stroke=\"url(#rightBioGrad)\" stroke-width=\"1.0\" opacity=\"0.65\">
      <circle cx=\"0\" cy=\"0\" r=\"22\" />
      <circle cx=\"0\" cy=\"0\" r=\"11\" stroke-dasharray=\"2 2\" />
      <circle cx=\"0\" cy=\"0\" r=\"3\" fill=\"currentColor\" />
      <line x1=\"0\" y1=\"0\" x2=\"-18\" y2=\"-9\" />
      <line x1=\"0\" y1=\"0\" x2=\"16\" y2=\"-12\" />
      <line x1=\"0\" y1=\"0\" x2=\"-7\" y2=\"18\" />
      <line x1=\"0\" y1=\"0\" x2=\"14\" y2=\"16\" />
    </g>

    <g transform=\"translate(130, 760) rotate(45)\" stroke=\"url(#rightBioGrad)\" stroke-width=\"1.1\">
      <polygon points=\"0,-7 6,-3.5 6,3.5 0,7 -6,3.5 -6,-3.5\" fill=\"#fbbf24\" fill-opacity=\"0.1\" />
      <polygon points=\"14,-15 20,-11.5 20,-4.5 14,-1 8,-4.5 8,-11.5\" fill=\"#fbbf24\" fill-opacity=\"0.1\" />
      <polygon points=\"14,1 20,4.5 20,11.5 14,15 8,11.5 8,4.5\" fill=\"#fbbf24\" fill-opacity=\"0.1\" />
      <polygon points=\"0,9 6,12.5 6,19.5 0,23 -6,19.5 -6,12.5\" fill=\"#fbbf24\" fill-opacity=\"0.1\" />
      <polygon points=\"-14,1 -8,4.5 -8,11.5 -14,15 -20,11.5 -20,4.5\" fill=\"#fbbf24\" fill-opacity=\"0.1\" />
      <polygon points=\"-14,-15 -8,-11.5 -8,-4.5 -14,-1 -20,-4.5 -20,-11.5\" fill=\"#fbbf24\" fill-opacity=\"0.1\" />
      <polygon points=\"0,-23 6,-19.5 6,-12.5 0,-9 -6,-12.5 -6,-19.5\" fill=\"#fbbf24\" fill-opacity=\"0.1\" />
      <g font-family=\"monospace\" font-size=\"6.5\" fill=\"currentColor\" opacity=\"0.6\">
        <text x=\"26\" y=\"20\">L2-HEX</text>
      </g>
    </g>

    <g transform=\"translate(40, 1040) rotate(-22)\" stroke=\"url(#rightBioGrad)\" stroke-width=\"1.1\">
      <polygon points=\"10,0 110,0 110,54 0,54 0,10\" fill=\"#3b0764\" fill-opacity=\"0.2\" />
      <line x1=\"0\" y1=\"11\" x2=\"110\" y2=\"11\" stroke-width=\"0.6\" opacity=\"0.5\" />
      <g fill=\"currentColor\" opacity=\"0.75\">
        <rect x=\"12\" y=\"16\" width=\"2\" height=\"4\" />
        <rect x=\"12\" y=\"28\" width=\"2\" height=\"4\" />
        <rect x=\"22\" y=\"22\" width=\"2\" height=\"4\" />
        <rect x=\"32\" y=\"16\" width=\"2\" height=\"4\" />
        <rect x=\"44\" y=\"34\" width=\"2\" height=\"4\" />
        <rect x=\"58\" y=\"22\" width=\"2\" height=\"4\" />
        <rect x=\"70\" y=\"16\" width=\"2\" height=\"4\" />
        <rect x=\"82\" y=\"28\" width=\"2\" height=\"4\" />
      </g>
      <g font-family=\"monospace\" font-size=\"6.5\" fill=\"currentColor\" opacity=\"0.55\">
        <text x=\"10\" y=\"8\">MASK-80</text>
      </g>
    </g>

    <g transform=\"translate(125, 1320) rotate(55)\" stroke=\"url(#rightBioGrad)\" stroke-width=\"1.5\">
      <path d=\"M 10,38 L 10,13 C 10,5 24,5 24,13 L 24,42 C 24,52 5,52 5,42 L 5,18 C 5,11 17,11 17,18 L 17,38\" fill=\"none\" stroke-linecap=\"round\" />
      <circle cx=\"14\" cy=\"27\" r=\"16\" stroke-dasharray=\"3 2\" opacity=\"0.35\" stroke-width=\"0.8\" />
      <g font-family=\"monospace\" font-size=\"6.5\" fill=\"currentColor\" opacity=\"0.55\">
        <text x=\"24\" y=\"26\">CLIP-MAX</text>
      </g>
    </g>

    <g transform=\"translate(45, 1600) rotate(-16)\" stroke=\"url(#rightBioGrad)\" stroke-width=\"1.2\">
      <circle cx=\"0\" cy=\"0\" r=\"34\" fill=\"#4a044e\" fill-opacity=\"0.25\" />
      <ellipse cx=\"0\" cy=\"0\" rx=\"80\" ry=\"24\" stroke-width=\"1.6\" transform=\"rotate(-18)\" />
      <ellipse cx=\"0\" cy=\"0\" rx=\"68\" ry=\"19\" stroke-dasharray=\"4 3\" transform=\"rotate(-18)\" />
      <g font-family=\"monospace\" font-size=\"7\" fill=\"currentColor\" opacity=\"0.75\">
        <text x=\"-20\" y=\"48\">OPS.RTA</text>
      </g>
    </g>

    <g transform=\"translate(120, 1880) rotate(8)\" stroke=\"none\" fill=\"currentColor\" opacity=\"0.6\">
      <rect x=\"-8\" y=\"24\" width=\"50\" height=\"1.5\" />
      <rect x=\"16\" y=\"0\" width=\"14\" height=\"9\" />
      <rect x=\"20\" y=\"2\" width=\"2\" height=\"2\" fill=\"#000\" />
      <rect x=\"12\" y=\"7\" width=\"9\" height=\"10\" />
      <rect x=\"7\" y=\"11\" width=\"14\" height=\"7\" />
      <rect x=\"21\" y=\"11\" width=\"3\" height=\"2\" />
      <rect x=\"2\" y=\"9\" width=\"5\" height=\"5\" />
      <rect x=\"9\" y=\"18\" width=\"3\" height=\"6\" />
      <rect x=\"16\" y=\"18\" width=\"3\" height=\"4\" />
      <rect x=\"19\" y=\"22\" width=\"3\" height=\"2\" />
      <g font-family=\"monospace\" font-size=\"6.5\" fill=\"currentColor\" opacity=\"0.7\">
        <text x=\"32\" y=\"14\">0-LAG</text>
      </g>
    </g>

    <g transform=\"translate(40, 2160) rotate(-26)\" stroke=\"url(#rightBioGrad)\" stroke-width=\"1.2\">
      <rect x=\"-14\" y=\"-22\" width=\"28\" height=\"44\" rx=\"4\" fill=\"#3b0764\" fill-opacity=\"0.3\" />
      <circle cx=\"0\" cy=\"0\" r=\"11\" stroke-width=\"1.5\" />
      <circle cx=\"0\" cy=\"0\" r=\"6\" fill=\"#ef4444\" fill-opacity=\"0.8\" stroke=\"#f87171\" stroke-width=\"1.1\" />
      <circle cx=\"2\" cy=\"-2\" r=\"1.5\" fill=\"#fff\" opacity=\"0.9\" />
      <g font-family=\"monospace\" font-size=\"6.5\" fill=\"currentColor\" opacity=\"0.6\">
        <text x=\"-12\" y=\"30\">HAL-9K</text>
      </g>
    </g>

    <g transform=\"translate(130, 2440) rotate(45)\" stroke=\"url(#rightBioGrad)\" stroke-width=\"1.3\">
      <circle cx=\"0\" cy=\"0\" r=\"32\" stroke-dasharray=\"4 3\" fill=\"#3b0764\" fill-opacity=\"0.2\" />
      <circle cx=\"0\" cy=\"0\" r=\"13\" />
      <line x1=\"32\" y1=\"0\" x2=\"40\" y2=\"0\" stroke-width=\"2.2\" />
      <line x1=\"22.6\" y1=\"22.6\" x2=\"28.3\" y2=\"28.3\" stroke-width=\"2.2\" />
      <line x1=\"0\" y1=\"32\" x2=\"0\" y2=\"40\" stroke-width=\"2.2\" />
      <line x1=\"-22.6\" y1=\"22.6\" x2=\"-28.3\" y2=\"28.3\" stroke-width=\"2.2\" />
      <line x1=\"-32\" y1=\"0\" x2=\"-40\" y2=\"0\" stroke-width=\"2.2\" />
      <line x1=\"-22.6\" y1=\"-22.6\" x2=\"-28.3\" y2=\"-28.3\" stroke-width=\"2.2\" />
      <line x1=\"0\" y1=\"-32\" x2=\"0\" y2=\"-40\" stroke-width=\"2.2\" />
      <line x1=\"22.6\" y1=\"-22.6\" x2=\"28.3\" y2=\"-28.3\" stroke-width=\"2.2\" />
      <g font-family=\"monospace\" font-size=\"6.5\" fill=\"currentColor\" opacity=\"0.8\">
        <text x=\"-24\" y=\"52\" fill=\"#4ade80\">(! run)</text>
      </g>
    </g>

    <g transform=\"translate(45, 2720) rotate(-35)\" stroke=\"url(#rightBioGrad)\" stroke-width=\"1.2\">
      <rect x=\"-18\" y=\"-25\" width=\"36\" height=\"50\" rx=\"3\" fill=\"#3b0764\" fill-opacity=\"0.3\" />
      <circle cx=\"0\" cy=\"-25\" r=\"4\" fill=\"none\" />
      <line x1=\"-26\" y1=\"-15\" x2=\"-18\" y2=\"-15\" stroke-width=\"1.5\" />
      <line x1=\"18\" y1=\"-15\" x2=\"26\" y2=\"-15\" stroke-width=\"1.5\" />
      <line x1=\"-26\" y1=\"-5\" x2=\"-18\" y2=\"-5\" stroke-width=\"1.5\" />
      <line x1=\"18\" y1=\"-5\" x2=\"26\" y2=\"-5\" stroke-width=\"1.5\" />
      <line x1=\"-26\" y1=\"5\" x2=\"-18\" y2=\"5\" stroke-width=\"1.5\" />
      <line x1=\"18\" y1=\"5\" x2=\"26\" y2=\"5\" stroke-width=\"1.5\" />
      <line x1=\"-26\" y1=\"15\" x2=\"-18\" y2=\"15\" stroke-width=\"1.5\" />
      <line x1=\"18\" y1=\"15\" x2=\"26\" y2=\"15\" stroke-width=\"1.5\" />
      <g font-family=\"monospace\" font-size=\"6.5\" fill=\"currentColor\" opacity=\"0.7\">
        <text x=\"-12\" y=\"2\">NE555</text>
      </g>
    </g>
</g></defs><use href=\"#rightGutterCycle\" y=\"0\" /><use href=\"#rightGutterCycle\" y=\"2800\" /><use href=\"#rightGutterCycle\" y=\"5600\" /><use href=\"#rightGutterCycle\" y=\"8400\" /><use href=\"#rightGutterCycle\" y=\"11200\" /></svg></div>")

(df render-cosmic-background ()
  :d "Complete atmospheric cosmic landscape background."
  (s/concat
    "<div class=\"absolute inset-0 pointer-events-none select-none overflow-hidden z-0\" aria-hidden=\"true\">"
    "<div class=\"fixed inset-0 pointer-events-none overflow-hidden z-0\">"
    "<div class=\"absolute top-6 left-6 w-[550px] h-[550px] bg-purple-600/12 dark:bg-purple-900/20 blur-[150px] rounded-full\"></div>"
    "<div class=\"absolute top-1/3 right-8 w-[650px] h-[650px] bg-indigo-600/10 dark:bg-indigo-950/15 blur-[160px] rounded-full\"></div>"
    "<div class=\"absolute bottom-16 left-1/4 w-[700px] h-[550px] bg-purple-900/12 blur-[160px] rounded-full\"></div>"
    (render-blueprint-grid)
    (render-chameleon-perch)
    "</div>"
    (render-left-deflecting-stream)
    (render-right-cyclic-stream)
    "</div>"))


(df cosmic-landscape-background ()
  (render-cosmic-background))
