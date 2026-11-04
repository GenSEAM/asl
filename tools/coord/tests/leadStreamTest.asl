(module asl/tools/coord/tests/leadStreamTest
  :x [runTests]
  :i [(asl-tools/coord/leadStream :a ls) (asl-tools/coord/janitor :a j) (tools/remote/nodeWatch :a nw) (asl-tools/fleet/run :a fr)])

; (:m :ref LEAD-STREAM :do "gates on a fixture home: dedupe inside the window, the rotation bound, digest grouping, ack hiding, operator act rows, the nodeWatch escalate path and one janitor run each appending to the stream; every gate was proven red against a mutant of the change")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/leadStreamTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 120 16))

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! rowsOf dir: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:ev ")) (stringLines (resultOr (fileReadString (str dir "/lead/stream.asn")) "")))

fn ! evsAt runDir: String -> Int64
  (listLength (rowsOf runDir))

fn cfgIn dir: String -> ls/Cfg
  (ls/cfgAt dir "n1")

fn ! mk! cfg: ls/Cfg now: Int64 src: String sev: String kind: String key: String -> Bool
  (ok? (ls/emit! cfg now src sev kind key "" (str kind " " key)))

fn ! testDedupe base: String -> Bool
  (let [(d (str base "/dedupe"))
        (c (cfgIn d))
        (t0 1000000)]
    (do
      (assert (mk! c t0 "nodeWatch" "warn" "diskLow" "diskLow") "first event")
      (assert (mk! c (+ t0 120000) "nodeWatch" "warn" "diskLow" "diskLow") "repeat after two minutes")
      (assert (mk! c (+ t0 240000) "nodeWatch" "act" "diskLow" "diskLow") "repeat after four minutes, worse sev")
      (assert (= (evsAt d) 1) "a fault repeating inside the window is one row")
      (let [(e (optionOr (ls/evOf (optionOr (listHead (rowsOf d)) "")) (ls/Ev :id "" :at 0 :last 0 :node "" :src "" :sev "" :kind "" :key "" :unit "" :why "" :count 0 :ack false)))]
        (do (assert (= e.count 3) (str "the row counts three events: " (stringFromInt64 e.count)))
            (assert (= e.at t0) "the row keeps its first time")
            (assert (= e.last (+ t0 240000)) "the row moves its last time")
            (assert (= e.sev "act") "the row takes the worst sev")
            true))
      (assert (mk! c (+ t0 300000) "nodeWatch" "warn" "diskLow" "otherKey") "another key")
      (assert (mk! c (+ t0 300000) "janitor" "warn" "diskLow" "diskLow") "another src")
      (assert (mk! c (+ t0 300000) "nodeWatch" "warn" "diskStop" "diskLow") "another kind")
      (assert (= (evsAt d) 4) "key, src and kind each separate rows")
      (assert (mk! c (+ t0 240000 3700000) "nodeWatch" "warn" "diskLow" "diskLow") "repeat past the window")
      (assert (= (evsAt d) 5) "past the window a new row appears")
      true))

fn ! testRotation base: String -> Bool
  (let [(d (str base "/rot"))
        (c (with (cfgIn d) :maxRows 5))]
    (do
      (assert (fold (fn [(ok Bool) (i Int64)] -> Bool (and ok (mk! c (+ 1000 i) "conductor" "info" "k" (stringFromInt64 i)))) true (range 0 12)) "twelve distinct events")
      (assert (= (evsAt d) 5) (str "the file is cut to maxRows: " (stringFromInt64 (evsAt d))))
      (assert (stringContains? (resultOr (fileReadString (str d "/lead/stream.asn")) "") "\"k 11\"") "the newest survives")
      (assert (not (stringContains? (resultOr (fileReadString (str d "/lead/stream.asn")) "") "\"k 0\"")) "the oldest is gone")
      (let [(ids (map (fn [(l String)] -> String (optionOr (match (ls/evOf l) ((some e) (some e.id)) ((none) (none))) "")) (rowsOf d)))
            (newest (optionOr (listLast ids) ""))
            (second (optionOr (listGet ids 1) ""))]
        (do
          (assert (ok? (ls/ack! c (list second))) "ack the second oldest")
          (assert (mk! c 5000 "conductor" "info" "k" "99") "one more event")
          (assert (= (evsAt d) 5) "still bounded")
          (assert (not (stringContains? (resultOr (fileReadString (str d "/lead/stream.asn")) "") second)) "an acked row goes before older unacked rows")
          (assert (stringContains? (resultOr (fileReadString (str d "/lead/stream.asn")) "") "\"k 7\"") "older unacked rows stay")
          true))
      true))

fn ! testDigestAck base: String -> Bool
  (let [(d (str base "/dig"))
        (c (cfgIn d))]
    (do
      (assert (mk! c 1000 "nodeWatch" "warn" "diskLow" "a") "diskLow a")
      (assert (mk! c 2000 "nodeWatch" "warn" "diskLow" "b") "diskLow b")
      (assert (mk! c 3000 "nodeWatch" "act" "diskStop" "a") "diskStop")
      (assert (mk! c 4000 "janitor" "info" "removed" "run") "removed")
      (let [(all (ls/digest! c 9000 0 "info"))
            (warn (ls/digest! c 9000 0 "warn"))
            (late (ls/digest! c 9000 2500 "info"))]
        (do
          (assert (stringContains? all ":unacked 4") (str "digest counts four unacked: " all))
          (assert (stringContains? all ":kind diskLow :sev warn :rows 2 :count 2 :last 2000 :why \"diskLow b\"") (str "diskLow groups two rows with the newest why: " all))
          (assert (< (optionOr (stringIndexOf all ":kind diskStop") 0) (optionOr (stringIndexOf all ":kind diskLow") 0)) "the worst group comes first")
          (assert (not (stringContains? warn ":kind removed")) "--sev warn hides info")
          (assert (stringContains? warn ":unacked 3") "warn keeps three")
          (assert (and (stringContains? late ":unacked 2") (not (stringContains? late ":kind diskLow"))) (str "--since cuts older events: " late))
          (let [(ids (map (fn [(l String)] -> String (optionOr (match (ls/evOf l) ((some e) (if (= e.kind "diskLow") (some e.id) (none))) ((none) (none))) "")) (rowsOf d)))
                (r (ls/ack! c ids))]
            (do
              (assert (and (ok? r) (stringContains? (resultOr r "") ":n 2")) (str "ack reports two: " (resultOr r (resultOr (match r ((err e) (ok e)) ((ok _) (err ""))) ""))))
              (let [(after (ls/digest! c 9000 0 "info"))]
                (do (assert (stringContains? after ":unacked 2") (str "acked events leave the digest: " after))
                    (assert (not (stringContains? after ":kind diskLow")) "the acked kind is gone")
                    true))))
          (assert (mk! c 9500 "nodeWatch" "warn" "diskLow" "a") "the fault recurs after the ack")
          (assert (stringContains? (ls/digest! c 9600 0 "info") ":kind diskLow") "an acked fault that recurs is a new unacked row")
          true))))

fn ! testAct base: String -> Bool
  (let [(d (str base "/act"))
        (c (cfgIn d))]
    (do
      (assert (err? (ls/act! c 1 "e1" "explode")) "an unknown action is refused")
      (assert (ok? (ls/act! c 5000 "e1" "requeue")) "requeue row")
      (assert (ok? (ls/act! c 5001 "e2" "hold")) "hold row")
      (assert (= (listLength (ls/pendingActs! c)) 2) "two pending acts")
      (assert (stringContains? (ls/digest! c 9000 0 "info") ":acts 2") "digest counts pending acts")
      (let [(first (optionOr (listHead (optionOr (listHead (ls/pendingActs! c)) (list))) ""))]
        (do (assert (stringStartsWith? first "a5000-") "the oldest act first")
            (assert (ok? (ls/actDone! c first)) "close the first")
            (assert (= (listLength (ls/pendingActs! c)) 1) "one pending act left")
            true))
      true))

fn ! testNodeWatch base: String -> Bool
  (let [(d (str base "/nw"))
        (cfg (nw/defaultCfg))
        (snap (nw/Snap :relayOk true :hubOk true :conductorActive true :journalAgeS 0 :activityAgeS 0 :memMb 100000 :loadX100 10 :cores 4 :schedMax 4 :overdue (list) :repoBroken false :diskUsedPct 97 :diskFreeMb 100))
        (plan (nw/decide cfg snap (nw/emptyState) 1000))
        (rows (map (fn [(a nw/Act)] -> String (str "(:escalate :target " a.target ")")) plan.acts))
        (n (nw/leadEvents! d 1000000 plan.acts rows))
        (low (nw/decide cfg (with snap :diskUsedPct 88 :diskFreeMb 40000) (nw/emptyState) 1000))
        (_ (nw/leadEvents! d 1000000 low.acts (map (fn [(a nw/Act)] -> String (str "(:escalate :target " a.target ")")) low.acts)))
        (restart (nw/leadEvents! d 1000000 (list (nw/Act :kind "restart" :target "asl-relay" :why "down" :value 0 :start "")) (list "(:nodeWatch :action restart :ok false)")))
        (restartOk (nw/leadEvents! d 1000000 (list (nw/Act :kind "restart" :target "asl-hub" :why "down" :value 0 :start "")) (list "(:nodeWatch :action restart :ok true)")))
        (text (resultOr (fileReadString (str d "/lead/stream.asn")) ""))]
    (do
      (assert (= n 1) (str "a diskStop escalate lands one event: " (stringFromInt64 n)))
      (assert (stringContains? text ":src nodeWatch :sev act :kind diskStop") (str "diskStop is sev act: " text))
      (assert (stringContains? text ":sev warn :kind diskLow") "diskLow is sev warn")
      (assert (= restart 1) "a failed restart lands")
      (assert (stringContains? text ":kind restartFailed") "a failed restart is restartFailed")
      (assert (= restartOk 0) "a restart that took lands nothing")
      (assert (= (evsAt d) 3) "three events in all")
      true))

fn ! testJanitor base: String -> Bool
  (let [(d (str base "/jan"))
        (tmp (str d "/tmp"))
        (a (str tmp "/cmdTest-3999991"))
        (b (str tmp "/cmdTest-3999992"))
        (c (j/Cfg :tmp tmp :runDir (str d "/run") :modePath (str d "/mode.asn") :storeDir (str d "/store") :repo (str d "/repo") :wtBase (str d "/wts")
                  :minAgeS 3600 :forceAgeS 86400 :maxPaths 20 :walkTimeoutS 20 :budgetS 30))]
    (do
      (assert (= (sh "." (list "mkdir" "-p" a b (str d "/store"))).exit 0) "fixture dirs")
      (assert (put (str a "/f") "x") "file a")
      (assert (put (str b "/f") "x") "file b")
      (assert (= (sh "." (list "touch" "-t" "202001010000" a b)).exit 0) "old scratch")
      (assert (put (str d "/store/slots.asn") "(:slots :base 4 :level low)") "level low")
      (let [(t1 (j/tick! c))]
        (do (assert (stringContains? t1 ":mode dry") "dry run")
            (assert (= (evsAt (str d "/run")) 0) "a dry run lands no event")
            true))
      (assert (put (str d "/mode.asn") "(:janitor :mode apply)\n") "apply mode")
      (let [(t2 (j/tick! c))
            (rows (rowsOf (str d "/run")))]
        (do (assert (not (fileExists? a)) "scratch a removed")
            (assert (not (fileExists? b)) "scratch b removed")
            (assert (= (listLength rows) 1) (str "two removals land exactly one event: " (stringJoin rows "|")))
            (assert (stringContains? (optionOr (listHead rows) "") ":src janitor :sev info :kind removed") "an info event from the janitor")
            (assert (stringContains? (optionOr (listHead rows) "") "removed 2 paths,") "the event carries the count")
            true))
      (let [(tt (j/removedTotals "(:removed :path \"/x\" :class a :bytes 7 :ok true)\n(:removed :path \"/y\" :class a :bytes 5 :ok false)\n(:removed :path \"/z\" :class b :bytes 100 :ok true)\n"))]
        (do (assert (= (pairFirst tt) 2) "totals count the ok rows")
            (assert (= (pairSecond tt) 107) "totals sum the bytes of the ok rows")
            true))
      (let [(t3 (j/tick! c))]
        (do (assert (= (evsAt (str d "/run")) 1) "a run that removes nothing lands no event")
            true))
      true))

fn ! testWired -> Bool
  (let [(src (resultOr (fileReadString "tools/remote/nodeWatch.asl") ""))
        (jsrc (resultOr (fileReadString "asl/tools/coord/janitor.asl") ""))]
    (do (assert (stringContains? src "(> (leadEvents! (runDir!) (* nowS 1000) plan.acts rows) 0)") "nodeWatch tick! calls leadEvents! on the real path")
        (assert (stringContains? src "(or dry (listEmpty? rows)) false (> (leadEvents!") "the stream call is skipped on a dry tick")
        (assert (stringContains? jsrc "(_ (if apply (leadReport! cfg) false))") "janitor tick! reports once per apply run")
        true))

fn ! runTests -> Bool
  (let [(base (scratch))]
    (do (assert (= (sh "." (list "mkdir" "-p" base)).exit 0) "private base")
        (assert (testDedupe base) "dedupe")
        (assert (testRotation base) "rotation")
        (assert (testDigestAck base) "digest and ack")
        (assert (testAct base) "act rows")
        (assert (testNodeWatch base) "nodeWatch escalate path")
        (assert (testJanitor base) "janitor run")
        (assert (testWired) "wiring")
        (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
        true))
