(module aslWeb/views/playgroundTest)

(df makePlaygroundSampleMarkup ()
  "<div class=\"p-4 bg-surface border border-line rounded-2xl\">Table</div>")

(df testRenderPlayground [] -> Bool
  :d "Verifies playground markup generation with positive and negative polarity"
  (let [(html (makePlaygroundSampleMarkup))]
    (assert (string-contains? html "Table") "Rendered playground must contain Table")
    (assert (string-contains? html "bg-surface") "Rendered playground must contain surface class")
    (refute (string-contains? html "malicious-script") "Rendered playground must not contain malicious-script")
    true))
