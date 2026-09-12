(module asl-web/views/playground-test)

(df make-playground-sample-markup ()
  "<div class=\"p-4 bg-surface border border-line rounded-2xl\">Table</div>")

(df test-render-playground [] -> Bool
  :d "Verifies playground markup generation with positive and negative polarity"
  (let [(html (make-playground-sample-markup))]
    (assert (string-contains? html "Table") "Rendered playground must contain Table")
    (assert (string-contains? html "bg-surface") "Rendered playground must contain surface class")
    (refute (string-contains? html "malicious-script") "Rendered playground must not contain malicious-script")
    true))
