(module asl-store-fs/tests/raceTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-store/types :a ty) (asl-store-fs/fs :a fs)])

; (:m :ref VS-CORE :do "two real processes, started only through asl/tools/fleet/run.asl with a 150 s deadline and a descendant limit, race to create the same 40 keys with expectRev 0 after a shared start instant; the flock makes exactly one of them win each key and the stored row is the winner's")
fn keysCount -> Int64
  40

fn ! scratch -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/raceTest-" (stringFromInt64 (procSelf)))

fn ! rmTree! p: String -> Unit
  (match (fileStat p)
    ((err _) ())
    ((ok st) (let [(_ (if st.isDir (map (fn [(n String)] -> Unit (rmTree! (str p "/" n))) (resultOr (dirList p) (list))) (list)))
                   (_ (pathRemove p))]
               ())))

fn ! childJob! root: String dir: String role: String startNs: Int64 -> fr/Job
  (fr/job (list "nice" "-n" "10" (fr/nativeCliFor root) "test" "asl/packages/asl-store-fs/support/raceContender.asl")
          root
          (listAppend (fr/sideEnv root) (list (str "RACE_ROOT=" dir) (str "RACE_ROLE=" role) (str "RACE_START_NS=" (stringFromInt64 startNs)) (str "RACE_KEYS=" (stringFromInt64 (keysCount))))))

fn winsOf text: String -> (List String)
  (map (fn [(l String)] -> String (optionOr (stringSlice l 4 (stringLength l)) "")) (filter (fn [(l String)] -> Bool (stringStartsWith? l "won ")) (stringLines text)))

fn ! winnerValue! st: fs/FsStore key: String -> String
  (match (fs/fsCall! st (ty/opGet (ty/Key :collection "race" :id key) 1))
    ((ty/rValue 1 v _) v)
    (_ ""))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (dir (scratch))
        (_ (rmTree! dir))
        (opened (fs/fsOpen! dir 1000))
        (startNs (+ (nowNs) 6000000000))
        (done (fr/runPoolLimited (list (childJob! root dir "A" startNs) (childJob! root dir "B" startNs)) 2 (fr/limits 150 32)))
        (a (winsOf (resultOr (fileReadString (str dir "/out.A")) "")))
        (b (winsOf (resultOr (fileReadString (str dir "/out.B")) "")))
        (keys (map (fn [(i Int64)] -> String (str "k" (stringFromInt64 i))) (range 0 (keysCount))))
        (both (filter (fn [(k String)] -> Bool (and (listContains? a k) (listContains? b k))) keys))
        (neither (filter (fn [(k String)] -> Bool (and (not (listContains? a k)) (not (listContains? b k)))) keys))
        (wrongRow (match opened
                    ((ok st) (filter (fn [(k String)] -> Bool (not (= (winnerValue! st k) (if (listContains? a k) "A" "B")))) keys))
                    ((err _) keys)))
        (exits (map (fn [(d fr/Done)] -> Int64 d.exit) done))
        (_ (rmTree! dir))]
    (do (assert (and (= (listLength done) 2) (listAll? (fn [(x Int64)] -> Bool (= x 0)) exits)) (str "both contenders exited 0: " (stringJoin (map (fn [(d fr/Done)] -> String (str (stringFromInt64 d.exit) " " d.verdict " " d.out)) done) " | ")))
        (assert (listEmpty? both) (str "keys won by both processes: " (stringJoin both " ")))
        (assert (listEmpty? neither) (str "keys won by neither process: " (stringJoin neither " ")))
        (assert (= (+ (listLength a) (listLength b)) (keysCount)) "exactly one winner per key across the two processes")
        (assert (listEmpty? wrongRow) (str "stored value differs from the winner for: " (stringJoin wrongRow " ")))
        true))
