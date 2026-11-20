(module asl-cli/variantKeyTest :x [runTests] :i [(asl/packages/asl-cli/src/nativeBuild :a nb) (asl-tools/fleet/run :a run)])

; (:m :ref VARIANTKEY-CLOSURE-20261025 :do "variantKey! keys the runtime variant cache on the import closure of gcRoute/rtAbi/rtFloor: an edit to gcAsl.asl (imported by gcRoute.asl, not a root) must change the key, an edit to an unrelated package must not; checked on a scratch copy of the tree, never the live one")
fn ! sh! cmd: String -> Bool
  (= (run/runOneLimited (run/job (list "/bin/sh" "-c" cmd) "/" (run/childEnv (list))) (run/limits 120 8)).exit 0)

fn ! keyOf! root: String -> String
  (let [(b (nb/Build :root root :cache (str root "/cache") :tmp (str root "/tmp") :lib "" :base "" :clangVersion "clang-test" :owner "" :deadlineNs 0 :maxDesc 8))]
    (resultOr (nb/variantKey! b (str root "/asl/packages") "notrace") ""))

fn ! runTests -> Bool
  (let [(real (resultOr (realPath ".") "."))
        (t (str "/tmp/variantKeyTest." (stringFromInt64 (procSelf))))
        (copied (sh! (str "set -e; mkdir -p " t "/asl && cp -R " real "/asl/packages " t "/asl/packages && cp -R " real "/asl/prelude " t "/asl/prelude && cp " real "/.asl.config.asn " t "/.asl.config.asn")))
        (k0 (keyOf! t))
        (k0b (keyOf! t))
        (gc (str t "/asl/packages/asl-target-llvm/src/gcAsl.asl"))
        (edited (sh! (str "printf '\\n; edit\\n' >> " gc)))
        (k1 (keyOf! t))
        (reverted (sh! (str "cd " real " && cp asl/packages/asl-target-llvm/src/gcAsl.asl " gc)))
        (k2 (keyOf! t))
        (other (sh! (str "printf '\\n; edit\\n' >> " t "/asl/packages/asl-cli/src/command.asl")))
        (k3 (keyOf! t))
        (cleaned (sh! (str "rm -rf " t)))]
    (do (assert copied "the scratch tree was copied")
        (assert (= (stringLength k0) 64) "the key is a sha256")
        (assert (= k0 k0b) "the key is stable when nothing changed")
        (assert edited "gcAsl.asl was edited in the scratch copy")
        (assert (!= k0 k1) "editing gcAsl.asl, imported by gcRoute.asl, changes the key")
        (assert reverted "gcAsl.asl was restored")
        (assert (= k0 k2) "restoring the file restores the key")
        (assert other "an unrelated file was edited")
        (assert (= k0 k3) "editing an unrelated file leaves the key unchanged")
        (assert cleaned "the scratch tree was removed")
        true))
