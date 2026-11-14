(module aslGateway/capOrderStats
  :x [JournalRow journalRowOf modelNames aliasesOf journalStats ledgerStats measuredStats orderConfigText configUnchanged! commitOrdered! orderCli!]
  :i [(aslGateway/capOrder :a co)
      (aslGateway/usageLedger :a ul)
      (aslGateway/config :a c)
      (aslGateway/modelSync :a ms)
      (asl-parser/reader :a rd)
      (asl-text/say :a sys)])

; (:m :ref GW-CAP-ORDER :do "stat readers and the write-back for capability ordering. Ledger side: the gateway call rows exactly as usageLedger parses them, grouped by alias. Journal side: the conductor journal rows (:t :unit ID :from S :to S :stage STAGE :model M :verdict V :at MS); the journal names the writer model of a unit on its write stage row, not a profile or lane, so a model is credited when it equals a chain alias, and a unit counts green when its journal ever shows :to merged (gated, reviewed and merged), the revert-red proof being part of that merge gate rather than a journal field")
(schema JournalRow
  (:f unit String)
  (:f to String)
  (:f stage String)
  (:f model String)
  (:f verdict String)
  (:f atMs Int64))

fn listAppendOne xs: (List T) x: T -> (List T)
  (listAppend xs (list x))

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn argAfter args: (List String) flag: String d: String -> String
  (match (listHead args)
    ((none) d)
    ((some a) (if (= a flag) (optionOr (listGet args 1) d) (argAfter (optionOr (listTail args) (list)) flag d))))

fn scalarText props: (Map String rd/SExpr) key: String -> String
  (match (mapGet props key)
    ((none) "")
    ((some v) (match (c/asnScalar v) ((c/scalarStr s) s) ((c/scalarInt n) (stringFromInt64 n)) (_ ""))))

fn intText props: (Map String rd/SExpr) key: String -> Int64
  (match (mapGet props key)
    ((none) 0)
    ((some v) (match (c/asnScalar v) ((c/scalarInt n) n) (_ 0))))

; (:m :do "one conductor journal line as a row, none for any other row kind (:profile, :stale, :providerFail ...) or an unreadable line")
fn journalRowOf line: String -> (Option JournalRow)
  (if (not (stringStartsWith? line "(:t "))
    (none)
    (match (c/asnProps (rd/parseSexpr line) (some ":t"))
      ((err _) (none))
      ((ok p) (some (JournalRow :unit (scalarText p "unit") :to (scalarText p "to") :stage (scalarText p "stage")
                      :model (scalarText p "model") :verdict (scalarText p "verdict") :atMs (intText p "at"))))))

; (:m :do "a write attempt the model answers for: a write stage row, minus provider failures, rebases and stall requeues, which say nothing about the model's work; a row without a usable model is still an attempt, counted as unattributed")
fn attempt? r: JournalRow -> Bool
  (and (= r.stage "write")
    (and (not (stringStartsWith? r.verdict "providerFail"))
      (and (!= r.verdict "needs rebase") (!= r.verdict "stalled"))))

fn writerMap rows: (List JournalRow) -> (Map String String)
  (fold (fn [(m (Map String String)) (r JournalRow)] -> (Map String String)
          (if (and (= r.stage "write") (and (= r.to "gating") (not (stringEmpty? r.model)))) (mapSet m r.unit r.model) m))
        (mapEmpty) rows)

fn newest rows: (List JournalRow) -> Int64
  (fold (fn [(a Int64) (r JournalRow)] -> Int64 (if (> r.atMs a) r.atMs a)) 0 rows)

; (:m :do "the journal names the upstream model string, not the alias: two strings match when equal ignoring case, or when one is the other behind a provider/ prefix")
fn sameModel? a: String b: String -> Bool
  (let [(x (stringLower a))
        (y (stringLower b))]
    (and (not (or (stringEmpty? x) (= x "unknown")))
      (or (= x y) (or (stringEndsWith? x (str "/" y)) (stringEndsWith? y (str "/" x))))))

; (:m :do "every alias whose config model row names the string; several aliases sharing one upstream string each match")
fn aliasesOf names: (List (Pair String String)) model: String -> (List String)
  (map (fn [(p (Pair String String))] -> String (pairFirst p))
       (filter (fn [(p (Pair String String))] -> Bool (sameModel? (pairSecond p) model)) names))

; (:m :do "(alias upstream-name) for every model row of a config text, empty when the text does not parse")
fn modelNames cfg: String -> (List (Pair String String))
  (match (c/asnProps (rd/parseSexpr cfg) (some ":gateway"))
    ((err _) (list))
    ((ok props)
      (let [(items (match (mapGet props "models") ((some (rd/sexprList l)) l) ((some (rd/sexprVect v)) v) (_ (list))))]
        (listFlatMap (fn [(m rd/SExpr)] -> (List (Pair String String))
                       (match (c/asnProps m (some ":model"))
                         ((err _) (list))
                         ((ok p) (list (pair (scalarText p "id") (scalarText p "name"))))))
                     items))))

; (:m :do "per alias from journal text through the alias table: attempts and green units, and the count of write attempts no alias claims (unknown, empty or unmatched strings), which credit nobody; only :at >= sinceMs rows count, a merged unit credits the aliases of its last write-to-gating row")
fn journalStats journal: String sinceMs: Int64 names: (List (Pair String String)) -> (Pair (List co/AliasStat) Int64)
  (let [(rows (filter (fn [(r JournalRow)] -> Bool (>= r.atMs sinceMs))
                (listFlatMap (fn [(l String)] -> (List JournalRow) (match (journalRowOf l) ((some r) (list r)) ((none) (list)))) (stringLines journal))))
        (writers (writerMap rows))
        (mergedUnits (mapKeys (fold (fn [(m (Map String Int64)) (r JournalRow)] -> (Map String Int64) (mapSet m r.unit 1)) (mapEmpty) (filter (fn [(r JournalRow)] -> Bool (= r.to "merged")) rows))))
        (greenAliases (listFlatMap (fn [(u String)] -> (List String) (match (mapGet writers u) ((some m) (aliasesOf names m)) ((none) (list)))) mergedUnits))
        (attempts (filter attempt? rows))
        (lost (listLength (filter (fn [(r JournalRow)] -> Bool (listEmpty? (aliasesOf names r.model))) attempts)))
        (hit (fn [(a String) (r JournalRow)] -> Bool (listContains? (aliasesOf names r.model) a)))
        (aliases (mapKeys (fold (fn [(m (Map String Int64)) (r JournalRow)] -> (Map String Int64)
                                  (fold (fn [(m2 (Map String Int64)) (a String)] -> (Map String Int64) (mapSet m2 a 1)) m (aliasesOf names r.model)))
                                (mapEmpty) attempts)))]
    (pair (map (fn [(a String)] -> co/AliasStat
                 (let [(mine (filter (fn [(r JournalRow)] -> Bool (hit a r)) attempts))]
                   (co/AliasStat :alias a :attempts (listLength mine) :green (listLength (filter (fn [(x String)] -> Bool (= x a)) greenAliases)) :calls 0 :callsOk 0 :limitHits 0
                     :capPermille -1 :lastMs (newest mine))))
               aliases)
          lost))

fn limitRow? r: ul/CallRow -> Bool
  (or (= r.status 429) (or (stringStartsWith? r.outcome "limit") (stringStartsWith? r.outcome "daily")))

fn newestCall rows: (List ul/CallRow) -> Int64
  (fold (fn [(a Int64) (r ul/CallRow)] -> Int64 (if (> r.atMs a) r.atMs a)) 0 rows)

; (:m :do "per alias from ledger rows at or after sinceMs: calls that reached the provider, those ok, limit hits (429 or a limit or daily skip), and the free cap in permille as the share of rows that were not limit hits")
fn ledgerStats rows: (List ul/CallRow) sinceMs: Int64 -> (List co/AliasStat)
  (let [(live (filter (fn [(r ul/CallRow)] -> Bool (>= r.atMs sinceMs)) rows))
        (groups (fold (fn [(m (Map String (List ul/CallRow))) (r ul/CallRow)] -> (Map String (List ul/CallRow))
                        (mapSet m r.alias (cons r (optionOr (mapGet m r.alias) (list)))))
                      (mapEmpty) live))]
    (map (fn [(a String)] -> co/AliasStat
           (let [(rs (optionOr (mapGet groups a) (list)))
                 (sent (filter (fn [(r ul/CallRow)] -> Bool (ul/sentOutcome? r.outcome)) rs))
                 (hits (listLength (filter limitRow? rs)))]
             (co/AliasStat :alias a :attempts 0 :green 0 :calls (listLength sent)
               :callsOk (listLength (filter (fn [(r ul/CallRow)] -> Bool (= r.outcome "ok")) sent))
               :limitHits hits :capPermille (- 1000 (/ (* hits 1000) (listLength rs))) :lastMs (newestCall rs))))
         (mapKeys groups)))

fn mergeOne a: co/AliasStat b: co/AliasStat -> co/AliasStat
  (co/AliasStat :alias a.alias :attempts (+ a.attempts b.attempts) :green (+ a.green b.green) :calls (+ a.calls b.calls)
    :callsOk (+ a.callsOk b.callsOk) :limitHits (+ a.limitHits b.limitHits)
    :capPermille (if (>= a.capPermille 0) a.capPermille b.capPermille) :lastMs (if (> a.lastMs b.lastMs) a.lastMs b.lastMs))

; (:m :do "ledger and journal stats unioned by alias, journal fields and ledger fields never double counted since each source fills only its own")
fn measuredStats led: (List co/AliasStat) jr: (List co/AliasStat) -> (List co/AliasStat)
  (let [(names (mapKeys (fold (fn [(m (Map String Int64)) (s co/AliasStat)] -> (Map String Int64) (mapSet m s.alias 1)) (mapEmpty) (listAppend led jr))))]
    (map (fn [(n String)] -> co/AliasStat
           (mergeOne (optionOr (listHead (filter (fn [(s co/AliasStat)] -> Bool (= s.alias n)) led)) (co/untestedStat n))
                     (optionOr (listHead (filter (fn [(s co/AliasStat)] -> Bool (= s.alias n)) jr)) (co/untestedStat n))))
         names))

; (:m :do "one route as source: the profile id, the intent and the chain aliases, plus its options; routes whose chain holds anything but bare aliases are not touched")
(schema OrderRoute
  (:f profile String)
  (:f intent String)
  (:f chain (List String))
  (:f opts co/OrderOpts))

fn routeOf pid: String rf: rd/SExpr -> (Result (Option OrderRoute) String)
  (match (c/asnProps rf (none))
    ((err e) (ok (none)))
    ((ok props)
      (match (co/orderOptsOfProps props)
        ((err e) (err (str "profile " pid ": " e)))
        ((ok (none)) (ok (none)))
        ((ok (some o))
          (let [(chainItems (match (mapGet props "chain") ((some (rd/sexprList l)) l) ((some (rd/sexprVect v)) v) (_ (list))))
                (aliases (listFlatMap (fn [(e rd/SExpr)] -> (List String) (match e ((rd/sexprAtom s) (if (stringStartsWith? s "\"") (list) (list s))) (_ (list)))) chainItems))]
            (if (or (listEmpty? aliases) (!= (listLength aliases) (listLength chainItems)))
              (ok (none))
              (ok (some (OrderRoute :profile pid :intent (stringLower (scalarText props "intent")) :chain aliases :opts o)))))))))

fn profileRoutes pf: rd/SExpr -> (Result (List OrderRoute) String)
  (match (c/asnProps pf (some ":profile"))
    ((err _) (ok (list)))
    ((ok props)
      (let [(pid (scalarText props "id"))
            (items (match (mapGet props "routes") ((some (rd/sexprList l)) l) ((some (rd/sexprVect v)) v) (_ (list))))]
        (fold (fn [(acc (Result (List OrderRoute) String)) (rf rd/SExpr)] -> (Result (List OrderRoute) String)
                (match acc
                  ((err e) (err e))
                  ((ok xs) (match (routeOf pid rf) ((err e) (err e)) ((ok (none)) (ok xs)) ((ok (some r)) (ok (listAppendOne xs r)))))))
              (ok (list)) items))))

; (:m :do "the routes of a gateway config text that carry :order measured; an error text for a bad :order row")
fn orderRoutes cfg: String -> (Result (List OrderRoute) String)
  (match (c/asnProps (rd/parseSexpr cfg) (some ":gateway"))
    ((err e) (err e))
    ((ok props)
      (let [(profiles (match (mapGet props "profiles") ((some (rd/sexprList l)) l) ((some (rd/sexprVect v)) v) (_ (list))))]
        (fold (fn [(acc (Result (List OrderRoute) String)) (pf rd/SExpr)] -> (Result (List OrderRoute) String)
                (match acc
                  ((err e) (err e))
                  ((ok xs) (match (profileRoutes pf) ((err e) (err e)) ((ok more) (ok (listAppend xs more)))))))
              (ok (list)) profiles))))

fn pairsText ps: (List (Pair String Int64)) -> String
  (str "(" (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(" (pairFirst p) " " (stringFromInt64 (pairSecond p)) ")")) ps) " ") ")")

; (:m :do "rewrites each due route: :chain in rank order, :spread to the positive weights (kept as is when none is positive), :orderAt to nowMs; a route not yet due, or without :order, is left byte for byte; the second value is one receipt row per opted route; a config without :order routes comes back identical")
fn orderConfigText cfg: String stats: (List co/AliasStat) nowMs: Int64 -> (Result (Pair String (List String)) String)
  (match (orderRoutes cfg)
    ((err e) (err e))
    ((ok routes)
      (ok (fold (fn [(acc (Pair String (List String))) (r OrderRoute)] -> (Pair String (List String))
                  (let [(label (str r.profile "/" r.intent))]
                    (if (not (co/refreshDue? r.opts nowMs))
                      (pair (pairFirst acc) (listAppendOne (pairSecond acc) (str "(:order :route " label " :status fresh)")))
                      (let [(rk (co/rankChain r.chain stats r.opts nowMs))
                            (span (ms/routeSpan (pairFirst acc) r.profile r.intent))
                            (a (ms/setField (pairFirst acc) (pairFirst span) (pairSecond span) ":chain" (str "(" (stringJoin (listAppend rk.chain rk.excluded) " ") ")")))
                            (span2 (ms/routeSpan (pairFirst a) r.profile r.intent))
                            (sp (co/spreadWeights rk))
                            (b (if (listEmpty? sp) a (ms/setField (pairFirst a) (pairFirst span2) (pairSecond span2) ":spread" (pairsText sp))))
                            (span3 (ms/routeSpan (pairFirst b) r.profile r.intent))
                            (d (ms/setField (pairFirst b) (pairFirst span3) (pairSecond span3) ":orderAt" (stringFromInt64 nowMs)))]
                        (if (< (pairFirst span) 0)
                          (pair (pairFirst acc) (listAppendOne (pairSecond acc) (str "(:order :route " label " :status missing)")))
                          (pair (pairFirst d)
                                (listAppendOne (pairSecond acc)
                                  (str "(:order :route " label " :status ranked :weights " (pairsText (map (fn [(w (Pair String Int64))] -> (Pair String Int64) w) rk.weights))
                                       " :explored (" (stringJoin rk.explored " ") ") :excluded (" (stringJoin rk.excluded " ") "))"))))))))
                (pair cfg (list)) routes))))

; (:m :do "true when the file still holds exactly the text it was read as, checked just before the rename so a concurrent writer's edit is not overwritten; an unreadable file is changed")
fn ! configUnchanged! path: String expected: String -> Bool
  (match (fileReadString path) ((ok now) (= now expected)) ((err _) false))

fn ! orderRefuse! why: String -> (Result Int64 String)
  (do (sys/sayErr! (str "(:order :status :refused :why " (q why) " :configWritten false)")) (ok 1))

; (:m :do "the write step of `gateway order`, a seam so the race is testable: backup of the text ranked from, tmp file, then between! (nothing in production, a concurrent writer in tests), then the config must still hold the ranked-from text before the rename, else ERR_CONFIG_CHANGED and the tmp file goes; ok 0 only when the config was renamed over")
fn ! commitOrdered! config: String cfgText: String newText: String tmp: String backup: String between!: (fn [] -> Bool) -> (Result Int64 String)
  (cond
    ((not (ok? (fileWrite backup cfgText))) (orderRefuse! (str "cannot write the backup " backup)))
    ((not (ok? (fileWrite tmp newText))) (orderRefuse! (str "cannot write " tmp)))
    ((not (between!)) (do (pathRemove tmp) (orderRefuse! "between hook failed")))
    ((not (configUnchanged! config cfgText)) (do (pathRemove tmp) (orderRefuse! (str "ERR_CONFIG_CHANGED: " config " changed while ranking; nothing written, rerun"))))
    (else
      (match (pathRename tmp config)
        ((err e) (do (pathRemove tmp) (orderRefuse! (str "cannot rename over " config ": " e))))
        ((ok _) (ok 0)))))

; (:m :do "asl gateway order [--config P] [--ledger P] [--journal P] [--now MS] [--windowH H] [--apply]: ranks every route carrying :order measured from the ledger and the conductor journal, prints one receipt row per route, and with --apply writes the config through a backup and a tmp file after config check passes; without --apply nothing is written")
fn ! orderCli! args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") "/tmp"))
        (config (argAfter args "--config" (c/gatewayProfilesPath home)))
        (nowMs (optionOr (stringToInt64 (argAfter args "--now" "")) (/ (nowNs) 1000000)))
        (windowH (optionOr (stringToInt64 (argAfter args "--windowH" "")) 72))
        (sinceMs (- nowMs (* windowH 3600000)))
        (tmp (str config ".order.tmp"))
        (root (optionOr (envGet "ASL_GATEWAY_ROOT") (optionOr (envGet "ROOT_DIR") ".")))
        (registryEnv (optionOr (envGet "ASL_CALIBRATION_INDEX") ""))
        (registry (if (stringEmpty? registryEnv) (str root "/.asl/mem/calibration/index.asn") registryEnv))]
    (match (fileReadString config)
      ((err e) (orderRefuse! (str "cannot read " config ": " e)))
      ((ok cfgText)
        (let [(ledgerPath (argAfter args "--ledger" (optionOr (c/gatewaySharedUsagePathOverride cfgText) (ul/defaultSharedUsagePath home))))
              (journalPath (argAfter args "--journal" ""))
              (rows (resultOr (ul/readRowsSince! ledgerPath sinceMs) (list)))
              (journal (if (stringEmpty? journalPath) "" (resultOr (fileReadString journalPath) "")))
              (jres (journalStats journal sinceMs (modelNames cfgText)))
              (stats (measuredStats (ledgerStats rows sinceMs) (pairFirst jres)))]
          (match (orderConfigText cfgText stats nowMs)
            ((err e) (orderRefuse! e))
            ((ok res)
              (let [(newText (pairFirst res))
                    (receipt (str "(:order :config " (q config) " :now " (stringFromInt64 nowMs) " :ledgerRows " (stringFromInt64 (listLength rows))
                                  " :journal " (if (stringEmpty? journalPath) "none" (q journalPath)) " :unattributed " (stringFromInt64 (pairSecond jres)) " :routes (" (stringJoin (pairSecond res) " ") ")"))]
                (cond
                  ((= newText cfgText) (do (sys/say! (str receipt " :changed false :configWritten false)")) (ok 0)))
                  ((not (listContains? args "--apply")) (do (sys/say! (str receipt " :changed true :configWritten false)")) (ok 0)))
                  (else
                    (let [(checked (c/gatewayConfigCheckText! newText tmp registry))]
                      (if (!= (pairSecond checked) 0)
                        (do (sys/sayErr! (pairFirst checked)) (orderRefuse! "configCheck failed on the ranked config; the config is untouched"))
                        (let [(backup (str config ".bak-" (ms/todayUtc!) "-" (stringFromInt64 nowMs)))]
                          (match (commitOrdered! config cfgText newText tmp backup (fn [] -> Bool true))
                            ((ok 0) (do (sys/say! (str receipt " :changed true :backup " (q backup) " :configWritten true)")) (ok 0)))
                            (other other))))))))))))))
