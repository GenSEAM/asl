(module asl-ui/theme :x [ColorToken makeColorToken ThemePalette makeThemePalette defaultDarkTheme defaultLightTheme sds1DarkTheme calculateLuminance calculateContrastRatio verifyWcagAa verifyWcagAaa validateThemeContrast validateSds1ThemeContrast formatStatusBadgeWithCue])

(schema ColorToken (:f name String) (:f hex String) (:f r Int64) (:f g Int64) (:f b Int64))

(schema ThemePalette (:f bgBase ColorToken) (:f bgSurface ColorToken) (:f fgPrimary ColorToken) (:f fgMuted ColorToken) (:f accent ColorToken) (:f border ColorToken) (:f surfaceElevated ColorToken) (:f surfaceInset ColorToken) (:f statusVerified ColorToken) (:f statusDefect ColorToken) (:f statusVacuousMock ColorToken) (:f statusCoupling ColorToken) (:f statusTelemetry ColorToken))

fn makeColorToken name: String hex: String r: Int64 g: Int64 b: Int64 -> ColorToken
  (ColorToken :name name :hex hex :r r :g g :b b)

fn makeThemePalette bgBase: ColorToken bgSurface: ColorToken fgPrimary: ColorToken fgMuted: ColorToken accent: ColorToken border: ColorToken surfaceElevated: ColorToken surfaceInset: ColorToken statusVerified: ColorToken statusDefect: ColorToken statusVacuousMock: ColorToken statusCoupling: ColorToken statusTelemetry: ColorToken -> ThemePalette
  (ThemePalette :bgBase bgBase :bgSurface bgSurface :fgPrimary fgPrimary :fgMuted fgMuted :accent accent :border border :surfaceElevated surfaceElevated :surfaceInset surfaceInset :statusVerified statusVerified :statusDefect statusDefect :statusVacuousMock statusVacuousMock :statusCoupling statusCoupling :statusTelemetry statusTelemetry)

fn defaultDarkTheme -> ThemePalette
  (let [(bgBase (ColorToken :name "bgBase" :hex "#0f172a" :r 15 :g 23 :b 42)) (bgSurface (ColorToken :name "bgSurface" :hex "#1e293b" :r 30 :g 41 :b 59)) (fgPrimary (ColorToken :name "fgPrimary" :hex "#f8fafc" :r 248 :g 250 :b 252)) (fgMuted (ColorToken :name "fgMuted" :hex "#94a3b8" :r 148 :g 163 :b 184)) (accent (ColorToken :name "accent" :hex "#38bdf8" :r 56 :g 189 :b 248)) (border (ColorToken :name "border" :hex "#334155" :r 51 :g 65 :b 85)) (elevated (ColorToken :name "surfaceElevated" :hex "#334155" :r 51 :g 65 :b 85)) (inset (ColorToken :name "surfaceInset" :hex "#020617" :r 2 :g 6 :b 23)) (ver (ColorToken :name "statusVerified" :hex "#10b981" :r 16 :g 185 :b 129)) (def (ColorToken :name "statusDefect" :hex "#ef4444" :r 239 :g 68 :b 68)) (vac (ColorToken :name "statusVacuousMock" :hex "#f59e0b" :r 245 :g 158 :b 11)) (cpl (ColorToken :name "statusCoupling" :hex "#eab308" :r 234 :g 179 :b 8)) (tel (ColorToken :name "statusTelemetry" :hex "#38bdf8" :r 56 :g 189 :b 248))] (ThemePalette :bgBase bgBase :bgSurface bgSurface :fgPrimary fgPrimary :fgMuted fgMuted :accent accent :border border :surfaceElevated elevated :surfaceInset inset :statusVerified ver :statusDefect def :statusVacuousMock vac :statusCoupling cpl :statusTelemetry tel))

fn defaultLightTheme -> ThemePalette
  (let [(bgBase (ColorToken :name "bgBase" :hex "#ffffff" :r 255 :g 255 :b 255)) (bgSurface (ColorToken :name "bgSurface" :hex "#f8fafc" :r 248 :g 250 :b 252)) (fgPrimary (ColorToken :name "fgPrimary" :hex "#0f172a" :r 15 :g 23 :b 42)) (fgMuted (ColorToken :name "fgMuted" :hex "#64748b" :r 100 :g 116 :b 139)) (accent (ColorToken :name "accent" :hex "#0284c7" :r 2 :g 132 :b 199)) (border (ColorToken :name "border" :hex "#e2e8f0" :r 226 :g 232 :b 240)) (elevated (ColorToken :name "surfaceElevated" :hex "#f1f5f9" :r 241 :g 245 :b 249)) (inset (ColorToken :name "surfaceInset" :hex "#f8fafc" :r 248 :g 250 :b 252)) (ver (ColorToken :name "statusVerified" :hex "#059669" :r 5 :g 150 :b 105)) (def (ColorToken :name "statusDefect" :hex "#dc2626" :r 220 :g 38 :b 38)) (vac (ColorToken :name "statusVacuousMock" :hex "#d97706" :r 217 :g 119 :b 6)) (cpl (ColorToken :name "statusCoupling" :hex "#ca8a04" :r 202 :g 138 :b 4)) (tel (ColorToken :name "statusTelemetry" :hex "#0284c7" :r 2 :g 132 :b 199))] (ThemePalette :bgBase bgBase :bgSurface bgSurface :fgPrimary fgPrimary :fgMuted fgMuted :accent accent :border border :surfaceElevated elevated :surfaceInset inset :statusVerified ver :statusDefect def :statusVacuousMock vac :statusCoupling cpl :statusTelemetry tel))

fn sds1DarkTheme -> ThemePalette
  (let [(bgBase (ColorToken :name "surfaceCanvas" :hex "#0b0f19" :r 11 :g 15 :b 25)) (bgSurface (ColorToken :name "surfaceTile" :hex "#111827" :r 17 :g 24 :b 39)) (fgPrimary (ColorToken :name "fgPrimary" :hex "#f8fafc" :r 248 :g 250 :b 252)) (fgMuted (ColorToken :name "fgMuted" :hex "#94a3b8" :r 148 :g 163 :b 184)) (accent (ColorToken :name "accent" :hex "#38bdf8" :r 56 :g 189 :b 248)) (border (ColorToken :name "borderSubtle" :hex "#1e293b" :r 30 :g 41 :b 59)) (elevated (ColorToken :name "surfaceElevated" :hex "#1f2937" :r 31 :g 41 :b 55)) (inset (ColorToken :name "surfaceInset" :hex "#030712" :r 3 :g 7 :b 18)) (ver (ColorToken :name "statusVerified" :hex "#10b981" :r 16 :g 185 :b 129)) (def (ColorToken :name "statusDefect" :hex "#ef4444" :r 239 :g 68 :b 68)) (vac (ColorToken :name "statusVacuousMock" :hex "#f59e0b" :r 245 :g 158 :b 11)) (cpl (ColorToken :name "statusCoupling" :hex "#eab308" :r 234 :g 179 :b 8)) (tel (ColorToken :name "statusTelemetry" :hex "#38bdf8" :r 56 :g 189 :b 248))] (ThemePalette :bgBase bgBase :bgSurface bgSurface :fgPrimary fgPrimary :fgMuted fgMuted :accent accent :border border :surfaceElevated elevated :surfaceInset inset :statusVerified ver :statusDefect def :statusVacuousMock vac :statusCoupling cpl :statusTelemetry tel))

fn calculateLuminance color: ColorToken -> Int64
  (let [(r color.r) (g color.g) (b color.b) (scaledSum (+ (+ (* 2126 r) (* 7152 g)) (* 722 b)))] (/ scaledSum 255))

fn calculateContrastRatio c1: ColorToken c2: ColorToken -> Int64
  (let [(l1 (calculateLuminance c1)) (l2 (calculateLuminance c2)) (lMax (if (>= l1 l2) l1 l2)) (lMin (if (>= l1 l2) l2 l1)) (num (* (+ lMax 500) 100)) (den (+ lMin 500))] (/ num den))

fn verifyWcagAa fg: ColorToken bg: ColorToken -> Bool
  (>= (calculateContrastRatio fg bg) 450)

fn verifyWcagAaa fg: ColorToken bg: ColorToken -> Bool
  (>= (calculateContrastRatio fg bg) 700)

fn validateThemeContrast theme: ThemePalette -> (Result Bool String)
  (let [(fg theme.fgPrimary) (bg theme.bgBase) (surface theme.bgSurface)] (if (and (verifyWcagAa fg bg) (verifyWcagAa fg surface)) (ok true) (err "ERR_WCAG_CONTRAST_INSUFFICIENT")))

fn validateSds1ThemeContrast theme: ThemePalette -> (Result Bool String)
  (let [(fg theme.fgPrimary) (bgCanvas theme.bgBase) (bgTile theme.bgSurface) (bgElev theme.surfaceElevated)] (if (and (and (verifyWcagAaa fg bgCanvas) (verifyWcagAaa fg bgTile)) (verifyWcagAa fg bgElev)) (ok true) (err "ERR_SDS1_CONTRAST_INSUFFICIENT")))

fn formatStatusBadgeWithCue status: String -> String
  (cond ((= status "verified") "[OK] Verified") ((= status "defect") "[FAIL] Defect") ((= status "vacuousMock") "[VACUOUS] Hollow Mock") ((= status "coupling") "[CYCLE] High Coupling") ((= status "telemetry") "[RUN] Telemetry Active") (else "[INFO] Idle"))
