(module asl/host/tests/buildClangTest :x [runTests] :i [(asl-tools/fleet/run :a run)])

fn toolNames -> String
  "mkdir cp rm ls head tail cat sed grep awk uname tr cut ar gzip chmod mv basename dirname env perl sh tee wc sort printf sha256sum shasum openssl nice"

fn setupScript -> String
  "set -e; w=$1; rm -rf \"$w\"; mkdir -p \"$w/tools\" \"$w/out\"; for t in $2; do p=$(command -v $t 2>/dev/null || true); [ -n \"$p\" ] && ln -s \"$p\" \"$w/tools/$t\" || true; done; printf '#!/bin/sh\\necho \"$0 $*\" >> \"%s/clangCalls\"\\nexit 1\\n' \"$w\" > \"$w/tools/clang-18\"; chmod +x \"$w/tools/clang-18\"; printf 'KEEP' > \"$w/out/libaslrt.a\""

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 60 8))

fn ! build! root: String w: String path: String clang: (Option String) -> run/Done
  (let [(base (list (str "ASL_HOST_OUT=" w "/out") (str "ASL_HOST_CACHE_DIR=" w "/hosts") (str "PATH=" path) (str "HOME=" w)))
        (env (match clang ((some c) (cons (str "CLANG=" c) base)) ((none) base)))]
    (run/runOneLimited (run/job (list "/bin/sh" (str root "/asl/host/build.sh")) root env) (run/limits 300 32)))

; (:m :ref VPSLIN-2 :do "with CLANG unset and only clang-18 on PATH build.sh calls clang-18; with no clang at all it exits 1 and an installed libaslrt.a stays")
fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (w (str root "/.asl/cache/buildClang/" (stringFromInt64 (procSelf))))
        (made (sh! root (list "/bin/sh" "-c" (setupScript) "sh" w (toolNames))))
        (probed (build! root w (str w "/tools") (none)))
        (calls (resultOr (fileReadString (str w "/clangCalls")) ""))
        (absent (build! root w (str w "/tools") (some "clang-none")))
        (kept (resultOr (fileReadString (str w "/out/libaslrt.a")) ""))
        (cleaned (sh! root (list "/bin/rm" "-rf" w)))]
    (do (assert (= made.exit 0) (str "fixture built: " made.out))
        (refute (stringContains? probed.out "not found") (str "clang-18 was found with CLANG unset: " probed.out))
        (assert (stringContains? calls "clang-18") (str "the probe called clang-18: [" calls "] " probed.out))
        (refute (= absent.exit 0) "no clang at all exits non-zero")
        (assert (stringContains? absent.out "not found") (str "the log says clang is not found: " absent.out))
        (assert (= kept "KEEP") "an installed libaslrt.a is left intact")
        (assert (= cleaned.exit 0) "fixture removed")
        true))
