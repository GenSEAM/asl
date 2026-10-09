(module aslBrowserPlugin/domCompiler :x [compileProbeJs compileTableExtractor compileTextSelector] :i [(asl-text/escape :a esc)])

fn compileProbeJs targetSelector: Str attribute: Str -> Str
  (str "(() => {\nconst el = document.querySelector(\"" (esc/escapeJsonStr targetSelector) "\")\nreturn el ? el.getAttribute(\"" (esc/escapeJsonStr attribute) "\") : null\n})()")

fn compileTableExtractor tableSelector: Str -> Str
  (str "(() => {\nconst rows = Array.from(document.querySelectorAll(\"" (esc/escapeJsonStr tableSelector) " tr\"))\nreturn JSON.stringify(rows.map(r => Array.from(r.children).map(c => c.textContent.trim())))\n})()")

fn compileTextSelector selector: Str -> Str
  (str "(() => {\nconst el = document.querySelector(\"" (esc/escapeJsonStr selector) "\")\nreturn el ? el.innerText.trim() : ''\n})()")
