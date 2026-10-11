(module asl-checker/hlCheckTypeRegressionTest :x [runTests] :i [(asl-checker/check :a c) (asl-checker/types :a ty)])

fn diagnosticsText ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn ! checkSnippet! tag: String src: String -> (List ty/Diagnostic)
  (let [(path (str (optionOr (envGet "TMPDIR") "/tmp/") "hlCheckTypeRegression_" tag "_" (stringFromInt64 (nowNs)) ".asl"))
        (_wrote (fileWrite path src))
        (ds (resultOr (resultMapErr (fn [(e IoError)] -> String (str e)) (c/checkFile! path (list "."))) (list)))
        (_cleaned (pathRemove path))]
    ds)

fn ! testProcAliveReturnsResult! -> Bool
  (let [(ds (checkSnippet! "procAlive" "(module m :x [f])\n\nfn ! f x: Int64 -> Bool\n  (mt (procAlive? x) ((ok v) v) ((err _) false))\n"))]
    (do (assert (listEmpty? ds) (str "procAlive? is (Result Bool String), not Bool, so an ok/err match on its call is legal: " (diagnosticsText ds))) true))

fn ! testSelfPassLambdaNeedsAnyAnnotation! -> Bool
  (let [(ds (checkSnippet! "selfPass" "(module m :x [f])\n\nfn f n: Int64 -> Int64\n  (let [(step (fn [(step Any) i] -> Int64 (if (< i n) (step step (+ i 1)) i)))]\n    (step step 0))\n"))]
    (do (assert (listEmpty? ds) (str "a self-passed recursive lambda's own parameter must be annotated Any to avoid an occurs-check cycle: " (diagnosticsText ds))) true))

fn ! testDiscardedResultBranchesUnify! -> Bool
  (let [(ds (checkSnippet! "discard" "(module m :x [f])\n\nfn ! f path: String text: String -> Unit\n  (do (if (fileExists? path) (fileWrite path text) (ok ())) ())\n"))]
    (do (assert (listEmpty? ds) (str "a discarded if's two Result arms must share one payload type (Unit here), not Unit vs Bool: " (diagnosticsText ds))) true))

fn ! testHeterogeneousAnyTupleViaHelper! -> Bool
  (let [(ds (checkSnippet! "anyTuple" "(module m :x [f])\n\nfn tuple3 a: Any b: Any c: Any -> (List Any)\n  (list a b c)\n\nfn f -> (List Any)\n  (tuple3 \"tag\" true 1)\n"))]
    (do (assert (listEmpty? ds) (str "an ad hoc heterogeneous tuple must be built through an Any-typed helper, not a direct bare list call: " (diagnosticsText ds))) true))

fn ! testGenericHelperNotMonomorphic! -> Bool
  (let [(ds (checkSnippet! "genericHelper" "(module m :x [f])\n\nfn appendOne xs: (List T) x: T -> (List T)\n  (listAppend xs (list x))\n\nfn f -> (List String)\n  (appendOne (list \"a\") \"b\")\n"))]
    (do (assert (listEmpty? ds) (str "a local listAppendOne-style helper must stay generic (List T) T -> (List T), not hardcode one element type: " (diagnosticsText ds))) true))

fn ! testFileLstatReturnsLinkStat! -> Bool
  (let [(ds (checkSnippet! "lstat" "(module m :x [f])\n\nfn ! f path: String -> Bool\n  (mt (fileLstat path) ((ok ls) ls.isSymlink) ((err _) false))\n"))]
    (do (assert (listEmpty? ds) (str "fileLstat is (Result LinkStat String), not (Result FileStat String); LinkStat alone carries isSymlink: " (diagnosticsText ds))) true))

fn ! testMapLiteralKeysAreKeyword! -> Bool
  (let [(ds (checkSnippet! "mapKeyword" "(module m :x [f])\n\nfn g -> (Map Keyword Any)\n  (mapSet (mapSet (mapEmpty) :a 1) :b 2)\n\nfn f -> (Option Any)\n  (mapGet (g) :a)\n"))]
    (do (assert (listEmpty? ds) (str "a mapSet-built (Map Keyword Any) accepts a Keyword key end to end, matching worklistCursorNext/worklistClaimBatch's corrected signature (not Map String Any): " (diagnosticsText ds))) true))

fn ! runTests -> Bool
  (do
    (assert (testProcAliveReturnsResult!) "procAlive? keeps its (Result Bool String) builtin signature (HL-CHECK-TYPE)")
    (assert (testSelfPassLambdaNeedsAnyAnnotation!) "self-passed recursive lambdas stay legal with an Any-annotated self parameter (HL-CHECK-TYPE)")
    (assert (testDiscardedResultBranchesUnify!) "discarded if/match Result branches must share one payload type (HL-CHECK-TYPE)")
    (assert (testHeterogeneousAnyTupleViaHelper!) "an Any-typed helper legally builds a heterogeneous ad hoc tuple (HL-CHECK-TYPE)")
    (assert (testGenericHelperNotMonomorphic!) "a generic (List T) T -> (List T) helper accepts any element type (HL-CHECK-TYPE)")
    (assert (testFileLstatReturnsLinkStat!) "fileLstat keeps its (Result LinkStat String) builtin signature, distinct from fileStat's FileStat (HL-CHECK-TYPE)")
    (assert (testMapLiteralKeysAreKeyword!) "a mapSet-built Map Keyword Any type-checks end to end (HL-CHECK-TYPE)")
    true)
