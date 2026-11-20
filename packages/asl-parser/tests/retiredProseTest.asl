(module asl-parser/retiredProseTest
  :x [runTests]
  :i [(asl-parser/ast :a ast)])

fn verdict src: String -> String
  (match (ast/parse src) ((ok _) "ok") ((err e) e.msg))

fn legacy src: String -> String
  (match (ast/parseLegacy src) ((ok _) "ok") ((err e) e.msg))

fn head -> String
  "(module probe :x [f])\n\n"

fn runTests -> Bool
  (do
    (assert (stringStartsWith? (verdict (str (head) "; prose\nfn f -> Int64\n  1\n")) "ERR_READ_COMMENT") "a free comment is rejected")
    (assert (stringStartsWith? (verdict (str (head) "; (:m :why \"x\")\nfn f -> Int64\n  1\n")) "ERR_READ_COMMENT") "a why comment is rejected")
    (assert (stringStartsWith? (verdict (str (head) "fn f -> Int64\n  1 ; one\n")) "ERR_READ_COMMENT") "a trailing comment is rejected")
    (assert (stringStartsWith? (verdict "(module probe :d \"x\" :x [f])\n\nfn f -> Int64\n  1\n") "ERR_READ_DOC") "a module :d is rejected")
    (assert (stringStartsWith? (verdict "(module probe :doc \"x\" :x [f])\n\nfn f -> Int64\n  1\n") "ERR_READ_DOC") "a module :doc is rejected")
    (assert (stringStartsWith? (verdict (str (head) "fn f -> Int64\n  :d \"x\"\n  1\n")) "ERR_READ_DOC") "a fn :d is rejected")
    (assert (stringStartsWith? (verdict "(module probe :x [S])\n\n(schema S :d \"x\" (:f a Int64))\n") "ERR_READ_DOC") "a schema :d is rejected")
    (assert (= (verdict (str (head) "; (:m :tags (probe))\nfn f -> Int64\n  \"; not a comment\"\n")) "ok") "a meta comment and a ; inside a string are fine")
    (assert (= (verdict "(module probe :x [S f])\n\n(schema S (:f d String))\n\nfn f -> S\n  (S :d \"x\")\n") "ok") "a record field named d is data")
    (let [(m (verdict (str (head) "; (:m :why \"x\")\nfn f -> Int64\n  1\n")))]
      (do
        (assert (stringContains? m "for example: ; (:m :do \"what and why\")") (str "the comment message shows the one allowed line, got " m))
        (assert (stringContains? m "whole line that starts with ;") (str "the message says the allowed form starts with ;, got " m))
        (assert (stringContains? m "without the leading ; is not a top-level form") (str "the message forbids a bare (:m ...) top-level form, got " m))
        (refute (stringContains? m "are retired") (str "the message no longer says comments are retired and then allows one, got " m))
        true))
    (assert (= (legacy (str (head) "; prose\nfn f -> Int64\n  :d \"x\"\n  1\n")) "ok") "parseLegacy still reads retired prose for the extractor")
    true)
