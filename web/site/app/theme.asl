(module aslSite/app/theme
  :x [Swatch palette swatchDark swatchLight tokenRules sheet stylesheet]
  :i [(aslSite/ui/css :a c)])

(enum Swatch (:c swatch [(name String) (dark String) (light String)] "one colour role: its dark and light value"))

fn palette -> (List Swatch)
  [(swatch "ground" "#121012" "#faf8f9")
   (swatch "sunken" "#0c0a0c" "#f2eef1")
   (swatch "surface" "#1a171a" "#ffffff")
   (swatch "inset" "#151215" "#f5f1f4")
   (swatch "line" "#2e292d" "#e4dde2")
   (swatch "line-strong" "#6b5f69" "#8d7f8a")
   (swatch "ink" "#f3eff2" "#1b161a")
   (swatch "ink-2" "#c9c0c7" "#4a4048")
   (swatch "ink-3" "#9a8f98" "#6e626b")
   (swatch "signal" "#ff5aa8" "#c2185b")
   (swatch "signal-wash" "rgba(255,90,168,.12)" "rgba(194,24,91,.08)")]

fn swatchDark s: Swatch -> c/Decl
  (mt s ((swatch name dark light) (c/decl (str "--" name) dark)))

fn swatchLight s: Swatch -> c/Decl
  (mt s ((swatch name dark light) (c/decl (str "--" name) light)))

fn tokenRules -> (List c/Rule)
  [(c/rule ":root" (listAppend (map swatchDark (palette)) [(c/decl "color-scheme" "dark")]))
   (c/media "(prefers-color-scheme: light)" [(c/rule ":root:not([data-theme=dark])" (listAppend (map swatchLight (palette)) [(c/decl "color-scheme" "light")]))])
   (c/rule ":root[data-theme=light]" (listAppend (map swatchLight (palette)) [(c/decl "color-scheme" "light")]))]

fn v name: String -> String
  (c/tokenVar name)

fn d prop: String value: String -> c/Decl
  (c/decl prop value)

fn r selector: String decls: (List c/Decl) -> c/Rule
  (c/rule selector decls)

fn sans -> String
  "ui-sans-serif,system-ui,-apple-system,\"Segoe UI\",Roboto,\"Helvetica Neue\",Arial,sans-serif"

fn mono -> String
  "ui-monospace,\"SF Mono\",\"JetBrains Mono\",Menlo,Consolas,\"Liberation Mono\",monospace"

fn base -> (List c/Rule)
  [(r "*,*::before,*::after" [(d "box-sizing" "border-box")])
   (r "html" [(d "-webkit-text-size-adjust" "100%") (d "scroll-padding-top" "5rem")])
   (r "body" [(d "margin" "0") (d "background" (v "ground")) (d "color" (v "ink")) (d "font" (str "16px/1.6 " (sans))) (d "-webkit-font-smoothing" "antialiased") (d "overflow-x" "hidden")])
   (r "a" [(d "color" "inherit") (d "text-decoration-color" (v "line-strong")) (d "text-underline-offset" "3px")])
   (r "a:hover" [(d "text-decoration-color" (v "signal"))])
   (r "code,pre,kbd,.mono" [(d "font-family" (mono)) (d "font-variant-ligatures" "none")])
   (r "h1,h2,h3,h4,p,ul,ol,figure,pre,blockquote" [(d "margin" "0")])
   (r ":focus-visible" [(d "outline" (str "2px solid " (v "signal"))) (d "outline-offset" "3px") (d "border-radius" "4px")])
   (r "::selection" [(d "background" (v "signal-wash")) (d "color" (v "ink"))])
   (r ".skip" [(d "position" "absolute") (d "left" "-999px") (d "top" "8px")])
   (r ".skip:focus" [(d "left" "16px") (d "z-index" "60") (d "background" (v "surface")) (d "padding" "8px 12px") (d "border-radius" "999px")])
   (c/media "(prefers-reduced-motion: reduce)" [(r "*" [(d "transition" "none !important") (d "scroll-behavior" "auto !important")])])]

fn layout -> (List c/Rule)
  [(r ".shell" [(d "max-width" "72rem") (d "margin" "0 auto") (d "padding" "0 16px")])
   (c/media "(min-width: 640px)" [(r ".shell" [(d "padding" "0 24px")])])
   (r ".band" [(d "padding" "5.5rem 0") (d "border-top" (str "1px solid " (v "line")))])
   (r ".band.sunken" [(d "background" (v "sunken"))])
   (c/media "(min-width: 640px)" [(r ".band" [(d "padding" "7.5rem 0")])])
   (r ".stack>*+*" [(d "margin-top" "1rem")])
   (r ".gap-top" [(d "margin-top" "2rem")])]

fn chrome -> (List c/Rule)
  [(r ".top" [(d "position" "sticky") (d "top" "0") (d "z-index" "50") (d "background" (v "ground")) (d "border-bottom" (str "1px solid " (v "line")))])
   (r ".top .shell" [(d "display" "flex") (d "align-items" "center") (d "justify-content" "space-between") (d "gap" "12px") (d "height" "56px")])
   (r ".mark" [(d "display" "inline-flex") (d "align-items" "baseline") (d "gap" "10px") (d "text-decoration" "none") (d "font-weight" "600") (d "letter-spacing" "-.01em")])
   (r ".mark .glyph" [(d "font-family" (mono)) (d "font-weight" "500") (d "color" (v "ink-3"))])
   (r ".mark .glyph b" [(d "color" (v "signal")) (d "font-weight" "700")])
   (r ".links" [(d "display" "flex") (d "align-items" "center") (d "gap" "2px")])
   (r ".links a" [(d "padding" "6px 10px") (d "border-radius" "999px") (d "font-size" ".875rem") (d "color" (v "ink-2")) (d "text-decoration" "none")])
   (r ".links a:hover,.links a[aria-current=page]" [(d "color" (v "ink")) (d "background" (v "inset"))])
   (c/media "(max-width: 479px)" [(r ".links .wide" [(d "display" "none")])])
   (r ".toggle" [(d "display" "inline-flex") (d "align-items" "center") (d "justify-content" "center") (d "width" "34px") (d "height" "34px") (d "margin-left" "4px") (d "border-radius" "999px") (d "border" (str "1px solid " (v "line-strong"))) (d "background" "transparent") (d "color" (v "ink-2")) (d "cursor" "pointer") (d "font" "inherit")])
   (r ".toggle:hover" [(d "color" (v "ink")) (d "border-color" (v "ink-3"))])
   (r ".foot" [(d "border-top" (str "1px solid " (v "line"))) (d "padding" "3rem 0 4rem") (d "font-size" ".875rem") (d "color" (v "ink-3"))])
   (r ".foot .shell" [(d "display" "grid") (d "gap" "1.5rem")])
   (c/media "(min-width: 768px)" [(r ".foot .shell" [(d "grid-template-columns" "1.4fr 1fr 1fr")])])
   (r ".foot h4" [(d "font" (str "500 .75rem/1.4 " (mono))) (d "text-transform" "uppercase") (d "letter-spacing" ".08em") (d "color" (v "ink-3")) (d "margin-bottom" ".75rem")])
   (r ".foot ul" [(d "list-style" "none") (d "padding" "0") (d "display" "grid") (d "gap" ".4rem")])
   (r ".foot a" [(d "color" (v "ink-2")) (d "text-decoration" "none")])
   (r ".foot a:hover" [(d "color" (v "ink"))])]

fn type -> (List c/Rule)
  [(r ".eyebrow" [(d "display" "inline-flex") (d "align-items" "center") (d "gap" "12px") (d "font" (str "500 .75rem/1 " (mono))) (d "text-transform" "uppercase") (d "letter-spacing" ".08em") (d "color" (v "ink-3"))])
   (r ".eyebrow .idx" [(d "color" (v "signal"))])
   (r ".eyebrow .rule" [(d "width" "32px") (d "height" "1px") (d "background" (v "line-strong"))])
   (r ".display" [(d "font-size" "clamp(2.4rem,4.2vw + 1rem,4.4rem)") (d "line-height" "1.04") (d "letter-spacing" "-.035em") (d "font-weight" "650") (d "max-width" "16ch") (d "text-wrap" "balance")])
   (r ".display em" [(d "font-style" "normal") (d "color" (v "signal"))])
   (r ".h2" [(d "font-size" "clamp(1.75rem,2.2vw + 1rem,2.65rem)") (d "line-height" "1.12") (d "letter-spacing" "-.025em") (d "font-weight" "620") (d "max-width" "22ch") (d "text-wrap" "balance")])
   (r ".h3" [(d "font-size" "1.125rem") (d "line-height" "1.35") (d "font-weight" "600") (d "letter-spacing" "-.01em")])
   (r ".lead" [(d "font-size" "clamp(1.06rem,.4vw + 1rem,1.25rem)") (d "line-height" "1.6") (d "color" (v "ink-2")) (d "max-width" "60ch")])
   (r ".meta" [(d "font-size" ".9375rem") (d "color" (v "ink-2"))])
   (r ".micro" [(d "font" (str "500 .75rem/1.5 " (mono))) (d "color" (v "ink-3")) (d "letter-spacing" ".02em")])
   (r ".head" [(d "display" "grid") (d "gap" "1rem") (d "margin-bottom" "3rem")])]

fn hero -> (List c/Rule)
  [(r ".hero" [(d "padding" "4.5rem 0 5rem") (d "background-image" (str "radial-gradient(" (v "line") " 1px,transparent 1px)")) (d "background-size" "22px 22px") (d "background-position" "-11px -11px")])
   (c/media "(min-width: 640px)" [(r ".hero" [(d "padding" "7rem 0 7.5rem")])])
   (r ".hero .stack>*+*" [(d "margin-top" "1.5rem")])
   (r ".cmd" [(d "display" "flex") (d "align-items" "center") (d "gap" "12px") (d "max-width" "36rem") (d "padding" "8px 8px 8px 18px") (d "border" (str "1px solid " (v "line-strong"))) (d "border-radius" "999px") (d "background" (v "surface")) (d "font" (str ".875rem/1.4 " (mono)))])
   (r ".cmd code" [(d "flex" "1") (d "min-width" "0") (d "overflow-x" "auto") (d "white-space" "nowrap") (d "scrollbar-width" "none")])
   (r ".cmd .sigil" [(d "color" (v "signal")) (d "user-select" "none")])
   (r ".copy" [(d "flex" "none") (d "padding" "7px 14px") (d "border-radius" "999px") (d "border" (str "1px solid " (v "line"))) (d "background" (v "inset")) (d "color" (v "ink-2")) (d "font" (str "500 .75rem/1 " (mono))) (d "text-transform" "uppercase") (d "letter-spacing" ".06em") (d "cursor" "pointer")])
   (r ".copy:hover" [(d "color" (v "ink")) (d "border-color" (v "line-strong"))])
   (r ".facts" [(d "display" "flex") (d "flex-wrap" "wrap") (d "gap" "8px 24px") (d "padding" "0") (d "list-style" "none")])
   (r ".facts li" [(d "font" (str ".8125rem/1.5 " (mono))) (d "color" (v "ink-3"))])
   (r ".facts li b" [(d "color" (v "ink")) (d "font-weight" "500")])]

fn panels -> (List c/Rule)
  [(r ".grid" [(d "display" "grid") (d "gap" "1px") (d "background" (v "line")) (d "border" (str "1px solid " (v "line"))) (d "border-radius" "16px") (d "overflow" "hidden")])
   (c/media "(min-width: 768px)" [(r ".grid.two" [(d "grid-template-columns" "1fr 1fr")]) (r ".grid.three" [(d "grid-template-columns" "repeat(3,1fr)")]) (r ".grid.four" [(d "grid-template-columns" "repeat(2,1fr)")])])
   (c/media "(min-width: 1024px)" [(r ".grid.four" [(d "grid-template-columns" "repeat(4,1fr)")])])
   (r ".cell" [(d "background" (v "surface")) (d "padding" "1.75rem") (d "display" "grid") (d "gap" ".75rem") (d "align-content" "start")])
   (r ".cell .n" [(d "font" (str "500 .75rem/1 " (mono))) (d "color" (v "ink-3"))])
   (r ".cell p" [(d "color" (v "ink-2")) (d "font-size" ".9375rem")])
   (r ".cell .cost" [(d "font" (str ".8125rem/1.5 " (mono))) (d "color" (v "ink-3")) (d "padding-top" ".75rem") (d "border-top" (str "1px dashed " (v "line")))])
   (r ".frame" [(d "background" (v "inset")) (d "border" (str "1px solid " (v "line"))) (d "border-radius" "12px") (d "padding" "1rem 1.1rem") (d "font" (str ".8125rem/1.65 " (mono))) (d "overflow-x" "auto") (d "white-space" "pre") (d "color" (v "ink-2"))])
   (r ".frame.live" [(d "border-color" (v "signal")) (d "color" (v "ink"))])
   (r ".count" [(d "display" "flex") (d "align-items" "baseline") (d "justify-content" "space-between") (d "gap" "1rem")])
   (r ".count .big" [(d "font-size" "2.75rem") (d "line-height" "1") (d "font-weight" "620") (d "letter-spacing" "-.03em") (d "font-variant-numeric" "tabular-nums")])
   (r ".count .big.on" [(d "color" (v "signal"))])
   (r ".note" [(d "margin-top" "1.25rem") (d "font-size" ".875rem") (d "color" (v "ink-3"))])
   (r ".steps" [(d "list-style" "none") (d "padding" "0") (d "display" "grid") (d "gap" "1px") (d "background" (v "line")) (d "border" (str "1px solid " (v "line"))) (d "border-radius" "16px") (d "overflow" "hidden")])
   (r ".steps li" [(d "background" (v "surface")) (d "padding" "1.1rem 1.25rem") (d "display" "grid") (d "gap" ".35rem")])
   (c/media "(min-width: 768px)" [(r ".steps li" [(d "grid-template-columns" "minmax(0,22rem) 1fr") (d "align-items" "baseline") (d "gap" "1.5rem")])])
   (r ".steps code" [(d "font-size" ".8125rem") (d "color" (v "ink")) (d "overflow-wrap" "anywhere")])
   (r ".steps span" [(d "color" (v "ink-2")) (d "font-size" ".9375rem")])
   (r ".proof" [(d "display" "grid") (d "gap" "1px") (d "background" (v "line")) (d "border" (str "1px solid " (v "line"))) (d "border-radius" "16px") (d "overflow" "hidden") (d "margin-top" "2.5rem")])
   (c/media "(min-width: 768px)" [(r ".proof" [(d "grid-template-columns" "repeat(4,1fr)")])])
   (r ".proof div" [(d "background" (v "surface")) (d "padding" "1.25rem 1.5rem") (d "display" "grid") (d "gap" ".35rem")])
   (r ".proof b" [(d "font-size" "1.5rem") (d "font-weight" "600") (d "letter-spacing" "-.02em") (d "font-variant-numeric" "tabular-nums")])
   (r ".proof b.live" [(d "color" (v "signal"))])]

fn prose -> (List c/Rule)
  [(r ".prose" [(d "max-width" "44rem") (d "font-size" "1.0625rem") (d "line-height" "1.75") (d "color" (v "ink-2"))])
   (r ".prose>*+*" [(d "margin-top" "1.15em")])
   (r ".prose h1" [(d "font-size" "clamp(2rem,2.4vw + 1rem,2.9rem)") (d "line-height" "1.1") (d "letter-spacing" "-.03em") (d "color" (v "ink")) (d "font-weight" "640")])
   (r ".prose h2" [(d "margin-top" "2.4em") (d "font-size" "1.5rem") (d "line-height" "1.25") (d "letter-spacing" "-.02em") (d "color" (v "ink")) (d "font-weight" "620")])
   (r ".prose h3" [(d "margin-top" "1.8em") (d "font-size" "1.15rem") (d "color" (v "ink")) (d "font-weight" "600")])
   (r ".prose strong" [(d "color" (v "ink")) (d "font-weight" "600")])
   (r ".prose ul,.prose ol" [(d "padding-left" "1.25rem")])
   (r ".prose li+li" [(d "margin-top" ".4em")])
   (r ".prose :not(pre)>code" [(d "font-size" ".875em") (d "padding" ".1em .35em") (d "border-radius" "6px") (d "background" (v "inset")) (d "border" (str "1px solid " (v "line"))) (d "color" (v "ink"))])
   (r ".prose pre" [(d "background" (v "inset")) (d "border" (str "1px solid " (v "line"))) (d "border-radius" "12px") (d "padding" "1rem 1.1rem") (d "font-size" ".8125rem") (d "line-height" "1.65") (d "overflow-x" "auto") (d "color" (v "ink"))])
   (r ".prose blockquote" [(d "border-left" (str "2px solid " (v "signal"))) (d "padding-left" "1rem") (d "color" (v "ink-2"))])
   (r ".prose .tablewrap" [(d "overflow-x" "auto") (d "border" (str "1px solid " (v "line"))) (d "border-radius" "12px")])
   (r ".prose table" [(d "border-collapse" "collapse") (d "width" "100%") (d "font-size" ".875rem")])
   (r ".prose th,.prose td" [(d "padding" ".6rem .8rem") (d "border-bottom" (str "1px solid " (v "line"))) (d "text-align" "left") (d "vertical-align" "top")])
   (r ".prose th" [(d "color" (v "ink")) (d "font-weight" "600") (d "background" (v "inset"))])
   (r ".prose hr" [(d "border" "0") (d "border-top" (str "1px solid " (v "line")))])
   (r ".page" [(d "padding-top" "4rem") (d "padding-bottom" "6rem")])
   (r ".byline" [(d "display" "flex") (d "flex-wrap" "wrap") (d "gap" "6px 16px") (d "margin" "1rem 0 2.5rem") (d "font" (str ".8125rem/1.5 " (mono))) (d "color" (v "ink-3"))])
   (r ".posts" [(d "list-style" "none") (d "padding" "0") (d "display" "grid") (d "gap" "1px") (d "background" (v "line")) (d "border" (str "1px solid " (v "line"))) (d "border-radius" "16px") (d "overflow" "hidden")])
   (r ".posts li" [(d "background" (v "surface"))])
   (r ".posts a" [(d "display" "grid") (d "gap" ".4rem") (d "padding" "1.25rem 1.5rem") (d "text-decoration" "none")])
   (r ".posts a:hover h3" [(d "color" (v "signal"))])
   (r ".posts p" [(d "color" (v "ink-2")) (d "font-size" ".9375rem")])
   (r ".toc" [(d "display" "flex") (d "flex-wrap" "wrap") (d "gap" "8px") (d "padding" "0") (d "list-style" "none") (d "margin-bottom" "2.5rem")])
   (r ".prose .toc" [(d "padding-left" "0")])
   (r ".toc a" [(d "display" "inline-block") (d "padding" "5px 12px") (d "border" (str "1px solid " (v "line"))) (d "border-radius" "999px") (d "font-size" ".8125rem") (d "text-decoration" "none") (d "color" (v "ink-2"))])
   (r ".toc a:hover" [(d "color" (v "ink")) (d "border-color" (v "line-strong"))])]

fn sheet -> (List c/Rule)
  (listAppend (tokenRules) (listAppend (base) (listAppend (layout) (listAppend (chrome) (listAppend (type) (listAppend (hero) (listAppend (panels) (prose))))))))

fn stylesheet -> String
  (c/renderSheet (sheet))
