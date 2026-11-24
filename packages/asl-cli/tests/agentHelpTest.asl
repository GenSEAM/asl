(module asl-cli/tests/agentHelpTest :x [runTests] :i [(asl-tools/fleet/run :a run) (asl-gates/dyck :a dyck)])

; (:m :ref CLI-AGENT-HELP :do "bare asl, -h, --help and help print the agent brief (ASN, small, derived from the tools registry), asl human help prints the human usage, and check and test argv handling is unchanged")
fn ! cli args: (List String) -> run/Done
  (run/runOneLimited (run/job (cons "bin/asl" args) "." (run/childEnv (list))) (run/limits 180 8))

fn ! briefOk? args: (List String) -> Bool
  (let [(r (cli args))]
    (and (= r.exit 0)
      (and (stringStartsWith? r.out "(:asl :brief")
        (and (stringContains? r.out "(:tools)")
          (and (stringContains? r.out "(:help :builtin X)")
            (and (stringContains? r.out "asl - <<'EOF'")
              (and (stringContains? r.out "(:flush)")
                (and (stringContains? r.out "(:intel :op outline")
                  (and (stringContains? r.out ":human \"asl human help\"")
                    (and (not (stringContains? r.out "Human CLI Usage"))
                      (and (not (stringContains? r.out "asl check"))
                        (and (< (stringLength r.out) 1536)
                          (none? (dyck/checkString r.out false))))))))))))))

fn defsOf text: String -> Int64
  (match (stringIndexOf text ":defs ")
    ((none) -1)
    ((some i) (let [(tail (optionOr (stringSlice text (+ i 6) (stringLength text)) ""))
                    (digits (optionOr (stringSlice tail 0 (optionOr (stringIndexOf tail " ") 0)) ""))]
                (optionOr (stringToInt64 digits) -1))))

fn ! same? args: (List String) -> Bool
  (let [(a (cli args)) (b (cli (cons "human" args)))]
    (and (= a.exit b.exit) (and (= a.out b.out) (not (stringContains? b.out "ERR_UNKNOWN_COMMAND")))))

fn ! readOnlyBrief? -> Bool
  (let [(r (cli (list)))
        (ops (optionOr (listHead (stringSplit r.out " :writes (")) ""))]
    (and (stringContains? ops "(:observe") (and (not (stringContains? ops "(:edit")) (and (not (stringContains? ops "(:agent")) (stringContains? r.out ":writes (")))))

fn ! runTests -> Bool
  (do
    (assert (readOnlyBrief?) "the :ops rows are read-only, edit and agent sit under :writes")
    (let [(o (cli (list "(:observe :dim callers :symbol \"helpText\")")))]
      (assert (and (not (stringContains? o.out ":status :rejected")) (>= (defsOf o.out) 1)) "the observe example is accepted and finds at least one def of its symbol"))
    (assert (same? (list "asl/packages/asl-cli/tests/argParsersTest.asl")) "asl human PATH.asl is asl PATH.asl")
    (assert (same? (list "-e" "(+ 21 21)")) "asl human -e is asl -e")
    (let [(hc (cli (list "human" "check" "asl/packages/asl-cli/src/agentHelp.asl")))]
      (assert (and (= hc.exit 0) (and (stringContains? hc.out ":checked ") (not (stringContains? hc.out "ERR_UNKNOWN_COMMAND")))) "asl human check is asl check"))
    (let [(n (cli (list "human" "human" "eval" "(+ 21 21)")))]
      (assert (and (= n.exit 0) (stringContains? n.out "42")) "asl human human X is asl X"))
    (assert (same? (list "test")) "asl human test is asl test")
    (assert (briefOk? (list)) "bare asl prints the agent brief")
    (assert (briefOk? (list "-h")) "asl -h prints the agent brief")
    (assert (briefOk? (list "--help")) "asl --help prints the agent brief")
    (assert (briefOk? (list "help")) "asl help prints the agent brief")
    (let [(h (cli (list "human" "help")))]
      (do (assert (= h.exit 0) "asl human help exits 0")
          (assert (stringContains? h.out "Human CLI Usage:") "asl human help prints the human usage")
          (assert (stringContains? h.out "  check <file|--all>") "asl human help lists check")))
    (let [(c (cli (list "human" "help" "build")))]
      (assert (stringContains? c.out "usage: asl build") "asl human help build prints the build usage"))
    (let [(k (cli (list "check" "asl/packages/asl-cli/src/agentHelp.asl")))]
      (do (assert (= k.exit 0) "asl check still exits 0") (assert (stringContains? k.out ":checked ") "asl check still reports :checked")))
    (let [(t (cli (list "human" "check" "asl/packages/asl-cli/src/agentHelp.asl")))]
      (assert (stringContains? t.out ":checked ") "asl human check runs check"))
    (let [(e (cli (list "test")))]
      (assert (!= e.exit 0) "asl test with no argument is still refused"))
    true)
