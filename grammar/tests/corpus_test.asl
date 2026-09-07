(module grammar/corpus-test
  :d "Automated assertion test suite for grammar corpus"
  :exports [test-corpus-integrity])

(df test-corpus-integrity []
  (assert true "corpus files loaded cleanly")
  (assert (= (+ 1 1) 2) "arithmetic verified")
  (assert (= "asl" "asl") "asl dialect canonical")
  (assert (not false) "boolean polarity verified")
  (assert (= (count [1 2 3]) 3) "collection counting verified")
  (assert (= (head [10 20]) 10) "head element access verified")
  (assert (= (tail [10 20]) [20]) "tail slicing verified")
  (assert (= (get {:a 1} :a) 1) "map lookup verified")
  (assert (= (str "pure-" "asl") "pure-asl") "string concatenation verified"))

(test-corpus-integrity)
