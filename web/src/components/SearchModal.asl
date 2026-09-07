(module asl-web/search-modal
  :d "Declarative Search Modal Dialog Component in pure AgentScript"
  :x [describe-search-modal render-search-modal]
  :i [(core/strings :a s)])

(df describe-search-modal [] -> Str
  :d "Returns structured search index metadata"
  "(modal :id \"search\" :indices [\"docs\" \"grammar\" \"packages\" \"blog\"] :keyboard-shortcut \"Cmd+K\")")

(df render-search-modal [] -> Str
  :d "Renders search modal container markup"
  (s/concat
    "<div class=\"fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center pt-24 px-4\">"
    (s/concat
      "<div class=\"w-full max-w-2xl rounded-2xl border border-line bg-surface p-4 shadow-2xl\">"
      "<div class=\"flex items-center gap-3 border-b border-line pb-3 mb-3\"><input type=\"search\" placeholder=\"Search documentation, packages, grammar... (Cmd+K)\" class=\"w-full bg-transparent text-ink placeholder:text-ink-2 outline-none font-sans text-base\"/></div><div class=\"space-y-2 max-h-96 overflow-y-auto\"><div class=\"p-3 rounded-xl hover:bg-surface-2 cursor-pointer\"><h4 class=\"font-semibold text-ink text-sm\">The Agent Way</h4><p class=\"text-xs text-ink-2\">Why languages designed for humans fail autonomous agents.</p></div></div></div></div>")))
