(module asl-store-fs/support/raceContender
  :x [runTests]
  :i [(asl-store/types :a ty) (asl-store-fs/fs :a fs) (asl-store-fs/log :a lg)])

; (:m :ref VS-CORE :do "one contender of raceTest: without RACE_ROOT it has nothing to do; with it, it waits for the shared start instant, tries to create keys k0..kN with expectRev 0 and writes the keys it won to out.ROLE, so the parent can compare both lists")
fn env name: String -> String
  (optionOr (envGet name) "")

fn ! waitUntil! ns: Int64 -> Unit
  (if (< (nowNs) ns) (do (sleepMs 2) (waitUntil! ns)) ())

fn ! attempt! st: fs/FsStore role: String i: Int64 -> String
  (match (fs/fsCall! st (ty/opCas (ty/Key :collection "race" :id (str "k" (stringFromInt64 i))) 0 role 0 1))
    ((ty/rWritten 1) (str "won k" (stringFromInt64 i) "\n"))
    ((ty/rConflict _) "")
    (r (str "error k" (stringFromInt64 i) "\n")))
fn ! contend! root: String role: String startNs: Int64 keys: Int64 -> Bool
  (match (fs/fsOpen! root 1000)
    ((err e) false)
    ((ok st)
      (let [(_ (waitUntil! startNs))
            (lines (map (fn [(i Int64)] -> String (attempt! st role i)) (range 0 keys)))]
        (ok? (lg/replaceFile! (str root "/out." role) (stringJoin lines ""))))))

fn ! runTests -> Bool
  (let [(root (env "RACE_ROOT"))
        (done (if (stringEmpty? root) true (contend! root (env "RACE_ROLE") (optionOr (stringToInt64 (env "RACE_START_NS")) 0) (optionOr (stringToInt64 (env "RACE_KEYS")) 0))))]
    (do (assert done "the contender opened the store and wrote its result file")
        true))
