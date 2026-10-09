(module aslVdom/theme :x [ThemeColors ThemeSpacing ThemeTypography ThemeRadii Theme defaultColors darkColors defaultSpacing defaultTypography defaultRadii createTheme defaultTheme darkTheme resolveColor resolveSpacing resolveRadius resolveTypography isValidHexColor? isValidTheme? emitCssThemeSelector emitCssThemeVariables emitAestheticStyles])

(schema ThemeColors (:f primary String) (:f background String) (:f surface String) (:f text String) (:f border String))

(schema ThemeSpacing (:f xs Int64) (:f sm Int64) (:f md Int64) (:f lg Int64) (:f xl Int64))

(schema ThemeTypography (:f fontSizeSm String) (:f fontSizeBase String) (:f fontSizeLg String))

(schema ThemeRadii (:f sm Int64) (:f md Int64) (:f lg Int64))

(schema Theme (:f name String) (:f colors ThemeColors) (:f spacing ThemeSpacing) (:f typography ThemeTypography) (:f radii ThemeRadii))

fn defaultColors -> ThemeColors
  (ThemeColors :primary "#2563eb" :background "#ffffff" :surface "#f8fafc" :text "#0f172a" :border "#e2e8f0")

fn darkColors -> ThemeColors
  (ThemeColors :primary "#2563eb" :background "#090d16" :surface "#111827" :text "#f9fafb" :border "#1f2937")

fn defaultSpacing -> ThemeSpacing
  (ThemeSpacing :xs 4 :sm 8 :md 16 :lg 24 :xl 32)

fn defaultTypography -> ThemeTypography
  (ThemeTypography :fontSizeSm "14px" :fontSizeBase "16px" :fontSizeLg "18px")

fn defaultRadii -> ThemeRadii
  (ThemeRadii :sm 2 :md 4 :lg 8)

fn createTheme name: String colors: ThemeColors spacing: ThemeSpacing typography: ThemeTypography radii: ThemeRadii -> Theme
  (Theme :name name :colors colors :spacing spacing :typography typography :radii radii)

fn defaultTheme -> Theme
  (createTheme "light" (defaultColors) (defaultSpacing) (defaultTypography) (defaultRadii))

fn darkTheme -> Theme
  (createTheme "dark" (darkColors) (defaultSpacing) (defaultTypography) (defaultRadii))

fn resolveColor theme: Theme key: String -> String
  (let [(c theme.colors)] (cond ((= key "primary") c.primary) ((= key "background") c.background) ((= key "surface") c.surface) ((= key "text") c.text) ((= key "border") c.border) (else c.text)))

fn resolveSpacing theme: Theme key: String -> Int64
  (let [(s theme.spacing)] (cond ((= key "xs") s.xs) ((= key "sm") s.sm) ((= key "md") s.md) ((= key "lg") s.lg) ((= key "xl") s.xl) (else s.md)))

fn resolveRadius theme: Theme key: String -> Int64
  (let [(r theme.radii)] (cond ((= key "sm") r.sm) ((= key "md") r.md) ((= key "lg") r.lg) (else r.md)))

fn resolveTypography theme: Theme key: String -> String
  (let [(typ theme.typography)] (cond ((or (= key "sm") (= key "fontSizeSm")) typ.fontSizeSm) ((or (= key "base") (= key "fontSizeBase")) typ.fontSizeBase) ((or (= key "lg") (= key "fontSizeLg")) typ.fontSizeLg) (else typ.fontSizeBase)))

fn isValidHexColor? hex: String -> Bool
  (and (not (stringEmpty? hex)) (and (stringStartsWith? hex "#") (or (= (stringLength hex) 4) (or (= (stringLength hex) 7) (= (stringLength hex) 9)))))

fn isValidTheme? t: Theme -> Bool
  (let [(c t.colors) (s t.spacing) (r t.radii)] (and (not (stringEmpty? t.name)) (and (isValidHexColor? c.primary) (and (isValidHexColor? c.background) (and (isValidHexColor? c.surface) (and (isValidHexColor? c.text) (and (isValidHexColor? c.border) (and (>= s.xs 0) (and (>= s.sm 0) (and (>= s.md 0) (and (>= s.lg 0) (and (>= s.xl 0) (and (>= r.sm 0) (and (>= r.md 0) (>= r.lg 0)))))))))))))))

fn emitCssThemeSelector theme: Theme selector: String -> String
  (let [(c theme.colors) (s theme.spacing) (typ theme.typography) (r theme.radii)] (str selector " {\n" "  --color-primary: " c.primary ";\n" "  --color-background: " c.background ";\n" "  --color-surface: " c.surface ";\n" "  --color-text: " c.text ";\n" "  --color-border: " c.border ";\n" "  --spacing-xs: " (stringFromInt64 s.xs) "px;\n" "  --spacing-sm: " (stringFromInt64 s.sm) "px;\n" "  --spacing-md: " (stringFromInt64 s.md) "px;\n" "  --spacing-lg: " (stringFromInt64 s.lg) "px;\n" "  --spacing-xl: " (stringFromInt64 s.xl) "px;\n" "  --font-size-sm: " typ.fontSizeSm ";\n" "  --font-size-base: " typ.fontSizeBase ";\n" "  --font-size-lg: " typ.fontSizeLg ";\n" "  --radius-sm: " (stringFromInt64 r.sm) "px;\n" "  --radius-md: " (stringFromInt64 r.md) "px;\n" "  --radius-lg: " (stringFromInt64 r.lg) "px;\n" "}"))

fn emitCssThemeVariables theme: Theme -> String
  (emitCssThemeSelector theme ":root")

fn emitAestheticStyles -> String
  (str ":root {\n" "  --neon-bloom: 0 0 20px 2px rgba(138, 43, 226, 0.4), 0 0 40px rgba(138, 43, 226, 0.2);\n" "  --border-gradient: linear-gradient(135deg, rgba(255,255,255,0.2), rgba(255,255,255,0.01));\n" "  --backdrop-radial: radial-gradient(circle at 50% 0%, rgba(50, 15, 80, 0.8) 0%, rgba(10, 5, 20, 1) 70%);\n" "  --text-glow: 0 0 10px rgba(200, 150, 255, 0.8);\n" "}\n" "body {\n" "  background: var(--backdrop-radial);\n" "  box-shadow: inset 0 0 150px rgba(0, 0, 0, 0.9);\n" "  color: #fff;\n" "  font-family: 'Inter', sans-serif;\n" "  margin: 0;\n" "  min-height: 100vh;\n" "}\n" ".ui-card {\n" "  background: rgba(20, 10, 40, 0.4);\n" "  backdrop-filter: blur(12px);\n" "  border: 1px solid transparent;\n" "  border-image: var(--border-gradient) 1;\n" "  box-shadow: var(--neon-bloom);\n" "  transition: transform 0.3s cubic-bezier(0.25, 0.46, 0.45, 0.94), box-shadow 0.3s;\n" "}\n" ".ui-card:hover {\n" "  transform: translateY(-4px) scale(1.02);\n" "  box-shadow: 0 0 30px 4px rgba(138, 43, 226, 0.6), 0 0 60px rgba(138, 43, 226, 0.3);\n" "}\n" ".asl-typography-glowing {\n" "  background: linear-gradient(180deg, #ffffff 0%, #a882ff 100%);\n" "  -webkit-background-clip: text;\n" "  -webkit-text-fill-color: transparent;\n" "  filter: drop-shadow(var(--text-glow));\n" "}\n")
