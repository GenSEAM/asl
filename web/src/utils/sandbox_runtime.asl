(module asl-web/sandbox-runtime
  :d "In-Browser Sandbox Runtime & Harness in pure AgentScript"
  :x [runtime-preamble clean-raw-code prepare-sandbox-document]
  :i [(core/strings :a s)])

(df runtime-preamble [] -> Str
  :d "Returns the HTML/CSS/JS runtime preamble for sandboxed iframes"
  "<meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\"><style>:root { --bg: #090d16; --surface: #0f172a; --signal: #38bdf8; } * { box-sizing: border-box; } html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: var(--bg); color: #f1f5f9; font-family: system-ui, sans-serif; }</style>")

(df clean-raw-code [(raw Str)] -> Str
  :d "Strips markdown fences and isolates executable code from LLM output"
  (let [(t1 (s/trim raw))
        (t2 (if (s/contains? t1 "```") (s/replace t1 "```" "") t1))]
    (s/trim t2)))

(df prepare-sandbox-document [(raw-html Str)] -> Str
  :d "Injects runtime preamble and wraps HTML code for sandbox iframe execution"
  (let [(clean (clean-raw-code raw-html))]
    (if (s/contains? clean "<html")
      clean
      (s/concat "<!DOCTYPE html><html><head>" (s/concat (runtime-preamble) (s/concat "</head><body>" (s/concat clean "</body></html>")))))))
