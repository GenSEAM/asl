(module aslWeb/hero
  :d "Declarative Hero Banner Component with Cyber Chameleon mascot in pure AgentScript"
  :x [viewHero
      renderHero
      heroView
      hero]
  :i [(asl-text/string :a s)
      (aslWeb/ui/logo :a logo)
      (aslWeb/components/mascot :a mascot)
      (aslVdom/html :a h)])

(df viewHero [] -> (List Any)
  :d "Pure VNode representation of hero section with floating perched chameleon, spacious typography, horizontal cards, and neon install command"
  (list
    (h/sec (h/attrsOf (list (h/attrId "top") (h/attrClass "relative pt-24 pb-16 sm:pt-28 sm:pb-20 overflow-hidden ambient-top-light")))
      (list
        (h/div (h/attrsOf (list (h/attrClass "max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10 space-y-12")))
          (list
            (h/div (h/attrsOf (list (h/attrClass "grid grid-cols-1 lg:grid-cols-12 gap-8 lg:gap-12 items-center")))
              (list
                (h/div (h/attrsOf (list (h/attrClass "lg:col-span-5 flex flex-col justify-center items-center relative py-4")))
                  (list
                    (h/div (h/attrsOf (list (h/attrClass "absolute inset-0 bg-signal/20 blur-3xl rounded-full pointer-events-none scale-110"))) (list))
                    (h/div (h/attrsOf (list (h/attrClass "neon-svg-glow transition-transform duration-300 hover:scale-105")))
                      (list (h/t (mascot/viewChameleon))))
                    (h/div (h/attrsOf (list (h/attrClass "mt-2 font-mono text-[11px] text-ink-3 tracking-wider uppercase text-center")))
                      (list (h/t "AX-4 Chameleon · Sovereign Agent Substrate")))))
                (h/div (h/attrsOf (list (h/attrClass "lg:col-span-7 space-y-5 text-left")))
                  (list
                    (h/div (h/attrsOf (list (h/attrClass "flex items-center gap-2 flex-wrap")))
                      (list
                        (h/span (h/attrsOf (list (h/attrClass "font-mono text-xs px-3 py-1 rounded-full bg-signal/15 text-signal border border-signal/30 font-semibold shadow-[0_0_12px_rgba(176,96,255,0.25)]")))
                          (list (h/t "v0.4.1 [clean-break]")))
                        (h/span (h/attrsOf (list (h/attrClass "font-mono text-xs px-3 py-1 rounded-full bg-surface text-ink-2 border border-line")))
                          (list (h/t "Universal Multi-Target")))
                        (h/span (h/attrsOf (list (h/attrClass "font-mono text-xs px-3 py-1 rounded-full bg-surface text-signal border border-line font-medium")))
                          (list (h/t "~68% Token Savings")))
                        (h/span (h/attrsOf (list (h/attrClass "font-mono text-xs px-3 py-1 rounded-full bg-surface text-ink-2 border border-line")))
                          (list (h/t "Self-Hosted & Portable")))))
                    (h/h1 (h/attrsOf (list (h/attrClass "text-display font-bold text-ink tracking-tight text-3xl sm:text-4xl lg:text-5xl leading-[1.1] neon-title-gradient")))
                      (list
                        (h/t "The Universal Polyglot Substrate for ")
                        (h/span (h/attrsOf (list (h/attrClass "text-signal neon-text-glow")))
                          (list (h/t "Autonomous Agents")))))
                    (h/p (h/attrsOf (list (h/attrClass "text-lead text-ink-2 leading-relaxed text-base sm:text-lg")))
                      (list (h/t "Engineered for autonomous models: impossible to write bad code, balanced single-pass S-expressions, average 68% token reduction, and clean ahead-of-time transpilation into C99, WebAssembly, Python, and TypeScript.")))))))

            (h/div (h/attrsOf (list (h/attrClass "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4")))
              (list
                (h/div (h/attrsOf (list (h/attrClass "p-5 rounded-2xl neon-card flex flex-col justify-between")))
                  (list
                    (h/div (h/attrsOf (list (h/attrClass "flex items-center gap-2 mb-2")))
                      (list
                        (h/span (h/attrsOf (list (h/attrClass "w-2.5 h-2.5 rounded-full bg-signal shadow-[0_0_8px_#B060FF]"))) (list))
                        (h/h3 (h/attrsOf (list (h/attrClass "font-bold text-ink text-sm font-sans tracking-tight")))
                          (list (h/t "Multi-Target Transpilation")))))
                    (h/p (h/attrsOf (list (h/attrClass "text-xs text-ink-3 leading-relaxed font-sans")))
                      (list (h/t "Clean ahead-of-time emission into C99, WASM, Python, and TypeScript with zero runtime baggage and ~68% token reduction.")))))
                (h/div (h/attrsOf (list (h/attrClass "p-5 rounded-2xl neon-card flex flex-col justify-between")))
                  (list
                    (h/div (h/attrsOf (list (h/attrClass "flex items-center gap-2 mb-2")))
                      (list
                        (h/span (h/attrsOf (list (h/attrClass "w-2.5 h-2.5 rounded-full bg-signal shadow-[0_0_8px_#B060FF]"))) (list))
                        (h/h3 (h/attrsOf (list (h/attrClass "font-bold text-ink text-sm font-sans tracking-tight")))
                          (list (h/t "Global Agent Toolbelt")))))
                    (h/p (h/attrsOf (list (h/attrClass "text-xs text-ink-3 leading-relaxed font-sans")))
                      (list (h/t "1-command global injection via asl toolbelt across Claude Code, Cursor, Windsurf, Antigravity, Factory Droid, and Codex.")))))
                (h/div (h/attrsOf (list (h/attrClass "p-5 rounded-2xl neon-card flex flex-col justify-between")))
                  (list
                    (h/div (h/attrsOf (list (h/attrClass "flex items-center gap-2 mb-2")))
                      (list
                        (h/span (h/attrsOf (list (h/attrClass "w-2.5 h-2.5 rounded-full bg-signal shadow-[0_0_8px_#B060FF]"))) (list))
                        (h/h3 (h/attrsOf (list (h/attrClass "font-bold text-ink text-sm font-sans tracking-tight")))
                          (list (h/t "Autonomous Subagents & Harness")))))
                    (h/p (h/attrsOf (list (h/attrClass "text-xs text-ink-3 leading-relaxed font-sans")))
                      (list (h/t "Enforce correct-by-construction code, scoped permissions, and custom system prompt overrides (asl launch) with deterministic receipts.")))))
                (h/div (h/attrsOf (list (h/attrClass "p-5 rounded-2xl neon-card flex flex-col justify-between")))
                  (list
                    (h/div (h/attrsOf (list (h/attrClass "flex items-center gap-2 mb-2")))
                      (list
                        (h/span (h/attrsOf (list (h/attrClass "w-2.5 h-2.5 rounded-full bg-signal shadow-[0_0_8px_#B060FF]"))) (list))
                        (h/h3 (h/attrsOf (list (h/attrClass "font-bold text-ink text-sm font-sans tracking-tight")))
                          (list (h/t "In-Memory VFS & State")))))
                    (h/p (h/attrsOf (list (h/attrClass "text-xs text-ink-3 leading-relaxed font-sans")))
                      (list (h/t "Sub-15ms BM25 vector queries, staged RAM buffer edits (asl mem), and stateless 9-syscall isolation across any host.")))))))

            (h/div (h/attrsOf (list (h/attrClass "max-w-2xl mx-auto flex flex-col items-center gap-3.5 w-full pt-4")))
              (list
                (h/div (h/attrsOf (list (h/attrClass "install-terminal asl-install-bar neon-glow-pill p-4 rounded-2xl font-mono text-sm flex items-center justify-between w-full transition-transform duration-200 hover:scale-[1.01]")))
                  (list
                    (h/div (h/attrsOf (list (h/attrClass "flex items-center gap-2.5")))
                      (list
                        (h/span (h/attrsOf (list (h/attrClass "text-signal text-xs font-bold"))) (list (h/t ">_")))
                        (h/span (h/attrsOf (list (h/attrClass "text-ink font-medium")))
                          (list (h/t "curl -fsSL https://aslang.dev/install.sh | sh")))))
                    (h/span (h/attrsOf (list (h/attrClass "text-signal text-xs font-semibold px-3 py-1 rounded-lg bg-signal/15 border border-signal/30 cursor-pointer copy-btn hover:bg-signal/25 transition-colors")))
                      (list (h/t "COPY")))))
                (h/div (h/attrsOf (list (h/attrClass "p-3 rounded-xl bg-surface/60 border border-line/60 font-mono text-xs flex items-center justify-between w-full max-w-xl")))
                  (list
                    (h/div (h/attrsOf (list (h/attrClass "flex items-center gap-2")))
                      (list
                        (h/span (h/attrsOf (list (h/attrClass "text-signal font-semibold"))) (list (h/t "AGENTS")))
                        (h/span (h/attrsOf (list (h/attrClass "text-ink-2")))
                          (list (h/t "asl toolbelt install --all")))))
                    (h/span (h/attrsOf (list (h/attrClass "text-ink-3 hover:text-signal cursor-pointer copy-btn font-medium")))
                      (list (h/t "COPY")))))))))))))

(df renderHero [] -> Str
  :d "Renders hero component to HTML string"
  (h/vnodeToHtml (option-or (list-get (viewHero) 0) (h/divPlain (list)))))

(df heroView [] -> Str
  :d "Hero view alias"
  (renderHero))

(df hero [] -> Str
  :d "Hero alias"
  (renderHero))
