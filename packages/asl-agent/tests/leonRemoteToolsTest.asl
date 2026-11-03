(module aslAgent/tests/leonRemoteToolsTest
  :x [runTests]
  :i [(aslAgent/exec :a x)
      (aslAgent/core :a c)
      (aslAgent/runOps :a r)
      (aslAgent/txn :a t)
      (aslAgent/main :a m)
      (asl-tools/fleet/run :a fr)
      (tools/remote/transport :a tr)])

; (:m :ref LEON-REMOTE-TOOLS :do "a loopback relay: a real bridge process on a unix socket in a scratch dir serves exec frames, the config says via relay with an unusable ssh, so every remote step must travel the relay; the bridge is bounded by --for and killed with its tree at the end, the scratch dir is removed")
fn passSource -> String
  "(module pass\n  :x [runTests]\n  :i [])\n\nfn twice n: Int64 -> Int64\n  (+ n n)\n\nfn runTests -> Bool\n  (do (assert (= (twice 1) 2) \"one plus one\")\n      (assert (= (twice 2) 4) \"two plus two\")\n      true)\n"

fn failSource -> String
  "(module fail\n  :x [runTests]\n  :i [])\n\nfn runTests -> Bool\n  (do (assert (= 1 2) \"broken on purpose\")\n      true)\n"

fn token -> String
  "0123456789abcdef0123456789abcdef01234567"

fn ! put! path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! waitSock! path: String tries: Int64 -> Bool
  (cond
    ((fileExists? path) true)
    ((<= tries 0) false)
    (else (do (sleepMs 200) (waitSock! path (- tries 1)))))

fn kv k: String v: String -> (Pair String c/KvVal)
  (pair k (c/kvStr v))

fn ! step! env: x/ExecEnv op: (List (Pair String c/KvVal)) -> (List (Pair String x/Val))
  (let [n (str "i" (nowNs))
        out (x/execOp! op env (r/newProcs) (fn [] n) (fn [f] true) (fn [rel pre mode] true) (fn [form rootDir] (t/aslRun 99 "" "no local run")))]
    out.rec)

fn field rec: (List (Pair String x/Val)) k: String -> String
  (x/pyStr (optionOr (x/recGet rec k) (x/vNone)))

fn ! runTests -> Bool
  (let [repo (resultOr (realPath ".") ".")
        base (str (tr/scratchDir!) "/leonRemote-" (procSelf) "-" (nowNs))
        wt (str base "/wt/LR")
        sock (str "/tmp/lrt-" (procSelf) ".sock")
        tokenPath (str base "/relay.token")
        cfgPath (str base "/remote.asn")
        bridgeCfg (str base "/bridge.asn")
        local (str base "/local")
        _dirs (and (ok? (dirCreate base)) (and (ok? (dirCreate (str base "/wt"))) (and (ok? (dirCreate wt)) (and (ok? (dirCreate (str wt "/bin"))) (ok? (dirCreate local))))))
        _seed (and (put! (str wt "/notes.txt") "alpha\nbeta\nalpha2\n") (and (put! (str wt "/pass.asl") (passSource)) (and (put! (str wt "/fail.asl") (failSource)) (put! (str wt "/big.txt") (stringJoin (map (fn [i] "aaaaaaaaaa") (range 0 3000)) "")))))
        _link (pathSymlink (str repo "/bin/asl") (str wt "/bin/asl"))
        _tok (and (put! tokenPath (str (token) "\n")) (ok? (fileChmod tokenPath 384)))
        _bcfg (put! bridgeCfg (str "(:bridge :exec \"true\" :stateDir \"" base "/state\" :wtBase \"" base "/wt\" :maxJobs 4 :timeout 120 :maxTimeout 300)\n"))
        _cfg (put! cfgPath (str "(:remote :host \"loopback\" :ssh \"/nonexistent-ssh\" :connectTimeout 1 :timeout 30 :via \"relay\" :wtBase \"wt\" :relaySock \"" sock "\" :relayToken \"" tokenPath "\")\n"))
        started (fr/spawn 0 (fr/job (list (fr/nativeCli!) "run" "tools/remote/bridge.asl" "serve" "--unix" sock "--config" bridgeCfg "--root" base "--for" "240") repo (fr/childEnv (list))))
        up (match started ((ok run) (waitSock! sock 50)) ((err _) false))
        env (x/makeExecEnv local local "implement" (list) true "main" (list) (map (fn [o] (pair o "local")) (list "read" "write" "edit" "test" "check" "run")) "" (list) 20000 120 (none) "leon" (none))
        rcfg (kv "remoteCfg" cfgPath)
        read1 (step! env (list (kv "type" "step") (kv "op" "read") (kv "remote" "LR") (kv "file" "notes.txt") rcfg))
        edit1 (step! env (list (kv "type" "step") (kv "op" "edit") (kv "remote" "LR") (kv "file" "notes.txt") (kv "old" "beta") (kv "new" "gamma") rcfg))
        onDisk (resultOr (fileReadString (str wt "/notes.txt")) "unreadable")
        amb (step! env (list (kv "type" "step") (kv "op" "edit") (kv "remote" "LR") (kv "file" "notes.txt") (kv "old" "alpha") (kv "new" "z") rcfg))
        miss (step! env (list (kv "type" "step") (kv "op" "edit") (kv "remote" "LR") (kv "file" "notes.txt") (kv "old" "nothere") (kv "new" "z") rcfg))
        wrote (step! env (list (kv "type" "step") (kv "op" "write") (kv "remote" "LR") (kv "file" "sub/new.txt") (kv "content" "fresh\n") rcfg))
        newDisk (resultOr (fileReadString (str wt "/sub/new.txt")) "unreadable")
        big (step! env (list (kv "type" "step") (kv "op" "read") (kv "remote" "LR") (kv "file" "big.txt") rcfg))
        escape (step! env (list (kv "type" "step") (kv "op" "read") (kv "remote" "LR") (kv "file" "../etc/passwd") rcfg))
        nowt (step! env (list (kv "type" "step") (kv "op" "read") (kv "remote" "NOPE") (kv "file" "notes.txt") rcfg))
        tpass (step! env (list (kv "type" "step") (kv "op" "test") (kv "remote" "LR") (kv "file" "pass.asl") rcfg))
        tfail (step! env (list (kv "type" "step") (kv "op" "test") (kv "remote" "LR") (kv "file" "fail.asl") rcfg))
        chk (step! env (list (kv "type" "step") (kv "op" "check") (kv "remote" "LR") (kv "file" "pass.asl") rcfg))
        sh (step! env (list (kv "type" "step") (kv "op" "run") (kv "remote" "LR") (kv "cmd" "cat notes.txt | wc -l") rcfg))
        killed (match started ((ok run) (fr/killTree! run.pid)) ((err _) 0))
        cleaned (and (ok? (pathRemove base)) (or (not (fileExists? sock)) (ok? (pathRemove sock))))]
    (do
      (assert up "the loopback bridge listens on its unix socket")
      (assert (and (= (field read1 "status") "ok") (and (stringContains? (field read1 "content") "alpha\nbeta") (not (stringContains? (field read1 "content") "(some")))) (str "remote read returns the VPS file: " (x/serRec read1)))
      (assert (and (= (field edit1 "status") "ok") (= onDisk "alpha\ngamma\nalpha2\n")) (str "remote edit replaced the one match on the VPS file: " (x/serRec edit1) " " onDisk))
      (assert (and (stringStartsWith? (field big "content") "aaaa") (stringContains? (field big "content") "truncated") (not (stringContains? (field big "content") "(some"))) (str "a read over the cap is cut with a plain marker: " (stringSlice (field big "content") 0 30)))
      (assert (= (field amb "error") "ERR_EDIT_AMBIGUOUS") (str "an :old with two matches is refused: " (x/serRec amb)))
      (assert (= (field miss "error") "ERR_EDIT_NOMATCH") (str "an :old with no match is refused: " (x/serRec miss)))
      (assert (and (= (field wrote "status") "ok") (= newDisk "fresh\n")) (str "remote write creates the file and its directory: " (x/serRec wrote)))
      (assert (= (field escape "error") "ERR_REMOTE_PATH") (str "a climbing path never leaves the worktree: " (x/serRec escape)))
      (assert (= (field nowt "error") "ERR_REMOTE_NO_WORKTREE") (str "an unknown unit is a missing worktree: " (x/serRec nowt)))
      (assert (and (= (field tpass "status") "ok") (stringContains? (field tpass "receipt") ":executed 2")) (str "remote test of a passing file runs both asserts on the VPS: " (x/serRec tpass)))
      (assert (and (= (field tfail "status") "failed") (stringContains? (field tfail "receipt") ":failed 1")) (str "remote test of a failing file is failed: " (x/serRec tfail)))
      (assert (= (field chk "status") "ok") (str "remote check passes: " (x/serRec chk)))
      (assert (and (= (field sh "status") "ok") (stringContains? (field sh "receipt") "3")) (str "remote run executes in the worktree: " (x/serRec sh)))
      (assert (and (listContains? (m/acceptedKeys) "remote") (= (listLength (m/withRemote (list (kv "op" "read")) "LR")) 2) (= (listLength (m/withRemote (list (kv "op" "read") (kv "remote" "X")) "LR")) 2) (= (listLength (m/withRemote (list (kv "op" "read")) "")) 1)) "a task-level :remote key is accepted and tags steps that name none")
      (assert cleaned "the scratch dir is removed")
      (assert (> killed -1) "the bridge tree is killed")
      true))
