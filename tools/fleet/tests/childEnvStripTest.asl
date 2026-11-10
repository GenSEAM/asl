(module asl-tools/fleet/tests/childEnvStripTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref CHILDENV-STRIP-MORE :do "the fleet bridge and gateway children must not inherit the owner ssh agent socket row or any password row: secretName? is true for the exact name SSH_AUTH_SOCK and for any name containing PASSWORD, childEnv drops those inherited rows while an explicit override passes through once, and sideEnv of a side with no prelude keeps its one ASL_ROOT row")

fn envName row: String -> String
  (optionOr (listHead (stringSplit row "=")) row)

fn rowsNamed env: (List String) name: String -> (List String)
  (filter (fn [(r String)] -> Bool (= (envName r) name)) env)

fn rowsNamedContaining env: (List String) needle: String -> (List String)
  (filter (fn [(r String)] -> Bool (stringContains? (envName r) needle)) env)

fn ! freshDir -> String
  (let [(base (optionOr (envGet "TMPDIR") "/tmp"))
        (dir (str base "/childEnvStripTest-" (stringFromInt64 (nowNs))))]
    (match (dirCreate dir)
      ((ok _) dir)
      ((err _) dir)))

fn ! runTests -> Bool
  (let [(dir (freshDir))
        (side (fr/sideEnv dir))
        (roots (filter (fn [(r String)] -> Bool (stringStartsWith? r "ASL_ROOT=")) side))]
    (do
      (assert (fr/secretName? "SSH_AUTH_SOCK") "secretName? is true for the exact env name SSH_AUTH_SOCK")
      (assert (fr/secretName? "DB_PASSWORD") "secretName? is true for DB_PASSWORD")
      (assert (fr/secretName? "MY_PASSWORD_HASH") "secretName? is true for MY_PASSWORD_HASH")
      (assert (fr/secretName? "X_API_KEY") "secretName? is true for X_API_KEY")
      (assert (fr/secretName? "TOKENIZER") "secretName? still matches TOKEN")
      (assert (not (fr/secretName? "HOME")) "secretName? is false for HOME")
      (assert (not (fr/secretName? "PATH")) "secretName? is false for PATH")
      (assert (listEmpty? (rowsNamed (fr/childEnv (list)) "SSH_AUTH_SOCK")) "childEnv (list) keeps zero inherited rows named SSH_AUTH_SOCK")
      (assert (listEmpty? (rowsNamedContaining (fr/childEnv (list)) "PASSWORD")) "childEnv (list) keeps zero inherited rows whose name contains PASSWORD")
      (assert (= (rowsNamed (fr/childEnv (list "SSH_AUTH_SOCK=/tmp/given")) "SSH_AUTH_SOCK") (list "SSH_AUTH_SOCK=/tmp/given")) "an explicit SSH_AUTH_SOCK override passes through exactly once")
      (match (envGet "KEEP_CHILD_ENV_TEST")
        ((some keep) (assert (= (rowsNamed (fr/childEnv (list)) "KEEP_CHILD_ENV_TEST") (list (str "KEEP_CHILD_ENV_TEST=" keep))) "a parent KEEP_CHILD_ENV_TEST row survives childEnv (list) exactly once"))
        ((none) (eprintln "childEnvStripTest: skipped the KEEP_CHILD_ENV_TEST survival case, this parent shell has no KEEP_CHILD_ENV_TEST row")))
      (assert (= roots (list (str "ASL_ROOT=" dir))) (str "sideEnv of a side with no prelude has exactly one ASL_ROOT row: " (stringJoin roots " ")))
      (assert (listEmpty? (rowsNamed side "SSH_AUTH_SOCK")) "sideEnv carries no ssh agent row")
      (assert (listEmpty? (rowsNamedContaining side "PASSWORD")) "sideEnv carries no password row")
      (let [(_ (pathRemove dir))] true)))
