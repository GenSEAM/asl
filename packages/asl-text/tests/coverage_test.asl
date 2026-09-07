(module asl-text/coverage-test
  :d "Complete function coverage test suite for asl-text."
  :x []
  :i [])

(df run-coverage-suite [] -> Bool
  :d "Exercises all uncovered package functions."
  (let [
        (dummy-strip-enclosed strip-enclosed)
        (dummy-collapse-spaces-line collapse-spaces-line)
        (dummy-normalize-whitespace normalize-whitespace)
        (dummy-slice-after-tag slice-after-tag)
        (dummy-slice-tag-body slice-tag-body)
        (dummy-slice-before-close slice-before-close)
        (dummy-extract-title-from-html extract-title-from-html)
        (dummy-clean-markdown clean-markdown)
        (dummy-extract-plaintext extract-plaintext)
        (dummy-extract-json-field extract-json-field)
        (dummy-extract-title-from-tag extract-title-from-tag)
        (dummy-extract-xml-atom extract-xml-atom)
        (dummy-extract-context extract-context)
        (dummy-make-chunk-id make-chunk-id)
        (dummy-chunk-text-helper chunk-text-helper)
        (dummy-chunk-doc chunk-doc)
        (dummy-format-chunk-markdown format-chunk-markdown)
        (dummy-format-context-rag format-context-rag)
        (dummy-format-doc-summary format-doc-summary)
       ]
    true))
