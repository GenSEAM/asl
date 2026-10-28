(module asl-cli/tests/clangResolveTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a run) (asl/packages/asl-cli/src/nativeCli :a nc)])

; (:m :ref CLI-CLANG-PROBE :do "a PATH holding only a clang-18 shim resolves clang-18 with CLANG unset; a :native :clang row wins over CLANG and PATH; with none of them the error names what was tried. The shims live in a scratch dir and are never run")
fn ! sh! script: String args: (List String) -> Int64
  (run/runGuarded (listAppend (list "/bin/sh" "-c" script "sh") args) "/" (run/childEnv (list)) (run/limits 60 4)).exitCode

fn ! testPathProbe work: String -> Bool
  (let [(only18 (str work "/only18"))
        (empty (str work "/empty"))
        (both (str work "/both"))
        (made (sh! "mkdir -p \"$1\" \"$2\" \"$3\" && printf '#!/bin/sh\\nexit 0\\n' > \"$1/clang-18\" && chmod +x \"$1/clang-18\" && cp \"$1/clang-18\" \"$3/clang-16\" && cp \"$1/clang-18\" \"$3/clang-19\" && printf 'x' > \"$2/clang\""
                   (list only18 empty both)))
        (found18 (nc/clangOnPathIn! (str "/nonexistent:" only18)))
        (foundNone (nc/clangOnPathIn! empty))
        (foundBoth (nc/clangOnPathIn! (str both ":" only18)))]
    (do (assert (= made 0) "the shims are written")
        (assert (= found18 (list "clang-18")) (str "a PATH with only a clang-18 shim finds clang-18: " (stringJoin found18 " ")))
        (assert (= (nc/clangPick (none) (none) found18) (ok "clang-18")) "with no row and CLANG unset it resolves clang-18")
        (assert (listEmpty? foundNone) (str "a non-executable file named clang is not a clang: " (stringJoin foundNone " ")))
        (assert (= foundBoth (list "clang-19" "clang-18" "clang-16")) (str "candidates come in build.sh's order, newest first: " (stringJoin foundBoth " ")))
        true))

fn ! testOrder work: String -> Bool
  (let [(row "(:aslConfig :workspace \"fx\" :native (:storeCap 2G :clang clang-17))\n")
        (cfgDir (str work "/ws/sub"))
        (made (sh! "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/../.asl.config.asn\"" (list cfgDir row)))
        (nothing (nc/clangPick (none) (none) (list)))
        (noneText (match nothing ((err e) e) ((ok c) (str "resolved " c))))]
    (do (assert (= made 0) "a workspace config with a :native :clang row is written")
        (assert (= (nc/configClang row) (some "clang-17")) "configClang reads the :clang value of the :native row")
        (assert (none? (nc/configClang "(:aslConfig :native (:storeCap 2G))\n")) "a :native row without :clang names no clang")
        (assert (= (nc/clangPick (some "clang-17") (some "/opt/x/clang") (list "clang-18")) (ok "clang-17")) "the config row wins over CLANG and PATH")
        (assert (= (nc/clangPick (none) (some "/opt/x/clang") (list "clang-18")) (ok "/opt/x/clang")) "CLANG wins over PATH")
        (assert (= (nc/clangFor! cfgDir) (ok "clang-17")) "clangFor! finds the row in the nearest config above the dir, whatever CLANG and PATH hold")
        (refute (ok? nothing) "with no row, no CLANG and nothing on PATH nothing resolves")
        (assert (stringContains? noneText ":native :clang") (str "the error names the config row: " noneText))
        (assert (stringContains? noneText "CLANG unset") (str "and CLANG: " noneText))
        (assert (stringContains? noneText "clang-19 clang-18 clang-17 clang-16 clang-15") (str "and every PATH name tried: " noneText))
        true))

fn ! runTests -> Bool
  (let [(work (str "/tmp/aslClangResolve." (stringFromInt64 (procSelf))))
        (probe (testPathProbe work))
        (order (testOrder work))
        (cleaned (sh! "rm -rf \"$1\"" (list work)))]
    (do (assert probe "the PATH probe finds the versioned clang")
        (assert order "row, CLANG, PATH, then a clear error")
        (assert (= cleaned 0) "the scratch dir is removed")
        true))
