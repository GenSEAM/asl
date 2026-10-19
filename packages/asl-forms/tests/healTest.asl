(module asl-forms/tests/healTest
  :x [runTests healsTo? untouched?]
  :i [(asl-forms/heal :a h) (asl-checker/types :a ty) (asl-proc/jobPool :a jp)])

; (:m :do "one fixture per heal rule (HEAL 2026-10-15): the broken text has diagnostics before, the pipeline without the rule (the mutant) does not heal it, the full pipeline heals to the exact expected text with the rule named in :repaired and nothing left, healing the result again changes nothing, and a near-miss text that already checks stays byte-identical")

fn hdr -> String
  "(module m :x [f])\n\n"

fn healsTo? rule: String broken: String want: String vocab: (List String) -> Bool
  (let [(before (h/healDiags broken (mapEmpty) "m.asl"))
        (res (h/healSourceWith broken "m.asl" (mapEmpty) vocab))
        (again (h/healSourceWith res.text "m.asl" (mapEmpty) vocab))
        (mutant (h/healSourceRules broken "m.asl" (mapEmpty) vocab (filter (fn [(r String)] -> Bool (!= r rule)) (h/healRuleNames))))]
    (assert (not (listEmpty? before)) (str rule ": the broken fixture has diagnostics before healing"))
    (assert (= res.text want) (str rule ": heals to the expected text, got " res.text " receipt " res.receipt))
    (assert (listContains? res.repaired rule) (str rule ": the receipt names the rule, got " res.receipt))
    (assert (listEmpty? res.left) (str rule ": nothing is left, got " res.receipt))
    (assert (and (not again.changed) (= again.text res.text)) (str rule ": healing the healed text changes nothing"))
    (assert (not (and (= mutant.text want) (listEmpty? mutant.left))) (str rule ": the mutant pipeline without this rule does not heal the fixture"))
    true)

fn untouched? label: String text: String -> Bool
  (let [(res (h/healSource text "m.asl"))]
    (assert (listEmpty? (h/healDiags text (mapEmpty) "m.asl")) (str label ": the near-miss already checks"))
    (assert (and (= res.text text) (not res.changed)) (str label ": a checking text is returned byte-identical"))
    (assert (= res.receipt "(:repaired () :left ())") (str label ": its receipt is empty, got " res.receipt))
    true)

fn testDelimiterBalance -> Bool
  (and (healsTo? "delimiterBalance" (str (hdr) "fn f n: Int64 -> Int64\n  (+ n 1))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (+ n 1)\n") (list))
       (untouched? "delimiterBalance near-miss" (str (hdr) "fn f n: Int64 -> Int64\n  (+ (+ n 1) 1)\n")))

fn testLineHeader -> Bool
  (and (healsTo? "lineHeader" "module m\ndoc \"adds one\"\nexports f\n\nfn f n: Int64 -> Int64\n  (+ n 1)\n"
                 "(module m :x [f])\n; (:m :doc \"adds one\")\n\nfn f n: Int64 -> Int64\n  (+ n 1)\n" (list))
       (untouched? "lineHeader near-miss" "(module m :x [f])\n; (:m :note \"module m\")\n\nfn f n: Int64 -> Int64\n  (+ n 1)\n"))

fn testFreeComment -> Bool
  (and (healsTo? "freeComment" (str (hdr) "; adds one\nfn f n: Int64 -> Int64\n  (+ n 1)\n") (str (hdr) "; (:m :note \"adds one\")\nfn f n: Int64 -> Int64\n  (+ n 1)\n") (list))
       (untouched? "freeComment near-miss" (str (hdr) "; (:m :note \"adds one\")\nfn f n: Int64 -> Int64\n  (+ n 1)\n")))

fn testFnHeaderUnwrap -> Bool
  (and (healsTo? "fnHeaderUnwrap" (str (hdr) "(fn f n: Int64 -> Int64\n  (+ n 1))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (+ n 1)\n") (list))
       (healsTo? "fnHeaderUnwrap" (str (hdr) "(fn f n: Int64 -> Int64 (+ n 1))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (+ n 1)\n") (list))
       (untouched? "fnHeaderUnwrap near-miss" (str (hdr) "fn f n: Int64 -> Int64\n  ((fn [(x Int64)] -> Int64 (+ x 1)) n)\n")))

fn testBodyIndent -> Bool
  (and (healsTo? "bodyIndent" (str (hdr) "fn f n: Int64 -> Int64\n(let [(a (+ n 1))]\n a)\n") (str (hdr) "fn f n: Int64 -> Int64\n  (let [(a (+ n 1))]\n   a)\n") (list))
       (untouched? "bodyIndent near-miss" (str (hdr) "fn f n: Int64 -> Int64\n   (let [(a (+ n 1))]\n    a)\n")))

; (:m :ref FIX-COND-SHAPE-20261016 :do "staysDiagnosed?: a clause whose swap would not help (neither reading is a Bool test) is not guessed at; the diagnostic the checker already gives, naming cond, is what is left")
fn staysDiagnosed? rule: String text: String needle: String -> Bool
  (let [(res (h/healSourceWith text "m.asl" (mapEmpty) (list)))]
    (do (assert (not res.changed) (str rule ": the ambiguous fixture is not rewritten, got " res.receipt))
        (assert (not (listEmpty? res.left)) (str rule ": the ambiguous fixture keeps a real diagnostic, got " res.receipt))
        (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (stringContains? (h/diagText d) needle)) res.left) (str rule ": the diagnostic names the cond shape, got " res.receipt))
        true))

; (:m :ref FIX-COND-SHAPE-20261016 :do "the 6 E11 checkFail shapes (SH/plan.asn amend rejudged: unmarked pooled checkFail 22, ERR_TYPE_MISMATCH 18 malformed cond test/value pairing, ERR_UNKNOWN_SYMBOL 4 else as a binding/seq); the raw cand.asl files under the SYN13 run dirs are gone, so these 6 are rebuilt from the classification: 4 shifted test/value pairs (3 heal, 1 genuinely ambiguous so it keeps the checker's own diagnostic naming cond) and 2 else-as-a-bare-atom-inside-brackets, both already covered by the brackets mode above")
fn testCondShapeE11 -> Bool
  (and (healsTo? "condClauses" (str (hdr) "fn f n: Int64 -> Int64\n  (cond\n    (1 (> n 0))\n    (else 0))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (cond\n    ((> n 0) 1)\n    (else 0))\n") (list))
       (healsTo? "condClauses" (str (hdr) "fn f n: Int64 -> Int64\n  (cond\n    (1 (> n 0))\n    (-1 (< n 0))\n    (else 0))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (cond\n    ((> n 0) 1)\n    ((< n 0) -1)\n    (else 0))\n") (list))
       (healsTo? "condClauses" (str (hdr) "fn f s: String -> String\n  (cond\n    ((stringEmpty? s) \"empty\")\n    (\"nonempty\" (not (stringEmpty? s)))\n    (else \"?\"))\n") (str (hdr) "fn f s: String -> String\n  (cond\n    ((stringEmpty? s) \"empty\")\n    ((not (stringEmpty? s)) \"nonempty\")\n    (else \"?\"))\n") (list))
       (staysDiagnosed? "condClauses" (str (hdr) "fn f n: Int64 -> Int64\n  (cond\n    ((> n 0) \"x\")\n    (else 0))\n") "cond")
       (healsTo? "condClauses" (str (hdr) "fn f n: Int64 -> Int64\n  (cond\n    [(> n 0) 1]\n    [(< n 0) -1]\n    [else 0])\n") (str (hdr) "fn f n: Int64 -> Int64\n  (cond\n    ((> n 0) 1)\n    ((< n 0) -1)\n    (else 0))\n") (list))
       (healsTo? "condClauses" (str (hdr) "fn f n: Int64 -> Int64\n  (cond\n    ((> n 0) 1)\n    ((< n 0) -1)\n    [else 0])\n") (str (hdr) "fn f n: Int64 -> Int64\n  (cond\n    ((> n 0) 1)\n    ((< n 0) -1)\n    (else 0))\n") (list)))

fn testCondClauses -> Bool
  (and (healsTo? "condClauses" (str (hdr) "fn f n: Int64 -> Int64\n  (cond [(> n 0) 1] [(else 0)])\n") (str (hdr) "fn f n: Int64 -> Int64\n  (cond ((> n 0) 1) (else 0))\n") (list))
       (healsTo? "condClauses" (str (hdr) "fn f n: Int64 -> Int64\n  (cond ((> n 0) 1) ((else 0)))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (cond ((> n 0) 1) (else 0))\n") (list))
       (healsTo? "condClauses" (str (hdr) "fn f n: Int64 -> Int64\n  (cond ((> n 0) 1 (else 0)))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (cond ((> n 0) 1) (else 0))\n") (list))
       (healsTo? "condClauses" (str (hdr) "fn f n: Int64 -> Int64\n  (cond (> n 0) 1 (< n 0) 2 (else 0))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (cond ((> n 0) 1) ((< n 0) 2) (else 0))\n") (list))
       (testCondShapeE11)
       (untouched? "condClauses near-miss" (str (hdr) "fn f n: Int64 -> Int64\n  (let [(b (> n 0))]\n    (cond (b 1) (else 0)))\n")))

fn testLetBindingVector -> Bool
  (and (healsTo? "letBindingVector" (str (hdr) "fn f n: Int64 -> Int64\n  (let ((a 1) (b n)) (+ a b))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (let [(a 1) (b n)] (+ a b))\n") (list))
       (healsTo? "letBindingVector" (str (hdr) "fn f n: Int64 -> Int64\n  (let (a 1 b n) (+ a b))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (let [(a 1) (b n)] (+ a b))\n") (list))
       (untouched? "letBindingVector near-miss" (str (hdr) "fn f n: Int64 -> Int64\n  (let [(a 1) (b n)] (+ a b))\n")))

fn testTestPredicate -> Bool
  (and (healsTo? "testPredicate" (str (hdr) "fn f n: Int64 -> Int64\n  (let [(o (some n))]\n    (cond ((some o) 1) (else 0)))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (let [(o (some n))]\n    (cond ((some? o) 1) (else 0)))\n") (list))
       (healsTo? "testPredicate" (str (hdr) "fn f n: Int64 -> Int64\n  (let [(o (some n))]\n    (if (none o) 0 1))\n") (str (hdr) "fn f n: Int64 -> Int64\n  (let [(o (some n))]\n    (if (none? o) 0 1))\n") (list))
       (untouched? "testPredicate near-miss" (str (hdr) "fn f n: Int64 -> Int64\n  (let [(o (some n))]\n    (cond ((some? o) 1) (else 0)))\n")))

fn testSymbolRename -> Bool
  (and (healsTo? "symbolRename" (str (hdr) "fn f n: Int64 -> Int64\n  (if (isSome (some n)) 1 0)\n") (str (hdr) "fn f n: Int64 -> Int64\n  (if (some? (some n)) 1 0)\n") (list))
       (healsTo? "symbolRename" (str (hdr) "fn ! f n: Int64 -> Int64\n  (let [(p (println! n))]\n    n)\n") (str (hdr) "fn ! f n: Int64 -> Int64\n  (let [(p (println n))]\n    n)\n") (list))
       (healsTo? "symbolRename" (str (hdr) "fn f n: Int64 -> Int64\n  (listSun [n 1])\n") (str (hdr) "fn f n: Int64 -> Int64\n  (listSum [n 1])\n") (list "listSum" "listSort"))
       (healsTo? "symbolRename" "(module m :x [f addOne])\n\nfn addOne n: Int64 -> Int64\n  (+ n 1)\n\nfn f n: Int64 -> Int64\n  (add_one n)\n" "(module m :x [f addOne])\n\nfn addOne n: Int64 -> Int64\n  (+ n 1)\n\nfn f n: Int64 -> Int64\n  (addOne n)\n" (list))
       (untouched? "symbolRename near-miss" (str (hdr) "fn f n: Int64 -> Int64\n  (listSum [n 1])\n")))

; (:m :ref EFFECT-INFER :do "InferWhatCanBeInferred (2026-10-16): ! is optional and the checker infers an unmarked effect, so the plain fixture no longer reports ERR_EFFECT_UNMARKED and effectMark has nothing to repair; m.asl has no manifest.asn on disk, so it is never a :pure package. testEffectMarkPure below proves the rule still does its job for real, against a genuine :pure package on disk (packagePure! reads the filesystem by path).")
fn testEffectMark -> Bool
  (and (untouched? "effectMark: an unmarked effectful fn outside a :pure package infers clean" (str (hdr) "fn f n: Int64 -> Int64\n  (let [(p (println n))]\n    n)\n"))
       (untouched? "effectMark near-miss" (str (hdr) "fn ! f n: Int64 -> Int64\n  (let [(p (println n))]\n    n)\n")))

fn ! writePureManifest! dir: String -> Bool
  (ok? (fileWrite (str dir "/manifest.asn") "(:package puretest :pure true)\n"))

fn ! testEffectMarkPure -> Bool
  (let [(made (jp/runOne (jp/job (list "mktemp" "-d") "." (jp/childEnv (list))))) (dir (stringReplace made.out "\n" "")) (path (str dir "/m.asl"))
        (broken (str (hdr) "fn f n: Int64 -> Int64\n  (let [(p (println n))]\n    n)\n"))
        (want (str (hdr) "fn ! f n: Int64 -> Int64\n  (let [(p (println n))]\n    n)\n"))]
    (do (assert (= made.exit 0) "mktemp -d makes a workspace directory")
        (assert (writePureManifest! dir) "pure manifest written")
        (let [(before (h/healDiags broken (mapEmpty) path))
              (res (h/healSourceWith broken path (mapEmpty) (list)))
              (again (h/healSourceWith res.text path (mapEmpty) (list)))
              (mutant (h/healSourceRules broken path (mapEmpty) (list) (filter (fn [(r String)] -> Bool (!= r "effectMark")) (h/healRuleNames))))]
          (do (assert (not (listEmpty? before)) "a :pure package reports the unmarked effect before healing")
              (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "ERR_EFFECT_UNMARKED")) before) (str "the diagnostic is ERR_EFFECT_UNMARKED, got " (stringJoin (map (fn [(d ty/Diagnostic)] -> String d.code) before) ",")))
              (assert (= res.text want) (str "effectMark heals the :pure violation, got " res.text " receipt " res.receipt))
              (assert (listContains? res.repaired "effectMark") (str "the receipt names effectMark, got " res.receipt))
              (assert (listEmpty? res.left) (str "nothing is left, got " res.receipt))
              (assert (and (not again.changed) (= again.text res.text)) "healing the healed text changes nothing")
              (assert (not (and (= mutant.text want) (listEmpty? mutant.left))) "the mutant pipeline without effectMark does not heal the :pure violation")
              true))
        (assert (= (jp/runOne (jp/job (list "rm" "-rf" dir) "." (jp/childEnv (list)))).exit 0) "workspace removed")
        true))

fn testUnrepairableIsReported -> Bool
  (let [(broken "(module m :x [f])\n\n(let [(a (+ n 1))] a)\n")
        (res (h/healSource broken "m.asl"))]
    (assert (not (listEmpty? res.left)) "a missing defun header is not invented: the unbound parameter is left")
    (assert (stringContains? res.receipt ":left (\"ERR_UNKNOWN_SYMBOL") (str "the receipt lists what is left, got " res.receipt))
    true)

fn testEdits -> Bool
  (let [(t "abcdef")]
    (assert (= (h/applyEdits t (list (h/Edit :start 1 :end 2 :with "X") (h/Edit :start 1 :end 1 :with "<"))) "a<Xcdef") "an insertion lands before a replacement at the same offset")
    (assert (= (h/applyEdits t (list (h/Edit :start 1 :end 4 :with "") (h/Edit :start 2 :end 3 :with "Y"))) "aef") "an edit overlapping a kept one is dropped")
    (assert (= (h/editDistance "listSun" "listSum") 1) "edit distance of one substitution")
    (assert (= (h/editDistance "kitten" "sitting") 3) "edit distance kitten/sitting")
    true)

fn runTests -> Bool
  (and (testDelimiterBalance) (testLineHeader) (testFreeComment) (testFnHeaderUnwrap) (testBodyIndent) (testCondClauses)
       (testLetBindingVector) (testTestPredicate) (testSymbolRename) (testEffectMark) (testEffectMarkPure) (testUnrepairableIsReported) (testEdits))
