(module asl-web/logo
  :d "Declarative Chameleon Logo & Brand Identity Vectors in pure AgentScript"
  :x [chameleon-logo-svg schematic-chameleon-svg brand-wordmark]
  :i [(core/strings :a s)])

(df chameleon-logo-svg [] -> Str
  :d "Returns SVG markup of the signature chameleon spiral logo"
  "<svg viewBox=\"0 0 100 100\" class=\"w-8 h-8\" role=\"img\" aria-label=\"ASL Logo\"><path d=\"M 78,82 C 83,72 84,48 81,32 C 77,16 64,8 46,8 C 26,8 13,19 8,36 C 4,52 7,72 18,84 C 28,94 44,95 56,88 C 64,82 68,70 67,58 C 66,44 57,35 44,35 C 32,35 25,44 25,54 C 25,62 31,67 38,67 C 43,67 46,63 46,58 C 46,53 41,52 38,55 C 36,57 34,55 34,52 C 34,46 40,41 46,41 C 53,41 57,48 57,57 C 57,67 50,75 42,76 C 31,77 21,70 17,60 C 14,48 16,36 24,26 C 33,16 46,15 56,19 C 66,24 70,35 70,50 L 70,82 C 70,86 77,86 78,82 Z\" fill=\"#a855f7\" stroke=\"#d8b4fe\" stroke-width=\"1.2\"/></svg>")

(df schematic-chameleon-svg [] -> Str
  :d "Returns full schematic line-art vector for the chameleon mascot"
  "<svg viewBox=\"0 0 120 140\" class=\"w-48 h-48\" fill=\"none\" stroke=\"#a855f7\" stroke-width=\"2.0\"><path d=\"M 52 14 C 62 16, 78 26, 84 38 C 88 47, 85 54, 76 56 C 66 58, 54 54, 48 46\"/><path d=\"M 52 14 C 44 14, 38 22, 42 30 C 30 36, 16 52, 14 74 C 11 98, 22 118, 42 124 C 62 130, 80 118, 78 96 C 75 80, 58 74, 46 84 C 38 92, 44 104, 54 102 C 60 100, 60 92, 54 90 C 50 89, 47 92, 49 95\"/><circle cx=\"72\" cy=\"40\" r=\"11\"/><circle cx=\"72\" cy=\"40\" r=\"4.5\" fill=\"rgba(216, 180, 254, 0.25)\"/><path d=\"M 48 46 C 56 52, 60 62, 54 72 C 48 80, 38 82, 34 88\"/></svg>")

(df brand-wordmark [] -> Str
  :d "Returns HTML markup for brand wordmark with logo and typography"
  (s/concat "<span class=\"inline-flex items-center gap-2.5 font-sans font-semibold tracking-tight text-ink text-lg\">" (s/concat (chameleon-logo-svg) "<span>aslang<span class=\"text-signal\">.dev</span></span></span>")))
