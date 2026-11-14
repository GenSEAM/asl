(module asl-cli/tests/childEnvMarkerTest
  :x [runTests]
  :i [(asl-cli/system :a sys)])

; (:m :ref CLI-HOST-FALLBACK :do "childEnv is what a re-entered bin/asl inherits (asl train, asl timeout): ASL_CLI_USER_PRELUDE passes with its value, empty (no user override) or a path (a real one), every other ASL_CLI_ name is dropped, a row named in extra replaces the inherited one; then the same on this process's real environment")
fn nameOf row: String -> String
  (optionOr (listHead (stringSplit row "=")) row)

fn named rows: (List String) name: String -> (List String)
  (filter (fn [(r String)] -> Bool (= (nameOf r) name)) rows)

fn otherCli rows: (List String) -> (List String)
  (filter (fn [(r String)] -> Bool (and (stringStartsWith? (nameOf r) "ASL_CLI_") (!= (nameOf r) "ASL_CLI_USER_PRELUDE"))) rows)

fn ! runTests -> Bool
  (let [(marker "ASL_CLI_USER_PRELUDE")
        (rows (list "PATH=/usr/bin" "ASL_PRELUDE=/w/asl/prelude/prelude.asl" "ASL_CLI_USER_PRELUDE=" "ASL_CLI_ROOT=/w" "ASL_CLI_ENTRY_PID=7" "ASL_CLI_ARGV0=/w/bin/asl" "ASL_CLI_HOST_BIN=/h" "ASL_HOST=/h"))
        (none (sys/childEnvOf rows (list) false))
        (user (sys/childEnvOf (list "ASL_CLI_USER_PRELUDE=/u/mine.asl" "ASL_CLI_ROOT=/w") (list) false))
        (given (sys/childEnvOf rows (list "ASL_CLI_USER_PRELUDE=/x.asl" "ASL_CLI_ROOT=/y") true))
        (real (sys/childEnv! (list)))]
    (do
      (assert (= (named none marker) (list "ASL_CLI_USER_PRELUDE=")) "the empty marker, no user override, survives the round trip")
      (assert (= none (list "PATH=/usr/bin" "ASL_PRELUDE=/w/asl/prelude/prelude.asl" "ASL_CLI_USER_PRELUDE=" "ASL_HOST=/h")) "every other ASL_CLI_ name is dropped and the rest passes in order")
      (assert (= user (list "ASL_CLI_USER_PRELUDE=/u/mine.asl")) "a real user override reaches the nested call with its value")
      (assert (= (named given marker) (list "ASL_CLI_USER_PRELUDE=/x.asl")) "a marker row in extra replaces the inherited one")
      (assert (= (named given "ASL_CLI_ROOT") (list "ASL_CLI_ROOT=/y")) "an ASL_CLI_ row in extra is passed")
      (assert (listEmpty? (named given "ASL_HOST")) "ASL_HOST is dropped on request")
      (assert (= (named real marker) (named (envList) marker)) "this process's own marker row passes childEnv! unchanged")
      (assert (listEmpty? (otherCli real)) "and no other ASL_CLI_ name of this process does")
      true))
