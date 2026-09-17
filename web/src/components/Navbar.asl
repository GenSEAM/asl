(module aslWeb/navbar
  :d "Declarative Floating Navbar Toolbar Component in pure AgentScript"
  :x [renderNavbar
      navbarView
      navbar
      checkKonamiSequence]
  :i [(asl-text/string :a s)
      (aslWeb/ui/logo :a logo)
      (aslWeb/themeToggle :a theme)
      (aslVdom/html :a h)])

(df checkKonamiSequence [(keys (List Str))] -> (Map Keyword Any)
  :d "Checks if key buffer contains the Konami unlock sequence"
  (let [(len (list-length keys))]
    (if (>= len 10)
      (let [(k0 (option-or (list-get keys (- len 10)) ""))
            (k1 (option-or (list-get keys (- len 9)) ""))
            (k2 (option-or (list-get keys (- len 8)) ""))
            (k3 (option-or (list-get keys (- len 7)) ""))
            (k4 (option-or (list-get keys (- len 6)) ""))
            (k5 (option-or (list-get keys (- len 5)) ""))
            (k6 (option-or (list-get keys (- len 4)) ""))
            (k7 (option-or (list-get keys (- len 3)) ""))
            (k8 (option-or (list-get keys (- len 2)) ""))
            (k9 (option-or (list-get keys (- len 1)) ""))]
        (if (and (= k0 "ArrowUp")
            (and (= k1 "ArrowUp")
            (and (= k2 "ArrowDown")
            (and (= k3 "ArrowDown")
            (and (= k4 "ArrowLeft")
            (and (= k5 "ArrowRight")
            (and (= k6 "ArrowLeft")
            (and (= k7 "ArrowRight")
            (and (= k8 "b")
                 (= k9 "a"))))))))))
          (map-set (map-set (map-empty) :unlocked true) :theme "crt-amber")
          (map-set (map-set (map-empty) :unlocked false) :theme "none")))
      (map-set (map-set (map-empty) :unlocked false) :theme "none"))))

(df renderNavbar [] -> Str
  :d "Renders the floating navigation bar with Logo, links, search, and ThemeToggle"
  (h/vnodeToHtml
    (h/div (h/attrsOf (list (h/attrClass "fixed top-2 sm:top-3 left-0 right-0 z-50 flex justify-center px-2 sm:px-4 pointer-events-none w-full max-w-[100vw]")))
      (list
        (h/div (h/attrsOf (list (h/attrClass "relative pointer-events-auto max-w-shell w-full")))
          (list
            (h/header (h/attrsOf (list (h/attrClass "relative z-10 w-full rounded-full border border-line/80 bg-surface/90 backdrop-blur-2xl px-3 sm:px-4 h-12 sm:h-14 flex items-center justify-between shadow-sm transition-colors")))
              (list
                (h/div (h/attrsOf (list (h/attrClass "flex items-center gap-2 sm:gap-3 shrink-0")))
                  (list
                    (h/a (h/attrsOf (list (h/attrHref "/") (h/attrClass "rounded-full shrink-0 flex items-center gap-2 group") (h/attrTitle "aslang.dev home")))
                      (list
                        (h/t (logo/viewLogo))))
                    (h/a (h/attrsOf (list (h/attrHref "/mascot") (h/attrClass "inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-semibold bg-signal/15 text-signal border border-signal/30 hover:bg-signal/25 transition-all shadow-[0_0_10px_rgba(176,96,255,0.2)]") (h/attrTitle "Mascot Development Preview")))
                      (list
                        (h/span (h/attrsOf (list (h/attrClass "w-1.5 h-1.5 rounded-full bg-signal animate-pulse"))) (list))
                        (h/t "Mascot")))))
                (h/nav (h/attrsOf (list (h/attrClass "flex items-center gap-2 shrink-0")))
                  (list
                    (h/a (h/attrsOf (list (h/attrHref "/") (h/attrClass "px-3 py-1 rounded-full font-mono text-sm text-ink-muted hover:text-ink hover:bg-inset transition-colors")))
                      (list (h/t "Home")))
                    (h/a (h/attrsOf (list (h/attrHref "/roadmap") (h/attrClass "px-3 py-1 rounded-full font-mono text-sm text-ink-muted hover:text-ink hover:bg-inset transition-colors")))
                      (list (h/t "Roadmap")))
                    (h/a (h/attrsOf (list (h/attrHref "/docs") (h/attrClass "px-3 py-1 rounded-full font-mono text-sm text-ink-muted hover:text-ink hover:bg-inset transition-colors")))
                      (list (h/t "Docs")))
                    (h/a (h/attrsOf (list (h/attrHref "/blog") (h/attrClass "px-3 py-1 rounded-full font-mono text-sm text-ink-muted hover:text-ink hover:bg-inset transition-colors")))
                      (list (h/t "Blog")))))
                (h/div (h/attrsOf (list (h/attrClass "flex items-center gap-2 shrink-0")))
                  (list
                    (h/t (theme/renderThemeToggle))))))))))))

(df navbarView [] -> Str
  :d "Alias for render-navbar"
  (renderNavbar))

(df navbar [] -> Str
  :d "Navbar component alias"
  (renderNavbar))
