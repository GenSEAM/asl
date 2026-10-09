(module asl-ir/tests/patchTest
  :x [testSpliceRoundTrips testSpliceStandaloneInverse testSpliceDeletedMismatch runTests]
  :i [(asl-ir/patch :a patch)])

fn treeF -> Str
  "(defun f [(x Int64)] -> Int64 (println \"a\") (+ x 1) (* x 2))"

fn treeFg -> Str
  (str "(defun f [(x Int64)] -> Int64 (println \"a\") (+ x 1) (* x 2))" "\n\n" "(defun g [(y Int64)] -> Int64 (let [(z (+ y 1))] z) (if (> y 0) y (- 0 y)))")

fn splicePatch id: Str ops: Str -> patch/AstPatch
  (mt (patch/parsePatch (str "(:astPatch :id \"" id "\" :targetModule \"m\" :ops [" ops "])"))
    ((ok p) p)
    ((err d) (do (assert false (str "patch text parses: " d.message)) (patch/makeAstPatch id "m" (none) (none) (list)))))

fn roundTrip label: Str src: Str p: patch/AstPatch expected: Str -> Bool
  (let [(fwd (patch/applyPatch p src))]
    (do
      (assert fwd.success (str label ": forward splice applies"))
      (assert (= fwd.patchedSource expected) (str label ": forward splice yields the expected tree"))
      (mt fwd.inversePatch
        ((none) (do (assert false (str label ": forward result carries an inverse")) false))
        ((some inv)
          (let [(back (patch/applyPatch inv fwd.patchedSource))]
            (do
              (assert back.success (str label ": inverse applies to the patched tree"))
              (assert (= back.patchedSource src) (str label ": apply then invert is the identity"))
              true))))))

fn testSpliceRoundTrips -> Bool
  (do
    (assert (roundTrip "replaceMiddle" (treeF) (splicePatch "p1" "(:splice :target \"f\" :anchor \"body\" :index 1 :deletedNodes [\"(+ x 1)\"] :insertNodes [\"(- x 3)\"])") "(defun f [(x Int64)] -> Int64 (println \"a\") (- x 3) (* x 2))") "replaceMiddle")
    (assert (roundTrip "deleteTwo" (treeF) (splicePatch "p2" "(:splice :target \"f\" :anchor \"body\" :index 0 :deletedNodes [\"(println \\\"a\\\")\" \"(+ x 1)\"] :insertNodes [])") "(defun f [(x Int64)] -> Int64 (* x 2))") "deleteTwo")
    (assert (roundTrip "insertEnd" (treeF) (splicePatch "p3" "(:splice :target \"f\" :anchor \"body\" :index 3 :deletedNodes [] :insertNodes [\"(+ x 9)\" \"(* x x)\"])") "(defun f [(x Int64)] -> Int64 (println \"a\") (+ x 1) (* x 2) (+ x 9) (* x x))") "insertEnd")
    (assert (roundTrip "twoForms" (treeFg) (splicePatch "p4" "(:splice :target \"g\" :anchor \"body\" :index 1 :deletedNodes [\"(if (> y 0) y (- 0 y))\"] :insertNodes [\"y\"]) (:splice :target \"f\" :anchor \"body\" :index 2 :deletedNodes [\"(* x 2)\"] :insertNodes [])") (str "(defun f [(x Int64)] -> Int64 (println \"a\") (+ x 1))" "\n\n" "(defun g [(y Int64)] -> Int64 (let [(z (+ y 1))] z) y)")) "twoForms")
    true)

fn testSpliceStandaloneInverse -> Bool
  (let [(p (splicePatch "p5" "(:splice :target \"f\" :anchor \"body\" :index 0 :deletedNodes [\"(println \\\"a\\\")\" \"(+ x 1)\" \"(* x 2)\"] :insertNodes [\"(- x 3)\"])"))
        (fwd (patch/applyPatch p (treeF)))
        (inv (patch/invertPatch p))
        (reparsed (patch/parsePatch (patch/renderPatch inv)))]
    (do
      (assert (= fwd.patchedSource "(defun f [(x Int64)] -> Int64 (- x 3))") "forward splice replaces three nodes by one")
      (assert (= (patch/applyPatch inv fwd.patchedSource).patchedSource (treeF)) "invertPatch alone restores the deleted nodes")
      (mt reparsed
        ((err d) (do (assert false (str "rendered inverse parses: " d.message)) false))
        ((ok inv2)
          (do
            (assert (= (patch/applyPatch inv2 fwd.patchedSource).patchedSource (treeF)) "rendered and reparsed inverse restores the deleted nodes")
            true)))))

fn testSpliceDeletedMismatch -> Bool
  (let [(res (patch/applyPatch (splicePatch "p6" "(:splice :target \"f\" :anchor \"body\" :index 1 :deletedNodes [\"(+ x 7)\"] :insertNodes [])") (treeF)))]
    (do
      (refute res.success "a splice naming nodes absent at its index is refused")
      (assert (= res.patchedSource (treeF)) "a refused splice leaves the source unchanged")
      (assert (listAny? (fn [(d patch/PatchDiag)] -> Bool (= d.code "ERR_PATCH_OLD_NODE_MISMATCH")) res.diagnostics) "the refusal names the mismatch")
      true))

fn runTests -> Bool
  (do
    (assert (testSpliceRoundTrips) "testSpliceRoundTrips")
    (assert (testSpliceStandaloneInverse) "testSpliceStandaloneInverse")
    (assert (testSpliceDeletedMismatch) "testSpliceDeletedMismatch")
    true)
