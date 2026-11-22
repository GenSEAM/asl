(module asl-cli/tests/sandboxNiceTest :x [runTests] :i [(asl-tools/fleet/run :a run)])

; (:m :ref SANDBOX-NICE-FALLBACK :do "bin/asl check, asl test FILE and a (:read) form exit 0 under a macOS sandbox-exec profile that writes only inside the tree and a scratch dir, denies network and makes nice fail as a sandbox that denies setpriority does (a PATH shim, since sandbox-exec cannot deny setpriority alone); the control case shows the shim really breaks a bare nice, so the green cases prove the fallback; no sandbox-exec or a nested sandbox prints (:skip) and runs no case")
fn ! sh! cwd: String script: String args: (List String) -> run/Done
  (run/runOneLimited (run/job (listAppend (list "/bin/sh" "-c" script "sh") args) cwd (run/childEnv (list "ASL_ROOT=" "ASL_PRELUDE=" "ASL_CLI_USER_PRELUDE=" ))) (run/limits 900 16))

fn profile root: String scratch: String -> String
  (str "(version 1)\n(allow default)\n(deny network*)\n(deny file-write* (require-not (require-any (subpath \"" root "\") (subpath \"" scratch "\") (subpath \"/dev\") (subpath \"/private/var/folders\") (subpath \"/private/tmp\"))))\n")

fn countOf text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

; (:m :do "the second suite starts a nested bin/asl check as a child: its environment carries ASL_NICE_STATE from the parent, so the nested CLI prints no (:nice :denied) line of its own")
fn nestedSuite root: String file: String -> String
  (str "(module sandboxNested :x [runTests] :i [(asl-tools/fleet/run :a run)])\n\nfn ! runTests -> Bool\n  (let [(r (run/runOneLimited (run/job (list \"" root "/bin/asl\" \"check\" \"" file "\") \"" root "\" (run/childEnv (list \"ASL_ROOT=\" \"ASL_PRELUDE=\" \"ASL_CLI_USER_PRELUDE=\"))) (run/limits 600 16)))]\n    (do (assert (= r.exit 0) (str \"nested check exits 0: \" r.out))\n        (assert (not (stringContains? r.out \"(:nice :denied\")) (str \"the nested CLI inherits the state and prints no nice line: \" r.out))\n        true))\n")

fn tinySuite -> String
  "(module sandboxTiny :x [runTests] :i [])\n\nfn ! runTests -> Bool\n  (do (assert (> (procSelf) 0) \"a live process\")\n      true)\n"

; (:m :do "args: root scratch then the asl argv; the profile and the denied nice live in scratch, the real HOME stays readable and unwritable")
fn ! sandboxed! root: String scratch: String argv: (List String) -> run/Done
  (sh! root "r=$1 s=$2; shift 2; rm -f \"$s/probes\"; exec sandbox-exec -f \"$s/p.sb\" env -u ASL_NICE_STATE -u ASL_NATIVE_TEST_CACHE \"PATH=$s/deny:$PATH\" \"ASL_PROBE_LOG=$s/probes\" \"$r/bin/asl\" \"$@\"" (cons root (cons scratch argv)))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (scratch (str root "/.asl/cache/sandboxNiceTest/" (stringFromInt64 (procSelf))))
        (made (sh! root "rm -rf \"$1\" && mkdir -p \"$1/deny\" && printf '#!/bin/sh\\necho \"$*\" >> \"${ASL_PROBE_LOG:-/dev/null}\"\\necho \"nice: setpriority: Operation not permitted\" >&2\\nexit 1\\n' > \"$1/deny/nice\" && chmod +x \"$1/deny/nice\"" (list scratch)))
        (_p (fileWrite (str scratch "/p.sb") (profile root scratch)))
        (_t (fileWrite (str scratch "/tinyTest.asl") (tinySuite)))
        (_t2 (fileWrite (str scratch "/tinyTwoTest.asl") (nestedSuite root (str scratch "/tinyTest.asl"))))
        (probe (sh! root "sandbox-exec -f \"$1/p.sb\" /bin/sh -c ':'" (list scratch)))]
    (if (or (not (fileExists? "/usr/bin/sandbox-exec")) (!= probe.exit 0))
      (do (println "(:skip :test sandboxNice :reason \"no usable sandbox-exec\")") (sh! root "rm -rf \"$1\"" (list scratch)) true)
      (let [(control (sh! root "exec sandbox-exec -f \"$1/p.sb\" env \"PATH=$1/deny:$PATH\" nice -n 15 /usr/bin/true" (list scratch)))
            (net (sh! root "exec sandbox-exec -f \"$1/p.sb\" /usr/bin/nc -z -w 2 127.0.0.1 22" (list scratch)))
            (chk (sandboxed! root scratch (list "check" (str scratch "/tinyTest.asl"))))
            (tst (sandboxed! root scratch (list "test" (str scratch "/tinyTest.asl") (str scratch "/tinyTwoTest.asl"))))
            (probes (sh! root "cat \"$1/probes\" 2>/dev/null | wc -l" (list scratch)))
            (rd (sandboxed! root scratch (list "(:read :file \"asl/packages/asl-cli/tests/sandboxNiceTest.asl\" :symbol \"tinySuite\")")))
            (_c (sh! root "rm -rf \"$1\"" (list scratch)))]
        (do (assert (!= control.exit 0) (str "control: a bare nice fails under the denied-setpriority shim: " control.out))
            (assert (!= net.exit 0) "control: loopback is denied by the profile")
            (assert (= chk.exit 0) (str "asl check exits 0 with nice denied: " chk.out))
            (assert (= tst.exit 0) (str "asl test exits 0 with nice denied: " tst.out))
            (assert (= (countOf tst.out "(:nice :denied") 1) (str "two suites under one denied nice print the nice line exactly once: " tst.out))
            (assert (and (stringContains? tst.out ":what setpriority") (and (stringContains? tst.out ":why ") (and (stringContains? tst.out ":effect ") (stringContains? tst.out ":fix ")))) (str "the nice line names what, why, effect and fix: " tst.out))
            (assert (= (stringTrim probes.out) "1") (str "the root process probes nice exactly once for two suites, nested CLI included: " probes.out))
            (assert (<= (countOf tst.out "(:cache :denied") 1) (str "the cache line is printed at most once: " tst.out))
            (assert (or (= (countOf tst.out "(:cache :denied") 0) (and (stringContains? tst.out ":what nativeTestCache") (stringContains? tst.out ":fix \"grant write access"))) (str "a cache line names what, why, effect and fix: " tst.out))
            (assert (and (= rd.exit 0) (stringContains? rd.out ":kind")) (str "a (:read) form answers with nice denied: " rd.out))
            true))))
