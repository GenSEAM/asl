(ns asl.web.views.playground.test)

(df render-playground-test ()
  "<div class=\"p-4 bg-surface border border-line rounded-2xl\">Table</div>")

(df test-render-playground [] -> Bool
  :d "Verifies playground markup generation"
  (let [(html (render-playground-test))]
    (assert (string-contains? html "Table") "Rendered playground must contain Table")
    (assert (string-contains? html "bg-surface") "Rendered playground must contain surface class")
    true))
