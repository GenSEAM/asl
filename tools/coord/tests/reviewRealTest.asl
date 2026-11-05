(module asl-tools/coord/tests/reviewRealTest
  :x [runTests envFor prepare! receiptFor! verdictOf sigOf]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref PIPE-GATES :do "G4: the real review stage (bin/asl run conductor.asl stage review UNIT) on a temp repo and store, its gateway calls going through the real provider to a stand-in hub (fixtures/hubVerdictStub.asl) named by the child's own HOME/.asl/hub.asn; the stub answers a verdict form read from a file; a pass verdict reaches the review Res row with the diff in the reviewers' request, and anything the stage could not read (lane table) is not a pass")
fn ! envFor root: String -> (List String)
  (list (str "HOME=" root "/home") (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))) "ASL_GATEWAY_URL=http://127.0.0.1:1/v1/chat/completions" (str "ASL_GATEWAY_CONFIG=" root "/home/.asl/gateway.asn"))

fn ! prepare! root: String -> Bool
  (let [(_ (dirCreate (str root "/home/.asl")))
        (_ (dirCreate (str root "/store/runs")))
        (a (fileWrite (str root "/home/.asl/gateway.asn") (str (pf/gatewayText) "\n")))
        (b (fileWrite (str root "/home/lanes.asn") (str (pf/lanesText) "\n")))
        (c (fileWrite (str root "/home/.asl/hub.asn") (str "(:hub :sock \"" root "/hub.sock\" :class \"lead\")\n")))
        (d (fileWrite (str root "/hubReply.txt") "(:verdict :pass :defects () :model m)"))]
    (and (ok? a) (and (ok? b) (and (ok? c) (ok? d)))))

fn ! receiptFor! root: String id: String -> Bool
  (ok? (fileWrite (cd/runPath (str root "/store") id "receipt" "asn") (str "(:receipt \"" id "\" :gates ((:gate \"g\" :exit 0 :executed 3)) :redBefore ((:gate \"g\" :exit 1 :executed 0)))\n")))

fn verdictOf r: (Result cd/Res String) -> String
  (match r ((ok x) x.verdict) ((err e) (str "noRow: " e)))

fn sigOf r: (Result cd/Res String) -> String
  (match r ((ok x) x.sig) ((err _) ""))

fn ! runTests -> Bool
  (let [(root (pf/scratch "reviewReal" "g4"))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (prep (prepare! root))
        (hub (pf/startHub! root))
        (env (envFor root))
        (uA (pf/unitIn "RA" "sh check.sh impl.txt"))
        (uE (pf/unitIn "RE" "sh check.sh impl.txt"))
        (uD (pf/unitIn "RD" "sh check.sh impl.txt"))
        (wtA (pf/seedUnit! root uA "reviewing" "impl.txt"))
        (wtE (pf/seedUnit! root uE "reviewing" "impl.txt"))
        (wtD (pf/seedUnit! root uD "reviewing" "impl.txt"))
        (rcpts (and (receiptFor! root "RA") (and (receiptFor! root "RE") (receiptFor! root "RD"))))
        (dA (pf/stageChild! root "review" "RA" (list) env 600))
        (seenA (pf/hubSeen root))
        (resA (pf/readResOf! root "RA" "review"))
        (journalA (resultOr (fileReadString (cd/journalPath (str root "/store"))) ""))
        (_ (fileWrite (str root "/hubReply.txt") "(:verdict :fail :defects (\"impl.txt: stand-in defect\") :model m)"))
        (dE (pf/stageChild! root "review" "RE" (list) env 600))
        (resE (pf/readResOf! root "RE" "review"))
        (_ (pathRemove (str root "/home/lanes.asn")))
        (dD (pf/stageChild! root "review" "RD" (list) env 600))
        (resD (pf/readResOf! root "RD" "review"))
        (_ (pf/stopHub! hub))
        (_ (pf/cleanup root))]
    (do (assert (and (not (stringEmpty? repo)) (and prep (and (> hub 0) (and rcpts (and (not (stringEmpty? wtA)) (and (not (stringEmpty? wtE)) (not (stringEmpty? wtD)))))))) "fixture: repo, store, hub stand-in up, two reviewing units with proven receipts")
        (assert (= dA.exit 0) (str "the stage child exits 0: " (stringFromInt64 dA.exit) " " dA.out))
        (assert (= (verdictOf resA) "pass") (str "a pass verdict from the stand-in hub is a pass Res row: " (verdictOf resA) " " (sigOf resA)))
        (assert (stringContains? seenA "impl.txt") (str "the reviewers' request carried the unit's real diff: " (optionOr (stringSlice seenA 0 300) "")))
        (assert (stringContains? journalA ":verdict accept :note \"ladder R1\"") (str "the ruling's grade row reached the journal: " journalA))
        (assert (and (= (verdictOf resE) "fail") (stringContains? (sigOf resE) "stand-in defect")) (str "a fail verdict from the stand-in hub is a fail Res row carrying its defect: " (verdictOf resE) " " (sigOf resE)))
        (assert (and (not (= (verdictOf resD) "pass")) (or (= (verdictOf resD) "defer") (= (verdictOf resD) "block"))) (str "an unreadable lane table is a defer or block, not a pass: " (verdictOf resD) " " (sigOf resD)))
        true))
