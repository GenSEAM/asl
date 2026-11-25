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

fn ! runTests -> Bool
  (let [(src (resultOr (realPath ".") "."))
        (raw (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/nativeObjectClosureMemoTest.XXXXXX" 5000) "")))
        (root (resultOr (realPath raw) raw))
        (copied (and (not (stringEmpty? raw)) (copyTree! src root)))
        (fp0 (fpOf root))
        (resolved (nt/objectClosureIn! root))
        (hit0 (memoOf root))
        (bodyWrote (ok? (fileAppend (str root "/" (lowerRel)) "\nfn objectFpProbe -> Int64\n  1\n")))
        (hitBody (memoOf root))
        (lowerSrc (resultOr (fileReadString (str root "/" (lowerRel))) ""))
        (ghostWrote (ok? (fileWrite (str root "/" (lowerRel)) (stringReplace lowerSrc (lowerAnchor) (str ":i [(asl-nowhere/ghost :a gh) " (optionOr (stringSlice (lowerAnchor) 4 (stringLength (lowerAnchor))) ""))))))
        (missHeader (memoOf root))
        (unresolved (nt/objectClosureIn! root))
        (fpG (fpOf root))
        (lintWrote (ok? (fileAppend (str root "/asl/packages/asl-checker/src/lint.asl") "\nfn objectFpProbe -> Int64\n  1\n")))
        (fpG2 (fpOf root))
        (removed (sh! (str "/bin/rm -rf " root)))]
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
      (assert removed (str "remove " root))
      true))
