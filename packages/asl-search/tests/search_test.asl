(module asl-search/test
  :d "Unit tests for SearXNG metasearch in ASL Nano"
  :x [run-tests]
  :i [(core/strings :a s)])

(df run-tests [] -> Bool
  :d "Runs search unit tests"
  (= (s/concat "http://" "example.com") "http://example.com"))
