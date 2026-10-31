(module aslGateway/usageLedger
  :x [CallRow
      CallParams
      defaultCallParams
      Stat
      maxLedgerBytes
      defaultLedgerPath
      legacyLedgerPath
      defaultSharedUsagePath
      callRowLine
      callRowParse
      rotateIfNeeded!
      defaultLedgerKeep
      generations!
      rotateWith!
      appendCallRow!
      appendCallRowWith!
      readRows!
      readRowsSince!
      windowRead!
      redactReason
      rowsInWindow
      filterByTag
      paramNames
      keyByParam
      keyByParamNamed
      keyByProvider
      keyByModel
      keyByAlias
      dayKeyOf
      keyByDayProviderModel
      keyFor
      windowMsOf
      computeStats
      computeDailyStats
      profileTokensToday
      statLine
      statsAsn]
  :i [(aslGateway/usage :a g)
      (aslGateway/wire :a wire)
      (aslGateway/config :a c)
      (aslGateway/localTime :a lt)
      (asl-parser/reader :a rd)])

; (:m one append-only row per gateway upstream attempt: at/profile/intent/alias/provider/model/in/cached/out/ttftMs/ms/outcome/charge, plus a caller tag for joining with calibration runs and the effective request parameters applied after profile/model defaults; ttftMs, ms and the optional params are absent when the caller never measured or set them)
(schema CallRow
  (:f atMs Int64)
  (:f profile String)
  (:f intent String)
  (:f alias String)
  (:f provider String)
  (:f model String)
  (:f inTokens Int64)
  (:f cachedTokens Int64)
  (:f outTokens Int64)
  (:f reasoningTokens Int64)
  (:f ttftMs (Option Int64))
  (:f ms (Option Int64))
  (:f outcome String)
  (:f charge Int64)
  (:f tag (Option String))
  (:f temperature (Option Float64))
  (:f topP (Option Float64))
  (:f maxTokens (Option Int64))
  (:f effort (Option String))
  (:f api String)
  (:f stream Bool)
  (:f toolCount Int64)
  (:f promptBytes Int64)
  (:f sysHash String)
  (:f session (Option String))
  (:f turn (Option Int64))
  (:f consumer (Option String))
  (:f cacheWriteTokens (Option Int64))
  ; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "the HTTP status the upstream answered (0 when there was no answer: a skip, a timeout, a transport error) and, for a failed attempt, the upstream's own reason, redacted by callRowLine; both optional on read so older rows still parse")
  (:f status Int64)
  (:f reason (Option String)))

; (:m the effective request parameters actually sent upstream, read back out of the outgoing request body rather than guessed from config, so a parameter the provider ignored is still recorded as sent)
(schema CallParams
  (:f temperature (Option Float64))
  (:f topP (Option Float64))
  (:f maxTokens (Option Int64))
  (:f effort (Option String))
  (:f api String)
  (:f stream Bool)
  (:f toolCount Int64)
  (:f promptBytes Int64)
  (:f sysHash String))

fn defaultCallParams -> CallParams
  (CallParams :temperature none :topP none :maxTokens none :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "")

(schema Stat
  (:f key String)
  (:f calls Int64)
  (:f ok Int64)
  (:f inTokens Int64)
  (:f cachedTokens Int64)
  (:f outTokens Int64)
  (:f reasoningTokens Int64)
  (:f meanMs (Option Float64))
  (:f p50Ms (Option Int64))
  (:f p90Ms (Option Int64))
  (:f outputTps (Option Float64))
  (:f tpsBasis String)
  (:f charge Int64))

fn maxLedgerBytes -> Int64
  10485760

; (:m :ref SUBPACE :do "one ledger: the stats ledger and the shared accounting ledger are the same file (usage/gatewayCalls.asn), so every reader sees every call; before this the server appended each row to two files that started on different days and counted differently (4947 against 1852 rows on the Mac); legacyLedgerPath is the old stats file, folded in once by subs ledgerMerge")
fn defaultLedgerPath home: String -> String
  (g/posixJoin home ".asl/run/usage/gatewayCalls.asn")

fn legacyLedgerPath home: String -> String
  (g/posixJoin home ".asl/run/gatewayCalls.asn")

; (:m :ref GW-USAGE-ACCOUNTING-20261017 :do "distinct from defaultLedgerPath above: this is the shared accounting ledger every gateway call appends to regardless of HOME, meant to survive a scratch HOME's deletion; the default here is still home-derived (same as defaultLedgerPath) because a process with no override genuinely has no other home to use -- gatewaySharedUsagePathOverride (asl-gateway/config) is what actually makes this survive a scratch HOME, by carrying an absolute path verbatim into every copy of the real gateway.asn")
fn defaultSharedUsagePath home: String -> String
  (g/posixJoin home ".asl/run/usage/gatewayCalls.asn")

fn asnStr s: String -> String
  (str "\"" (wire/asnEscape s) "\"")

fn optIntAsn v: (Option Int64) -> String
  (match v ((some n) (stringFromInt64 n)) ((none) "absent"))

fn optFloatAsn v: (Option Float64) -> String
  (match v ((some f) (stringFromFloat64 f)) ((none) "absent"))

fn optStrAsn v: (Option String) -> String
  (match v ((some s) (asnStr s)) ((none) "absent"))

; (:m a grouping key is a raw value, never ASN-quoted: statLine/statsAsn quote the whole key once when rendering a Stat, so a key built from an already-quoted string would double-quote on display)
fn optStrGroup v: (Option String) -> String
  (match v ((some s) s) ((none) "absent"))

fn boolAsn b: Bool -> String
  (if b "true" "false")

; (:m :ref LEON-ATTRIB-20261028 :do "the attribution fields are written only when the caller supplied them, never as absent or a default: a row with no session, turn, consumer or cache-write figure is byte-identical to one written before the fields existed")
fn attribAsn row: CallRow -> String
  (str (match row.session ((some s) (str " :session " (asnStr s))) ((none) ""))
       (match row.turn ((some n) (str " :turn " (stringFromInt64 n))) ((none) ""))
       (match row.consumer ((some c) (str " :consumer " (asnStr c))) ((none) ""))
       (match row.cacheWriteTokens ((some n) (str " :cacheWrite " (stringFromInt64 n))) ((none) ""))
       (if (> row.status 0) (str " :status " (stringFromInt64 row.status)) "")
       (match row.reason ((some r) (str " :reason " (asnStr (redactReason r)))) ((none) "")))

fn redactChar? c: String -> Bool
  (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_." c)

fn keyShaped? run: String -> Bool
  (let [(n (stringLength run))
        (letter (fn [(c String)] -> Bool (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" c)))
        (digit (fn [(c String)] -> Bool (stringContains? "0123456789" c)))
        (chars (map (fn [(i Int64)] -> String (optionOr (stringSlice run i (+ i 1)) "")) (range 0 n)))]
    (or (and (stringStartsWith? run "sk-") (>= n 12))
        (and (>= n 24) (and (listAny? letter chars) (listAny? digit chars)))))

fn labelRun? run: String -> Bool
  (let [(u (stringUpper run))]
    (listAny? (fn [(l String)] -> Bool (stringEndsWith? u l)) (list "KEY" "TOKEN" "SECRET" "AUTHORIZATION" "PASSWORD")))

; (:m :ref GW-LEDGER-ROTATION-WINDOW :tags (secrets) :do "a reason is upstream text and may echo a credential: the run after Bearer, the run after a key, token, secret, authorization or password label joined by : or =, and every key-shaped run (24 or more letters, digits, dash, underscore or dot holding a letter and a digit, or sk- and 9 more) become [redacted]; newlines become spaces and the result keeps at most 200 characters")
fn redactReason text: String -> String
  (let [(flat (stringReplace (stringReplace (stringReplace (optionOr (stringSlice text 0 600) text) "\n" " ") "\r" " ") "\t" " "))
        (n (stringLength flat))
        (flush (fn [(st (List String))] -> (List String)
                 (let [(out (optionOr (listGet st 0) "")) (run (optionOr (listGet st 1) "")) (pending (optionOr (listGet st 2) "")) (sep (optionOr (listGet st 3) ""))]
                   (if (stringEmpty? run)
                     st
                     (let [(hide (or (keyShaped? run) (or (= pending "bearer") (and (= pending "label") (or (stringContains? sep ":") (stringContains? sep "="))))))
                           (next (cond ((= (stringUpper run) "BEARER") "bearer") ((labelRun? run) "label") (else "")))]
                       (list (str out (if hide "[redacted]" run)) "" next ""))))))
        (step (fn [(st (List String)) (i Int64)] -> (List String)
                (let [(c (optionOr (stringSlice flat i (+ i 1)) ""))]
                  (if (redactChar? c)
                    (list (optionOr (listGet st 0) "") (str (optionOr (listGet st 1) "") c) (optionOr (listGet st 2) "") (optionOr (listGet st 3) ""))
                    (let [(f (flush st))]
                      (list (str (optionOr (listGet f 0) "") c) "" (optionOr (listGet f 2) "") (str (optionOr (listGet f 3) "") c)))))))
        (done (flush (fold step (list "" "" "" "") (range 0 n))))
        (out (optionOr (listGet done 0) ""))]
    (optionOr (stringSlice out 0 200) out))

fn callRowLine row: CallRow -> String
  (str "(:call :at " (stringFromInt64 row.atMs)
       " :profile " (asnStr row.profile)
       " :intent " (asnStr row.intent)
       " :alias " (asnStr row.alias)
       " :provider " (asnStr row.provider)
       " :model " (asnStr row.model)
       " :in " (stringFromInt64 row.inTokens)
       " :cached " (stringFromInt64 row.cachedTokens)
       " :out " (stringFromInt64 row.outTokens)
       " :reasoning " (stringFromInt64 row.reasoningTokens)
       " :ttftMs " (optIntAsn row.ttftMs)
       " :ms " (optIntAsn row.ms)
       " :outcome " (asnStr row.outcome)
       " :charge " (stringFromInt64 row.charge)
       " :tag " (optStrAsn row.tag)
       " :temperature " (optFloatAsn row.temperature)
       " :topP " (optFloatAsn row.topP)
       " :maxTokens " (optIntAsn row.maxTokens)
       " :effort " (optStrAsn row.effort)
       " :api " (asnStr row.api)
       " :stream " (boolAsn row.stream)
       " :toolCount " (stringFromInt64 row.toolCount)
       " :promptBytes " (stringFromInt64 row.promptBytes)
       " :sysHash " (asnStr row.sysHash) (attribAsn row) ")\n")

fn fieldInt props: (Map String rd/SExpr) key: String -> (Option Int64)
  (match (mapGet props key)
    ((none) none)
    ((some e) (match (c/asnScalar e) ((c/scalarInt n) (some n)) (_ none))))

fn fieldStr props: (Map String rd/SExpr) key: String -> (Option String)
  (match (mapGet props key)
    ((none) none)
    ((some e) (match (c/asnScalar e) ((c/scalarStr s) (some s)) (_ none))))

fn fieldOptInt props: (Map String rd/SExpr) key: String -> (Option (Option Int64))
  (match (mapGet props key)
    ((none) none)
    ((some e)
     (match (c/asnScalar e)
       ((c/scalarInt n) (some (some n)))
       ((c/scalarStr s) (if (= s "absent") (some none) none))
       (_ none))))

fn fieldOptFloat props: (Map String rd/SExpr) key: String -> (Option (Option Float64))
  (match (mapGet props key)
    ((none) none)
    ((some e)
     (match (c/asnScalar e)
       ((c/scalarFloat f) (some (some f)))
       ((c/scalarInt n) (some (some (int64ToFloat64 n))))
       ((c/scalarStr s) (if (= s "absent") (some none) none))
       (_ none))))

fn fieldOptStr props: (Map String rd/SExpr) key: String -> (Option (Option String))
  (match (mapGet props key)
    ((none) none)
    ((some e)
     (match (c/asnScalar e)
       ((c/scalarStr s) (if (= s "absent") (some none) (some (some s))))
       (_ none))))

fn fieldBool props: (Map String rd/SExpr) key: String -> (Option Bool)
  (match (mapGet props key)
    ((none) none)
    ((some e) (match (c/asnScalar e) ((c/scalarBool b) (some b)) (_ none))))

fn callRowParse line: String -> (Result CallRow String)
  (let [(trimmed (stringTrim line))]
    (if (stringEmpty? trimmed)
      (err "corrupt call row: empty line")
      (match (c/asnProps (rd/parseSexpr trimmed) (some ":call"))
        ((err e) (err (str "corrupt call row: " e)))
        ((ok props)
         (let [(at (fieldInt props "at")) (profile (fieldStr props "profile")) (intent (fieldStr props "intent"))
               (alias (fieldStr props "alias")) (provider (fieldStr props "provider")) (model (fieldStr props "model"))
               (inTok (fieldInt props "in")) (cachedTok (fieldInt props "cached")) (outTok (fieldInt props "out"))
               ; (:m :ref GW-USAGE-ACCOUNTING-20261017 :do ":reasoning is read as optional, never added to allOk below: every row written before this field existed has none, and callRowParse must keep reading a ledger a gateway wrote yesterday")
               (reasoningTok (fieldInt props "reasoning"))
               (ttft (fieldOptInt props "ttftMs")) (ms (fieldOptInt props "ms")) (outcome (fieldStr props "outcome"))
               (charge (fieldInt props "charge")) (tag (fieldOptStr props "tag"))
               (temperature (fieldOptFloat props "temperature")) (topP (fieldOptFloat props "topP"))
               (maxTokens (fieldOptInt props "maxTokens")) (effort (fieldOptStr props "effort"))
               (api (fieldStr props "api")) (stream (fieldBool props "stream"))
               (toolCount (fieldInt props "toolCount")) (promptBytes (fieldInt props "promptBytes"))
               (sysHash (fieldStr props "sysHash"))
               (allOk (listAll? (fn [(b Bool)] -> Bool b)
                        (list (some? at) (some? profile) (some? intent) (some? alias) (some? provider) (some? model)
                              (some? inTok) (some? cachedTok) (some? outTok) (some? ttft) (some? ms) (some? outcome) (some? charge)
                              (some? tag) (some? temperature) (some? topP) (some? maxTokens) (some? effort)
                              (some? api) (some? stream) (some? toolCount) (some? promptBytes) (some? sysHash))))]
           (if (not allOk)
             (err (str "corrupt call row: missing or mistyped field in " trimmed))
             (ok (CallRow :atMs (optionOr at 0) :profile (optionOr profile "") :intent (optionOr intent "") :alias (optionOr alias "")
                   :provider (optionOr provider "") :model (optionOr model "") :inTokens (optionOr inTok 0) :cachedTokens (optionOr cachedTok 0)
                   :outTokens (optionOr outTok 0) :reasoningTokens (optionOr reasoningTok 0) :ttftMs (optionOr ttft none) :ms (optionOr ms none) :outcome (optionOr outcome "")
                   :charge (optionOr charge 0) :tag (optionOr tag none)
                   :temperature (optionOr temperature none) :topP (optionOr topP none) :maxTokens (optionOr maxTokens none)
                   :effort (optionOr effort none) :api (optionOr api "") :stream (optionOr stream false)
                   :toolCount (optionOr toolCount 0) :promptBytes (optionOr promptBytes 0) :sysHash (optionOr sysHash "")
                   :session (optionOr (fieldOptStr props "session") none) :turn (optionOr (fieldOptInt props "turn") none)
                   :consumer (optionOr (fieldOptStr props "consumer") none) :cacheWriteTokens (optionOr (fieldOptInt props "cacheWrite") none)
                   :status (optionOr (fieldInt props "status") 0) :reason (optionOr (fieldOptStr props "reason") none)))))))))

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "a full ledger is renamed to path.N with N one above the highest kept generation, so a generation keeps its name until it is pruned and a reader never sees a file change name under it; only the newest keep generations survive (default 8, (:gateway :ledgerKeep N)); the rename and prune run under path.rotate's lock, re-checking the size, so two writers never rotate twice nor overwrite a generation; before, path.1 was overwritten on every rotation and a 24 h window lost everything older than one 10 MB file")
fn defaultLedgerKeep -> Int64
  8

fn generationSeq base: String name: String -> (Option Int64)
  (if (and (stringStartsWith? name (str base ".")) (> (stringLength name) (+ (stringLength base) 1)))
    (let [(rest (optionOr (stringSlice name (+ (stringLength base) 1) (stringLength name)) ""))]
      (match (stringToInt64 rest) ((some k) (if (= (stringFromInt64 k) rest) (some k) none)) ((none) none)))
    none)

fn ! generations! path: String -> (List Int64)
  (let [(base (optionOr (listLast (stringSplit path "/")) path))]
    (listSort (fold (fn [(acc (List Int64)) (name String)] -> (List Int64) (match (generationSeq base name) ((some k) (cons k acc)) ((none) acc)))
                    (list) (resultOr (dirList (g/posixDirname path)) (list)))))

fn ! pruneGenerations! path: String gens: (List Int64) keep: Int64 -> Bool
  (listAll? (fn [(k Int64)] -> Bool (ok? (pathRemove (str path "." (stringFromInt64 k))))) (listTake gens (max 0 (- (listLength gens) (max 1 keep)))))

fn ! shiftUnderLock! path: String maxBytes: Int64 keep: Int64 -> (Result Bool String)
  (match (fileStat path)
    ((err _) (ok false))
    ((ok st)
     (if (or (not st.isFile) (< st.size maxBytes))
       (ok false)
       (let [(gens (generations! path))
             (next (+ (fold (fn [(a Int64) (b Int64)] -> Int64 (max a b)) 0 gens) 1))]
         (match (pathRename path (str path "." (stringFromInt64 next)))
           ((err e) (err (str "rotate " path ": " e)))
           ((ok _) (do (pruneGenerations! path (listAppend gens (list next)) keep) (ok true))))))))

fn ! rotateWith! path: String maxBytes: Int64 keep: Int64 -> (Result Bool String)
  (match (fileStat path)
    ((err _) (ok false))
    ((ok st)
     (if (not (and st.isFile (>= st.size maxBytes)))
       (ok false)
       (match (fileLock (str path ".rotate") true)
         ((err e) (if (= e "busy") (ok false) (err (str "rotate lock " path ": " e))))
         ((ok fd)
          (let [(res (shiftUnderLock! path maxBytes keep))
                (closed (fdClose fd))]
            res))))))

fn ! rotateIfNeeded! path: String -> (Result Bool String)
  (rotateWith! path (maxLedgerBytes) (defaultLedgerKeep))

fn ! appendCallRowWith! path: String row: CallRow maxBytes: Int64 keep: Int64 -> (Result Bool String)
  (match (dirCreate (g/posixDirname path))
    ((err e) (err (str "ledger dir " (g/posixDirname path) ": " e)))
    ((ok _)
     (match (rotateWith! path maxBytes keep)
       ((err e) (err e))
       ((ok _) (g/appendFile! path (callRowLine row) 200)))))

fn ! appendCallRow! path: String row: CallRow -> (Result Bool String)
  (appendCallRowWith! path row (maxLedgerBytes) (defaultLedgerKeep))

fn nonEmptyLines text: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringSplit text "\n"))

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "a reader does not take the append lock, so the last row may be half written; only text up to the last newline counts and the cut row is read on the next pass, never as a corrupt file")
fn completeLines text: String -> (List String)
  (let [(parts (stringSplit text "\n"))]
    (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (listTake parts (max 0 (- (listLength parts) 1)))))

fn parseRowsLoop lines: (List String) acc: (List CallRow) -> (Result (List CallRow) String)
  (match (listHead lines)
    ((none) (ok (listReverse acc)))
    ((some l)
     (match (callRowParse l)
       ((err e) (err e))
       ((ok row) (parseRowsLoop (optionOr (listTail lines) (list)) (cons row acc))))))

fn ! fileRows! file: String -> (Result (List CallRow) String)
  (match (fileStat file)
    ((err _) (ok (list)))
    ((ok st)
     (if st.isDir
       (err (str file " is a directory"))
       (match (fileReadString file)
         ((err e) (err (str "read " file ": " e)))
         ((ok raw) (parseRowsLoop (completeLines raw) (list)))))))

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "the live file read between two listings of the generations: when a rotation renamed it in between, the read repeats, so a row is never counted both in the live text and in the generation it moved to")
fn ! liveSnapshot! path: String tries: Int64 -> (Result (Pair (List Int64) (List CallRow)) String)
  (let [(before (generations! path))
        (live (fileRows! path))
        (after (generations! path))]
    (if (and (not (= before after)) (> tries 0))
      (liveSnapshot! path (- tries 1))
      (match live ((err e) (err e)) ((ok rows) (ok (pair after rows))))))

fn reachesBack? rows: (List CallRow) sinceMs: Int64 -> Bool
  (match (listHead rows) ((some r) (<= r.atMs sinceMs)) ((none) false))

fn ! olderUntil! path: String newestFirst: (List Int64) sinceMs: Int64 files: (List String) rows: (List CallRow) -> (Result (Pair (List String) (List CallRow)) String)
  (match (listHead newestFirst)
    ((none) (ok (pair files rows)))
    ((some k)
     (if (reachesBack? rows sinceMs)
       (ok (pair files rows))
       (let [(file (str path "." (stringFromInt64 k)))]
         (match (fileRows! file)
           ((err e) (err e))
           ((ok older) (olderUntil! path (optionOr (listTail newestFirst) (list)) sinceMs (listAppend files (list file)) (listAppend older rows))))))))

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "rows at or after sinceMs and the files read for them: the live file always, then generations newest first only until a file's first row is at or before sinceMs, so a minute window opens the live file alone and only a day, week or month window reaches older generations")
fn ! windowRead! path: String sinceMs: Int64 -> (Result (Pair (List String) (List CallRow)) String)
  (match (liveSnapshot! path 3)
    ((err e) (err e))
    ((ok snap)
     (match (olderUntil! path (listReverse (pairFirst snap)) sinceMs (list path) (pairSecond snap))
       ((err e) (err e))
       ((ok got) (ok (pair (pairFirst got) (filter (fn [(r CallRow)] -> Bool (>= r.atMs sinceMs)) (pairSecond got))))))))

fn ! readRowsSince! path: String sinceMs: Int64 -> (Result (List CallRow) String)
  (match (windowRead! path sinceMs) ((ok got) (ok (pairSecond got))) ((err e) (err e)))

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "every kept row, oldest generation first then the live file; before, only the live file was read, so after a rotation a 24 h window came back empty")
fn ! readRows! path: String -> (Result (List CallRow) String)
  (match (windowRead! path (- 0 1)) ((ok got) (ok (pairSecond got))) ((err e) (err e)))

fn windowMsOf text: String -> (Result Int64 String)
  (cond
    ((= text "1h") (ok 3600000))
    ((= text "24h") (ok 86400000))
    ((= text "7d") (ok 604800000))
    (else (err (str "unknown window " (asnStr text) ": use 1h, 24h or 7d"))))

fn rowsInWindow rows: (List CallRow) nowMs: Int64 windowMs: Int64 -> (List CallRow)
  (let [(since (- nowMs windowMs))]
    (filter (fn [(r CallRow)] -> Bool (>= r.atMs since)) rows))

; (:m an empty tag filters nothing, since the ledger's caller tag is itself optional; a non-empty tag matches only rows whose tag equals it exactly, calibration joins a run's outcome to its calls this way)
fn filterByTag rows: (List CallRow) tag: String -> (List CallRow)
  (if (stringEmpty? tag) rows (filter (fn [(r CallRow)] -> Bool (= (optionOr r.tag "") tag)) rows))

fn keyByProvider r: CallRow -> String
  r.provider

fn keyByModel r: CallRow -> String
  r.model

fn keyByAlias r: CallRow -> String
  r.alias

fn pad2 n: Int64 -> String
  (if (< n 10) (str "0" (stringFromInt64 n)) (stringFromInt64 n))

; (:m :ref GW-USAGE-ACCOUNTING-20261017 :do "calendar day in UTC from a row's :atMs, for the per-day per-provider per-model total command; UTC rather than local time keeps the bucketing stable across machines and avoids pulling in zone data for pure accounting")
fn dayKeyOf atMs: Int64 -> String
  (let [(days (/ atMs 86400000))
        (ymd (lt/civilFromDays days))
        (y (optionOr (listGet ymd 0) 1970)) (m (optionOr (listGet ymd 1) 1)) (d (optionOr (listGet ymd 2) 1))]
    (str (stringFromInt64 y) "-" (pad2 m) "-" (pad2 d)))

fn keyByDayProviderModel r: CallRow -> String
  (str (dayKeyOf r.atMs) "|" r.provider "|" r.model)

fn paramNames -> (List String)
  (list "temperature" "topP" "maxTokens" "effort" "api" "stream" "toolCount" "promptBytes" "sysHash" "tag")

fn keyByParam name: String r: CallRow -> String
  (cond
    ((= name "temperature") (optFloatAsn r.temperature))
    ((= name "topP") (optFloatAsn r.topP))
    ((= name "maxTokens") (optIntAsn r.maxTokens))
    ((= name "effort") (optStrGroup r.effort))
    ((= name "api") r.api)
    ((= name "stream") (boolAsn r.stream))
    ((= name "toolCount") (stringFromInt64 r.toolCount))
    ((= name "promptBytes") (stringFromInt64 r.promptBytes))
    ((= name "sysHash") r.sysHash)
    ((= name "tag") (optStrGroup r.tag))
    (else ""))

fn keyByParamNamed name: String -> (fn [CallRow] -> String)
  (fn [(r CallRow)] -> String (keyByParam name r))

fn keyFor by: String -> (Result (fn [CallRow] -> String) String)
  (cond
    ((= by "provider") (ok keyByProvider))
    ((= by "model") (ok keyByModel))
    ((= by "alias") (ok keyByAlias))
    ((= by "dayProviderModel") (ok keyByDayProviderModel))
    ((stringStartsWith? by "param:")
     (let [(name (optionOr (stringSlice by 6 (stringLength by)) ""))]
       (if (listContains? (paramNames) name)
         (ok (keyByParamNamed name))
         (err (str "unknown --by param:" (asnStr name) ": use one of " (stringJoin (paramNames) ", "))))))
    (else (err (str "unknown --by " (asnStr by) ": use provider, model, alias, dayProviderModel or param:NAME"))))

fn groupRows rows: (List CallRow) keyFn: (fn [CallRow] -> String) -> (Map String (List CallRow))
  (fold (fn [(m (Map String (List CallRow))) (r CallRow)] -> (Map String (List CallRow))
          (let [(k (keyFn r))] (mapSet m k (cons r (optionOr (mapGet m k) (list))))))
        (mapEmpty) rows)

fn latenciesOf rows: (List CallRow) -> (List Int64)
  (listSort (fold (fn [(acc (List Int64)) (r CallRow)] -> (List Int64) (match r.ms ((some m) (cons m acc)) ((none) acc))) (list) rows))

fn genMs r: CallRow -> (Option Int64)
  (match r.ms
    ((none) none)
    ((some m) (match r.ttftMs ((some t) (some (max 0 (- m t)))) ((none) (some m)))))

fn hasTtft? rows: (List CallRow) -> Bool
  (listAny? (fn [(r CallRow)] -> Bool (some? r.ttftMs)) rows)

fn sumGen rows: (List CallRow) -> (Pair Int64 Int64)
  (fold (fn [(acc (Pair Int64 Int64)) (r CallRow)] -> (Pair Int64 Int64)
          (match (genMs r)
            ((none) acc)
            ((some gm) (pair (+ (pairFirst acc) r.outTokens) (+ (pairSecond acc) gm)))))
        (pair 0 0) rows)

fn percentile sorted: (List Int64) p: Float64 -> Int64
  (let [(n (listLength sorted))]
    (if (<= n 0)
      0
      (let [(idx (optionOr (float64ToInt64 (* p (int64ToFloat64 (- n 1)))) 0))]
        (optionOr (listGet sorted idx) 0))))

fn statFor key: String rows: (List CallRow) -> Stat
  (let [(n (listLength rows))
        (okN (listLength (filter (fn [(r CallRow)] -> Bool (= r.outcome "ok")) rows)))
        (inSum (listSum (map (fn [(r CallRow)] -> Int64 r.inTokens) rows)))
        (cachedSum (listSum (map (fn [(r CallRow)] -> Int64 r.cachedTokens) rows)))
        (outSum (listSum (map (fn [(r CallRow)] -> Int64 r.outTokens) rows)))
        (reasoningSum (listSum (map (fn [(r CallRow)] -> Int64 r.reasoningTokens) rows)))
        (chargeSum (listSum (map (fn [(r CallRow)] -> Int64 r.charge) rows)))
        (lats (latenciesOf rows))
        (meanMs (if (listEmpty? lats) none (some (g/pyRound3 (/ (int64ToFloat64 (listSum lats)) (int64ToFloat64 (listLength lats)))))))
        (p50 (if (listEmpty? lats) none (some (percentile lats 0.5))))
        (p90 (if (listEmpty? lats) none (some (percentile lats 0.9))))
        (gen (sumGen rows))
        (tps (if (= (pairSecond gen) 0) none (some (g/pyRound3 (/ (int64ToFloat64 (pairFirst gen)) (/ (int64ToFloat64 (pairSecond gen)) 1000.0))))))
        (basis (if (hasTtft? rows) "ttft" "ms"))]
    (Stat :key key :calls n :ok okN :inTokens inSum :cachedTokens cachedSum :outTokens outSum :reasoningTokens reasoningSum
          :meanMs meanMs :p50Ms p50 :p90Ms p90 :outputTps tps :tpsBasis basis :charge chargeSum))

fn computeStats rows: (List CallRow) nowMs: Int64 windowMs: Int64 keyFn: (fn [CallRow] -> String) -> (List Stat)
  (let [(windowed (rowsInWindow rows nowMs windowMs))
        (groups (groupRows windowed keyFn))]
    (listSortBy (fn [(s Stat)] -> Int64 (- 0 s.calls)) (map (fn [(k String)] -> Stat (statFor k (optionOr (mapGet groups k) (list)))) (mapKeys groups))))

; (:m :ref GW-USAGE-ACCOUNTING-20261017 :do "the per-day per-provider per-model total: every row, no 'now'-relative window, grouped by keyByDayProviderModel; a report rather than a live window, since a day in the past is still a day worth totalling after it ends")
fn computeDailyStats rows: (List CallRow) -> (List Stat)
  (let [(groups (groupRows rows keyByDayProviderModel))]
    (listSortBy (fn [(s Stat)] -> Int64 (- 0 s.calls)) (map (fn [(k String)] -> Stat (statFor k (optionOr (mapGet groups k) (list)))) (mapKeys groups))))

; (:m :ref GW-BUDGET-ENFORCE-20261018 :do "today's total tokens (in+cached+out+reasoning) for one profile, across every provider/model/outcome; feeds the pre-dispatch budget refusal, a single filter+sum rather than another keyFor grouping since enforcement needs one number, not a report")
fn profileTokensToday rows: (List CallRow) day: String profile: String -> Int64
  (listSum (map (fn [(r CallRow)] -> Int64 (+ r.inTokens (+ r.cachedTokens (+ r.outTokens r.reasoningTokens))))
             (filter (fn [(r CallRow)] -> Bool (and (= (dayKeyOf r.atMs) day) (= r.profile profile))) rows)))

fn pct part: Int64 whole: Int64 -> Float64
  (if (= whole 0) 0.0 (g/pyRound3 (* 100.0 (/ (int64ToFloat64 part) (int64ToFloat64 whole)))))

fn statLine s: Stat -> String
  (str "(:stats :key " (asnStr s.key) " :calls " (stringFromInt64 s.calls) " :ok " (stringFromInt64 s.ok)
       " :okPct " (stringFromFloat64 (pct s.ok s.calls))
       " :inTokens " (stringFromInt64 s.inTokens) " :cachedTokens " (stringFromInt64 s.cachedTokens) " :outTokens " (stringFromInt64 s.outTokens)
       " :reasoningTokens " (stringFromInt64 s.reasoningTokens)
       " :cachedSharePct " (stringFromFloat64 (pct s.cachedTokens s.inTokens))
       " :meanMs " (optFloatAsn s.meanMs) " :p50Ms " (optIntAsn s.p50Ms) " :p90Ms " (optIntAsn s.p90Ms)
       " :outputTps " (optFloatAsn s.outputTps) " :tpsBasis " (asnStr s.tpsBasis) " :charge " (stringFromInt64 s.charge) ")")

fn statsAsn stats: (List Stat) -> String
  (stringJoin (map statLine stats) "\n")
