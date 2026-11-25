(module asl-tools/tests/nativeObjectFpTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a fr) (asl-ir/link :a lk)])

; (:m :ref NT-FP-NARROW :do "a module object is keyed by what can shape its bytes: on a copy of the toolchain tree, a checker-only, check-cache or asl1 edit keeps every module key (0 recompiles) while the whole fingerprint still moves (slots relink, verdicts recheck); a target-llvm, runtime archive, prelude or linked-checker edit moves the key")

fn packages -> (List String)
  (list "asl-compiler" "asl-checker" "asl-codegen" "asl-ir" "asl-parser" "asl-syntax" "asl-target-llvm")

fn ! sh! cmd: String -> Bool
  (ok? (fr/shellOut cmd 60000))

; (:m :ref NT-FP-NARROW :do "the copy holds every toolchain root plus the package manifests and workspace configs the resolver reads, so the object closure resolves inside it exactly as in the source tree")
fn ! copyTree! src: String dst: String -> Bool
  (and (sh! (str "/bin/mkdir -p " dst "/asl/packages " dst "/asl/tools " dst "/asl/host/out " dst "/m"))
       (and (sh! (str "/bin/cp " src "/.asl.config.asn " dst "/ && /bin/cp " src "/asl/.asl.config.asn " dst "/asl/"))
            (and (listAll? (fn [(p String)] -> Bool (sh! (str "/bin/mkdir -p " dst "/asl/packages/" p " && /bin/cp -R " src "/asl/packages/" p "/src " src "/asl/packages/" p "/manifest.asn " dst "/asl/packages/" p "/"))) (packages))
                 (sh! (str "/bin/cp -R " src "/asl/prelude " dst "/asl/ && /bin/cp " src "/asl/tools/nativeTest.asl " dst "/asl/tools/ && /bin/cp " src "/asl/host/out/libaslrt.a " src "/asl/host/out/prelude.asl " dst "/asl/host/out/")))))

fn ! fpOf root: String -> String
  (nt/fingerprintIn root "clang test" "test-triple")

fn ! keyOf root: String fp: String -> String
  (nt/unitKeyIn root fp "-O1" (lk/LinkUnit :path (str root "/m/x.asl") :name "m/x" :forms (list) :positions (mapEmpty) :imports (list)) (mapEmpty) false (list))

fn ! touch! root: String rel: String -> Bool
  (and (fileExists? (str root "/" rel)) (ok? (fileAppend (str root "/" rel) "\nfn objectFpProbe -> Int64\n  1\n")))

(schema Step
  (:f rel String)
  (:f fp String)
  (:f key String)
  (:f wrote Bool))

fn ! edit! root: String rel: String -> Step
  (let [(wrote (touch! root rel))
        (fp (fpOf root))]
    (Step :rel rel :fp fp :key (keyOf root fp) :wrote wrote))

fn ! runTests -> Bool
  (let [(src (resultOr (realPath ".") "."))
        (raw (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/nativeObjectFpTest.XXXXXX" 5000) "")))
        (root (resultOr (realPath raw) raw))
        (copied (and (not (stringEmpty? raw)) (copyTree! src root)))
        (_ (fileWrite (str root "/m/x.asl") "(module m/x :x [f] :i [])\n\nfn f -> Int64\n  1\n"))
        (fp0 (fpOf root))
        (k0 (keyOf root fp0))
        (lint (edit! root "asl/packages/asl-checker/src/lint.asl"))
        (cached (edit! root "asl/packages/asl-checker/src/checkCached.asl"))
        (asl1 (edit! root "asl/packages/asl-compiler/src/asl1.asl"))
        (c99 (edit! root "asl/packages/asl-codegen/src/emit.asl"))
        (emit (edit! root "asl/packages/asl-target-llvm/src/emit.asl"))
        (lower (edit! root "asl/packages/asl-ir/src/lower.asl"))
        (check (edit! root "asl/packages/asl-checker/src/check.asl"))
        (rtWrote (ok? (fileAppend (str root "/asl/host/out/libaslrt.a") "x")))
        (rtFp (fpOf root))
        (rtKey (keyOf root rtFp))
        (prelude (edit! root "asl/prelude/prelude.asl"))
        (removed (sh! (str "/bin/rm -rf " root)))]
    (do
      (assert copied (str "a copy of the toolchain tree at " root))
      (assert (= (stringLength fp0) 64) (str "the fingerprint is 64 hex: " fp0))
      (assert (and lint.wrote (and cached.wrote (and asl1.wrote (and c99.wrote (and emit.wrote (and lower.wrote (and check.wrote (and rtWrote prelude.wrote)))))))) "every probed file exists in the copy")
      (refute (= lint.fp fp0) "a lint.asl edit moves the whole fingerprint, so suite slots relink and checker verdicts recheck")
      (assert (= lint.key k0) "a lint.asl edit (checker diagnostics only) keeps the module key: 0 recompiles")
      (refute (= cached.fp lint.fp) "a checkCached.asl edit moves the whole fingerprint")
      (assert (= cached.key k0) "a checkCached.asl edit (verdict cache) keeps the module key")
      (assert (= asl1.key k0) "an asl1.asl edit (front-end driver) keeps the module key")
      (assert (= c99.key k0) "an asl-codegen edit (C99 backend, not on the LLVM path) keeps the module key")
      (refute (= emit.key k0) "an asl-target-llvm/emit.asl edit moves the module key")
      (refute (= lower.key emit.key) "an asl-ir/lower.asl edit moves the module key")
      (refute (= check.key lower.key) "an asl-checker/check.asl edit moves the module key (link elaborates matches and scripts through it)")
      (refute (= rtKey check.key) "a runtime archive edit moves the module key")
      (refute (= prelude.key rtKey) "a prelude edit moves the module key")
      (assert removed (str "remove " root))
      true))
