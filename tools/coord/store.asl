(module asl-tools/coord/store
  :x [Task Lease Req defaultDir! clashPath unitsDir leasesDir unitPath leasePath renderUnit renderLease parseUnit parseLease
      live? fenced? ownsClash readUnits! readLeases! put! claim! claimNext! heartbeat! release! commit! list! apply! main]
  :i [(asl-syntax/asl/asn :a asn) (asl-coord/claims :a cl)])

; (:m :ref FK-STORE :do "row-keyed unit queue with fenced leases: one row per unit under <dir>/units, one lease per held unit under <dir>/leases, every mutation under the <dir>/.lock flock (the asl-coord/claims pattern) and written by tmp+rename; the epoch lives in the unit row so it stays monotonic across expiry, and heartbeat, release and commit are refused unless they carry the current epoch")
(schema Task
  (:f id String) (:f owns (List String)) (:f reads (List String)) (:f gate String) (:f channel String) (:f model String)
  (:f base String) (:f after (List String)) (:f st String) (:f epoch Int64) (:f receipt String))

(schema Lease
  (:f id String) (:f holder String) (:f epoch Int64) (:f at Int64) (:f beat Int64) (:f ttl Int64) (:f owns (List String)) (:f reads (List String)))

(schema Req
  (:f op String) (:f id String) (:f holder String) (:f ttl Int64) (:f epoch Int64) (:f unit Task) (:f receipt String))

fn ! defaultDir! -> String
  (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/coord")

fn unitsDir dir: String -> String
  (str dir "/units")

fn leasesDir dir: String -> String
  (str dir "/leases")

fn unitPath dir: String id: String -> String
  (str (unitsDir dir) "/" id ".asn")

fn leasePath dir: String id: String -> String
  (str (leasesDir dir) "/" id ".asn")

fn q s: String -> String
  (let [(a (stringReplace s "\\" "\\\\"))
        (b (stringReplace a "\"" "\\\""))]
    (str "\"" (stringReplace b "\n" "\\n") "\""))

fn qList items: (List String) -> String
  (str "(" (stringJoin (map q items) " ") ")")

fn renderUnit u: Task -> String
  (str "(:unit :id " (q u.id) " :owns " (qList u.owns) " :reads " (qList u.reads) " :gate " (q u.gate) " :channel " (q u.channel)
       " :model " (q u.model) " :base " (q u.base) " :after " (qList u.after) " :st " u.st
       " :epoch " (stringFromInt64 u.epoch) " :receipt " (q u.receipt) ")")

fn renderLease l: Lease -> String
  (str "(:lease :id " (q l.id) " :holder " (q l.holder) " :epoch " (stringFromInt64 l.epoch)
       " :at " (stringFromInt64 l.at) " :beat " (stringFromInt64 l.beat) " :ttl " (stringFromInt64 l.ttl)
       " :owns " (qList l.owns) " :reads " (qList l.reads) ")")

fn refusal id: String why: String detail: String -> String
  (str "(:refused :unit " (q id) " :why " why detail ")")

fn field fields: (List asn/AsnField) key: String -> (Option asn/AsnValue)
  (match (listFind (fn [(f asn/AsnField)] -> Bool (= f.key (str ":" key))) fields)
    ((some f) (some f.val))
    ((none) (none)))

fn textOf v: asn/AsnValue -> String
  (match v
    ((asn/asnSym name) name)
    (_ (optionOr (asn/asnStringValue v) "")))

fn itemsOf v: asn/AsnValue -> (List String)
  (let [(vals (match v
                ((asn/asnUnit) (list))
                ((asn/asnTuple items) items)
                ((asn/asnVec items) items)
                ((asn/asnPair a b) (list a b))
                (_ (list v))))]
    (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map textOf vals)))

fn textField fields: (List asn/AsnField) key: String -> String
  (match (field fields key) ((some v) (textOf v)) ((none) ""))

fn intField fields: (List asn/AsnField) key: String -> Int64
  (match (field fields key) ((some v) (optionOr (asn/asnIntValue v) 0)) ((none) 0))

fn listField fields: (List asn/AsnField) key: String -> (List String)
  (match (field fields key) ((some v) (itemsOf v)) ((none) (list)))

fn rowFields raw: String tag: String -> (Result (List asn/AsnField) String)
  (match (asn/asnRead (stringTrim raw))
    ((err e) (err e))
    ((ok (asn/asnTagged t fields _)) (if (= t (str ":" tag)) (ok fields) (err (str "not a " tag " row"))))
    ((ok _) (err (str "not a " tag " row"))))

fn parseUnit raw: String -> (Result Task String)
  (match (rowFields raw "unit")
    ((err e) (err e))
    ((ok fs)
      (let [(id (textField fs "id"))]
        (if (stringEmpty? id) (err "unit row without :id")
          (ok (Task :id id :owns (listField fs "owns") :reads (listField fs "reads") :gate (textField fs "gate") :channel (textField fs "channel")
                    :model (textField fs "model") :base (textField fs "base") :after (listField fs "after")
                    :st (let [(st (textField fs "st"))] (if (stringEmpty? st) "queued" st))
                    :epoch (intField fs "epoch") :receipt (textField fs "receipt")))))))

fn parseLease raw: String -> (Result Lease String)
  (match (rowFields raw "lease")
    ((err e) (err e))
    ((ok fs)
      (let [(id (textField fs "id"))]
        (if (stringEmpty? id) (err "lease row without :id")
          (ok (Lease :id id :holder (textField fs "holder") :epoch (intField fs "epoch") :at (intField fs "at")
                     :beat (intField fs "beat") :ttl (intField fs "ttl") :owns (listField fs "owns") :reads (listField fs "reads")))))))

fn validId? id: String -> Bool
  (and (not (stringEmpty? id)) (not (stringStartsWith? id ".")) (not (stringContains? id "/"))
       (not (stringContains? id "\\")) (not (stringContains? id "\"")) (not (stringContains? id " ")))

fn validPath? path: String -> Bool
  (and (not (stringEmpty? path)) (not (stringStartsWith? path "/")) (!= path "..")
       (not (stringStartsWith? path "../")) (not (stringContains? path "/../")) (not (stringEndsWith? path "/..")))

fn ! writeAtomic! path: String text: String -> (Result Unit String)
  (let [(tmp (str path "." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs)) ".tmp"))]
    (match (fileWrite tmp (str text "\n"))
      ((err e) (err e))
      ((ok _) (match (pathRename tmp path)
                ((ok _) (ok ()))
                ((err e) (let [(_ (pathRemove tmp))] (err e)))))))

fn rowName? name: String -> Bool
  (and (stringEndsWith? name ".asn") (not (stringStartsWith? name ".")))

fn ! readRows! dir: String names: (List String) parse: (fn [String] -> (Result T String)) acc: (List T) -> (Result (List T) String)
  (match (listHead names)
    ((none) (ok (listReverse acc)))
    ((some name)
      (let [(rest (listDrop names 1))]
        (if (not (rowName? name)) (readRows! dir rest parse acc)
          (match (fileReadString (str dir "/" name))
            ((err e) (err (str dir "/" name ": " e)))
            ((ok raw) (match (parse raw)
                        ((err e) (err (str dir "/" name ": " e)))
                        ((ok row) (readRows! dir rest parse (cons row acc))))))))))

fn ! readUnits! dir: String -> (Result (List Task) String)
  (match (dirList (unitsDir dir))
    ((err e) (err e))
    ((ok names) (readRows! (unitsDir dir) (listSort names) parseUnit (list))))

fn ! readLeases! dir: String -> (Result (List Lease) String)
  (match (dirList (leasesDir dir))
    ((err e) (err e))
    ((ok names) (readRows! (leasesDir dir) (listSort names) parseLease (list))))

fn live? l: Lease now: Int64 -> Bool
  (<= (- now l.beat) (* l.ttl 1000000))

; (:m :ref FK-STORE :do "the fencing check: an operation on a held unit names the epoch its claim returned, and only the current epoch of a leased unit passes, so a holder that expired and was reclaimed cannot release, commit or heartbeat over the new holder")
fn fenced? u: Task epoch: Int64 -> Bool
  (and (= u.st "leased") (= epoch u.epoch))

fn leaseOf leases: (List Lease) id: String -> (Option Lease)
  (listFind (fn [(l Lease)] -> Bool (= l.id id)) leases)

fn unitOf units: (List Task) id: String -> (Option Task)
  (listFind (fn [(u Task)] -> Bool (= u.id id)) units)

fn ownsHit mine: (List String) theirs: (List String) -> String
  (match (listFind (fn [(p String)] -> Bool (listAny? (fn [(o String)] -> Bool (cl/pathsOverlap? p o)) theirs)) mine)
    ((some p) p)
    ((none) ""))

; (:m :ref FK-STORE :do "the asl-mesh coord areClaimsFullyDisjoint rule (write-write, write-read, read-write) over path prefixes: u's :owns against a live lease's :owns and :reads, and u's :reads against its :owns; the first hit path, empty when disjoint")
fn clashPath u: Task l: Lease -> String
  (let [(ww (ownsHit u.owns l.owns)) (wr (ownsHit u.owns l.reads)) (rw (ownsHit u.reads l.owns))]
    (cond ((not (stringEmpty? ww)) ww) ((not (stringEmpty? wr)) wr) (else rw)))

fn ownsClash u: Task held: (List Lease) -> String
  (match (listFind (fn [(l Lease)] -> Bool (and (!= l.id u.id) (not (stringEmpty? (clashPath u l))))) held)
    ((some l) (str " :by " (q l.id) " :path " (q (clashPath u l))))
    ((none) ""))

fn blockedBy u: Task units: (List Task) -> String
  (match (listFind (fn [(a String)] -> Bool (match (unitOf units a) ((some p) (!= p.st "done")) ((none) true))) u.after)
    ((some a) a)
    ((none) ""))

; (:m :ref FK-STORE :do "why u cannot be claimed now, empty when it can: done, held by a live lease, an :after unit not done, or a path clashing with another live lease (clashPath, on pathsOverlap? of asl-coord/claims)")
fn claimRefusal u: Task units: (List Task) held: (List Lease) -> String
  (let [(mine (leaseOf held u.id))
        (wait (blockedBy u units))
        (clash (ownsClash u held))]
    (cond
      ((= u.st "done") (refusal u.id "done" ""))
      ((some? mine) (let [(l (optionOr mine (Lease :id "" :holder "" :epoch 0 :at 0 :beat 0 :ttl 0 :owns (list) :reads (list))))]
                        (refusal u.id "held" (str " :holder " (q l.holder) " :epoch " (stringFromInt64 l.epoch)))))
      ((not (stringEmpty? wait)) (refusal u.id "after" (str " :wait " (q wait))))
      ((not (stringEmpty? clash)) (refusal u.id "owns" clash))
      (else "")))

fn ! appendLog! dir: String row: String -> (Result Unit String)
  (fileAppend (str dir "/log.asn") (str row "\n"))

fn ! grant! dir: String u: Task holder: String ttl: Int64 now: Int64 -> (Result String String)
  (let [(epoch (+ u.epoch 1))
        (lease (Lease :id u.id :holder holder :epoch epoch :at now :beat now :ttl ttl :owns u.owns :reads u.reads))]
    (match (writeAtomic! (unitPath dir u.id) (renderUnit (with u :st "leased" :epoch epoch)))
      ((err e) (err e))
      ((ok _) (match (writeAtomic! (leasePath dir u.id) (renderLease lease))
                ((err e) (err e))
                ((ok _) (match (appendLog! dir (str "(:claimed :unit " (q u.id) " :epoch " (stringFromInt64 epoch) " :holder " (q holder) " :at " (stringFromInt64 now) ")"))
                          ((err e) (err e))
                          ((ok _) (ok (renderLease lease)))))))))

fn ! closeLease! dir: String u: Task st: String receipt: String event: String now: Int64 -> (Result String String)
  (let [(row (str "(:" event " :unit " (q u.id) " :epoch " (stringFromInt64 u.epoch) " :at " (stringFromInt64 now) ")"))]
    (match (writeAtomic! (unitPath dir u.id) (renderUnit (with u :st st :receipt receipt)))
      ((err e) (err e))
      ((ok _) (match (removeLease! dir u.id)
                ((err e) (err e))
                ((ok _) (match (appendLog! dir row) ((err e) (err e)) ((ok _) (ok row))))))))

fn ! removeLease! dir: String id: String -> (Result Unit String)
  (if (fileExists? (leasePath dir id)) (pathRemove (leasePath dir id)) (ok ()))

fn ! applyPut! dir: String u: Task units: (List Task) held: (List Lease) -> (Result String String)
  (cond
    ((not (validId? u.id)) (err (refusal u.id "id" "")))
    ((not (listAll? validPath? (listAppend u.owns u.reads))) (err (refusal u.id "owns" " :path \"invalid\"")))
    (else
      (match (unitOf units u.id)
        ((some prior)
          (if (some? (leaseOf held u.id))
            (err (refusal u.id "held" ""))
            (match (writeAtomic! (unitPath dir u.id) (renderUnit (with u :st prior.st :epoch prior.epoch :receipt prior.receipt)))
              ((err e) (err e)) ((ok _) (ok (str "(:put :unit " (q u.id) " :st " prior.st ")"))))))
        ((none)
          (match (writeAtomic! (unitPath dir u.id) (renderUnit (with u :st "queued" :epoch 0 :receipt "")))
            ((err e) (err e)) ((ok _) (ok (str "(:put :unit " (q u.id) " :st queued)"))))))))

fn ! applyClaim! dir: String req: Req units: (List Task) held: (List Lease) now: Int64 -> (Result String String)
  (if (not (stringEmpty? req.id))
    (match (unitOf units req.id)
      ((none) (err (refusal req.id "missing" "")))
      ((some u) (let [(why (claimRefusal u units held))]
                  (if (stringEmpty? why) (grant! dir u req.holder req.ttl now) (err why)))))
    (match (listFind (fn [(u Task)] -> Bool (stringEmpty? (claimRefusal u units held))) units)
      ((none) (err "(:none)"))
      ((some u) (grant! dir u req.holder req.ttl now))))

fn ! beat! dir: String prior: Lease now: Int64 -> (Result String String)
  (let [(lease (with prior :beat now))]
    (match (writeAtomic! (leasePath dir prior.id) (renderLease lease))
      ((err e) (err e))
      ((ok _) (ok (renderLease lease)))))

fn ! applyFenced! dir: String req: Req units: (List Task) leases: (List Lease) now: Int64 -> (Result String String)
  (match (unitOf units req.id)
    ((none) (err (refusal req.id "missing" "")))
    ((some u)
      (if (not (fenced? u req.epoch))
        (err (refusal u.id "epoch" (str " :have " (stringFromInt64 req.epoch) " :current " (stringFromInt64 u.epoch) " :st " u.st)))
        (cond
          ((= req.op "heartbeat")
            (match (leaseOf leases u.id)
              ((none) (err (refusal u.id "lost" "")))
              ((some prior) (beat! dir prior now))))
          ((= req.op "release") (closeLease! dir u "queued" "" "released" now))
          (else (closeLease! dir u "done" req.receipt "committed" now))))))

fn ! applyLocked! dir: String req: Req -> (Result String String)
  (match (readUnits! dir)
    ((err e) (err e))
    ((ok units)
      (match (readLeases! dir)
        ((err e) (err e))
        ((ok leases)
          (let [(now (nowNs))
                (held (filter (fn [(l Lease)] -> Bool (live? l now)) leases))]
            (cond
              ((= req.op "put") (applyPut! dir req.unit units held))
              ((= req.op "claim") (applyClaim! dir req units held now))
              ((= req.op "list") (ok (str "(:store " (stringJoin (map renderUnit units) " ") " " (stringJoin (map renderLease held) " ") ")")))
              (else (applyFenced! dir req units leases now))))))))

; (:m :ref FK-STORE :do "the one locked path: dirs made, the store flock taken with a bound (fileLockWait as asl-coord/claims lockAcquire! takes it), the request applied, the lock fd closed whatever the outcome")
fn ! apply! dir: String req: Req -> (Result String String)
  (match (dirCreate (unitsDir dir))
    ((err e) (err e))
    ((ok _) (match (dirCreate (leasesDir dir))
      ((err e) (err e))
      ((ok _) (match (fileLockWait (str dir "/.lock") true 30000)
        ((err e) (err (str "store lock: " e)))
        ((ok fd) (let [(result (applyLocked! dir req))
                       (closed (fdClose fd))]
                   (match closed ((err e) (err e)) ((ok _) result)))))))))

fn emptyUnit id: String -> Task
  (Task :id id :owns (list) :reads (list) :gate "" :channel "" :model "" :base "" :after (list) :st "queued" :epoch 0 :receipt "")

fn req op: String id: String -> Req
  (Req :op op :id id :holder "" :ttl 0 :epoch 0 :unit (emptyUnit id) :receipt "")

fn ! put! dir: String u: Task -> (Result String String)
  (apply! dir (with (req "put" u.id) :unit u))

fn ! claim! dir: String id: String holder: String ttlMs: Int64 -> (Result String String)
  (apply! dir (with (req "claim" id) :holder holder :ttl ttlMs))

fn ! claimNext! dir: String holder: String ttlMs: Int64 -> (Result String String)
  (claim! dir "" holder ttlMs)

fn ! heartbeat! dir: String id: String epoch: Int64 -> (Result String String)
  (apply! dir (with (req "heartbeat" id) :epoch epoch))

fn ! release! dir: String id: String epoch: Int64 -> (Result String String)
  (apply! dir (with (req "release" id) :epoch epoch))

fn ! commit! dir: String id: String epoch: Int64 receipt: String -> (Result String String)
  (apply! dir (with (req "commit" id) :epoch epoch :receipt receipt))

fn ! list! dir: String -> (Result String String)
  (apply! dir (req "list" ""))

fn opt args: (List String) key: String fallback: String -> String
  (match (listFind (fn [(i Int64)] -> Bool (= (optionOr (listGet args i) "") (str "--" key))) (range 0 (listLength args)))
    ((some i) (optionOr (listGet args (+ i 1)) fallback))
    ((none) fallback))

fn csv s: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (map stringTrim (stringSplit s ",")))

fn intOpt args: (List String) key: String fallback: Int64 -> Int64
  (optionOr (stringToInt64 (opt args key "")) fallback)

fn usage -> String
  "usage: store (put --id ID [--owns a,b] [--reads c,d] [--after X,Y] [--gate G] [--channel C] [--model M] [--base B] | claim --holder H [--id ID] [--ttl MS] [--hold MS] [--drain MS] | heartbeat|release --id ID --epoch N | commit --id ID --epoch N [--receipt R] | list) [--dir D]"

fn leaseEpoch text: String -> Int64
  (match (parseLease text) ((ok l) l.epoch) ((err _) 0))

fn leaseId text: String -> String
  (match (parseLease text) ((ok l) l.id) ((err _) ""))

; (:m :ref FK-STORE :do "--hold keeps a granted lease alive by heartbeat every ttl/3 for MS ms (the killed-holder fixture); a refused heartbeat ends the hold with exit 1")
fn ! hold! dir: String id: String epoch: Int64 ttl: Int64 untilNs: Int64 -> Int64
  (if (>= (nowNs) untilNs) 0
    (let [(_ (sleepMs (if (> (/ ttl 3) 10) (/ ttl 3) 10)))]
      (match (heartbeat! dir id epoch)
        ((err e) (do (println e) 1))
        ((ok _) (hold! dir id epoch ttl untilNs)))))

; (:m :ref FK-STORE :do "--drain claims the next unit until (:none), holds each for MS ms, commits it with its epoch and prints one (:did ...) row per unit: the concurrent-claimer fixture")
fn ! drain! dir: String holder: String ttl: Int64 holdMs: Int64 n: Int64 -> Int64
  (if (> n 10000) 1
    (match (claimNext! dir holder ttl)
      ((err e) (if (= e "(:none)") 0 (do (println e) 1)))
      ((ok text)
        (let [(id (leaseId text)) (epoch (leaseEpoch text))
              (_ (sleepMs holdMs))]
          (match (commit! dir id epoch holder)
            ((err e) (do (println e) 1))
            ((ok _) (do (println (str "(:did :unit " (q id) " :epoch " (stringFromInt64 epoch) " :holder " (q holder) ")"))
                        (drain! dir holder ttl holdMs (+ n 1)))))))))

fn ! report! r: (Result String String) -> Int64
  (match r
    ((ok text) (do (println text) 0))
    ((err text) (do (println text) (if (stringStartsWith? text "(:") 1 2))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (dir (opt args "dir" (defaultDir!)))
        (id (opt args "id" ""))
        (ttl (intOpt args "ttl" 60000))
        (epoch (intOpt args "epoch" 0))]
    (cond
      ((= cmd "put") (ok (report! (put! dir (Task :id id :owns (csv (opt args "owns" "")) :reads (csv (opt args "reads" "")) :gate (opt args "gate" "") :channel (opt args "channel" "")
                                                 :model (opt args "model" "") :base (opt args "base" "") :after (csv (opt args "after" ""))
                                                 :st "queued" :epoch 0 :receipt "")))))
      ((= cmd "claim")
        (let [(holder (opt args "holder" (str "pid" (stringFromInt64 (procSelf)))))
              (drainMs (intOpt args "drain" -1))]
          (if (>= drainMs 0) (ok (drain! dir holder ttl drainMs 0))
            (match (claim! dir id holder ttl)
              ((err e) (ok (report! (err e))))
              ((ok text) (let [(_ (println text)) (holdMs (intOpt args "hold" 0))]
                           (if (> holdMs 0)
                             (ok (hold! dir (leaseId text) (leaseEpoch text) ttl (+ (nowNs) (* holdMs 1000000))))
                             (ok 0))))))))
      ((= cmd "heartbeat") (ok (report! (heartbeat! dir id epoch))))
      ((= cmd "release") (ok (report! (release! dir id epoch))))
      ((= cmd "commit") (ok (report! (commit! dir id epoch (opt args "receipt" "")))))
      ((= cmd "list") (ok (report! (list! dir))))
      (else (do (eprintln (usage)) (ok 2)))))
