(module asl/tools/fleet/tests/boundedTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl/tools/fleet/bounded :a bd)])

; (:m :ref WATCHDOG-GROUP-KILL :do "bounded.asl through its real command line, each case one child of this test run through fleet/run.asl with a 90 s limit: a command past SECS is killed with its whole tree (a sleeper child, a sleeper grandchild in a nested sh, and a nested bin/asl run with its own sleeper) with exit 124 and a timeout note, a command that ends keeps its exit code and output whole, a bad line is refused with exit 2 before any run; no sleeper survives")

fn ! ps! -> String
  (fr/runOneLimited (fr/job (list "ps" "-A" "-o" "command=") "/" (fr/childEnv (list))) (fr/limits 10 8)).out

fn ! survives? text: String secs: String -> Bool
  (stringContains? text (str "sleep " secs))

fn ! child! root: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "./bin/asl" "run" "asl/tools/fleet/bounded.asl") argv) root (fr/childEnv (list))) (fr/limits 90 64))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (before (ps!))
        (tree (child! root (list "3" "--" "sh" "-c" "sleep 121 & sh -c 'sleep 122 & wait' & wait")))
        (afterTree (ps!))
        (nested (child! root (list "3" "--" "sh" "-c" "exec ./bin/asl run asl/tools/fleet/bounded.asl 120 -- sleep 123")))
        (afterNested (ps!))
        (okRun (child! root (list "20" "--" "sh" "-c" "echo whole; echo err >&2; exit 7")))
        (noCmd (child! root (list "3" "--")))
        (noSep (child! root (list "3" "sleep" "1")))
        (zero (child! root (list "0" "--" "true")))]
    (do (assert (not (or (survives? before "121") (or (survives? before "122") (survives? before "123")))) "no sleeper of this test exists before it starts")
        (assert (= tree.exit 124) (str "a tree past SECS ends with exit 124: " (stringFromInt64 tree.exit)))
        (assert (stringContains? tree.out ":verdict :timeout") (str "the timeout note is printed: " tree.out))
        (assert (< tree.ms 60000) (str "the 120 s body is killed at SECS 3, long before its end: " (stringFromInt64 tree.ms)))
        (assert (not (survives? afterTree "121")) "the direct child's sleeper does not survive")
        (assert (not (survives? afterTree "122")) "the sleeper of the nested sh (a grandchild) does not survive")
        (assert (= nested.exit 124) (str "a nested bin/asl run past SECS ends with exit 124: " (stringFromInt64 nested.exit)))
        (assert (not (survives? afterNested "123")) "the nested bin/asl run's own sleeper does not survive")
        (assert (and (= okRun.exit 7) (and (stringContains? okRun.out "whole") (stringContains? okRun.out "err"))) (str "a command that ends keeps its exit code and output: " okRun.out))
        (assert (not (stringContains? okRun.out ":verdict")) "an ended command carries no kill note")
        (assert (and (= noCmd.exit 2) (stringContains? noCmd.out "the command is empty")) (str "an empty command is refused: " noCmd.out))
        (assert (and (= noSep.exit 2) (stringContains? noSep.out "the command must follow --")) (str "a missing separator is refused: " noSep.out))
        (assert (and (= zero.exit 2) (stringContains? zero.out "SECS must be a positive integer")) (str "SECS 0 is refused: " zero.out))
        (assert (= (bd/parseArgs (list "5" "--max-desc" "9" "--" "a" "b")).maxDesc 9) "parseArgs reads --max-desc")
        (assert (= (bd/parseArgs (list "5" "--" "a" "b")).maxDesc 64) "parseArgs defaults maxDesc to 64")
        true))
