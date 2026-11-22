(module asl-tools/coord/tests/rebriefTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref COND-REBRIEF :do "the operator verbs rebrief and remodel on a seeded store: a blocked unit gets a new brief, gate and owns from an ASN row and goes to queued with its old digest journalled, a remodel names the tier or the alias of the next attempts, and both refuse a unit that is writing or merging")
fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "rebriefTest" :ttlMs 600000 :maxWait 30 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! cuOf! dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) (pf/cuIn id "missing" "" ""))

fn ! unitOf! dir: String id: String -> st/Task
  (optionOr (listFind (fn [(u st/Task)] -> Bool (= u.id id)) (resultOr (st/readUnits! dir) (list))) (pf/unitIn "missing" ""))

fn ! seed! dir: String id: String stateName: String c: cd/CUnit -> Bool
  (let [(_ (st/put! dir (pf/unitIn id "true")))
        (_ (dirCreate (str dir "/tasks")))
        (_ (fileWrite (str dir "/tasks/" id ".txt") (str "old task of " id)))]
    (ok? (cd/writeCUnit! dir (with c :st stateName))))

fn ! journal dir: String -> String
  (readOr (str dir "/journal.asn"))

fn ! testRebrief root: String -> Bool
  (let [(dir (str root "/rb"))
        (_ (dirCreate root))
        (_ (dirCreate dir))
        (rows (str root "/new.asn"))
        (_ (fileWrite rows (str "(:u :id R1 :auto true :do \"new task of R1\" :owns (\"b.txt\") :gate \"./bin/asl test b.asl\")\n"
                                "(:u :id W1 :auto true :do \"new task of W1\" :owns (\"w.txt\") :gate \"true\")\n"
                                "(:u :id C1 :auto true :do \"clashing\" :owns (\"held.txt\") :gate \"true\")\n"
                                "(:u :id M1 :auto true :do \"new task of M1\" :owns (\"m.txt\") :gate \"true\")\n")))
        (base (pf/cuIn "X" "ready" "" ""))
        (_ (seed! dir "R1" "blocked" (with base :id "R1" :fails 3 :esc 1 :sig "vacuousGate: gate passes on the base" :waited 4)))
        (_ (seed! dir "W1" "writing" (with base :id "W1")))
        (_ (seed! dir "M1" "merging" (with base :id "M1")))
        (_ (seed! dir "C1" "blocked" (with base :id "C1" :sig "z")))
        (_ (st/put! dir (with (pf/unitIn "L1" "true") :owns (list "held.txt"))))
        (_ (st/claim! dir "L1" "t" 600000))
        (_ (dirCreate (str dir "/remodel")))
        (_ (fileWrite (cd/remodelAliasPath dir "R1") "flashLow\n"))
        (oldR1 (cd/unitDigest! dir (unitOf! dir "R1")))
        (asked (cd/requestRebrief! dir (list "R1" "W1" "M1" "C1") rows))
        (done (cd/rebriefDrain! (ctxOf dir)))
        (r1 (cuOf! dir "R1"))
        (u1 (unitOf! dir "R1"))
        (j (journal dir))
        (noRow (cd/requestRebrief! dir (list "R1") (str root "/absent.asn")))]
    (do (assert asked "the rebrief request is written")
        (assert (= done 1) (str "only R1 is rebriefed, the writing and merging units are refused: " (stringFromInt64 done)))
        (assert (= r1.st "queued") (str "the blocked unit goes to queued: " r1.st))
        (assert (and (= r1.fails 0) (and (= r1.esc 0) (and (= r1.waited 0) (= r1.sig "")))) (str "its counters are clean: " (stringFromInt64 r1.fails) " " r1.sig))
        (assert (= u1.gate "./bin/asl test b.asl") (str "the stored gate is the row's: " u1.gate))
        (assert (= u1.owns (list "b.txt")) (str "the stored owns are the row's: " (stringJoin u1.owns ",")))
        (assert (= (readOr (str dir "/tasks/R1.txt")) "new task of R1") "the task text is the row's")
        (assert (stringContains? j (str "(:rebrief :unit \"R1\" :old " (st/q oldR1) " :new ")) (str "the old digest is journalled: " j))
        (assert (not (stringContains? j (str "(:rebrief :unit \"R1\" :old " (st/q oldR1) " :new " (st/q oldR1)))) "and the new digest differs")
        (assert (and (stringContains? j "(:rebrief :unit \"W1\" :refused \"writing\" ") (stringContains? j "(:rebrief :unit \"M1\" :refused \"merging\" ")) (str "a writing and a merging unit are refused with their state: " j))
        (assert (and (= (cuOf! dir "W1").st "writing") (= (unitOf! dir "W1").gate "true") (= (readOr (str dir "/tasks/W1.txt")) "old task of W1")) "the writing unit keeps its definition")
        (assert (and (= (cuOf! dir "M1").st "merging") (= (readOr (str dir "/tasks/M1.txt")) "old task of M1")) "the merging unit keeps its definition")
        (assert (stringContains? j "(:rebrief :unit \"C1\" :refused \"owns clash") (str "new :owns that clash with a live lease are refused at once: " j))
        (assert (= (cuOf! dir "C1").st "blocked") "and the unit stays blocked")
        (assert (not (fileExists? (cd/remodelAliasPath dir "R1"))) "a rebrief drops the alias pin")
        (assert (let [(olds (filter (fn [(f String)] -> Bool (stringContains? f "R1.old-")) (resultOr (dirList (str dir "/rebrief")) (list))))] (and (= (listLength olds) 1) (let [(t (readOr (str dir "/rebrief/" (optionOr (listHead olds) ""))))] (and (stringContains? t "old task of R1") (stringContains? t ":gate \"true\""))))) "the old task text and unit row are kept in rebrief/R1.old-MS.asn")
        (assert (not noRow) "a row file that is missing is no request")
        true))

fn ! testRemodel root: String -> Bool
  (let [(dir (str root "/rm"))
        (_ (dirCreate dir))
        (base (pf/cuIn "X" "ready" "" ""))
        (_ (seed! dir "A1" "blocked" (with base :id "A1" :lane "free" :sig "x")))
        (_ (seed! dir "T1" "blocked" (with base :id "T1" :lane "free" :sig "y")))
        (_ (seed! dir "W1" "writing" (with base :id "W1" :lane "free")))
        (asked (and (cd/requestRemodel! dir (list "A1" "W1") "" "flashLow" false (pf/gatewayText) (pf/lanesText)) (cd/requestRemodel! dir (list "T1") "strong" "" false (pf/gatewayText) (pf/lanesText))))
        (none (cd/requestRemodel! dir (list "A1") "" "" false (pf/gatewayText) (pf/lanesText)))
        (badTier (cd/requestRemodel! dir (list "A1") "strng" "" false (pf/gatewayText) (pf/lanesText)))
        (badAlias (cd/requestRemodel! dir (list "A1") "" "flashLw" false (pf/gatewayText) (pf/lanesText)))
        (famAlias (cd/requestRemodel! dir (list "T1") "" "ocLongcat" false (pf/gatewayText) (pf/lanesText)))
        (prefixTypo (cd/requestRemodel! dir (list "T1") "" "ocLongcatX" false (pf/gatewayText) (pf/lanesText)))
        (noGateway (cd/requestRemodel! dir (list "T1") "" "flashLow" false "" (pf/lanesText)))
        (done (cd/remodelDrain! (ctxOf dir)))
        (j (journal dir))
        (rc (cd/realCfg (list "--repo" (str root "/repo") "--home" (str root "/home") "--worktrees" (str root "/wts")) dir))
        (pinA (cd/pinExtra (cd/remodelCfg rc dir "A1") ""))
        (pinT (cd/pinExtra (cd/remodelCfg rc dir "T1") ""))
        (pinW (cd/pinExtra (cd/remodelCfg rc dir "W1") ""))]
    (do (assert (and asked (not none)) "remodel needs a tier or an alias")
        (assert (= done 3) (str "A1 and T1 (tier, then family alias) are remodelled, the writing W1 is refused: " (stringFromInt64 done)))
        (assert (= pinA ":model \"flashLow\"") (str "the next write of A1 is pinned to the alias: " pinA))
        (assert (and (= pinT ":model \"ocLongcat\"") (= pinW "")) (str "T1 got its family alias, W1 keeps the profile chain: " pinT " " pinW))
        (assert (and (= (cuOf! dir "T1").lane "strong") (= (unitOf! dir "T1").channel "strong")) (str "the tier is the unit's lane and channel: " (cuOf! dir "T1").lane))
        (assert (= (cuOf! dir "A1").st "blocked") "a remodel changes no state, requeue does")
        (assert (and (stringContains? j "(:remodel :unit \"A1\" :alias \"flashLow\" ") (stringContains? j "(:remodel :unit \"T1\" :tier \"strong\" :was \"free\" ")) (str "both are journalled: " j))
        (assert (stringContains? j "(:remodel :unit \"W1\" :refused \"writing\" ") (str "the writing unit is refused with its state: " j))
        (assert (= (cuOf! dir "W1").st "writing") "the writing unit is left alone")
        (assert (and (not badTier) (not badAlias)) "a tier outside writeTiers and an alias nobody knows are refused")
        (assert (and (stringContains? j "(:remodel :unit \"A1\" :refused \"tier strng is not one of free paid strong lead\"") (stringContains? j "(:remodel :unit \"A1\" :refused \"alias flashLw is not a gateway model id\"")) (str "and journalled: " j))
        (assert (and (not prefixTypo) (not noGateway) (stringContains? (journal dir) "alias ocLongcatX is not a gateway model id") (stringContains? (journal dir) "no gateway.asn to check it against")) "a typo of the same family prefix is rejected, and a missing gateway.asn fails closed with the reason journalled")
        (assert famAlias "a gateway model id is accepted")
        (assert (let [(_ (cd/requestRemodel! dir (list "A1") "" "" true "" ""))] (let [(_ (cd/remodelDrain! (ctxOf dir)))] (and (= (cd/remodelAliasOf dir "A1") "") (not (fileExists? (cd/remodelAliasPath dir "A1")))))) "remodel --clear drops the pin")
        (assert (let [(_ (cd/requestRemodel! dir (list "T1") "" "flashLow" false (pf/gatewayText) (pf/lanesText)))] (let [(_ (cd/remodelDrain! (ctxOf dir)))] (let [(c (cuOf! dir "T1"))] (let [(_ (cd/moveA! (ctxOf dir) c "merged" "merge" "" "" 0 0 "ok" 0))] (not (fileExists? (cd/remodelAliasPath dir "T1"))))))) "a merge drops the pin")
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "rebrief" "t"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (a (testRebrief root))
        (b (testRemodel root))
        (_ (pf/cleanup root))]
    (do (assert a "rebrief")
        (assert b "remodel")
        true))
