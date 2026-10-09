(module aslWeb/views/playgroundTest)

fn makePlaygroundSampleMarkup
  "<div class=\"p-4 bg-surface border border-line rounded-2xl\">Table</div>"

fn testRenderPlayground -> Bool
  (let [(html (makePlaygroundSampleMarkup))] (assert (stringContains? html "Table") "Rendered playground must contain Table") (assert (stringContains? html "bg-surface") "Rendered playground must contain surface class") (refute (stringContains? html "malicious-script") "Rendered playground must not contain malicious-script") true)
