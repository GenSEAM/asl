(module asl-web/polyglot-banner
  :d "Declarative Polyglot Banner Component in ASL"
  :x [render-polyglot-banner]
  :i [(asl-text/string :a s)])

(df render-polyglot-banner [(framework Str) (speedup Str)] -> Str
  :d "Renders polyglot compilation status banner"
  (s/concat
    (s/concat "<div class=\"p-4 rounded-xl border border-line bg-surface-2 flex items-center justify-between text-xs font-mono\"><span>Target: " framework)
    (s/concat "</span><span class=\"text-emerald-400 font-bold\">" (s/concat speedup "</span></div>"))))
