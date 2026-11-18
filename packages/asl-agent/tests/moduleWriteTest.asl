(module aslAgent/tests/moduleWriteTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/turn :a tr)])

; (:m :ref ABSORB-AGENT-K1-K2-K4 :do "a bare (module ...) reply is the write of the one owned .asl file only when the header maps to that path without doubt")
fn src -> String
  "asl/packages/asl-agent/src/listkit.asl"

fn body name: String -> String
  (str "(module " name "\n  :x [a])\n\nfn a -> Int64\n  1")

fn show o: (Option (List (Pair String c/KvVal))) -> String
  (match o
    ((some op) (str (match (c/dictGet op "op") ((some (c/kvStr s)) s) (_ "?")) " " (match (c/dictGet op "file") ((some (c/kvStr s)) s) (_ "?")) " " (match (c/dictGet op "content") ((some (c/kvStr s)) s) (_ "?"))))
    ((none) "none"))

fn ! runTests -> Bool
  (let [text (body "aslAgent/listkit")
        want (str "write " (src) " " text "\n")
        bare (show (tr/moduleWrite (str "\n" text "\n") (list (src))))
        fenced (show (tr/moduleWrite (str "```asl\n" text "\n```") (list (src))))
        two (show (tr/moduleWrite text (list (src) "asl/packages/asl-agent/tests/listkitTest.asl")))
        mixed (show (tr/moduleWrite text (list (src) "README.md")))
        glob (show (tr/moduleWrite text (list "asl/packages/*/src/listkit.asl")))
        other (show (tr/moduleWrite (body "aslAgent/other") (list (src))))
        tests (show (tr/moduleWrite (body "aslAgent/tests/listkit") (list (src))))
        testFile (show (tr/moduleWrite (body "aslAgent/tests/listkitTest") (list "asl/packages/asl-agent/tests/listkitTest.asl")))
        prose (show (tr/moduleWrite (str "Here is the file:\n" text) (list (src))))]
    (do
      (assert (= bare want) (str "the bare text of the one owned file is its write, byte for byte with one final newline, got " bare))
      (assert (= fenced want) (str "the same text in one fenced block too, got " fenced))
      (assert (= testFile (str "write asl/packages/asl-agent/tests/listkitTest.asl " (body "aslAgent/tests/listkitTest") "\n")) (str "a tests module for the one owned tests file, got " testFile))
      (assert (= two "none") (str "two owned files leave it unbound, got " two))
      (assert (= mixed "none") (str "an owned non-.asl file beside it leaves it unbound, the file is not the only one owned, got " mixed))
      (assert (= glob "none") (str "a glob owns leaves it unbound, got " glob))
      (assert (= other "none") (str "a module named after another file leaves it unbound, got " other))
      (assert (= tests "none") (str "a tests module for a src file leaves it unbound, got " tests))
      (assert (= prose "none") (str "prose before the module leaves it unbound, got " prose))
      true))
