(module asl-tools/coord/tests/docSharedOwnsTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/planImport :a pi) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr)])

; (:m :ref COND-OWNS-DOC-SERIALISES :do "the paths the conductor adds to a unit's owns (the package doc.asn and its asl-know card) are a right to write, not part of the exclusive lease: units of one package whose declared owns are disjoint are admitted in the same pass and each still owns the doc.asn at its stages; units whose declared owns overlap on any other path are refused as before; a row an earlier import stored with the doc.asn appended is rewritten to its declared owns by the next import")
; (:m :ref COND-DOC-CLAIM-SHARED :do "a claim never clashes on a shared path (st/sharedPath?: a package doc.asn, an asl-know card, missing.asn), whether the row declares it, the conductor added it or an old lease still lists it, on either side of the comparison; every other path, asl/doc/tools.asn and a doc.asn under src included, stays exclusive. Each case has its own scratch dir, removed before its assertions run")
fn ! root name: String -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/docSharedOwnsTest-" (stringFromInt64 (procSelf)) "-" name)

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

; (:m :do "the package tree of the fixture, its doc.asn and src files, in an empty git repo under dir")
fn ! repo! dir: String -> Bool
  (let [(repo (str dir "/repo"))
        (_ (dirCreate (str repo "/asl/packages/pk/src")))
        (inited (= (fr/runOneLimited (fr/job (list "git" "init" "-q" "-b" "main" repo) dir (fr/childEnv (list))) (fr/limits 60 4)).exit 0))
        (doc (ok? (fileWrite (str repo "/" (docFile)) "(:doc :symbol \"asl/packages/pk/src/a.asl#old\" :text \"returns one\")\n")))
        (srcs (map (fn [(n String)] -> Bool (ok? (fileWrite (str repo "/" (srcOf n)) "x\n"))) (list "a" "b" "d" "e")))]
    (and inited (and doc (listAll? (fn [(b Bool)] -> Bool b) srcs))))

; (:m :do "put one queued unit with these owns and reads, then try to claim it: granted or the refusal row")
fn ! putClaim! store: String id: String owns: (List String) reads: (List String) -> String
  (match (st/put! store (st/Task :id id :owns owns :reads reads :gate "true" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt ""))
    ((err e) (str "put: " e))
    ((ok _) (refusal store id)))

fn refusedOn? why: String by: String path: String -> Bool
  (and (stringContains? why (str ":why owns :by " (st/q by))) (stringContains? why (str ":path " (st/q path))))

; (:m :do "a package tree with an existing doc.asn in an empty git repo, the five rows imported by the real plan import, then two admission passes: the first moves every unit to ready, the second claims")
fn ! testAdmit -> Bool
  (let [(dir (root "admit"))
        (_ (rm! dir))
        (_ (dirCreate dir))
        (repo (str dir "/repo"))
        (store (str dir "/store"))
        (inited (repo! dir))
        (_ (dirCreate store))
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
        (leaseE (leaseOwns store "E"))
        (writes (cd/docOwns stored.owns))
        (_ (cd/stopAll! ctx))
        (gone (rm! dir))]
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
        (assert (and (= (optionOr (listGet afterTwo 3) "") "writing") (= (optionOr (listGet afterTwo 4) "") "writing")) (str "D and E both declare the doc.asn themselves and are admitted in one pass: " (stringJoin afterTwo ",") " E: " whyE))
        (assert (and (stringContains? whyE ":why held ") (= leaseE (list (srcOf "e") (docFile)))) (str "E holds its own lease, the declared doc.asn in it: " whyE " | " (stringJoin leaseE ",")))
        (assert gone "the scratch dir of the admission case is removed")
        true))

; (:m :do "the store alone, one put and one claim per unit, leases staying live: an old lease and an old row that both list the doc.asn; a unit whose only path is the doc.asn; a card and missing.asn two units declare; a holder of the whole package dir against a claimant of its doc.asn and the reverse (the skip on each side); a doc.asn the holder only reads; and the paths that stay exclusive")
fn ! testStore -> Bool
  (let [(store (root "store"))
        (_ (rm! store))
        (_ (dirCreate store))
        (card "asl/packages/asl-know/cards/x.asn")
        (missing "asl/packages/asl-know/missing.asn")
        (tools "asl/doc/tools.asn")
        (srcDoc "asl/packages/x/src/doc.asn")
        (oldHolder (putClaim! store "H1" (list (srcOf "a") (docFile)) (list)))
        (oldLease (leaseOwns store "H1"))
        (oldRow (putClaim! store "P1" (list (srcOf "b") (docFile)) (list)))
        (srcClash (putClaim! store "P2" (list (srcOf "a")) (list)))
        (docOnly (putClaim! store "F1" (list (docFile)) (list)))
        (afterDocOnly (putClaim! store "F2" (list (srcOf "f") (docFile)) (list)))
        (cardOne (putClaim! store "G1" (list card) (list)))
        (cardTwo (putClaim! store "G2" (list card) (list)))
        (missOne (putClaim! store "M1" (list missing) (list)))
        (missTwo (putClaim! store "M2" (list missing) (list)))
        (toolsOne (putClaim! store "T1" (list tools) (list)))
        (toolsTwo (putClaim! store "T2" (list tools) (list)))
        (srcDocOne (putClaim! store "S1" (list srcDoc) (list)))
        (srcDocTwo (putClaim! store "S2" (list srcDoc) (list)))
        (dirHolder (putClaim! store "W1" (list "asl/packages/pw/") (list)))
        (docUnderDir (putClaim! store "W2" (list "asl/packages/pw/doc.asn") (list)))
        (srcUnderDir (putClaim! store "W3" (list "asl/packages/pw/src/y.asl") (list)))
        (docHolder (putClaim! store "Q1" (list "asl/packages/pq/doc.asn") (list)))
        (dirOverDoc (putClaim! store "Q2" (list "asl/packages/pq/") (list)))
        (readsDoc (putClaim! store "R1" (list "asl/packages/pr/src/r1.asl") (list "asl/packages/pr/doc.asn")))
        (ownsReadDoc (putClaim! store "R2" (list "asl/packages/pr/src/r2.asl" "asl/packages/pr/doc.asn") (list)))
        (readsHeldSrc (putClaim! store "R3" (list "asl/packages/pr/src/r3.asl") (list "asl/packages/pr/src/r1.asl")))
        (gone (rm! store))]
    (do (assert (and (= oldHolder "granted") (= oldLease (list (srcOf "a") (docFile)))) (str "fixture: a live lease that lists the package doc.asn: " oldHolder " | " (stringJoin oldLease ",")))
        (assert (= oldRow "granted") (str "a row stored with the doc.asn is claimed while an old lease lists the same doc.asn: " oldRow))
        (assert (refusedOn? srcClash "H1" (srcOf "a")) (str "a src path a live lease holds is still refused: " srcClash))
        (assert (= docOnly "granted") (str "a unit whose only path is the package doc.asn is claimed: " docOnly))
        (assert (= afterDocOnly "granted") (str "the doc.asn-only unit keeps no unit of its package out: " afterDocOnly))
        (assert (and (= cardOne "granted") (= cardTwo "granted")) (str "an asl-know card two units declare is claimed by both: " cardOne " | " cardTwo))
        (assert (and (= missOne "granted") (= missTwo "granted")) (str "missing.asn two units declare is claimed by both: " missOne " | " missTwo))
        (assert (and (= toolsOne "granted") (refusedOn? toolsTwo "T1" tools)) (str "asl/doc/tools.asn stays exclusive: " toolsOne " | " toolsTwo))
        (assert (and (= srcDocOne "granted") (refusedOn? srcDocTwo "S1" srcDoc)) (str "a doc.asn under src is no package contract and stays exclusive: " srcDocOne " | " srcDocTwo))
        (assert (and (= dirHolder "granted") (= docUnderDir "granted")) (str "the claimant's doc.asn is skipped against a holder of the whole package dir: " dirHolder " | " docUnderDir))
        (assert (refusedOn? srcUnderDir "W1" "asl/packages/pw/src/y.asl") (str "a src file under a held package dir is still refused: " srcUnderDir))
        (assert (and (= docHolder "granted") (= dirOverDoc "granted")) (str "the holder's doc.asn is skipped against a claimant of the whole package dir: " docHolder " | " dirOverDoc))
        (assert (and (= readsDoc "granted") (= ownsReadDoc "granted")) (str "a doc.asn the holder reads does not refuse its writer: " readsDoc " | " ownsReadDoc))
        (assert (refusedOn? readsHeldSrc "R1" "asl/packages/pr/src/r1.asl") (str "reading a src file a live lease owns is still refused: " readsHeldSrc))
        (assert gone "the scratch dir of the store case is removed")
        true))

; (:m :do "a store row that an import before this change wrote with the doc.asn appended: the next import of the same ledger row, in a repo where that doc.asn exists, rewrites it to the declared owns and journals one refresh, so the lease it takes afterwards no longer excludes its package")
fn ! testLegacy -> Bool
  (let [(dir (root "legacy"))
        (_ (rm! dir))
        (_ (dirCreate dir))
        (inited (repo! dir))
        (store (str dir "/legacy"))
        (_ (dirCreate (str store "/tasks")))
        (_ (fileWrite (cd/repoPath store) (str dir "/repo\n")))
        (_ (fileWrite (str store "/tasks/A.txt") "unit A"))
        (put (st/put! store (st/Task :id "A" :owns (list (srcOf "a") (docFile)) :reads (list) :gate "true" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt "")))
        (before (unitOf store "A"))
        (again (pi/plan! (rowOf "A" (list (srcOf "a"))) store "main" false))
        (after (unitOf store "A"))
        (journal (resultOr (fileReadString (str store "/journal.asn")) ""))
        (gone (rm! dir))]
    (do (assert (and inited (and (ok? put) (= before.owns (list (srcOf "a") (docFile))))) "fixture: a row stored with the doc.asn appended")
        (assert (match again ((ok r) (= r.refreshed (list "A"))) ((err _) false)) "the import refreshes the row")
        (assert (= after.owns (list (srcOf "a"))) (str "the row holds the declared owns again: " (stringJoin after.owns ",")))
        (assert (stringContains? journal "(:refresh :unit \"A\" :changed (owns)") (str "one refresh row names owns: " journal))
        (assert gone "the scratch dir of the legacy case is removed")
        true))

; (:m :do "reload re-reads the row from the ledger of ledger.path and stores what it declares: a unit stored with the doc.asn appended comes back with its declared owns, in a repo where that doc.asn exists")
fn ! testReload -> Bool
  (let [(dir (root "reload"))
        (_ (rm! dir))
        (_ (dirCreate dir))
        (inited (repo! dir))
        (store (str dir "/reload"))
        (_ (dirCreate (str store "/tasks")))
        (_ (fileWrite (str store "/tasks/A.txt") "unit A"))
        (_ (fileWrite (cd/repoPath store) (str dir "/repo\n")))
        (_ (fileWrite (str store "/plan.asn") (rowOf "A" (list (srcOf "a")))))
        (_ (fileWrite (cd/ledgerPath store) (str store "/plan.asn\n")))
        (put (st/put! store (st/Task :id "A" :owns (list (srcOf "a") (docFile)) :reads (list) :gate "true" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt "")))
        (asked (cd/requestReload! store (list "A")))
        (done (cd/reloadDrain! (ctxOf store)))
        (after (unitOf store "A"))
        (docThere (fileExists? (str dir "/repo/" (docFile))))
        (journal (resultOr (fileReadString (cd/journalPath store)) ""))
        (gone (rm! dir))]
    (do (assert (and inited (and (ok? put) (and asked docThere))) "fixture: a stored row with the doc.asn appended, a reload request, the doc.asn in the repo")
        (assert (= done 1) (str "the unit is reloaded: " (stringFromInt64 done)))
        (assert (= after.owns (list (srcOf "a"))) (str "the reloaded row holds the declared owns only: " (stringJoin after.owns ",") " " journal))
        (assert gone "the scratch dir of the reload case is removed")
        true))

fn ! runTests -> Bool
  (let [(admit (testAdmit))
        (store (testStore))
        (legacy (testLegacy))
        (reload (testReload))]
    (do (assert admit "units of one package are admitted together, a declared doc.asn included; a declared src overlap is refused")
        (assert store "a claim never clashes on a shared path, every other path stays exclusive")
        (assert legacy "a row stored with the doc.asn appended is refreshed to its declared owns")
        (assert reload "a reload stores the declared owns")
        true))
