(module asl-tools/coord/leadStream
  :x [Cfg Ev defaultCfg cfgAt nodeName! sevRank renderEv evOf rotate emit! emitAt! ack! act! digest! pendingActs! actDone! main]
  :i [(asl-syntax/asl/asn :a asn) (asl-tools/coord/store :a st)])

; (:m :ref LEAD-STREAM :do "the node's escalation stream to the controlling agent: one file ~/.asl/run/lead/stream.asn of (:ev ...) rows (src nodeWatch|janitor|conductor|mergeCheck, sev info|warn|act) and (:act ...) operator rows; every write is one flock'd read-modify-write landed by tmp+rename, a repeat of an unacked src+kind+key inside dedupeS bumps :count instead of adding a row, the file is cut to maxRows (acked rows first, then oldest); the lead pulls it with `digest` over ssh, nothing is pushed and no writer ever blocks on it")
(schema Cfg
  (:f dir String)
  (:f node String)
  (:f dedupeS Int64)
  (:f maxRows Int64))

(schema Ev
  (:f id String)
  (:f at Int64)
  (:f last Int64)
  (:f node String)
  (:f src String)
  (:f sev String)
  (:f kind String)
  (:f key String)
  (:f unit String)
  (:f why String)
  (:f count Int64)
  (:f ack Bool))

(schema Group
  (:f kind String)
  (:f sev String)
  (:f rows Int64)
  (:f count Int64)
  (:f last Int64)
  (:f why String))

fn ! home! -> String
  (optionOr (envGet "HOME") "/tmp")

fn ! nodeName! -> String
  (let [(f (stringTrim (resultOr (fileReadString "/etc/hostname") "")))]
    (if (stringEmpty? f) (optionOr (envGet "HOSTNAME") "node") f))

fn cfgAt runDir: String node: String -> Cfg
  (Cfg :dir (str runDir "/lead") :node node :dedupeS 3600 :maxRows 500)

fn ! defaultCfg -> Cfg
  (cfgAt (str (home!) "/.asl/run") (nodeName!))

fn sevRank s: String -> Int64
  (cond ((= s "act") 2) ((= s "warn") 1) (else 0))

fn sevName n: Int64 -> String
  (cond ((>= n 2) "act") ((= n 1) "warn") (else "info"))

fn bool b: Bool -> String
  (if b "true" "false")

fn int n: Int64 -> String
  (stringFromInt64 n)

fn tok s: String -> String
  (let [(t (stringJoin (filter (fn [(c String)] -> Bool (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" c)) (stringChars s)) ""))]
    (if (stringEmpty? t) "unknown" t))

fn clip s: String n: Int64 -> String
  (if (> (stringLength s) n) (optionOr (stringSlice s 0 n) s) s)

fn streamPath cfg: Cfg -> String
  (str cfg.dir "/stream.asn")

fn renderEv e: Ev -> String
  (str "(:ev :id " (st/q e.id) " :at " (int e.at) " :last " (int e.last) " :node " (st/q e.node) " :src " e.src " :sev " e.sev " :kind " e.kind
       " :key " (st/q e.key) (if (stringEmpty? e.unit) "" (str " :unit " (st/q e.unit))) " :why " (st/q e.why) " :count " (int e.count) " :ack " (bool e.ack) ")")

fn evOf line: String -> (Option Ev)
  (match (st/rowFields line "ev")
    ((err _) (none))
    ((ok fs)
      (if (stringEmpty? (st/textField fs "id")) (none)
        (some (Ev :id (st/textField fs "id") :at (st/intField fs "at") :last (st/intField fs "last") :node (st/textField fs "node")
                  :src (st/textField fs "src") :sev (st/textField fs "sev") :kind (st/textField fs "kind") :key (st/textField fs "key")
                  :unit (st/textField fs "unit") :why (st/textField fs "why") :count (st/intField fs "count")
                  :ack (stringEndsWith? (stringTrim line) " :ack true)"))))))

fn actFields line: String -> (Option (List asn/AsnField))
  (match (st/rowFields line "act") ((err _) (none)) ((ok fs) (some fs)))

fn renderAct id: String at: Int64 node: String target: String do: String done: Bool -> String
  (str "(:act :id " (st/q id) " :at " (int at) " :node " (st/q node) " :target " (st/q target) " :do " do " :done " (bool done) ")")

fn doneLine? line: String -> Bool
  (match (evOf line)
    ((some e) e.ack)
    ((none) (match (actFields line) ((some fs) (stringEndsWith? (stringTrim line) " :done true)")) ((none) false))))

fn ! readLines! cfg: Cfg -> (List String)
  (match (fileReadString (streamPath cfg))
    ((err _) (list))
    ((ok text) (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines text))))

; (:m :ref LEAD-STREAM :do "bound: over maxRows, finished rows (acked events, done acts) go first oldest first, then the oldest rows of any kind")
fn rotate maxRows: Int64 lines: (List String) -> (List String)
  (let [(over (- (listLength lines) maxRows))]
    (if (<= over 0) lines
      (let [(pass (listReverse (pairSecond (fold (fn [(a (Pair Int64 (List String))) (l String)] -> (Pair Int64 (List String))
                                                   (if (and (> (pairFirst a) 0) (doneLine? l))
                                                     (pair (- (pairFirst a) 1) (pairSecond a))
                                                     (pair (pairFirst a) (cons l (pairSecond a)))))
                                                 (pair over (list)) lines))))
            (left (- (listLength pass) maxRows))]
        (if (> left 0) (listDrop pass left) pass))))

fn ! writeAtomic! path: String text: String -> (Result Unit String)
  (let [(tmp (str path "." (int (procSelf)) "." (int (nowNs)) ".tmp"))]
    (match (fileWrite tmp (str text "\n"))
      ((err e) (err e))
      ((ok _) (match (pathRename tmp path)
                ((ok _) (ok ()))
                ((err e) (let [(_ (pathRemove tmp))] (err e)))))))

fn ! mutateLocked! cfg: Cfg step: (fn [(List String)] -> (Pair (List String) String)) -> (Result String String)
  (let [(out (step (readLines! cfg)))]
    (match (writeAtomic! (streamPath cfg) (stringJoin (rotate cfg.maxRows (pairFirst out)) "\n"))
      ((err e) (err e))
      ((ok _) (ok (pairSecond out)))))

fn ! mutate! cfg: Cfg step: (fn [(List String)] -> (Pair (List String) String)) -> (Result String String)
  (match (dirCreate cfg.dir)
    ((err e) (err e))
    ((ok _) (match (fileLockWait (str cfg.dir "/.lock") true 10000)
      ((err e) (err (str "lead lock: " e)))
      ((ok fd) (let [(r (mutateLocked! cfg step))
                     (_ (fdClose fd))]
                 r)))))

fn replaceAt lines: (List String) i: Int64 new: String -> (List String)
  (map (fn [(j Int64)] -> String (if (= j i) new (optionOr (listGet lines j) ""))) (range 0 (listLength lines)))

fn dedupeTarget cfg: Cfg nowMs: Int64 src: String kind: String key: String lines: (List String) -> (Option Int64)
  (listFind (fn [(i Int64)] -> Bool
              (match (evOf (optionOr (listGet lines i) ""))
                ((none) false)
                ((some e) (and (and (= e.src src) (= e.kind kind)) (and (and (= e.key key) (not e.ack)) (<= (- nowMs e.last) (* cfg.dedupeS 1000)))))))
            (listReverse (range 0 (listLength lines))))

fn bumped e: Ev nowMs: Int64 why: String sev: String -> Ev
  (with e :count (+ e.count 1) :last nowMs :why (clip why 300) :sev (sevName (max (sevRank e.sev) (sevRank sev))))

fn markAcked e: Ev -> Ev
  (with e :ack true)

; (:m :ref LEAD-STREAM :do "one event in: a repeat of an unacked src+kind+key inside the dedupe window raises the count, the last time, the text and the worst sev of the existing row; otherwise a new row; returns the event id")
fn ! emit! cfg: Cfg nowMs: Int64 src: String sev: String kind: String key: String unit: String why: String -> (Result String String)
  (mutate! cfg
    (fn [(lines (List String))] -> (Pair (List String) String)
      (match (dedupeTarget cfg nowMs (tok src) (tok kind) key lines)
        ((some i)
          (match (evOf (optionOr (listGet lines i) ""))
            ((some e) (pair (replaceAt lines i (renderEv (bumped e nowMs why sev))) e.id))
            ((none) (pair lines ""))))
        ((none)
          (let [(id (str "e" (int nowMs) "-" (int (procSelf)) "-" (int (mod (nowNs) 1000000))))]
            (pair (listAppend lines (list (renderEv (Ev :id id :at nowMs :last nowMs :node cfg.node :src (tok src) :sev (sevName (sevRank sev)) :kind (tok kind) :key key
                                                        :unit unit :why (clip why 300) :count 1 :ack false))))
                  id))))))

; (:m :ref LEAD-STREAM :do "the writers' entry: runDir is the node's ~/.asl/run; the stream never blocks a writer, so the result is whether the event landed")
fn ! emitAt! runDir: String nowMs: Int64 src: String sev: String kind: String key: String unit: String why: String -> Bool
  (ok? (emit! (cfgAt runDir (nodeName!)) nowMs src sev kind key unit why))

fn ! ack! cfg: Cfg ids: (List String) -> (Result String String)
  (mutate! cfg
    (fn [(lines (List String))] -> (Pair (List String) String)
      (let [(hit (filter (fn [(l String)] -> Bool (match (evOf l) ((some e) (and (not e.ack) (listContains? ids e.id))) ((none) false))) lines))
            (out (map (fn [(l String)] -> String
                        (match (evOf l) ((some e) (if (and (not e.ack) (listContains? ids e.id)) (renderEv (markAcked e)) l)) ((none) l)))
                      lines))]
        (pair out (str "(:acked :n " (int (listLength hit)) " :asked " (int (listLength ids)) ")")))))

fn doOk? d: String -> Bool
  (or (= d "requeue") (or (= d "hold") (= d "release")))

; (:m :ref LEAD-STREAM :do "operator intervention as a row only: (:act :id :target EVENTID :do requeue|hold|release :done false) lands in the stream; the conductor consumes it through pendingActs! and closes it with actDone!, nothing here touches a unit")
fn ! act! cfg: Cfg nowMs: Int64 target: String do: String -> (Result String String)
  (if (not (doOk? do)) (err (str "(:err :code usage :msg \"--do is requeue, hold or release\")"))
    (if (stringEmpty? target) (err "(:err :code usage :msg \"--id needed\")")
      (mutate! cfg
        (fn [(lines (List String))] -> (Pair (List String) String)
          (let [(id (str "a" (int nowMs) "-" (int (procSelf)) "-" (int (mod (nowNs) 1000000))))]
            (pair (listAppend lines (list (renderAct id nowMs cfg.node target do false))) (str "(:act :id " (st/q id) " :target " (st/q target) " :do " do ")")))))))

; (:m :ref LEAD-STREAM :do "the conductor's consume point: undone (:act ...) rows as (id target do), oldest first")
fn ! pendingActs! cfg: Cfg -> (List (List String))
  (filter (fn [(r (List String))] -> Bool (not (listEmpty? r)))
    (map (fn [(l String)] -> (List String)
           (match (actFields l)
             ((none) (list))
             ((some fs) (if (stringEndsWith? (stringTrim l) " :done true)") (list) (list (st/textField fs "id") (st/textField fs "target") (st/textField fs "do"))))))
         (readLines! cfg)))

fn ! actDone! cfg: Cfg id: String -> (Result String String)
  (mutate! cfg
    (fn [(lines (List String))] -> (Pair (List String) String)
      (pair (map (fn [(l String)] -> String
                   (match (actFields l)
                     ((none) l)
                     ((some fs) (if (= (st/textField fs "id") id)
                                  (renderAct id (st/intField fs "at") (st/textField fs "node") (st/textField fs "target") (st/textField fs "do") true)
                                  l)))) lines)
            "(:done)")))

fn evsOf lines: (List String) -> (List Ev)
  (fold (fn [(a (List Ev)) (l String)] -> (List Ev) (match (evOf l) ((some e) (listAppend a (list e))) ((none) a))) (list) lines)

fn groupOf kind: String es: (List Ev) -> Group
  (let [(newest (optionOr (listHead es) (Ev :id "" :at 0 :last 0 :node "" :src "" :sev "info" :kind kind :key "" :unit "" :why "" :count 0 :ack false)))]
    (Group :kind kind :sev (sevName (fold (fn [(m Int64) (e Ev)] -> Int64 (max m (sevRank e.sev))) 0 es)) :rows (listLength es)
           :count (fold (fn [(n Int64) (e Ev)] -> Int64 (+ n e.count)) 0 es) :last newest.last :why newest.why))

fn renderGroup g: Group ids: (List String) -> String
  (str "(:g :kind " g.kind " :sev " g.sev " :rows " (int g.rows) " :count " (int g.count) " :last " (int g.last) " :why " (st/q g.why) " :ids " (st/qList ids) ")")

; (:m :ref LEAD-STREAM :do "one ASN line: unacked events with :last >= since and sev >= minSev, grouped by kind (count is the sum of :count, why is the newest, sev the worst), worst and newest group first, each with its event ids for ack; :acts is the number of undone operator rows")
fn ! digest! cfg: Cfg nowMs: Int64 since: Int64 minSev: String -> String
  (let [(lines (readLines! cfg))
        (evs (listSortBy (fn [(e Ev)] -> Int64 (- 0 e.last))
                         (filter (fn [(e Ev)] -> Bool (and (and (not e.ack) (>= e.last since)) (>= (sevRank e.sev) (sevRank minSev)))) (evsOf lines))))
        (kinds (fold (fn [(a (List String)) (e Ev)] -> (List String) (if (listContains? a e.kind) a (listAppend a (list e.kind)))) (list) evs))
        (groups (listSortBy (fn [(g Group)] -> Int64 (- 0 (+ (* (sevRank g.sev) 10000000000000) g.last)))
                            (map (fn [(k String)] -> Group (groupOf k (filter (fn [(e Ev)] -> Bool (= e.kind k)) evs))) kinds)))
        (acts (listLength (pendingActs! cfg)))]
    (str "(:digest :node " (st/q cfg.node) " :at " (int nowMs) " :since " (int since) " :minSev " (tok minSev) " :unacked " (int (listLength evs)) " :acts " (int acts)
         " :groups (" (stringJoin (map (fn [(g Group)] -> String
                                         (renderGroup g (map (fn [(e Ev)] -> String e.id) (filter (fn [(e Ev)] -> Bool (= e.kind g.kind)) evs)))) groups) " ") "))"))

fn ! nowMs! -> Int64
  (/ (nowNs) 1000000)

fn csv s: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (map stringTrim (stringSplit s ",")))

fn usage -> String
  "(:err :code usage :msg \"leadStream digest [--since MS] [--sev info|warn|act] | ack --ids a,b | act --id EVENT --do requeue|hold|release | emit --src S --kind K [--sev V] [--key K] [--unit U] [--why W] [--dir D]\")"

fn ! report! r: (Result String String) -> Int64
  (match r
    ((ok text) (do (println text) 0))
    ((err text) (do (println text) 1)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (base (defaultCfg))
        (cfg (with base :dir (st/opt args "dir" base.dir)))
        (now (nowMs!))]
    (cond
      ((= cmd "digest") (do (println (digest! cfg now (st/intOpt args "since" 0) (st/opt args "sev" "info"))) (ok 0)))
      ((= cmd "ack") (ok (report! (ack! cfg (csv (st/opt args "ids" ""))))))
      ((= cmd "act") (ok (report! (act! cfg now (st/opt args "id" "") (st/opt args "do" "")))))
      ((= cmd "emit") (ok (report! (emit! cfg now (st/opt args "src" "conductor") (st/opt args "sev" "info") (st/opt args "kind" "") (st/opt args "key" "") (st/opt args "unit" "") (st/opt args "why" "")))))
      (else (do (eprintln (usage)) (ok 2)))))
