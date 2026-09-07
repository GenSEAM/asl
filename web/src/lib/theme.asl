(module asl-web/theme
  :d "Theme Management & Color Scheme Resolver in pure AgentScript"
  :x [Theme default-theme resolve-theme theme-class-name]
  :i [(core/strings :a s)])

(dfe Theme
  (:c theme-dark [] "Dark theme (high-contrast deep space palette)")
  (:c theme-light [] "Light theme (clean paper daylight palette)")
  (:c theme-system [] "System OS prefers-color-scheme setting"))

(df default-theme [] -> Str
  :d "Returns default application theme"
  "dark")

(df resolve-theme [(theme Str) (prefers-dark Bool)] -> Str
  :d "Resolves effective theme considering system preference"
  (if (= theme "system")
    (if prefers-dark "dark" "light")
    (if (= theme "light") "light" "dark")))

(df theme-class-name [(theme Str)] -> Str
  :d "Returns root CSS class for theme"
  (if (= theme "light") "light" "dark"))
