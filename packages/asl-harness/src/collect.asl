(module asl-harness/collect
  :x [Scan scanClaude scanCodex scanAgy isoEpoch epochDays slugOf receiptText pickTranscript! collect!]
  :i [(asl-json/json :a j)])

(schema Scan (:f turns Int64) (:f tokIn Int64) (:f tokOut Int64) (:f tokCached Int64)
  (:f tools (Map String Int64)) (:f errors (Map String Int64)))

fn slice s: String i: Int64 j: Int64 -> String
  (optionOr (stringSlice s i j) "")

fn ! mtimeOf path: String -> Int64
  (match (fileStat path) ((ok st) st.mtime) ((err _) 0))

fn pad2 n: Int64 -> String
  (if (< n 10) (str "0" (stringFromInt64 n)) (stringFromInt64 n))

fn digits s: String -> Int64
  (optionOr (stringToInt64 s) -1)

fn endsWith s: String suffix: String -> Bool
  (let [(n (stringLength s)) (k (stringLength suffix))]
    (and (>= n k) (= (slice s (- n k) n) suffix)))

fn isAlnum c: Int64 -> Bool
  (or (and (>= c 48) (<= c 57)) (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122))))

fn slugOf cwd: String -> String
  (stringJoin (map (fn [(c String)] -> String (if (isAlnum (charCode c)) c "-")) (stringChars cwd)) "")

fn baseName path: String -> String
  (optionOr (listHead (listReverse (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit path "/")))) "")

fn isoEpoch s: String -> Int64
  (let [(y0 (digits (slice s 0 4))) (m (digits (slice s 5 7))) (d (digits (slice s 8 10)))
        (hh (digits (slice s 11 13))) (mm (digits (slice s 14 16))) (ss (digits (slice s 17 19)))]
    (if (or (< y0 0) (or (< m 1) (or (> m 12) (or (< d 1) (or (< hh 0) (or (< mm 0) (< ss 0)))))))
      0
      (let [(y (if (<= m 2) (- y0 1) y0))
            (era (/ y 400))
            (yoe (- y (* era 400)))
            (doy (+ (/ (+ (* 153 (if (> m 2) (- m 3) (+ m 9))) 2) 5) (- d 1)))
            (doe (+ (* yoe 365) (+ (- (/ yoe 4) (/ yoe 100)) doy)))
            (days (- (+ (* era 146097) doe) 719468))]
        (+ (* days 86400) (+ (* hh 3600) (+ (* mm 60) ss))))))

fn epochDays secs: Int64 -> String
  (let [(z (+ (/ secs 86400) 719468))
        (era (/ z 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (- doe (+ (/ doe 1460) (- (/ doe 146096) (/ doe 36524)))) 365))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))
        (y (+ (+ yoe (* era 400)) (if (<= m 2) 1 0)))]
    (str (stringFromInt64 y) "/" (pad2 m) "/" (pad2 d)))

fn parseLine line: String -> (Option j/Json)
  (match (j/jsonParse line) ((ok v) (some v)) ((err _) (none)))

fn textAt o: j/Json key: String -> String
  (match (j/jsonGet o key) ((some v) (match v ((j/jstr s) s) (_ ""))) ((none) ""))

fn intAt o: j/Json key: String -> Int64
  (match (j/jsonGet o key) ((some v) (match v ((j/jint n) n) (_ 0))) ((none) 0))

fn hasAt o: j/Json key: String -> Bool
  (some? (j/jsonGet o key))

fn trueAt o: j/Json key: String -> Bool
  (match (j/jsonGet o key) ((some v) (match v ((j/jbool b) b) (_ false))) ((none) false))

fn objAt o: j/Json key: String -> j/Json
  (optionOr (j/jsonGet o key) (j/jobj (list)))

fn itemsAt o: j/Json key: String -> (List j/Json)
  (match (j/jsonGet o key) ((some v) (match v ((j/jarr xs) xs) (_ (list)))) ((none) (list)))

fn bump m: (Map String Int64) k: String -> (Map String Int64)
  (mapSet m k (+ 1 (optionOr (mapGet m k) 0)))

fn sumMap m: (Map String Int64) -> Int64
  (fold (fn [(acc Int64) (k String)] -> Int64 (+ acc (optionOr (mapGet m k) 0))) 0 (mapKeys m))

fn countNames names: (List String) -> (Map String Int64)
  (fold (fn [(m (Map String Int64)) (n String)] -> (Map String Int64) (bump m n)) (mapEmpty) names)

fn lines text: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringSplit text "\n"))


(schema CAcc (:f ins (Map String Int64)) (:f outs (Map String Int64)) (:f cached (Map String Int64))
  (:f tools (Map String String)) (:f errors (Map String Int64)))

fn claudeAssistant acc: CAcc v: j/Json -> CAcc
  (let [(msg (objAt v "message"))
        (id (if (stringEmpty? (textAt msg "id")) (textAt v "uuid") (textAt msg "id")))
        (u (objAt msg "usage"))
        (blocks (filter (fn [(b j/Json)] -> Bool (= (textAt b "type") "tool_use")) (itemsAt msg "content")))
        (tools (fold (fn [(m (Map String String)) (b j/Json)] -> (Map String String) (mapSet m (textAt b "id") (textAt b "name"))) acc.tools blocks))
        (errs (if (trueAt v "isApiErrorMessage") (bump acc.errors "apiError") acc.errors))]
    (CAcc :ins (mapSet acc.ins id (+ (intAt u "input_tokens") (intAt u "cache_creation_input_tokens")))
          :outs (mapSet acc.outs id (intAt u "output_tokens"))
          :cached (mapSet acc.cached id (intAt u "cache_read_input_tokens"))
          :tools tools :errors errs))

fn claudeUser acc: CAcc v: j/Json -> CAcc
  (let [(bad (filter (fn [(b j/Json)] -> Bool (and (= (textAt b "type") "tool_result") (trueAt b "is_error"))) (itemsAt (objAt v "message") "content")))]
    (CAcc :ins acc.ins :outs acc.outs :cached acc.cached :tools acc.tools
          :errors (fold (fn [(m (Map String Int64)) (b j/Json)] -> (Map String Int64) (bump m "toolError")) acc.errors bad)))

fn claudeLine acc: CAcc line: String -> CAcc
  (if (not (or (stringContains? line "\"assistant\"") (stringContains? line "tool_result")))
    acc
    (match (parseLine line)
      ((none) (CAcc :ins acc.ins :outs acc.outs :cached acc.cached :tools acc.tools :errors (bump acc.errors "unparsedLine")))
      ((some v)
        (let [(t (textAt v "type"))]
          (cond
            ((= t "assistant") (claudeAssistant acc v))
            ((= t "user") (claudeUser acc v))
            (else acc))))))

fn scanClaude text: String -> Scan
  (let [(a (fold claudeLine (CAcc :ins (mapEmpty) :outs (mapEmpty) :cached (mapEmpty) :tools (mapEmpty) :errors (mapEmpty)) (lines text)))]
    (Scan :turns (listLength (mapKeys a.ins)) :tokIn (sumMap a.ins) :tokOut (sumMap a.outs) :tokCached (sumMap a.cached)
          :tools (countNames (map (fn [(k String)] -> String (optionOr (mapGet a.tools k) "")) (mapKeys a.tools)))
          :errors a.errors))


(schema XAcc (:f records Int64) (:f counts Int64) (:f tokIn Int64) (:f tokOut Int64) (:f tokCached Int64)
  (:f tools (Map String Int64)) (:f errors (Map String Int64)))

fn codexLine acc: XAcc line: String -> XAcc
  (if (not (or (stringContains? line "token_") (or (stringContains? line "function_call\"") (or (stringContains? line "custom_tool_call\"") (or (stringContains? line "error") (stringContains? line "turn_aborted"))))))
    acc
    (match (parseLine line)
      ((none) (XAcc :records acc.records :counts acc.counts :tokIn acc.tokIn :tokOut acc.tokOut :tokCached acc.tokCached :tools acc.tools :errors (bump acc.errors "unparsedLine")))
      ((some v)
        (let [(top (textAt v "type"))
              (p (objAt v "payload"))
              (pt (textAt p "type"))
              (tot (objAt (objAt p "info") "total_token_usage"))
              (isCount (and (= pt "token_count") (hasAt tot "input_tokens")))]
          (XAcc :records (if (= top "token_usage_record") (+ acc.records 1) acc.records)
                :counts (if (= pt "token_count") (+ acc.counts 1) acc.counts)
                :tokIn (if isCount (intAt tot "input_tokens") acc.tokIn)
                :tokOut (if isCount (intAt tot "output_tokens") acc.tokOut)
                :tokCached (if isCount (intAt tot "cached_input_tokens") acc.tokCached)
                :tools (if (or (= pt "function_call") (= pt "custom_tool_call")) (bump acc.tools (textAt p "name")) acc.tools)
                :errors (if (or (= pt "error") (or (= pt "stream_error") (= pt "turn_aborted"))) (bump acc.errors pt) acc.errors))))))

fn scanCodex text: String -> Scan
  (let [(a (fold codexLine (XAcc :records 0 :counts 0 :tokIn 0 :tokOut 0 :tokCached 0 :tools (mapEmpty) :errors (mapEmpty)) (lines text)))]
    (Scan :turns (if (> a.records 0) a.records a.counts) :tokIn (- a.tokIn a.tokCached) :tokOut a.tokOut :tokCached a.tokCached
          :tools a.tools :errors a.errors))


fn agyLine acc: Scan line: String -> Scan
  (match (parseLine line)
    ((none) (Scan :turns acc.turns :tokIn acc.tokIn :tokOut acc.tokOut :tokCached acc.tokCached :tools acc.tools :errors (bump acc.errors "unparsedLine")))
    ((some v)
      (let [(planner (= (textAt v "type") "PLANNER_RESPONSE"))
            (status (textAt v "status"))
            (calls (if planner (itemsAt v "tool_calls") (list)))
            (errs (if (or (stringEmpty? status) (= status "DONE")) acc.errors (bump acc.errors (str "step" status))))]
        (Scan :turns (if planner (+ acc.turns 1) acc.turns)
              :tokIn (+ acc.tokIn (intAt v "input_tokens"))
              :tokOut (+ acc.tokOut (intAt v "output_tokens"))
              :tokCached (+ acc.tokCached (intAt v "cache_read_tokens"))
              :tools (fold (fn [(m (Map String Int64)) (c j/Json)] -> (Map String Int64) (bump m (textAt c "name"))) acc.tools calls)
              :errors errs))))

fn scanAgy text: String -> Scan
  (fold agyLine (Scan :turns 0 :tokIn 0 :tokOut 0 :tokCached 0 :tools (mapEmpty) :errors (mapEmpty)) (lines text))


fn stampKey client: String -> String
  (if (= client "agy") "\"created_at\":\"" "\"timestamp\":\"")

fn firstStamp client: String text: String -> Int64
  (let [(key (stampKey client))]
    (match (stringIndexOf text key)
      ((some i) (isoEpoch (slice text (+ i (stringLength key)) (+ i (+ (stringLength key) 19)))))
      ((none) 0)))

fn codexCwd text: String -> String
  (match (parseLine (optionOr (listHead (stringSplit text "\n")) ""))
    ((some v) (textAt (objAt v "payload") "cwd"))
    ((none) ""))

fn ! accepts! client: String path: String startedAt: Int64 cwd: String -> Bool
  (if (< (mtimeOf path) startedAt)
    false
    (match (fileReadString path)
      ((err _) false)
      ((ok text)
        (and (>= (firstStamp client text) (- startedAt 5))
             (if (= client "codex") (= (codexCwd text) cwd) true)))))

fn ! listNames! dir: String -> (List String)
  (match (dirList dir) ((ok names) names) ((err _) (list)))

fn ! candidates! client: String home: String startedAt: Int64 cwd: String -> (List String)
  (cond
    ((= client "claude")
      (let [(dir (str home "/.claude/projects/" (slugOf cwd)))]
        (map (fn [(n String)] -> String (str dir "/" n)) (filter (fn [(n String)] -> Bool (endsWith n ".jsonl")) (listNames! dir)))))
    ((= client "codex")
      (let [(days (map epochDays (list (- startedAt 86400) startedAt (+ startedAt 86400))))]
        (listFlatMap (fn [(d String)] -> (List String)
                           (let [(dir (str home "/.codex/sessions/" d))]
                             (map (fn [(n String)] -> String (str dir "/" n))
                                  (filter (fn [(n String)] -> Bool (and (stringStartsWith? n "rollout-") (endsWith n ".jsonl"))) (listNames! dir)))))
                         days)))
    ((= client "agy")
      (let [(dir (str home "/.gemini/antigravity-cli/brain"))]
        (map (fn [(n String)] -> String (str dir "/" n "/.system_generated/logs/transcript.jsonl")) (listNames! dir))))
    (else (list)))

fn ! gather! client: String paths: (List String) startedAt: Int64 cwd: String acc: (List String) -> (List String)
  (match (listHead paths)
    ((none) (listReverse acc))
    ((some p)
      (gather! client (optionOr (listTail paths) (list)) startedAt cwd (if (accepts! client p startedAt cwd) (cons p acc) acc))))

fn ! pickTranscript! client: String home: String startedAt: Int64 cwd: String -> (Result String String)
  (if (not (listContains? (list "claude" "codex" "agy") client))
    (err (str "unknown client " client))
    (let [(found (gather! client (candidates! client home startedAt cwd) startedAt cwd (list)))]
      (match (listHead found)
        ((none) (err "no transcript written since launch"))
        ((some p) (if (= (listLength found) 1) (ok p) (err (str "ambiguous: " (stringFromInt64 (listLength found)) " transcripts match the launch window")))))))


fn quote s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn atomText s: String -> String
  (if (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (or (isAlnum (charCode c)) (listContains? (list "_" "-" "." ":" "/") c))) (stringChars s)))
    s
    (quote s))

fn countsText m: (Map String Int64) -> String
  (stringJoin (map (fn [(k String)] -> String (str (atomText k) " " (stringFromInt64 (optionOr (mapGet m k) 0)))) (listSort (mapKeys m))) " ")

fn headText client: String runDir: String digest: String startedAt: Int64 exit: Int64 -> String
  (str "(:launchRun :client " client " :run " (atomText (baseName runDir)) " :promptDigest " (quote digest)
       " :startedAt " (stringFromInt64 startedAt) " :exit " (stringFromInt64 exit))

fn receiptText client: String runDir: String digest: String startedAt: Int64 exit: Int64 path: String sc: Scan -> String
  (str (headText client runDir digest startedAt exit) " :transcript " (quote path)
       " :turns " (stringFromInt64 sc.turns)
       " :tokens (:in " (stringFromInt64 sc.tokIn) " :out " (stringFromInt64 sc.tokOut) " :cached " (stringFromInt64 sc.tokCached) ")"
       " :tools (" (countsText sc.tools) ") :errors (" (countsText sc.errors) "))\n")

fn noneText client: String runDir: String digest: String startedAt: Int64 exit: Int64 why: String -> String
  (str (headText client runDir digest startedAt exit) " :transcript :none :why " (quote why) ")\n")

fn ! scanFile! client: String path: String -> (Result Scan String)
  (match (fileReadString path)
    ((err e) (err (str "cannot read transcript: " e)))
    ((ok text)
      (ok (cond
            ((= client "claude") (scanClaude text))
            ((= client "codex") (scanCodex text))
            (else (scanAgy text))))))

fn ! collect! client: String home: String runDir: String startedAt: Int64 cwd: String exit: Int64 digest: String -> (Result String String)
  (let [(out (pathJoinRun runDir))
        (body (match (pickTranscript! client home startedAt cwd)
                ((err why) (noneText client runDir digest startedAt exit why))
                ((ok path)
                  (match (scanFile! client path)
                    ((err why) (noneText client runDir digest startedAt exit why))
                    ((ok sc) (receiptText client runDir digest startedAt exit path sc))))))]
    (match (fileWrite out body)
      ((ok _) (ok out))
      ((err e) (err (str "collect: cannot write " out ": " e)))))

fn pathJoinRun runDir: String -> String
  (if (endsWith runDir "/") (str runDir "run.asn") (str runDir "/run.asn"))
