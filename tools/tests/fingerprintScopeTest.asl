(module asl/tools/tests/fingerprintScopeTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt)])

; (:m :ref FPNARROW :do "the native cache fingerprint follows only what can shape a cached artifact: a driver-only body or a top-level comment in nativeTest.asl keeps it, a compile-path body, a new fn, a target-llvm or checker source changes it")

fn selfRel -> String
  "asl/tools/nativeTest.asl"

fn llvmRel -> String
  "asl/packages/asl-target-llvm/src/fpScopeProbe.asl"

fn checkerRel -> String
  "asl/packages/asl-checker/src/fpScopeProbe.asl"

fn ! put! root: String rel: String text: String -> Bool
  (let [(path (str root "/" rel))
        (dir (optionOr (stringSlice path 0 (- (stringLength path) (+ (stringLength (optionOr (listLast (stringSplit rel "/")) "")) 1))) root))]
    (and (ok? (dirCreate dir)) (ok? (fileWrite path text))))

; (:m :ref NT-FP-NARROW :do "the imports a module header names: the head word of every (name :a alias) item between :i [ and the first ]")
fn importsOf src: String -> (List String)
  (let [(afterI (optionOr (listGet (stringSplit src ":i [") 1) ""))
        (items (optionOr (listHead (stringSplit afterI "]")) ""))]
    (filter (fn [(w String)] -> Bool (not (stringEmpty? w)))
            (map (fn [(it String)] -> String (optionOr (listHead (stringSplit (stringTrim it) " ")) "")) (optionOr (listTail (stringSplit items "(")) (list)))))

fn ! fpOf root: String -> String
  (nt/fingerprintIn root "clang test" "test-triple")

; (:m :ref FPNARROW :do "a mutation whose anchor is gone would compare a file with itself, so each anchor is asserted before its fingerprint counts")
fn ! withSelf! root: String text: String -> String
  (if (put! root (selfRel) text) (fpOf root) "write failed")

fn ! runTests -> Bool
  (let [(rootRaw (str (optionOr (envGet "TMPDIR") "/tmp") "/fingerprintScopeTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (dirCreate rootRaw))
        (root (resultOr (realPath rootRaw) rootRaw))
        (src (resultOr (fileReadString (selfRel)) ""))
        (wroteLlvm (put! root (llvmRel) "fn probe -> Int64\n  1\n"))
        (wroteChecker (put! root (checkerRel) "fn probe -> Int64\n  1\n"))
        (base (withSelf! root src))
        (driverAnchor "(suiteWorkersFor k (resultOr (cpuCount) 1))")
        (driverBody (withSelf! root (stringReplace src driverAnchor "(suiteWorkersFor k (resultOr (cpuCount) 2))")))
        (strideAnchor "fn strideOrder n: Int64 w: Int64 -> (List Int64)\n")
        (driverComment (withSelf! root (stringReplace src strideAnchor (str "; (:m :ref FPSCOPE :do \"a new note\")\n" strideAnchor))))
        (codeAnchor "(str \"mod/1\\n\" compVer")
        (codeBody (withSelf! root (stringReplace src codeAnchor "(str \"mod/9\\n\" compVer")))
        (newFn (withSelf! root (str src "\nfn fpScopeFresh -> Int64\n  7\n")))
        (restored (withSelf! root src))
        (llvmEdit (if (put! root (llvmRel) "fn probe -> Int64\n  2\n") (fpOf root) "write failed"))
        (_ (put! root (llvmRel) "fn probe -> Int64\n  1\n"))
        (checkerEdit (if (put! root (checkerRel) "fn probe -> Int64\n  2\n") (fpOf root) "write failed"))
        (slice (nt/artifactSlice src))
        (mainAnchor "((= head \"--compile-units\") (compileUnitsWorker! (listDrop args 1)))")
        (mainEdit (nt/artifactSlice (stringReplace src mainAnchor "((= head \"--compile-units\") (compileUnitsWorker! (listDrop args 2)))")))
        (hdr "(module t/x :x [f] :i [])\n\n")
        (semiA (nt/artifactSlice (str hdr "fn f -> String\n  \"a;b\" ; note one\n")))
        (semiB (nt/artifactSlice (str hdr "fn f -> String\n  \"a;c\" ; note one\n")))
        (semiC (nt/artifactSlice (str hdr "fn f -> String\n  \"a;b\" ; note two\n")))
        (namedA (nt/artifactSlice (str hdr "fn f -> Int64\n  (strideOrder 1)\n\nfn strideOrder n: Int64 -> Int64\n  1\n")))
        (namedB (nt/artifactSlice (str hdr "fn f -> Int64\n  (strideOrder 1)\n\nfn strideOrder n: Int64 -> Int64\n  2\n")))
        (loneA (nt/artifactSlice (str hdr "fn f -> Int64\n  1\n\nfn strideOrder n: Int64 -> Int64\n  1\n")))
        (loneB (nt/artifactSlice (str hdr "fn f -> Int64\n  1\n\nfn strideOrder n: Int64 -> Int64\n  2\n")))
        (imports (importsOf src))
        (unclassified (filter (fn [(i String)] -> Bool (not (or (listContains? (nt/objectSeeds) i) (listContains? (nt/nonObjectImports) i)))) imports))
        (closure (nt/objectClosureIn! "."))
        (rels (optionOr closure (list)))
        (removed (pathRemove root))]
    (do
      (assert (and (ok? made) wroteLlvm wroteChecker) (str "a temp toolchain tree at " rootRaw))
      (assert (= (stringLength base) 64) (str "the fingerprint is a sha256 hex: " base))
      (assert (stringContains? src driverAnchor) "the prepareAllIn anchor is in nativeTest.asl")
      (assert (stringContains? src strideAnchor) "the strideOrder anchor is in nativeTest.asl")
      (assert (stringContains? src codeAnchor) "the moduleCacheKey anchor is in nativeTest.asl")
      (assert (= driverBody base) "editing the body of prepareAllIn (suite sweep pool, driver-only) keeps the fingerprint")
      (assert (= driverComment base) "adding a top-level comment keeps the fingerprint")
      (assert (= restored base) "the restored tree gives the base fingerprint again")
      (refute (= codeBody base) "editing moduleCacheKey (a compile-path body) changes the fingerprint")
      (refute (= newFn base) "a new fn no compile path names still changes the fingerprint (kept unless listed driver-only)")
      (refute (= llvmEdit base) "editing an asl-target-llvm source changes the fingerprint")
      (refute (= checkerEdit base) "editing an asl-checker source changes the fingerprint (lowering imports asl-checker/check, resolve, types, numKinds, foreign)")
      (assert (stringContains? slice "fn ! compileIn cDir:") "the slice keeps compileIn")
      (assert (stringContains? slice "fn ! compileUnitsWorker! args:") "the slice keeps the worker compile entry")
      (assert (stringContains? slice "(schema Built") "the slice keeps schemas")
      (refute (stringContains? slice "fn ! prepareAllIn cDir:") "the slice drops prepareAllIn")
      (refute (stringContains? slice "fn strideOrder n:") "the slice drops strideOrder")
      (refute (stringContains? slice "(:m :ref FPNARROW") "the slice drops comments")
      (assert (stringContains? src mainAnchor) "the main --compile-units route anchor is in nativeTest.asl")
      (refute (= mainEdit slice) "an edit only inside main's compileUnitsWorker! route changes the slice (workers run main)")
      (assert (stringContains? slice "fn ! keptRun root:") "the slice keeps keptRun, which computes its own slot lookup key")
      (refute (= semiA semiB) "an edit after a ';' inside a string changes the slice (the ';' is not a comment)")
      (assert (= semiA semiC) "an edit inside a trailing comment keeps the slice")
      (refute (= namedA namedB) "a driver-only fn named by a kept fn enters the slice")
      (assert (= loneA loneB) "a driver-only fn no kept fn names stays out of the slice")
      (assert (> (listLength imports) 10) (str "nativeTest.asl names its imports: " (stringJoin imports " ")))
      (assert (listEmpty? unclassified) (str "every nativeTest import is an object seed or a non-object import: " (stringJoin unclassified " ")))
      (assert (some? closure) "the object closure resolves in the source tree")
      (assert (listAll? (fn [(p String)] -> Bool (nt/rootCovered? p)) rels) (str "every object source lies under a toolchain root, so the stamp memo sees its edits: " (stringJoin (filter (fn [(p String)] -> Bool (not (nt/rootCovered? p))) rels) " ")))
      (assert (listContains? rels "asl/packages/asl-target-llvm/src/emit.asl") "the object closure holds asl-target-llvm/emit")
      (assert (listContains? rels "asl/packages/asl-checker/src/check.asl") "the object closure holds asl-checker/check (link elaborates through it)")
      (refute (listContains? rels "asl/packages/asl-checker/src/lint.asl") "the object closure leaves out asl-checker/lint")
      (refute (listContains? rels "asl/packages/asl-checker/src/checkCached.asl") "the object closure leaves out asl-checker/checkCached")
      (refute (listAny? (fn [(p String)] -> Bool (stringStartsWith? p "asl/packages/asl-compiler/")) rels) "the object closure leaves out asl-compiler")
      (assert (ok? removed) (str "remove " root))
      true))
