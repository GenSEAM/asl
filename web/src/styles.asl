(module aslWeb/styles
  :d "Instrumented Editorial / Cosmic Cybernetic design tokens and CSS custom property compilation"
  :x [getDarkPalette
      getLightPalette
      getSpatialScale
      getToken
      renderCssCustomProperties]
  :i [(asl-text/string :a s)])

(df getToken [(m (Map Str Str)) (k Str)] -> Str
  :d "Safe map string extractor unwrapping Option"
  (option-or (map-get m k) ""))

(df getDarkPalette [] -> (Map Str Str)
  :d "Returns canonical Dark Mode color palette tokens"
  (map-set (map-set (map-set (map-set (map-set (map-set (map-set (map-set (map-set (map-empty) "ground" "#0C0914") "surface" "#181327") "inset" "#110D1D") "line" "#302648") "lineStrong" "#8866C6") "ink" "#F6F4FF") "inkMuted" "#988CAF") "signal" "#B060FF") "accent" "#C084FC"))

(df getLightPalette [] -> (Map Str Str)
  :d "Returns canonical Light Mode color palette tokens"
  (map-set (map-set (map-set (map-set (map-set (map-set (map-set (map-set (map-set (map-empty) "ground" "#F8F7FC") "surface" "#FFFFFF") "inset" "#F4F2F8") "line" "#E1DBEC") "lineStrong" "#9280B0") "ink" "#181224") "inkMuted" "#706286") "signal" "#7E22CE") "accent" "#9333EA"))

(df getSpatialScale [] -> (Map Str Str)
  :d "Returns 8pt spatial grid scale increments"
  (map-set (map-set (map-set (map-set (map-set (map-set (map-set (map-set (map-empty) "gap0" "0px") "gap1" "4px") "gap2" "8px") "gap3" "12px") "gap4" "16px") "gap5" "20px") "gap6" "24px") "gap8" "32px"))

(df renderCssCustomProperties [] -> Str
  :d "Compiles token declarations into CSS root custom properties"
  (s/concat ":root {\n  --asl-ground: #0C0914;\n  --asl-surface: #181327;\n  --asl-inset: #110D1D;\n  --asl-line: #302648;\n  --asl-lineStrong: #8866C6;\n  --asl-ink: #F6F4FF;\n  --asl-inkMuted: #988CAF;\n  --asl-signal: #B060FF;\n  --asl-accent: #C084FC;\n  --asl-gap0: 0px;\n  --asl-gap1: 4px;\n  --asl-gap2: 8px;\n  --asl-gap3: 12px;\n  --asl-gap4: 16px;\n  --asl-gap5: 20px;\n  --asl-gap6: 24px;\n  --asl-gap8: 32px;\n}\n\n[data-theme=\"light\"] {\n  --asl-ground: #F8F7FC;\n  --asl-surface: #FFFFFF;\n  --asl-inset: #F4F2F8;\n  --asl-line: #E1DBEC;\n  --asl-lineStrong: #9280B0;\n  --asl-ink: #181224;\n  --asl-inkMuted: #706286;\n  --asl-signal: #7E22CE;\n  --asl-accent: #9333EA;\n}\n"))
