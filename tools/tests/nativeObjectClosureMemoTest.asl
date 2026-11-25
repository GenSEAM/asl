(module asl-tools/tests/nativeObjectClosureMemoTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a fr)])

; (:m :ref NT-FP-NARROW :do "the object closure is remembered by headers: a body edit in a closure file reuses it, a header edit re-resolves; a closure that cannot resolve falls back to every root, so a checker-only edit then moves the object half")

fn packages -> (List String)
  (list "asl-compiler" "asl-checker" "asl-codegen" "asl-ir" "asl-parser" "asl-syntax" "asl-target-llvm")

fn ! sh! cmd: String -> Bool
  (ok? (fr/shellOut cmd 60000))

fn ! copyTree! src: String dst: String -> Bool
  (and (sh! (str "/bin/mkdir -p " dst "/asl/packages " dst "/asl/tools " dst "/asl/host/out"))
       (and (sh! (str "/bin/cp " src "/.asl.config.asn " dst "/ && /bin/cp " src "/asl/.asl.config.asn " dst "/asl/"))
            (and (listAll? (fn [(p String)] -> Bool (sh! (str "/bin/mkdir -p " dst "/asl/packages/" p " && /bin/cp -R " src "/asl/packages/" p "/src " src "/asl/packages/" p "/manifest.asn " dst "/asl/packages/" p "/"))) (packages))
                 (sh! (str "/bin/cp -R " src "/asl/prelude " dst "/asl/ && /bin/cp " src "/asl/tools/nativeTest.asl " dst "/asl/tools/ && /bin/cp " src "/asl/host/out/libaslrt.a " src "/asl/host/out/prelude.asl " dst "/asl/host/out/")))))

fn ! fpOf root: String -> String
  (nt/fingerprintIn root "clang test" "test-triple")

fn half fp: String -> String
  (optionOr (stringSlice fp 0 32) fp)

fn ! memoOf root: String -> (Option (List String))
  (nt/objectClosureMemo! root (nt/fpLinesIn root))

fn lowerRel -> String
  "asl/packages/asl-ir/src/lower.asl"

fn lowerAnchor -> String
  ":i [(asl-ir/types :a ty)"

fn ! contextOf root: String -> String
  (nt/closureContext root (nt/fpLinesIn root))

; (:m :ref NT-FP-MEMO-LOWS :do "each input of the closure memo context is changed on its own and must move the context and miss the memo: a new module path under a root, a .asl.config.asn nested in a toolchain directory, a config above the root, and the manifest of a package outside the root packages; the unchanged tree keeps it")
fn ! probeInputs root: String ctx0: String -> (List (Pair String Bool))
  (let [(newModule (str root "/asl/packages/asl-ir/src/zzProbeNew.asl"))
        (nestDir (str root "/asl/packages/asl-ir/src/zzNest"))
        (above (str (optionOr (stringSlice root 0 (- (stringLength root) 6)) "") "/.asl.config.asn"))
        (strange (str root "/asl/packages/asl-zzProbe"))
        (w1 (ok? (fileWrite newModule "(module asl-ir/zzProbeNew :x [] :i [])\n")))
        (c1 (contextOf root))
        (m1 (memoOf root))
        (_u1 (pathRemove newModule))
        (w2 (and (ok? (dirCreate nestDir)) (ok? (fileWrite (str nestDir "/.asl.config.asn") "()\n"))))
        (c2 (contextOf root))
        (m2 (memoOf root))
        (w2b (ok? (fileWrite (str nestDir "/.asl.config.asn") "(changed)\n")))
        (c2b (contextOf root))
        (_u2 (pathRemove nestDir))
        (w3 (ok? (fileWrite above "()\n")))
        (c3 (contextOf root))
        (m3 (memoOf root))
        (_u3 (pathRemove above))
        (w4 (and (ok? (dirCreate strange)) (ok? (fileWrite (str strange "/manifest.asn") "(package zzProbe)\n"))))
        (c4 (contextOf root))
        (m4 (memoOf root))
        (_u4 (pathRemove strange))]
    (list (pair "pathList" (and w1 (and (!= c1 ctx0) (none? m1))))
          (pair "nestedConfig" (and w2 (and (!= c2 ctx0) (and (none? m2) (and w2b (!= c2b c2))))))
          (pair "configAbove" (and w3 (and (!= c3 ctx0) (none? m3))))
          (pair "otherManifest" (and w4 (and (!= c4 ctx0) (none? m4))))
          (pair "restored" (and (= (contextOf root) ctx0) (some? (memoOf root))))))

; (:m :ref NT-FP-MEMO-LOWS :do "prune sweeps closure-* memos too: ten memos with distinct mtimes leave the eight newest, and a fingerprint memo name is left to the existing rule")
fn ! probePrune rawReal: String -> Bool
  (let [(dir (str rawReal "/memos"))
        (_ (dirCreate dir))
        (names (map (fn [(i Int64)] -> String (str "closure-" (stringFromInt64 i))) (range 0 10)))
        (_w (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (fileWrite (str dir "/" n) "x")) acc)) true names))
        (_t (fold (fn [(acc Bool) (i Int64)] -> Bool (and (ok? (fileUtime (str dir "/closure-" (stringFromInt64 i)) (+ 1000000000000 (* i 1000000000)))) acc)) true (range 0 10)))
        (_p (nt/prune dir "none"))
        (left (filter (fn [(n String)] -> Bool (fileExists? (str dir "/" n))) names))]
    (and (= (listLength left) 8) (and (not (fileExists? (str dir "/closure-0"))) (and (not (fileExists? (str dir "/closure-1"))) (fileExists? (str dir "/closure-9"))))))

fn ! runTests -> Bool
  (let [(src (resultOr (realPath ".") "."))
        (raw (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/nativeObjectClosureMemoTest.XXXXXX" 5000) "")))
        (rawReal (resultOr (realPath raw) raw))
        (root (str rawReal "/inner"))
        (copied (and (not (stringEmpty? raw)) (copyTree! src root)))
        (fp0 (fpOf root))
        (resolved (nt/objectClosureIn! root))
        (hit0 (memoOf root))
        (bodyWrote (ok? (fileAppend (str root "/" (lowerRel)) "\nfn objectFpProbe -> Int64\n  1\n")))
        (hitBody (memoOf root))
        (ctx0 (contextOf root))
        (inputs (probeInputs root ctx0))
        (lowerSrc (resultOr (fileReadString (str root "/" (lowerRel))) ""))
        (ghostWrote (ok? (fileWrite (str root "/" (lowerRel)) (stringReplace lowerSrc (lowerAnchor) (str ":i [(asl-nowhere/ghost :a gh) " (optionOr (stringSlice (lowerAnchor) 4 (stringLength (lowerAnchor))) ""))))))
        (missHeader (memoOf root))
        (unresolved (nt/objectClosureIn! root))
        (fpG (fpOf root))
        (lintWrote (ok? (fileAppend (str root "/asl/packages/asl-checker/src/lint.asl") "\nfn objectFpProbe -> Int64\n  1\n")))
        (fpG2 (fpOf root))
        (pruned (probePrune rawReal))
        (removed (sh! (str "/bin/rm -rf " rawReal)))]
    (do
      (assert copied (str "a copy of the toolchain tree at " root))
      (assert (some? resolved) "the copy resolves its object closure")
      (assert (= hit0 resolved) "after a fingerprint the memo holds the resolved closure")
      (assert (and bodyWrote (stringContains? lowerSrc (lowerAnchor))) "lower.asl took a body edit and still has its header anchor")
      (assert (= hitBody resolved) "a body edit in a closure file keeps the memo: no re-resolution")
      (assert ghostWrote "lower.asl took a header edit")
      (assert (none? missHeader) "a header edit in a closure file misses the memo")
      (assert (none? unresolved) "a closure with an unresolved import is refused, not taken partial")
      (assert lintWrote "lint.asl took an edit")
      (refute (= (half fpG) (half fpG2)) "with no closure the object half covers every root, so a lint.asl edit moves it")
      (refute (= fpG fpG2) "and the whole fingerprint moves")
      (assert (listAll? (fn [(r (Pair String Bool))] -> Bool (pairSecond r)) inputs) (str "every input the closure memo context reads moves it: " (stringJoin (map (fn [(r (Pair String Bool))] -> String (if (pairSecond r) "" (pairFirst r))) inputs) " ")))
      (assert pruned "prune keeps the newest closure memos and removes the rest")
      (assert removed (str "remove " rawReal))
      true))
