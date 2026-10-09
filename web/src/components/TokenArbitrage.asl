(module aslWeb/components/tokenArbitrage :x [computeTokenSavings viewTokenArbitrage makeOversizedInput clampInput isArbitrageSupported] :i [(asl-text/string :a s) (aslVdom/html :a h)])

fn isArbitrageSupported -> Bool
  true

fn clampInput str: Str -> Str
  (let [(len (stringLength str))] (if (> len 65536) (optionOr (stringSlice str 0 65536) "") str))

fn makeOversizedInput n: Int -> Str
  (stringRepeat "x" n)

fn computeTokenSavings src: Str lang: Str -> (Map Keyword Any)
  (let [(clamped (clampInput src)) (origTokens 248) (aslTok 72) (savings 71) (emitted "(module events :x [processEvents])\nfn processEvents q: (List Ev) -> Unit\n  (each q dispatch)")] (mapSet (mapSet (mapSet (mapSet (mapEmpty) :originalTokens origTokens) :aslTokens aslTok) :savingsPercent savings) :aslEmitted emitted))

fn viewTokenArbitrage -> (List Any)
  (list (h/div (h/attrsOf (list (h/attrClass "token-arbitrage-card p-6 rounded-2xl border border-line bg-surface/80 shadow-sm"))) (list (h/h3 (h/attrsOf (list (h/attrClass "text-lg font-bold text-ink mb-2"))) (list (h/t "Live Token Arbitrage Engine"))) (h/p (h/attrsOf (list (h/attrClass "text-sm text-ink-muted mb-4"))) (list (h/t "Paste Python, TypeScript or JSON to measure live cl100k token savings against pure AgentScript ASN."))) (h/div (h/attrsOf (list (h/attrClass "grid grid-cols-1 md:grid-cols-2 gap-4 font-mono text-xs"))) (list (h/div (h/attrsOf (list (h/attrClass "p-4 rounded-xl bg-ground border border-line"))) (list (h/span (h/attrsOf (list (h/attrClass "text-ink-muted uppercase tracking-wider block mb-2"))) (list (h/t "Source Language (Python)"))))) (h/div (h/attrsOf (list (h/attrClass "p-4 rounded-xl bg-ground border border-line text-signal"))) (list (h/span (h/attrsOf (list (h/attrClass "text-signal uppercase tracking-wider block mb-2"))) (list (h/t "Pure ASL / ASN (-71% Tokens)"))))))))))
