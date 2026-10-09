(module aslGateway/omniApi
  :x [Word64 TargetTab BrowserSession BrowserTarget BrowserExtension SyncStore TargetStore ExtensionStore OmniState OmniReply
      emptyOmniState omniDispatch omniGet omniPost pyStrHash pyIntStr reQuoted reBare reLead reDigits dyckBalanced?]
  :i [(pyText :a pt)
      (asl-http/http11 :a h)])

(schema Word64 (:f hi Int64) (:f lo Int64))

(schema TargetTab (:f tabId String) (:f title String) (:f url String))

(schema BrowserSession
  (:f id String) (:f createdMs Int64) (:f lastActiveMs Int64) (:f profile String) (:f mode String)
  (:f currentUrl String) (:f tabId String) (:f status String) (:f history (List String)))

(schema BrowserTarget
  (:f id String) (:f kind String) (:f family String) (:f authenticated Bool) (:f registeredMs Int64)
  (:f heartbeatMs Int64) (:f status String) (:f tabs (List TargetTab)))

(schema BrowserExtension
  (:f agentId String) (:f registeredMs Int64) (:f lastPollMs Int64) (:f tabsCount String) (:f status String))

(schema SyncStore
  (:f projects (List (Pair String String))) (:f channels (List (Pair String String)))
  (:f research (List (Pair String String))) (:f assets (List (Pair String String))))

(schema TargetStore
  (:f targets (List (Pair String BrowserTarget)))
  (:f actions (List (Pair String (List String))))
  (:f receipts (List (Pair String (List String)))))

(schema ExtensionStore
  (:f extensions (List (Pair String BrowserExtension)))
  (:f actions (List (Pair String (List String))))
  (:f receipts (List (Pair String (List String)))))

(schema OmniState
  (:f sync SyncStore) (:f sessions (List (Pair String BrowserSession)))
  (:f targets TargetStore) (:f extensions ExtensionStore) (:f hashK0 Word64) (:f hashK1 Word64))

(schema OmniReply (:f state OmniState) (:f response h/HttpResponse))

fn emptyOmniState k0: Word64 k1: Word64 -> OmniState
  (OmniState :sync (SyncStore :projects (list) :channels (list) :research (list) :assets (list))
             :sessions (list)
             :targets (TargetStore :targets (list) :actions (list) :receipts (list))
             :extensions (ExtensionStore :extensions (list) :actions (list) :receipts (list))
             :hashK0 k0 :hashK1 k1)

fn withSync s: OmniState v: SyncStore -> OmniState
  (with s :sync v)

fn withSessions s: OmniState v: (List (Pair String BrowserSession)) -> OmniState
  (with s :sessions v)

fn withTargets s: OmniState v: TargetStore -> OmniState
  (with s :targets v)

fn withExtensions s: OmniState v: ExtensionStore -> OmniState
  (with s :extensions v)

fn assocGet xs: (List (Pair String T)) k: String -> (Option T)
  (mt (listHead xs)
    ((none) (none))
    ((some p) (if (= (pairFirst p) k) (some (pairSecond p)) (assocGet (preludeTail xs) k))))

fn assocHas? xs: (List (Pair String T)) k: String -> Bool
  (some? (assocGet xs k))

fn assocSet xs: (List (Pair String T)) k: String v: T -> (List (Pair String T))
  (if (assocHas? xs k)
    (map (fn [(p (Pair String T))] -> (Pair String T) (if (= (pairFirst p) k) (pair k v) p)) xs)
    (listAppend xs (list (pair k v))))

fn assocDel xs: (List (Pair String T)) k: String -> (List (Pair String T))
  (filter (fn [(p (Pair String T))] -> Bool (not (= (pairFirst p) k))) xs)

fn queueEnsure qs: (List (Pair String (List String))) k: String -> (List (Pair String (List String)))
  (if (assocHas? qs k) qs (listAppend qs (list (pair k (list)))))

fn queuePut qs: (List (Pair String (List String))) k: String item: String -> (List (Pair String (List String)))
  (map (fn [(p (Pair String (List String)))] -> (Pair String (List String))
         (if (= (pairFirst p) k) (pair k (listAppend (pairSecond p) (list item))) p))
       qs)

fn queuePutAll qs: (List (Pair String (List String))) item: String -> (List (Pair String (List String)))
  (map (fn [(p (Pair String (List String)))] -> (Pair String (List String)) (pair (pairFirst p) (listAppend (pairSecond p) (list item)))) qs)

fn queueTake qs: (List (Pair String (List String))) k: String -> (Pair (Option String) (List (Pair String (List String))))
  (mt (assocGet qs k)
    ((none) (pair (none) qs))
    ((some items)
      (mt (listHead items)
        ((none) (pair (none) qs))
        ((some first) (pair (some first) (assocSet qs k (preludeTail items)))))))

fn cpAtB bs: Bytes n: Int64 i: Int64 -> Int64
  (let [(b0 (bytesGet bs i)) (l (pt/cpLenAt b0))]
    (cond
      ((or (< b0 128) (> (+ i l) n)) b0)
      ((= l 2) (+ (* (& b0 31) 64) (& (bytesGet bs (+ i 1)) 63)))
      ((= l 3) (+ (* (& b0 15) 4096) (+ (* (& (bytesGet bs (+ i 1)) 63) 64) (& (bytesGet bs (+ i 2)) 63))))
      (else (+ (* (& b0 7) 262144) (+ (* (& (bytesGet bs (+ i 1)) 63) 4096) (+ (* (& (bytesGet bs (+ i 2)) 63) 64) (& (bytesGet bs (+ i 3)) 63)))))))

fn stepAt bs: Bytes n: Int64 i: Int64 -> Int64
  (min n (+ i (pt/cpLenAt (bytesGet bs i))))

fn wsEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (pt/isPySpace (cpAtB bs n i))) (wsEnd bs n (stepAt bs n i)) i)

fn tokenCp? cp: Int64 -> Bool
  (and (not (pt/isPySpace cp)) (not (= cp 34)) (not (= cp 39)) (not (= cp 41)))

fn tokenEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (tokenCp? (cpAtB bs n i))) (tokenEnd bs n (stepAt bs n i)) i)

fn quoteEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (not (= (bytesGet bs i) 34))) (quoteEnd bs n (+ i 1)) i)

fn ndZeros -> (List Int64)
  (list 48 1632 1776 1984 2406 2534 2662 2790 2918 3046 3174 3302 3430 3558 3664 3792 3872 4160 4240 6112 6160 6470
        6608 6784 6800 6992 7088 7232 7248 42528 43216 43264 43472 43504 43600 44016 65296 66720 68912 69734 69872
        69942 70096 70384 70736 70864 71248 71360 71472 71904 72016 72784 73040 73120 73552 92768 92864 93008 120782
        120792 120802 120812 120822 123200 123632 124144 125264 130032)

fn digitValue cp: Int64 -> (Option Int64)
  (mt (listHead (filter (fn [(z Int64)] -> Bool (and (>= cp z) (< cp (+ z 10)))) (ndZeros)))
    ((none) (none))
    ((some z) (some (- cp z))))

fn digitsScan bs: Bytes n: Int64 i: Int64 acc: (List String) -> (Pair Int64 (List String))
  (if (>= i n)
    (pair i (listReverse acc))
    (mt (digitValue (cpAtB bs n i))
      ((none) (pair i (listReverse acc)))
      ((some d) (digitsScan bs n (stepAt bs n i) (cons (stringFromInt64 d) acc)))))

fn pyIntStr digits: (List String) -> String
  (let [(trimmed (dropZeros digits))]
    (if (listEmpty? trimmed) "0" (stringJoin trimmed "")))

fn dropZeros ds: (List String) -> (List String)
  (mt (listHead ds) ((some d) (if (= d "0") (dropZeros (preludeTail ds)) ds)) ((none) ds))

fn captureAt s: String bs: Bytes n: Int64 j: Int64 kind: Int64 -> (Option String)
  (cond
    ((>= j n) (none))
    ((= kind 0)
      (if (= (bytesGet bs j) 34)
        (let [(e (quoteEnd bs n (+ j 1)))]
          (if (and (< e n) (> e (+ j 1))) (some (pt/sliceB s (+ j 1) e)) (none)))
        (none)))
    ((= kind 3)
      (let [(r (digitsScan bs n j (list)))]
        (if (listEmpty? (pairSecond r)) (none) (some (pyIntStr (pairSecond r))))))
    (else
      (let [(b (bytesGet bs j))
            (prefixed (or (= b 58) (and (= kind 2) (or (= b 34) (= b 39)))))
            (afterPrefix (if prefixed (tokenEnd bs n (+ j 1)) j))]
        (if (and prefixed (> afterPrefix (+ j 1)))
          (some (pt/sliceB s (+ j 1) afterPrefix))
          (let [(e (tokenEnd bs n j))]
            (if (> e j) (some (pt/sliceB s j e)) (none)))))))

fn litAt bs: Bytes n: Int64 i: Int64 lit: Bytes m: Int64 k: Int64 -> Bool
  (cond ((>= k m) true) ((>= (+ i k) n) false) ((= (bytesGet bs (+ i k)) (bytesGet lit k)) (litAt bs n i lit m (+ k 1))) (else false))

fn altsAt s: String bs: Bytes n: Int64 i: Int64 alts: (List String) kind: Int64 -> (Option String)
  (mt (listHead alts)
    ((none) (none))
    ((some a)
      (let [(lit (stringToBytes a)) (m (bytesLength lit))
            (hit (if (litAt bs n i lit m 0)
                   (let [(w (wsEnd bs n (+ i m)))] (if (> w (+ i m)) (captureAt s bs n w kind) (none)))
                   (none)))]
        (if (some? hit) hit (altsAt s bs n i (preludeTail alts) kind)))))

fn searchFrom s: String bs: Bytes n: Int64 i: Int64 alts: (List String) kind: Int64 -> (Option String)
  (if (>= i n)
    (none)
    (let [(hit (if (= (bytesGet bs i) 58) (altsAt s bs n i alts kind) (none)))]
      (if (some? hit) hit (searchFrom s bs n (+ i 1) alts kind))))

fn reSearch s: String alts: (List String) kind: Int64 -> (Option String)
  (let [(bs (stringToBytes s))] (searchFrom s bs (bytesLength bs) 0 alts kind))

fn reQuoted s: String alts: (List String) -> (Option String)
  (reSearch s alts 0)

fn reBare s: String alts: (List String) -> (Option String)
  (reSearch s alts 1)

fn reLead s: String alts: (List String) -> (Option String)
  (reSearch s alts 2)

fn reDigits s: String alts: (List String) -> (Option String)
  (reSearch s alts 3)

fn two32 -> Int64
  4294967296

fn pow2 k: Int64 -> Int64
  (if (<= k 0) 1 (* 2 (pow2 (- k 1))))

fn wAdd a: Word64 b: Word64 -> Word64
  (let [(lo (+ a.lo b.lo))]
    (Word64 :hi (mod (+ (+ a.hi b.hi) (/ lo (two32))) (two32)) :lo (mod lo (two32))))

fn wXor a: Word64 b: Word64 -> Word64
  (Word64 :hi (^ a.hi b.hi) :lo (^ a.lo b.lo))

fn wRotl x: Word64 k: Int64 -> Word64
  (cond
    ((= k 0) x)
    ((>= k 32) (wRotl (Word64 :hi x.lo :lo x.hi) (- k 32)))
    (else
      (let [(keep (pow2 (- 32 k))) (up (pow2 k))]
        (Word64 :hi (+ (* (mod x.hi keep) up) (/ x.lo keep))
                :lo (+ (* (mod x.lo keep) up) (/ x.hi keep))))))

(schema Sip (:f v0 Word64) (:f v1 Word64) (:f v2 Word64) (:f v3 Word64))

fn sipRound s: Sip -> Sip
  (let [(v0a (wAdd s.v0 s.v1))
        (v2a (wAdd s.v2 s.v3))
        (v1a (wXor (wRotl s.v1 13) v0a))
        (v3a (wXor (wRotl s.v3 16) v2a))
        (v0b (wRotl v0a 32))
        (v2b (wAdd v2a v1a))
        (v0c (wAdd v0b v3a))
        (v1b (wXor (wRotl v1a 17) v2b))
        (v3b (wXor (wRotl v3a 21) v0c))
        (v2c (wRotl v2b 32))]
    (Sip :v0 v0c :v1 v1b :v2 v2c :v3 v3b))

fn leWord bs: (List Int64) -> Word64
  (let [(at (fn [(i Int64)] -> Int64 (optionOr (listGet bs i) 0)))]
    (Word64 :hi (+ (+ (at 4) (* (at 5) 256)) (+ (* (at 6) 65536) (* (at 7) 16777216)))
            :lo (+ (+ (at 0) (* (at 1) 256)) (+ (* (at 2) 65536) (* (at 3) 16777216)))))

fn sipBlocks s: Sip bs: (List Int64) left: Int64 size: Int64 -> Sip
  (if (>= left 8)
    (let [(mi (leWord (listTake bs 8)))
          (r (sipRound (with s :v3 (wXor s.v3 mi))))]
      (sipBlocks (Sip :v0 (wXor r.v0 mi) :v1 r.v1 :v2 r.v2 :v3 r.v3) (listDrop bs 8) (- left 8) size))
    (let [(tail (leWord bs))
          (b (Word64 :hi (+ tail.hi (* (mod size 256) 16777216)) :lo tail.lo))
          (r (sipRound (with s :v3 (wXor s.v3 b))))
          (f (Sip :v0 (wXor r.v0 b) :v1 r.v1 :v2 (wXor r.v2 (Word64 :hi 0 :lo 255)) :v3 r.v3))]
      (sipRound (sipRound (sipRound f)))))

fn siphash13 k0: Word64 k1: Word64 bs: (List Int64) -> Word64
  (let [(init (Sip :v0 (wXor k0 (Word64 :hi 1936682341 :lo 1886610805))
                   :v1 (wXor k1 (Word64 :hi 1685025377 :lo 1852075885))
                   :v2 (wXor k0 (Word64 :hi 1819895653 :lo 1852142177))
                   :v3 (wXor k1 (Word64 :hi 1952801890 :lo 2037671283))))
        (n (listLength bs))
        (f (sipBlocks init bs n n))]
    (wXor (wXor f.v0 f.v1) (wXor f.v2 f.v3)))

fn strUnits cps: (List Int64) -> (List Int64)
  (let [(widest (fold (fn [(m Int64) (c Int64)] -> Int64 (max m c)) 0 cps))
        (width (cond ((< widest 256) 1) ((< widest 65536) 2) (else 4)))]
    (listReverse
      (fold (fn [(acc (List Int64)) (c Int64)] -> (List Int64)
              (cond
                ((= width 1) (cons c acc))
                ((= width 2) (cons (/ c 256) (cons (mod c 256) acc)))
                (else (cons (/ c 16777216) (cons (mod (/ c 65536) 256) (cons (mod (/ c 256) 256) (cons (mod c 256) acc)))))))
            (list) cps)))

fn pyStrHash k0: Word64 k1: Word64 s: String m: Int64 -> Int64
  (let [(units (strUnits (pt/cpList s)))]
    (if (listEmpty? units)
      0
      (let [(x (siphash13 k0 k1 units))
            (top (- (two32) 1))
            (minusOne (and (= x.hi top) (= x.lo top)))
            (negative (>= x.hi 2147483648))
            (mag (cond
                   (minusOne (Word64 :hi 0 :lo 2))
                   (negative (wAdd (Word64 :hi (- top x.hi) :lo (- top x.lo)) (Word64 :hi 0 :lo 1)))
                   (else x)))]
        (mod (+ (* (mod mag.hi m) (mod (two32) m)) (mod mag.lo m)) m))))

fn asnHeaders -> (List (Pair String String))
  (list (pair "Content-Type" "application/asn+sexpr") (pair "X-ASL-Wire-Protocol" "asn/1.0"))

fn respond s: OmniState status: Int64 headers: (List (Pair String String)) body: String -> (Result OmniReply String)
  (ok (OmniReply :state s :response (h/makeResponse status (if (= status 200) "OK" "Bad Request") (h/makeHeaders headers) body)))

fn asnOk s: OmniState body: String -> (Result OmniReply String)
  (respond s 200 (asnHeaders) body)

fn secs ms: Int64 -> String
  (stringFromInt64 (/ ms 1000))

fn exactPath? target: String p: String -> Bool
  (or (= target p) (= target (str p "/")))

fn stripSlashes s: String -> String
  (let [(a (if (stringStartsWith? s "/") (stripSlashes (pt/sliceB s 1 (stringLength s))) s))]
    (if (stringEndsWith? a "/") (stripSlashes (pt/sliceB a 0 (- (stringLength a) 1))) a))

fn afterPrefix s: String p: String -> String
  (pt/sliceB s (stringLength p) (stringLength s))

fn queryGet target: String a: String b: String dflt: String -> (Result String String)
  (mt (pt/urlparse target)
    ((err e) (err (pt/pyErrText e)))
    ((ok parts)
      (let [(pairs (listReverse (pt/parseQsl (optionOr (listGet parts 4) ""))))]
        (ok (optionOr (assocGet pairs a) (optionOr (assocGet pairs b) dflt))))))

fn browserStatusJson -> String
  "{\"status\": \"ok\", \"active\": true, \"tabs_count\": 1, \"engine\": \"extension-primary\", \"modes\": [\"extension\", \"patchright\", \"staticHttp\", \"cloudProxy\", \"auto\"]}"

fn projectGet s: OmniState target: String -> (Result OmniReply String)
  (let [(pid (stripSlashes (afterPrefix target "/api/asl/project/")))]
    (asnOk s (optionOr (assocGet s.sync.projects pid) (str "(:projectSync :id \"" pid "\" :status :notFound)"))))

fn channelsGet s: OmniState -> (Result OmniReply String)
  (asnOk s (str "(:channels (" (stringJoin (map pairSecond s.sync.channels) " ") "))"))

fn sessionListGet s: OmniState -> (Result OmniReply String)
  (let [(items (map (fn [(p (Pair String BrowserSession))] -> String
                      (let [(x (pairSecond p))]
                        (str "(:session :id \"" (pairFirst p) "\" :status :" x.status " :url \"" x.currentUrl "\")")))
                    s.sessions))]
    (asnOk s (str "(:browserSessions [" (stringJoin items " ") "])\n")))

fn targetListGet s: OmniState -> (Result OmniReply String)
  (let [(items (map (fn [(p (Pair String BrowserTarget))] -> String
                      (let [(t (pairSecond p))]
                        (str "(:browserTarget :id \"" (pairFirst p) "\" :kind :" t.kind " :family \"" t.family
                             "\" :authenticated " (if t.authenticated "true" "false")
                             " :tabsCount " (stringFromInt64 (listLength t.tabs)) " :lastHeartbeat " (secs t.heartbeatMs) ")")))
                    s.targets.targets))]
    (asnOk s (str "(:browserTargets [" (stringJoin items " ") "])\n")))

fn pollBody head: String idKey: String id: String item: (Option String) -> String
  (mt item
    ((some a) (str "(" head "\n  :status :action\n  " idKey " \"" id "\"\n  :hasAction true\n  :action " a ")\n"))
    ((none) (str "(" head "\n  :status :idle\n  " idKey " \"" id "\"\n  :hasAction false)\n")))

fn targetPollGet s: OmniState target: String -> (Result OmniReply String)
  (mt (queryGet target "targetId" "target_id" "target-default")
    ((err e) (err e))
    ((ok tid)
      (let [(ts s.targets)
            (taken (queueTake ts.actions tid))
            (s2 (withTargets s (TargetStore :targets ts.targets :actions (pairSecond taken) :receipts ts.receipts)))]
        (asnOk s2 (pollBody ":targetPollResponse" ":targetId" tid (pairFirst taken))))))

fn extensionPollGet s: OmniState target: String -> (Result OmniReply String)
  (mt (queryGet target "agentId" "agent_id" "ext-default")
    ((err e) (err e))
    ((ok aid)
      (let [(es s.extensions)
            (taken (queueTake es.actions aid))
            (s2 (withExtensions s (ExtensionStore :extensions es.extensions :actions (pairSecond taken) :receipts es.receipts)))]
        (asnOk s2 (pollBody ":extensionPollResponse" ":agentId" aid (pairFirst taken))))))

fn omniGet s: OmniState target: String -> (Option (Result OmniReply String))
  (cond
    ((stringStartsWith? target "/api/asl/project/") (some (projectGet s target)))
    ((exactPath? target "/api/asl/channels") (some (channelsGet s)))
    ((exactPath? target "/api/asl/browser/status") (some (respond s 200 (list (pair "Content-Type" "application/json")) (browserStatusJson))))
    ((exactPath? target "/api/asl/browser/session/list") (some (sessionListGet s)))
    ((exactPath? target "/api/asl/browser/target/list") (some (targetListGet s)))
    ((stringStartsWith? target "/api/asl/browser/target/poll") (some (targetPollGet s target)))
    ((stringStartsWith? target "/api/asl/browser/extension/poll") (some (extensionPollGet s target)))
    (else (none)))

fn dyckScan bs: Bytes n: Int64 i: Int64 depth: Int64 inStr: Bool esc: Bool -> Bool
  (if (>= i n)
    (= depth 0)
    (let [(c (bytesGet bs i))]
      (cond
        (esc (dyckScan bs n (+ i 1) depth inStr false))
        ((= c 92) (dyckScan bs n (+ i 1) depth inStr true))
        ((= c 34) (dyckScan bs n (+ i 1) depth (not inStr) false))
        (inStr (dyckScan bs n (+ i 1) depth inStr false))
        ((= c 40) (dyckScan bs n (+ i 1) (+ depth 1) inStr false))
        ((= c 41) (if (= depth 0) false (dyckScan bs n (+ i 1) (- depth 1) inStr false)))
        (else (dyckScan bs n (+ i 1) depth inStr false)))))

fn dyckBalanced? text: String -> Bool
  (let [(bs (stringToBytes text))] (dyckScan bs (bytesLength bs) 0 0 false false))

fn storeIf xs: (List (Pair String String)) hit: Bool k: String v: String -> (List (Pair String String))
  (if hit (assocSet xs k v) xs)

fn ingestPost s: OmniState body: String -> (Result OmniReply String)
  (if (not (dyckBalanced? body))
    (respond s 400 (list (pair "Content-Type" "application/asn+sexpr")) "(:aslReceipt :status :error :reason \"Unbalanced Dyck-1 S-expression\")")
    (let [(pid (optionOr (reQuoted body (list ":id")) "unspecified"))
          (st s.sync)
          (isP (pt/hasSubstr body ":projectSync")) (isC (pt/hasSubstr body ":channelSync"))
          (isR (pt/hasSubstr body ":researchSync")) (isA (pt/hasSubstr body ":assetSync"))
          (count (listLength (filter (fn [(b Bool)] -> Bool b) (list isP isC isR isA))))
          (sync2 (SyncStore :projects (storeIf st.projects isP pid body) :channels (storeIf st.channels isC pid body)
                            :research (storeIf st.research isR pid body) :assets (storeIf st.assets isA pid body)))
          (chash (str "h" (stringFromInt64 (pt/cpCount body)) "-" (stringFromInt64 (pyStrHash s.hashK0 s.hashK1 body 10000000))))]
      (asnOk (withSync s sync2)
             (str "(:aslReceipt\n  :status :ok\n  :entitiesUpdated " (stringFromInt64 (if (= count 0) 1 count))
                  "\n  :projectId \"" pid "\"\n  :contentHash \"" chash "\"\n  :assertCount 1)\n"))))

fn targetRegisterPost s: OmniState body: String nowMs: Int64 -> (Result OmniReply String)
  (let [(tid (optionOr (reQuoted body (list ":targetId" ":id")) "target-default"))
        (lower (pt/pyLower tid))
        (kind (optionOr (reBare body (list ":kind")) "extensionChrome"))
        (family (optionOr (reQuoted body (list ":browserFamily" ":family")) (if (pt/hasSubstr lower "safari") "safari" "chrome")))
        (auth (or (pt/hasSubstr body ":authenticated true") (pt/hasSubstr lower "auth")))
        (t (BrowserTarget :id tid :kind kind :family family :authenticated auth :registeredMs nowMs :heartbeatMs nowMs
                          :status "active" :tabs (list (TargetTab :tabId "tab-1" :title "Active Tab" :url "about:blank"))))
        (ts s.targets)
        (s2 (withTargets s (TargetStore :targets (assocSet ts.targets tid t)
                                        :actions (queueEnsure ts.actions tid)
                                        :receipts (queueEnsure ts.receipts tid))))]
    (asnOk s2 (str "(:targetRegistrationReceipt\n  :status :ok\n  :targetId \"" tid "\"\n  :registeredAt " (secs nowMs) "\n  :bridge :active)\n")))

fn targetReceiptPost s: OmniState body: String -> (Result OmniReply String)
  (let [(aid (optionOr (reQuoted body (list ":actionId")) "act-receipt"))
        (tid (optionOr (reQuoted body (list ":targetId" ":id")) "target-default"))
        (ts s.targets)
        (s2 (withTargets s (TargetStore :targets ts.targets :actions ts.actions :receipts (queuePut ts.receipts tid body))))]
    (asnOk s2 (str "(:targetReceiptAck\n  :status :ok\n  :targetId \"" tid "\"\n  :actionId \"" aid "\")\n")))

fn autoTarget targets: (List (Pair String BrowserTarget)) body: String -> String
  (let [(lower (pt/pyLower body))
        (steel (if (or (pt/hasSubstr lower "scrape") (pt/hasSubstr lower "crawl"))
                 (listHead (filter (fn [(p (Pair String BrowserTarget))] -> Bool (= (pairSecond p).kind "stealthSteel")) targets))
                 (none)))]
    (mt steel
      ((some p) (pairFirst p))
      ((none) (mt (listHead targets) ((some p) (pairFirst p)) ((none) "target-auto-steel")))))

fn targetExecPost s: OmniState body: String nowMs: Int64 -> (Result OmniReply String)
  (let [(aid (optionOr (reQuoted body (list ":id")) (str "act-" (stringFromInt64 (mod nowMs 1000000)))))
        (op (optionOr (reLead body (list ":op")) "navigate"))
        (ts s.targets)
        (tid (optionOr (reQuoted body (list ":targetId" ":target")) (autoTarget ts.targets body)))
        (s2 (withTargets s (TargetStore :targets ts.targets :actions (queuePut ts.actions tid body) :receipts ts.receipts)))]
    (asnOk s2 (str "(:targetActionReceipt\n  :id \"" aid "\"\n  :status :ok\n  :targetId \"" tid "\"\n  :op \"" op "\"\n  :queued true)\n")))

fn extensionRegisterPost s: OmniState body: String nowMs: Int64 -> (Result OmniReply String)
  (let [(aid (optionOr (reQuoted body (list ":agentId")) "ext-default"))
        (x (BrowserExtension :agentId aid :registeredMs nowMs :lastPollMs nowMs
                             :tabsCount (optionOr (reDigits body (list ":tabsCount")) "1") :status "active"))
        (es s.extensions)
        (s2 (withExtensions s (ExtensionStore :extensions (assocSet es.extensions aid x)
                                              :actions (queueEnsure es.actions aid)
                                              :receipts (queueEnsure es.receipts aid))))]
    (asnOk s2 (str "(:extensionRegistrationReceipt\n  :status :ok\n  :agentId \"" aid "\"\n  :registeredAt " (secs nowMs) "\n  :bridge :active)\n")))

fn extensionReceiptPost s: OmniState body: String -> (Result OmniReply String)
  (let [(actId (optionOr (reQuoted body (list ":actionId")) "act-receipt"))
        (aid (optionOr (reQuoted body (list ":agentId")) "ext-default"))
        (es s.extensions)
        (s2 (withExtensions s (ExtensionStore :extensions es.extensions :actions es.actions :receipts (queuePut es.receipts aid body))))]
    (asnOk s2 (str "(:extensionReceiptAck\n  :status :ok\n  :actionId \"" actId "\")\n")))

fn browserExecPost s: OmniState body: String -> (Result OmniReply String)
  (let [(actId (optionOr (reQuoted body (list ":id")) "act-exec-001"))
        (op (optionOr (reLead body (list ":op")) "navigate"))
        (url (optionOr (reQuoted body (list ":target")) "https://gemini.google.com/app"))
        (duration (optionOr (reDigits body (list ":durationSec" ":duration")) "45"))
        (es s.extensions)
        (s2 (withExtensions s (ExtensionStore :extensions es.extensions :actions (queuePutAll es.actions body) :receipts es.receipts)))]
    (asnOk s2 (str "(:browserActionReceipt\n  :id \"" actId "\"\n  :status :ok\n  :op \"" op "\"\n  :duration " duration
                   "\n  :url \"" url "\"\n  :artifact \"artifacts/snapshot.asn\"\n  :text \"Browser action " op " executed successfully\")\n")))

fn pad6 n: Int64 -> String
  (let [(d (stringFromInt64 n))] (str (stringRepeat "0" (max 0 (- 6 (stringLength d)))) d))

fn sessionSpawn s: OmniState body: String nowMs: Int64 -> (Result OmniReply String)
  (let [(sid (str "sess-" (pad6 (mod nowMs 1000000))))
        (x (BrowserSession :id sid :createdMs nowMs :lastActiveMs nowMs
                           :profile (optionOr (reQuoted body (list ":profile")) "chromeStealth")
                           :mode (optionOr (reBare body (list ":mode")) "auto")
                           :currentUrl "about:blank" :tabId (str "tab-" sid) :status "active" :history (list)))]
    (asnOk (withSessions s (assocSet s.sessions sid x))
           (str "(:browserSessionReceipt\n  :action :spawn\n  :status :ok\n  :sessionId \"" sid "\"\n  :tabId \"tab-" sid "\"\n  :active true)\n")))

fn sessionStep s: OmniState body: String nowMs: Int64 -> (Result OmniReply String)
  (let [(sid (optionOr (reQuoted body (list ":sessionId")) ""))
        (found (assocGet s.sessions sid))
        (stepOp (optionOr (reLead body (list ":stepOp")) "navigate"))
        (url (optionOr (reQuoted body (list ":url")) (mt found ((some x) x.currentUrl) ((none) "about:blank"))))
        (sessions2 (mt found
                     ((some x) (assocSet s.sessions sid
                                 (BrowserSession :id x.id :createdMs x.createdMs :lastActiveMs nowMs :profile x.profile
                                                 :mode x.mode :currentUrl url :tabId x.tabId :status x.status
                                                 :history (listAppend x.history (list stepOp)))))
                     ((none) s.sessions)))]
    (asnOk (withSessions s sessions2)
           (str "(:browserSessionReceipt\n  :action :step\n  :status :ok\n  :sessionId \"" sid "\"\n  :stepOp \"" stepOp "\"\n  :currentUrl \"" url "\")\n")))

fn sessionSnapshot s: OmniState body: String -> (Result OmniReply String)
  (let [(sid (optionOr (reQuoted body (list ":sessionId")) ""))
        (url (mt (assocGet s.sessions sid) ((some x) x.currentUrl) ((none) "https://example.com")))]
    (asnOk s (str "(:pageSnapshot\n  :sessionId \"" sid "\"\n  :url \"" url "\"\n  :title \"Session Document\"\n  :status :ok\n  :text \"Clean session page text content\")\n")))

fn sessionClose s: OmniState body: String -> (Result OmniReply String)
  (let [(sid (optionOr (reQuoted body (list ":sessionId")) ""))]
    (asnOk (withSessions s (assocDel s.sessions sid))
           (str "(:browserSessionReceipt\n  :action :close\n  :status :ok\n  :sessionId \"" sid "\")\n")))

fn sessionPost s: OmniState target: String body: String nowMs: Int64 -> (Result OmniReply String)
  (let [(action (stripSlashes (afterPrefix target "/api/asl/browser/session/")))]
    (cond
      ((= action "spawn") (sessionSpawn s body nowMs))
      ((= action "step") (sessionStep s body nowMs))
      ((= action "snapshot") (sessionSnapshot s body))
      ((= action "close") (sessionClose s body))
      (else (asnOk s (str "(:browserSessionReceipt :action :" action " :status :rejected :error \"Unknown session action\")\n")))))

fn omniPost s: OmniState target: String rawBody: String nowMs: Int64 -> (Option (Result OmniReply String))
  (let [(body (pt/decodeReplace rawBody))]
    (cond
      ((exactPath? target "/api/asl/ingest") (some (ingestPost s body)))
      ((exactPath? target "/api/asl/browser/target/register") (some (targetRegisterPost s body nowMs)))
      ((exactPath? target "/api/asl/browser/target/receipt") (some (targetReceiptPost s body)))
      ((exactPath? target "/api/asl/browser/target/exec") (some (targetExecPost s body nowMs)))
      ((exactPath? target "/api/asl/browser/extension/register") (some (extensionRegisterPost s body nowMs)))
      ((exactPath? target "/api/asl/browser/extension/receipt") (some (extensionReceiptPost s body)))
      ((exactPath? target "/api/asl/browser/exec") (some (browserExecPost s body)))
      ((stringStartsWith? target "/api/asl/browser/session/") (some (sessionPost s target body nowMs)))
      (else (none))))

fn omniDispatch s: OmniState method: String target: String body: String nowMs: Int64 -> (Option (Result OmniReply String))
  (cond
    ((= method "GET") (omniGet s target))
    ((= method "POST") (omniPost s target body nowMs))
    (else (none)))
