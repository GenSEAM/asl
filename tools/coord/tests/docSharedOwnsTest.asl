(module asl-tools/coord/tests/docSharedOwnsTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/planImport :a pi) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr)])

; (:m :ref COND-OWNS-DOC-SERIALISES :do "the paths the conductor adds to a unit's owns (the package doc.asn and its asl-know card) are a right to write, not part of the exclusive lease: units of one package whose declared owns are disjoint are admitted in the same pass and each still owns the doc.asn at its stages; units whose declared owns overlap, a doc.asn both rows name included, are refused as before; a row an earlier import stored with the doc.asn appended is rewritten to its declared owns by the next import")
fn ! root -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/docSharedOwnsTest-" (stringFromInt64 (procSelf)))

fn ! rm! dir: String -> Bool
  (= (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)).exit 0)

fn srcOf name: String -> String
  (str "asl/packages/pk/src/" name ".asl")

fn docFile -> String
  "asl/packages/pk/doc.asn"

fn rowOf id: String owns: (List String) -> String
  (str "(:u :id " id " :queue conductor :do \"unit " id "\" :owns " (st/qList owns) " :gate \"true\")\n")

fn ledger -> String
  (str (rowOf "A" (list (srcOf "a")))
       (rowOf "B" (list (srcOf "b")))
       (rowOf "C" (list (srcOf "a")))
       (rowOf "D" (list (srcOf "d") (docFile)))
       (rowOf "E" (list (srcOf "e") (docFile))))

fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "docSharedOwnsTest" :ttlMs 600000 :maxWait 50 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! units! store: String -> (List st/Task)
  (resultOr (st/readUnits! store) (list))

fn ! unitOf store: String id: String -> st/Task
  (optionOr (listFind (fn [(u st/Task)] -> Bool (= u.id id)) (units! store))
            (st/Task :id "" :owns (list) :reads (list) :gate "" :channel "" :model "" :base "" :after (list) :st "absent" :epoch 0 :receipt ""))

fn ! stOf store: String id: String -> String
  (match (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! store)) ((some c) c.st) ((none) "absent"))

fn ! leaseOwns store: String id: String -> (List String)
  (match (listFind (fn [(l st/Lease)] -> Bool (= l.id id)) (resultOr (st/readLeases! store) (list))) ((some l) l.owns) ((none) (list "noLease")))

fn ! refusal store: String id: String -> String
  (match (st/claim! store id "docSharedOwnsTest" 600000) ((ok _) "granted") ((err e) e))

; (:m :do "a package tree with an existing doc.asn in an empty git repo, the five rows imported by the real plan import, then two admission passes: the first moves every unit to ready, the second claims")
fn ! testAdmit dir: String -> Bool
  (let [(repo (str dir "/repo"))
        (store (str dir "/store"))
        (_ (dirCreate (str repo "/asl/packages/pk/src")))
        (inited (= (fr/runOneLimited (fr/job (list "git" "init" "-q" "-b" "main" repo) dir (fr/childEnv (list))) (fr/limits 60 4)).exit 0))
        (_ (dirCreate store))
        (_ (fileWrite (str repo "/" (docFile)) "(:doc :symbol \"asl/packages/pk/src/a.asl#old\" :text \"returns one\")\n"))
        (_ (map (fn [(n String)] -> Bool (ok? (fileWrite (str repo "/" (srcOf n)) "x\n"))) (list "a" "b" "d" "e")))
        (_ (fileWrite (cd/repoPath store) (str repo "\n")))
        (imported (pi/plan! (ledger) store "main" false))
        (stored (unitOf store "A"))
        (ctx (ctxOf store))
        (_ (cd/stepAll! ctx (units! store) 8))
        (afterOne (map (fn [(id String)] -> String (stOf store id)) (list "A" "B" "C" "D" "E")))
        (_ (cd/stepAll! ctx (units! store) 8))
        (afterTwo (map (fn [(id String)] -> String (stOf store id)) (list "A" "B" "C" "D" "E")))
        (leaseA (leaseOwns store "A"))
        (leaseB (leaseOwns store "B"))
        (whyB (refusal store "B"))
        (whyC (refusal store "C"))
        (whyE (refusal store "E"))
        (writes (cd/docOwns stored.owns))
        (_ (cd/stopAll! ctx))]
    (do (assert inited "fixture: an empty git repo holds the package tree")
        (assert (match imported ((ok r) (= (listLength r.put) 5)) ((err _) false)) "five rows imported")
        (assert (= afterOne (list "ready" "ready" "ready" "ready" "ready")) (str "the first pass readies every unit: " (stringJoin afterOne ",")))
        (assert (and (= (optionOr (listGet afterTwo 0) "") "writing") (= (optionOr (listGet afterTwo 1) "") "writing"))
                (str "A and B of one package, declared owns disjoint, are both admitted in one pass: " (stringJoin afterTwo ",") " B: " whyB))
        (assert (= stored.owns (list (srcOf "a"))) (str "the store row holds the declared owns only: " (stringJoin stored.owns ",")))
        (assert (stringContains? whyB ":why held ") (str "B holds its own lease: " whyB))
        (assert (and (= leaseA (list (srcOf "a"))) (= leaseB (list (srcOf "b")))) (str "each lease is exclusive over the declared path only: " (stringJoin leaseA ",") " | " (stringJoin leaseB ",")))
        (assert (and (listContains? writes (docFile)) (listContains? writes (cd/cardOf "asl/packages/pk"))) (str "the unit still owns the package doc.asn and card when a stage runs: " (stringJoin writes ",")))
        (assert (= (optionOr (listGet afterTwo 2) "") "ready") (str "C, declaring A's file, is not admitted: " (stringJoin afterTwo ",")))
        (assert (and (stringContains? whyC ":why owns :by \"A\"") (stringContains? whyC (str ":path " (st/q (srcOf "a"))))) (str "C is refused on the declared path A holds: " whyC))
        (assert (and (= (optionOr (listGet afterTwo 3) "") "writing") (= (optionOr (listGet afterTwo 4) "") "ready")) (str "D and E both declare the doc.asn themselves: one is admitted, the other waits: " (stringJoin afterTwo ",")))
        (assert (and (stringContains? whyE ":why owns :by \"D\"") (stringContains? whyE (str ":path " (st/q (docFile))))) (str "E is refused on the doc.asn both rows declare: " whyE))
        true))

; (:m :do "a store row that an import before this change wrote with the doc.asn appended: the next import of the same ledger row, in a repo where that doc.asn exists, rewrites it to the declared owns and journals one refresh, so the lease it takes afterwards no longer excludes its package")
fn ! testLegacy dir: String -> Bool
  (let [(store (str dir "/legacy"))
        (_ (dirCreate (str store "/tasks")))
        (_ (fileWrite (cd/repoPath store) (str dir "/repo\n")))
        (_ (fileWrite (str store "/tasks/A.txt") "unit A"))
        (put (st/put! store (st/Task :id "A" :owns (list (srcOf "a") (docFile)) :reads (list) :gate "true" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt "")))
        (before (unitOf store "A"))
        (again (pi/plan! (rowOf "A" (list (srcOf "a"))) store "main" false))
        (after (unitOf store "A"))
        (journal (resultOr (fileReadString (str store "/journal.asn")) ""))]
    (do (assert (and (ok? put) (= before.owns (list (srcOf "a") (docFile)))) "fixture: a row stored with the doc.asn appended")
        (assert (match again ((ok r) (= r.refreshed (list "A"))) ((err _) false)) "the import refreshes the row")
        (assert (= after.owns (list (srcOf "a"))) (str "the row holds the declared owns again: " (stringJoin after.owns ",")))
        (assert (stringContains? journal "(:refresh :unit \"A\" :changed (owns)") (str "one refresh row names owns: " journal))
        true))

; (:m :do "reload re-reads the row from the ledger of ledger.path and stores what it declares: a unit stored with the doc.asn appended comes back with its declared owns, in a repo where that doc.asn exists")
fn ! testReload dir: String -> Bool
  (let [(store (str dir "/reload"))
        (_ (dirCreate (str store "/tasks")))
        (_ (fileWrite (str store "/tasks/A.txt") "unit A"))
        (_ (fileWrite (cd/repoPath store) (str dir "/repo\n")))
        (_ (fileWrite (str store "/plan.asn") (rowOf "A" (list (srcOf "a")))))
        (_ (fileWrite (cd/ledgerPath store) (str store "/plan.asn\n")))
        (put (st/put! store (st/Task :id "A" :owns (list (srcOf "a") (docFile)) :reads (list) :gate "true" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt "")))
        (asked (cd/requestReload! store (list "A")))
        (done (cd/reloadDrain! (ctxOf store)))
        (after (unitOf store "A"))]
    (do (assert (and (ok? put) (and asked (fileExists? (str dir "/repo/" (docFile))))) "fixture: a stored row with the doc.asn appended, a reload request, the doc.asn in the repo")
        (assert (= done 1) (str "the unit is reloaded: " (stringFromInt64 done)))
        (assert (= after.owns (list (srcOf "a"))) (str "the reloaded row holds the declared owns only: " (stringJoin after.owns ",") " " (resultOr (fileReadString (cd/journalPath store)) "")))
        true))

fn ! runTests -> Bool
  (let [(dir (root))
        (_ (rm! dir))
        (_ (dirCreate dir))
        (admit (testAdmit dir))
        (legacy (testLegacy dir))
        (reload (testReload dir))
        (gone (rm! dir))]
    (do (assert admit "units of one package are admitted together, declared overlaps are refused")
        (assert legacy "a row stored with the doc.asn appended is refreshed to its declared owns")
        (assert reload "a reload stores the declared owns")
        (assert gone "the scratch dir is removed")
        true))
