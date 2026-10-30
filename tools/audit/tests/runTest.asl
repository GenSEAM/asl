(module asl/tools/audit/tests/runTest
  :x [runTests]
  :i [(asl-tools/audit/run :a ar) (tools/fleet/model :a fm)])

; (:m :ref AUD-RUN :do "fixture repo only: tag v0.0.1, then one commit touching two scoped source files and one test; the stub model call says real to knob prompts only; the run finds 4 candidates over 2 files, flags the 2 knob ones under rule all, writes one row per file, imports dry then for real into a scratch store, and a rerun is skipped by the import")
fn cfgText out: String store: String -> String
  (str "(:audit :v 1 :out " (fm/asnQuote out) " :store " (fm/asnQuote store) " :slice 3\n"
       " :lenses ((:lens knob :queue true :models (m1 m2) :rule all)\n"
       "          (:lens swallow :queue false :models (m1) :rule any)\n"
       "          (:lens stub :queue false :models (m1) :rule any)))\n")

fn srcA1 -> String
  "fn f -> Int64\n  1\n"

fn srcA2 -> String
  (str "fn f -> Int64\n  1\n\nfn ! endpoint! -> String\n  (str \"https://api.vendor.io/v1\")\n\n"
       "fn ! load! p: String -> (Result String String)\n  (match (fileReadString p)\n    ((err _) (ok \"\"))\n    ((ok t) (ok t))))\n")

fn srcB2 -> String
  "; TODO drop the pinned model\nfn g -> String\n  (let [(m \"gpt-5\")] m)\n"

fn ! write! root: String rel: String text: String -> Bool
  (let [(parts (ar/segs rel))
        (_ (fold (fn [(acc String) (p String)] -> String (let [(d (str acc "/" p)) (_ (dirCreate d))] d)) root (listTake parts (- (listLength parts) 1))))]
    (ok? (fileWrite (str root "/" rel) text)))

fn ! gitOk! dir: String args: (List String) -> Bool
  (= (ar/git! dir args).exit 0)

fn ! commit! dir: String msg: String -> Bool
  (and (gitOk! dir (list "add" "-A")) (gitOk! dir (list "-c" "user.email=audit@test" "-c" "user.name=audit" "commit" "-qm" msg)))

fn ! fixtureRepo! root: String -> Bool
  (let [(_ (dirCreate root))
        (a (and (gitOk! root (list "init" "-q")) (and (write! root "asl/packages/pkg/src/a.asl" (srcA1)) (write! root "asl/tools/x/b.asl" "fn g -> Int64\n  2\n"))))
        (b (and a (and (commit! root "base") (gitOk! root (list "tag" "v0.0.1")))))
        (c (and b (and (write! root "asl/packages/pkg/src/a.asl" (srcA2)) (and (write! root "asl/tools/x/b.asl" (srcB2)) (write! root "asl/packages/pkg/tests/aTest.asl" "fn ! runTests -> Bool\n  true\n")))))]
    (and c (commit! root "change")))

fn ! stubCall -> (fn ! [String String] -> (Result String String))
  (fn [(model String) (prompt String)] -> (Result String String)
    (if (and (stringContains? prompt "lens=knob") (or (= model "m1") (= model "m2")))
      (ok "(:verdict :id x :real true :severity medium :why \"literal\")")
      (ok "(:verdict :id x :real false :severity low :why \"intended\")")))

fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/auditRunTest-" name)

fn ! testConfigCheck -> Bool
  (let [(good (ar/parseConfig (cfgText "/tmp/o" "/tmp/s")))
        (topKey (ar/parseConfig "(:audit :v 1 :outt \"x\" :lenses ((:lens knob :models (m) :rule any)))"))
        (lensKey (ar/parseConfig "(:audit :v 1 :lenses ((:lens knob :models (m) :rule any :quue true)))"))
        (badRule (ar/parseConfig "(:audit :v 1 :lenses ((:lens knob :models (m) :rule most)))"))
        (badLens (ar/parseConfig "(:audit :v 1 :lenses ((:lens perf :models (m) :rule any)))"))
        (noModels (ar/parseConfig "(:audit :v 1 :lenses ((:lens knob :rule any)))"))
        (msg (fn [(r (Result ar/AuditCfg String))] -> String (match r ((err e) e) ((ok _) ""))))]
    (do (assert (match good ((ok c) (and (= (listLength c.lenses) 3) (= c.slice 3))) ((err _) false)) (str "a valid config parses: " (msg good)))
        (assert (stringContains? (msg topKey) "unknown key :outt") (str "unknown top key rejected: " (msg topKey)))
        (assert (stringContains? (msg lensKey) "unknown key :quue") (str "unknown lens key rejected: " (msg lensKey)))
        (assert (stringContains? (msg badRule) ":rule must be all or any") (str "bad rule rejected: " (msg badRule)))
        (assert (stringContains? (msg badLens) "unknown lens") (str "unknown lens rejected: " (msg badLens)))
        (assert (stringContains? (msg noModels) ":models is empty") (str "lens without models rejected: " (msg noModels)))
        true))

fn ! testConsensus -> Bool
  (let [(all (ar/Lens :name "knob" :queue true :models (list "a" "b") :rule "all"))
        (any (ar/Lens :name "knob" :queue true :models (list "a" "b") :rule "any"))]
    (do (assert (and (ar/flagged? all (list true true)) (not (ar/flagged? all (list true false)))) "rule all needs every vote")
        (assert (and (ar/flagged? any (list false true)) (not (ar/flagged? any (list false false)))) "rule any needs one vote")
        (assert (not (ar/flagged? all (list))) "no votes never flag")
        true))

fn ! testRun -> Bool
  (let [(root (scratch "run"))
        (_ (pathRemove root))
        (_ (dirCreate root))
        (repo (str root "/repo"))
        (store (str root "/store"))
        (_ (dirCreate store))
        (_ (dirCreate (str root "/out")))
        (built (fixtureRepo! repo))
        (cfg (ar/parseConfig (cfgText (str root "/out/<version>") store)))
        (first (match cfg ((ok c) (ar/run! c repo "" false (stubCall))) ((err e) (err e))))
        (sum (match first ((ok r) r.summary) ((err e) e)))
        (rows (match first ((ok r) r.rows) ((err _) "")))
        (lenses (match first ((ok r) (map (fn [(f ar/Finding)] -> String f.lens) r.findings)) ((err _) (list))))
        (tasks (and (fileExists? (str store "/tasks/AUD-v001-pkg-a.txt")) (fileExists? (str store "/tasks/AUD-v001-x-b.txt"))))
        (second (match cfg ((ok c) (ar/run! c repo "" false (stubCall))) ((err e) (err e))))
        (sum2 (match second ((ok r) r.summary) ((err e) e)))
        (outDir (match first ((ok r) (optionOr (match (stringIndexOf r.summary ":out \"") ((some i) (stringSlice r.summary (+ i 6) (- (stringLength r.summary) 2))) ((none) (none))) "")) ((err _) "")))
        (runs (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:auditRun ")) (stringLines (resultOr (fileReadString (str outDir "/summary.asn")) "")))))
        (prompt (ar/promptOf (ar/Finding :id "knob-0001" :lens "knob" :file "a.asl" :line 5 :symbol "endpoint!" :ret "String" :severity "low" :claim "c" :evidence "e") (srcA2) 1))
        (_ (pathRemove root))]
    (do (assert built "fixture repo with tag v0.0.1 and one change commit")
        (assert (ok? first) (str "run: " sum))
        (assert (stringContains? sum ":range \"v0.0.1..") (str "range starts at the last tag: " sum))
        (assert (stringContains? sum ":files 2 ") (str "two scoped files, the test file excluded: " sum))
        (assert (= (listSort lenses) (list "knob" "knob" "stub" "swallow")) (str "candidates per lens: " (stringJoin lenses ",")))
        (assert (stringContains? sum ":flagged 2 :queued 2 :rows 2 ") (str "knob votes flag 2 under rule all, one row per file: " sum))
        (assert (and (stringContains? rows ":id AUD-v001-pkg-a ") (stringContains? rows ":owns (\"asl/packages/pkg/src/a.asl\" \"asl/packages/pkg/tests/aAuditTest.asl\")")) (str "row id, owns and gate test path: " rows))
        (assert (not (stringContains? rows "swallow")) (str "the unflagged swallow finding is not queued: " rows))
        (assert (stringContains? sum ":dry (:import :put (\"AUD-v001-pkg-a\" \"AUD-v001-x-b\")") (str "dry import would put both rows: " sum))
        (assert tasks "the real import wrote both tasks to the store")
        (assert (stringContains? sum2 ":import (:import :put () :skipped (\"AUD-v001-pkg-a\" \"AUD-v001-x-b\")") (str "a rerun is skipped by the import: " sum2))
        (assert (= runs 2) (str "one summary row per run: " (stringFromInt64 runs)))
        (assert (and (stringContains? prompt "4| fn ! endpoint! -> String") (and (stringContains? prompt "lens=knob") (not (stringContains? prompt "7| ")))) (str "prompt carries the bounded slice only: " prompt))
        true))

fn ! testDry -> Bool
  (let [(root (scratch "dry"))
        (_ (pathRemove root))
        (_ (dirCreate root))
        (repo (str root "/repo"))
        (store (str root "/store"))
        (_ (dirCreate store))
        (_ (dirCreate (str root "/out")))
        (built (fixtureRepo! repo))
        (r (match (ar/parseConfig (cfgText (str root "/out/<version>") store)) ((ok c) (ar/run! c repo "v0.0.1" true (stubCall))) ((err e) (err e))))
        (sum (match r ((ok x) x.summary) ((err e) e)))
        (none (not (fileExists? (str store "/tasks/AUD-v001-pkg-a.txt"))))
        (_ (pathRemove root))]
    (do (assert built "dry fixture built")
        (assert (and (stringContains? sum ":dry (:import :put (\"AUD-v001-pkg-a\"") (stringContains? sum ":import skipped")) (str "--dry stops after the dry import: " sum))
        (assert none "and writes no task")
        true))

fn ! runTests -> Bool
  (do (assert (testConfigCheck) "config check")
      (assert (testConsensus) "consensus rule")
      (assert (testRun) "fixture run")
      (assert (testDry) "dry run")
      true)
