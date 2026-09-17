(module asl-ui/theme
  :d "Pure AgentScript Theme System, Semantic Color Tokens, and Compile-Time WCAG Contrast Validation"
  :x [ColorToken
      makeColorToken
      ThemePalette
      makeThemePalette
      defaultDarkTheme
      defaultLightTheme
      calculateLuminance
      calculateContrastRatio
      verifyWcagAa
      verifyWcagAaa
      validateThemeContrast])

(dfs ColorToken
  (:f name String)
  (:f hex String)
  (:f r Int64)
  (:f g Int64)
  (:f b Int64))

(dfs ThemePalette
  (:f bgBase ColorToken)
  (:f bgSurface ColorToken)
  (:f fgPrimary ColorToken)
  (:f fgMuted ColorToken)
  (:f accent ColorToken)
  (:f border ColorToken))

(df makeColorToken [(name String)
                    (hex String)
                    (r Int64)
                    (g Int64)
                    (b Int64)] -> ColorToken
  :d "Constructs a semantic color token"
  (ColorToken :name name
              :hex hex
              :r r
              :g g
              :b b))

(df makeThemePalette [(bgBase ColorToken)
                      (bgSurface ColorToken)
                      (fgPrimary ColorToken)
                      (fgMuted ColorToken)
                      (accent ColorToken)
                      (border ColorToken)] -> ThemePalette
  :d "Constructs a theme palette record"
  (ThemePalette :bgBase bgBase
                :bgSurface bgSurface
                :fgPrimary fgPrimary
                :fgMuted fgMuted
                :accent accent
                :border border))

(df defaultDarkTheme [] -> ThemePalette
  :d "Returns canonical dark theme palette conforming to WCAG contrast standards"
  (let [(bgBase (ColorToken :name "bgBase" :hex "#0f172a" :r 15 :g 23 :b 42))
        (bgSurface (ColorToken :name "bgSurface" :hex "#1e293b" :r 30 :g 41 :b 59))
        (fgPrimary (ColorToken :name "fgPrimary" :hex "#f8fafc" :r 248 :g 250 :b 252))
        (fgMuted (ColorToken :name "fgMuted" :hex "#94a3b8" :r 148 :g 163 :b 184))
        (accent (ColorToken :name "accent" :hex "#38bdf8" :r 56 :g 189 :b 248))
        (border (ColorToken :name "border" :hex "#334155" :r 51 :g 65 :b 85))]
    (ThemePalette :bgBase bgBase
                  :bgSurface bgSurface
                  :fgPrimary fgPrimary
                  :fgMuted fgMuted
                  :accent accent
                  :border border)))

(df defaultLightTheme [] -> ThemePalette
  :d "Returns canonical light theme palette conforming to WCAG contrast standards"
  (let [(bgBase (ColorToken :name "bgBase" :hex "#ffffff" :r 255 :g 255 :b 255))
        (bgSurface (ColorToken :name "bgSurface" :hex "#f8fafc" :r 248 :g 250 :b 252))
        (fgPrimary (ColorToken :name "fgPrimary" :hex "#0f172a" :r 15 :g 23 :b 42))
        (fgMuted (ColorToken :name "fgMuted" :hex "#64748b" :r 100 :g 116 :b 139))
        (accent (ColorToken :name "accent" :hex "#0284c7" :r 2 :g 132 :b 199))
        (border (ColorToken :name "border" :hex "#e2e8f0" :r 226 :g 232 :b 240))]
    (ThemePalette :bgBase bgBase
                  :bgSurface bgSurface
                  :fgPrimary fgPrimary
                  :fgMuted fgMuted
                  :accent accent
                  :border border)))

(df calculateLuminance [(color ColorToken)] -> Int64
  :d "Calculates relative luminance scaled to 0..10000 range using integer arithmetic"
  (let [(r (.-r color))
        (g (.-g color))
        (b (.-b color))
        (scaledSum (+ (+ (* 2126 r) (* 7152 g)) (* 722 b)))]
    (/ scaledSum 255)))

(df calculateContrastRatio [(c1 ColorToken) (c2 ColorToken)] -> Int64
  :d "Calculates WCAG contrast ratio multiplied by 100 using integer fixed-point arithmetic"
  (let [(l1 (calculateLuminance c1))
        (l2 (calculateLuminance c2))
        (lMax (if (>= l1 l2) l1 l2))
        (lMin (if (>= l1 l2) l2 l1))
        (num (* (+ lMax 500) 100))
        (den (+ lMin 500))]
    (/ num den)))

(df verifyWcagAa [(fg ColorToken) (bg ColorToken)] -> Bool
  :d "Verifies whether foreground/background contrast meets WCAG AA 4.5:1 ratio"
  (>= (calculateContrastRatio fg bg) 450))

(df verifyWcagAaa [(fg ColorToken) (bg ColorToken)] -> Bool
  :d "Verifies whether foreground/background contrast meets WCAG AAA 7.0:1 ratio"
  (>= (calculateContrastRatio fg bg) 700))

(df validateThemeContrast [(theme ThemePalette)] -> (Result Bool String)
  :d "Validates that primary foreground achieves WCAG AA contrast against base and surface"
  (let [(fg (.-fgPrimary theme))
        (bg (.-bgBase theme))
        (surface (.-bgSurface theme))]
    (if (and (verifyWcagAa fg bg) (verifyWcagAa fg surface))
      (ok true)
      (err "ERR_WCAG_CONTRAST_INSUFFICIENT"))))
