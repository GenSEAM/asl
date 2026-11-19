(module asl-tools/coord/reviewStage
  :x [sigOf blockedSig builtinNames LaneRow RevOut tableFor writerAliasFor profileChain modelNames modelRows costRows usageCost laneTable laneRowsOf unknownOf paceAllowance lanesFor startupProblems usageSum tokenSum tokensFilled callModelFor! reviewUnit! allowanceMap risingLanes reviewTask CiteCtx citeCtx cites? citeCall]
  :i [(asl-tools/coord/ladder :a l) (asl-tools/fleet/model :a fm) (aslGateway/subPace :a sp) (asl-parser/reader :a rd) (aslAgent/providers :a prov) (asl-json/json :a j)])

; (:m :ref COND3 :do "the conductor's real review stage over the COND2 ladder: lanes come from the lane table (alias, tier, quality, default allowance) with the allowance of subscription-backed aliases taken from subPace, the model call is the in-process gateway call Leon's provider uses, and the verdict goes back as a plain RevOut so the conductor owns the state machine")

(schema LaneRow (:f alias String) (:f tier String) (:f quality Int64) (:f allowance Int64))

(schema RevOut (:f action String) (:f models String) (:f tokens Int64) (:f costMicro Int64) (:f sig String) (:f rows (List String)))

; (:m :do "alias to provider for every (:model :id A :provider P ...) row of a gateway config text")
fn modelRows text: String -> (List (Pair String String))
  (match (fm/parseForms text)
    ((err _) (list))
    ((ok forms)
      (match (listHead forms)
        ((none) (list))
        ((some form)
          (map (fn [(m rd/SExpr)] -> (Pair String String)
                 (let [(items (fm/itemsOf m))]
                   (pair (fm/textOf (optionOr (fm/kvGet items ":id") (fm/makeEmpty))) (fm/textOf (optionOr (fm/kvGet items ":provider") (fm/makeEmpty))))))
               (fm/itemsOf (optionOr (fm/kvGet (fm/itemsOf form) ":models") (fm/makeEmpty))))))))

; (:m :ref COND4 :do "alias to :costMicros (micro-USD per call) of every gateway model row, -1 where the row has no price; a free-tier alias (tier free in its gateway row or in the lane table) costs 0 and is priced; a call to a paid alias with no price makes the review's cost unknown, not zero")
fn costRows text: String lanesText: String -> (List (Pair String Int64))
  (match (fm/parseForms text)
    ((err _) (list))
    ((ok forms)
      (match (listHead forms)
        ((none) (list))
        ((some form)
          (fold (fn [(acc (List (Pair String Int64))) (m rd/SExpr)] -> (List (Pair String Int64))
                     (let [(items (fm/itemsOf m))
                           (freeRow (or (= (fm/textOf (optionOr (fm/kvGet items ":tier") (fm/makeEmpty))) "free") (listAny? (fn [(l LaneRow)] -> Bool (and (= l.tier "free") (= l.alias (fm/textOf (optionOr (fm/kvGet items ":id") (fm/makeEmpty)))))) (laneRowsOf lanesText))))
                           (price (optionOr (fm/intOf (fm/kvGet items ":costMicros")) (if freeRow 0 -1)))
                           (name (fm/textOf (optionOr (fm/kvGet items ":name") (fm/makeEmpty))))]
                       (listAppend acc (cons (pair (fm/textOf (optionOr (fm/kvGet items ":id") (fm/makeEmpty))) price)
                                             (if (stringEmpty? name) (list) (list (pair name price)))))))
                   (list)
                   (fm/itemsOf (optionOr (fm/kvGet (fm/itemsOf form) ":models") (fm/makeEmpty))))))))

; (:m :ref REVIEW-DEFER :do "alias and served model name of every gateway model row")
fn modelNames text: String -> (List (Pair String String))
  (match (fm/parseForms text)
    ((err _) (list))
    ((ok forms)
      (match (listHead forms)
        ((none) (list))
        ((some form)
          (map (fn [(m rd/SExpr)] -> (Pair String String)
                 (let [(items (fm/itemsOf m))]
                   (pair (fm/textOf (optionOr (fm/kvGet items ":id") (fm/makeEmpty))) (fm/textOf (optionOr (fm/kvGet items ":name") (fm/makeEmpty))))))
               (fm/itemsOf (optionOr (fm/kvGet (fm/itemsOf form) ":models") (fm/makeEmpty))))))))

; (:m :ref REVIEW-WRITER-FAMILY :do "the grade intent routes are left out: they name the reviewers a profile may call, not the models that write, and the leon grade chain (glm, kimi) made the writer union moonshot+deepseek+zhipu so no lane could review its units")
; (:m :ref NODE2-WRITER-LITERAL-UNKNOWN :do "every alias on any route chain of the gateway profile with this id, in order, distinct: node2 writes run under profile ids (freeWriterNim, freeWriterOr, ...) that are never aliases, so the writer of such a unit has the families of its chains; empty for an id that is no profile")
fn profileChain gatewayText: String id: String -> (List String)
  (match (fm/parseForms gatewayText)
    ((err _) (list))
    ((ok forms)
      (match (listHead forms)
        ((none) (list))
        ((some form)
          (fold (fn [(acc (List String)) (m rd/SExpr)] -> (List String)
                  (let [(items (fm/itemsOf m))]
                    (if (!= (fm/textOf (optionOr (fm/kvGet items ":id") (fm/makeEmpty))) id) acc
                      (fold (fn [(a2 (List String)) (r rd/SExpr)] -> (List String)
                              (if (= (fm/textOf (optionOr (fm/kvGet (fm/itemsOf r) ":intent") (fm/makeEmpty))) "grade") a2
                              (fold (fn [(a3 (List String)) (x String)] -> (List String) (if (listContains? a3 x) a3 (listAppend a3 (list x))))
                                    a2 (fm/atomsOf (optionOr (fm/kvGet (fm/itemsOf r) ":chain") (fm/makeEmpty))))))
                            acc (fm/itemsOf (optionOr (fm/kvGet items ":routes") (fm/makeEmpty)))))))
                (list)
                (fm/itemsOf (optionOr (fm/kvGet (fm/itemsOf form) ":profiles") (fm/makeEmpty))))))))

; (:m :ref REVIEW-DEFER :do "the writer a review excludes, as an alias with a family: Leon's receipt names the served model (k3.1-pro), which no family row matches, so the review parked on writerFamily for good (node2 CACHE-BY-TURN); a name with no family resolves to the first gateway alias serving that model name that has one family; with none it stays as given and selection still waits")
fn writerAliasFor gatewayText: String lanesText: String writer: String -> String
  (let [(rows (l/familyRows (tableFor lanesText)))]
    (if (not (listEmpty? (l/familiesIn rows writer))) writer
      (match (listFind (fn [(p (Pair String String))] -> Bool (and (= (pairSecond p) writer) (not (stringEmpty? (l/familyIn rows (pairFirst p)))))) (modelNames gatewayText))
        ((some p) (pairFirst p))
        ((none)
          (let [(fams (filter (fn [(a String)] -> Bool (not (listEmpty? (l/familiesIn rows a)))) (profileChain gatewayText writer)))]
            (if (listEmpty? fams) writer (stringJoin fams "+")))))))

; (:m :ref COND4 :do "sum of the :costMicros of the usage rows; -1 (priced false) as soon as one call had no price, 0 for no calls")
fn usageCost text: String -> Int64
  (let [(costs (map (fn [(line String)] -> Int64 (optionOr (stringToInt64 (sp/tokAfter line ":costMicros")) -1))
                    (filter (fn [(x String)] -> Bool (stringContains? x "(:usage ")) (stringLines text))))]
    (if (listAny? (fn [(c Int64)] -> Bool (< c 0)) costs) -1 (fold (fn [(a Int64) (c Int64)] -> Int64 (+ a c)) 0 costs)))

fn laneTable text: String -> (List rd/SExpr)
  (match (fm/parseForms text)
    ((err _) (list))
    ((ok forms)
      (match (listHead forms)
        ((none) (list))
        ((some form) (fm/itemsOf (optionOr (fm/kvGet (fm/itemsOf form) ":lanes") (fm/makeEmpty)))))))

fn laneRowsOf text: String -> (List LaneRow)
  (map (fn [(r rd/SExpr)] -> LaneRow
         (let [(items (fm/itemsOf r))]
           (LaneRow :alias (fm/textOf (optionOr (fm/kvGet items ":alias") (fm/makeEmpty)))
                    :tier (fm/textOf (optionOr (fm/kvGet items ":tier") (fm/makeEmpty)))
                    :quality (optionOr (fm/intOf (fm/kvGet items ":quality")) 0)
                    :allowance (optionOr (fm/intOf (fm/kvGet items ":allowance")) 0))))
       (laneTable text))

; (:m :ref COND3 :do "the family table of the ladder plus the lane file's :familyExtra rows, so a new alias family needs a lane-file row, not an edit of ladder.asl")
fn tableFor lanesText: String -> String
  (let [(base (l/familyTableAsn))
        (extra (match (fm/parseForms lanesText)
                 ((err _) "")
                 ((ok forms) (match (listHead forms) ((none) "") ((some form) (fm/textOf (optionOr (fm/kvGet (fm/itemsOf form) ":familyExtra") (fm/makeEmpty))))))))]
    (if (stringEmpty? extra) base
      (str (optionOr (stringSlice base 0 (- (stringLength base) 1)) base) " " extra ")")))

fn unknownOf text: String -> (List String)
  (match (fm/parseForms text)
    ((err _) (list))
    ((ok forms)
      (match (listHead forms)
        ((none) (list))
        ((some form) (fm/atomsOf (optionOr (fm/kvGet (fm/itemsOf form) ":unknown") (fm/makeEmpty)))))))

; (:m :ref COND3 :do "adopted pace rule: a subscription past its hard limit or window has 0 calls, one past its soft limit 1, otherwise 5 scaled by its pace factor and at least 1; a subscription with no data gets the lane's default allowance")
fn paceAllowance p: sp/SubPace default: Int64 -> Int64
  (cond
    ((not p.known) default)
    ((or p.hard p.expired) 0)
    (p.over 1)
    (else (max 1 (roundInt (* p.factor 5.0)))))

fn subPaceOf paces: (List sp/SubPace) provider: String -> (Option sp/SubPace)
  (listFind (fn [(p sp/SubPace)] -> Bool (= p.id (sp/providerSub provider))) paces)

fn providerOfAlias models: (List (Pair String String)) alias: String -> String
  (match (listFind (fn [(m (Pair String String))] -> Bool (= (pairFirst m) alias)) models) ((some m) (pairSecond m)) ((none) ""))

; (:m :do "alias to allowance for every lane row, the numbers the ladder and the wake-on-refresh comparison both read")
fn allowanceMap gatewayText: String lanesText: String paces: (List sp/SubPace) -> (List (Pair String Int64))
  (let [(models (modelRows gatewayText))]
    (map (fn [(r LaneRow)] -> (Pair String Int64)
           (pair r.alias (match (subPaceOf paces (providerOfAlias models r.alias))
                           ((some p) (paceAllowance p r.allowance))
                           ((none) r.allowance))))
         (laneRowsOf lanesText)))

fn lanesFor gatewayText: String lanesText: String paces: (List sp/SubPace) -> (List l/Lane)
  (let [(al (allowanceMap gatewayText lanesText paces))]
    (map (fn [(r LaneRow)] -> l/Lane
           (l/Lane :alias r.alias :tier r.tier :allowance (pairSecond (optionOr (listFind (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) r.alias)) al) (pair "" 0))) :quality r.quality))
         (laneRowsOf lanesText)))

; (:m :ref COND3 :do "refusals at start: every gateway alias has exactly one family or is listed unknown in the lane table, every lane names a gateway alias with a family and a tier free, paid or strong")
fn startupProblems gatewayText: String lanesText: String -> (List String)
  (let [(models (modelRows gatewayText))
        (aliases (map pairFirst models))
        (rows (l/familyRows (tableFor lanesText)))
        (cov (l/coverageProblems rows aliases (unknownOf lanesText)))
        (laneProblems (fold (fn [(acc (List String)) (r LaneRow)] -> (List String)
                              (cond
                                ((not (listContains? aliases r.alias)) (listAppend acc (list (str "lane " r.alias ": not a gateway alias"))))
                                ((stringEmpty? (l/familyIn rows r.alias)) (listAppend acc (list (str "lane " r.alias ": no family"))))
                                ((not (listContains? (list "free" "paid" "strong") r.tier)) (listAppend acc (list (str "lane " r.alias ": tier " r.tier " is not free, paid or strong"))))
                                (else acc)))
                            (list) (laneRowsOf lanesText)))
        (empty (if (listEmpty? (laneRowsOf lanesText)) (list "lane table has no lanes") (list)))]
    (listAppend (listAppend cov laneProblems) empty))

; (:m :do "aliases whose allowance rose between two snapshots: a window reset or a raised allowance")
fn risingLanes before: (List (Pair String Int64)) after: (List (Pair String Int64)) -> (List String)
  (map pairFirst
       (filter (fn [(a (Pair String Int64))] -> Bool
                 (> (pairSecond a) (match (listFind (fn [(b (Pair String Int64))] -> Bool (= (pairFirst b) (pairFirst a))) before) ((some b) (pairSecond b)) ((none) (pairSecond a)))))
               after))

fn roundInt f: Float64 -> Int64
  (optionOr (float64ToInt64 (round f)) 0)

fn jsonInt v: j/Json -> Int64
  (match v ((j/jint i) i) ((j/jnum f) (roundInt f)) ((j/jfloat f) (roundInt f)) (_ 0))

fn tokenSum usage: (List (Pair String j/Json)) -> Int64
  (let [(total (filter (fn [(kv (Pair String j/Json))] -> Bool (stringContains? (pairFirst kv) "total")) usage))]
    (if (not (listEmpty? total)) (fold (fn [(a Int64) (kv (Pair String j/Json))] -> Int64 (+ a (jsonInt (pairSecond kv)))) 0 total)
      (fold (fn [(a Int64) (kv (Pair String j/Json))] -> Int64
              (if (or (or (stringContains? (pairFirst kv) "prompt") (stringContains? (pairFirst kv) "completion")) (or (stringStartsWith? (pairFirst kv) "input") (stringStartsWith? (pairFirst kv) "output"))) (+ a (jsonInt (pairSecond kv))) a))
            0 usage)))

fn usageSum text: String -> Int64
  (fold (fn [(a Int64) (line String)] -> Int64
          (+ a (optionOr (stringToInt64 (sp/tokAfter line ":tokens")) 0)))
        0 (filter (fn [(x String)] -> Bool (stringContains? x "(:usage ")) (stringLines text)))

; (:m :ref TRIAL-REVIEW-ROWS :do "the ladder cannot see usage, so its (:reviewCall ...) rows carry :tokens 0; the stage fills each from the usage rows of the same alias, in call order (the nth reviewCall of an alias takes the nth usage row of that alias); a call that never reached the provider writes no usage row and shifts later calls of the same alias, which only happens when one alias is called twice in a ruling")
fn usageFor alias: String us: (List (Pair String Int64)) -> (Option Int64)
  (optionMap pairSecond (listFind (fn [(x (Pair String Int64))] -> Bool (= (pairFirst x) alias)) us))

fn dropFirstUsage alias: String us: (List (Pair String Int64)) -> (List (Pair String Int64))
  (pairSecond (fold (fn [(acc (Pair Bool (List (Pair String Int64)))) (x (Pair String Int64))] -> (Pair Bool (List (Pair String Int64)))
                      (if (and (not (pairFirst acc)) (= (pairFirst x) alias))
                        (pair true (pairSecond acc))
                        (pair (pairFirst acc) (listAppend (pairSecond acc) (list x)))))
                    (pair false (list)) us))

fn usageRowsOf text: String -> (List (Pair String Int64))
  (map (fn [(x String)] -> (Pair String Int64) (pair (sp/tokAfter x ":alias") (optionOr (stringToInt64 (sp/tokAfter x ":tokens")) 0)))
       (filter (fn [(x String)] -> Bool (stringContains? x "(:usage ")) (stringLines text)))

fn tokensFilled rows: (List String) usageText: String -> (List String)
  (pairFirst (fold (fn [(acc (Pair (List String) (List (Pair String Int64)))) (row String)] -> (Pair (List String) (List (Pair String Int64)))
                     (if (not (stringStartsWith? row "(:reviewCall "))
                       (pair (listAppend (pairFirst acc) (list row)) (pairSecond acc))
                       (let [(alias (sp/tokAfter row ":alias"))]
                         (match (usageFor alias (pairSecond acc))
                           ((none) (pair (listAppend (pairFirst acc) (list row)) (pairSecond acc)))
                           ((some t) (pair (listAppend (pairFirst acc) (list (stringReplace row " :tokens 0 " (str " :tokens " (stringFromInt64 t) " "))))
                                           (dropFirstUsage alias (pairSecond acc))))))))
                   (pair (list) (usageRowsOf usageText)) rows))

; (:m :ref COND3 :do "the model call of the ladder is the in-process gateway call of Leon's provider (providers makeProvider! + nextTurn! with the alias as model); each call appends one usage row so the stage can report tokens")
fn ! callModelFor! root: String usagePath: String prices: (List (Pair String Int64)) -> (fn ! [String String] -> (Result String String))
  (fn [(alias String) (prompt String)] -> (Result String String)
    (let [(env (prov/providerEnv! root))]
      (match (prov/makeProvider! "agy" "review" root alias 600 "" 1200 true env "review")
        ((err e) (err (prov/errorMessage e)))
        ((ok p)
          (let [(t (prov/nextTurn! p "You are a strict code reviewer. Reply with the one requested form only." prompt))
                (tokens (match t.meta.usage ((some u) (tokenSum u)) ((none) 0)))
                (_ (fileAppend usagePath (str "(:usage :alias " alias " :tokens " (stringFromInt64 tokens) " :costMicros " (stringFromInt64 (match (listFind (fn [(pr (Pair String Int64))] -> Bool (= (pairFirst pr) alias)) prices) ((some pr) (pairSecond pr)) ((none) -1))) ")\n")))]
            (match t.reply
              ((err e) (err (prov/errorMessage e)))
              ((ok (some text)) (ok text))
              ((ok (none)) (err "empty reply"))))))))

; (:m :ref WRITERFAMILY-UNKNOWN-POLICY :do "a writer alias the lane file lists :unknown (a stealth vendor such as kiloGlyphCluster) is its own pseudo-family unknown:ALIAS for review selection only, so every known-family lane may review it; node2 2026-11-13 TEXT-WRAP deferred on writerFamily for good; the startup coverage gate keeps the plain table, so a listed unknown still never becomes a lane")
fn reviewTableFor lanesText: String writer: String -> String
  (let [(base (tableFor lanesText))
        (run (stringJoin (l/tokensOf writer) " "))]
    (if (or (stringEmpty? run) (not (listContains? (unknownOf lanesText) writer))) base
      (str (optionOr (stringSlice base 0 (- (stringLength base) 1)) base) " (:f :match \"" run "\" :family \"unknown:" writer "\"))")))

; (:m :ref REVIEW-INVENTED-BAN :do "the builtin names of the language, one space-joined string read from asl/prelude/prelude.asn under the repo root (every (:name \"X\" row); unreadable gives the empty string and then only words of the brief count as known)")
fn builtinNames root: String -> String
  (stringJoin (map (fn [(piece String)] -> String (optionOr (listHead (stringSplit piece "\"")) ""))
                   (listDrop (stringSplit (resultOr (fileReadString (str root "/asl/prelude/prelude.asn")) "") "(:name \"") 1))
              " ")

; (:m :ref REVIEW-BLOCK-WHY :do "a block carries its reason and the defects behind it, clipped to 300 chars, so the journal row of the move says what was wrong (the conductor writes the move verdict as block: plus this sig)")
fn blockedSig why: String defects: (List String) -> String
  (if (listEmpty? defects) why (str why " | defects: " (l/clip (stringJoin defects "; ") 300)))

fn sigOf r: l/Ruling -> String
  (cond ((= r.action "fix") (stringJoin r.defects "; ")) ((= r.action "await") r.awaitLane) ((= r.action "blocked") (blockedSig r.why r.defects)) (else ""))

; (:m :ref REVIEW-CRITERIA-DOCDUP :do "node2 2026-11-19: the STD task texts carry a RULES AND EXEMPLAR block for the writer (write src and test in one txn, src first) and the reviewers, given the same text, failed gate-green units for not following it (5 of 44 fails); the reviewer judges the result, so a task text has writer-only parts by structure: every line from a line that is --- writerOnly --- to a line that is --- end writerOnly --- or the end of the text is the writer's and never reaches the review brief; the header of the block already queued on the node opens such a part too, so those texts need no re-import; a requirement of the result is written outside the markers")
fn writerOnlyOpen -> String
  "--- writerOnly ---"

fn writerOnlyClose -> String
  "--- end writerOnly ---"

fn writerOnlyLegacy -> (List String)
  (list "RULES AND EXEMPLAR (")

fn opensWriterOnly? line: String -> Bool
  (let [(t (stringTrim line))]
    (or (= t (writerOnlyOpen)) (listAny? (fn [(h String)] -> Bool (stringStartsWith? t h)) (writerOnlyLegacy))))

fn reviewTask text: String -> String
  (stringTrim (stringJoin (pairSecond (fold (fn [(acc (Pair Bool (List String))) (l String)] -> (Pair Bool (List String))
                                              (cond
                                                ((= (stringTrim l) (writerOnlyClose)) (pair false (pairSecond acc)))
                                                ((or (pairFirst acc) (opensWriterOnly? l)) (pair true (pairSecond acc)))
                                                (else (pair false (listAppend (pairSecond acc) (list l))))))
                                            (pair false (list)) (stringLines text)))
                          "\n"))

; (:m :ref REVIEW-CRITERIA-DOCDUP :do "a fail has to point at the change or at the task: a defect cites when it names a changed path or its file name, a name the diff defines (fn, schema, enum, module), a camelCase word of a changed line, or two adjacent words of four or more letters of the task text the reviewer was shown; the context is built once per review from the whole diff, not the clipped one")
(schema CiteCtx (:f paths (List String)) (:f names (List String)) (:f toks (List String)) (:f pairs (List String)) (:f words (List String)))

fn spaceMarks -> (List String)
  (list " " " " " ")

fn dashMarks -> (List String)
  (list "‑" "‐" "–" "—")

fn wordsOf text: String -> (List String)
  (let [(spaced (fold (fn [(a String) (c String)] -> String (stringReplace a c " ")) text (spaceMarks)))
        (dashed (fold (fn [(a String) (c String)] -> String (stringReplace a c "-")) spaced (dashMarks)))]
    (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (l/identWords (stringReplace dashed "#" " "))))

fn genericWords -> (List String)
  (list "module" "function" "should" "tested" "against" "implement" "implemented" "missing" "return" "returns" "string" "number" "value" "values" "result" "results" "because" "enough" "correct" "incorrect" "proper" "properly" "working" "handle" "handled" "handles" "support" "supported" "support" "behavior" "behaviour" "feature" "features" "defined" "complete" "completely" "needed" "needs" "wrong" "broken" "failing" "failed" "fails" "without" "between" "another" "message" "default" "tests" "testing" "coverage" "package" "symbol" "symbols" "method" "methods" "create" "created" "update" "updated" "change" "changes" "changed" "output" "input" "inputs" "outputs" "expected" "actual" "wrapped" "single" "needed" "invalid" "issues" "problem" "problems" "quality" "design" "better" "unclear" "cannot" "actually" "nothing" "something" "anything" "everything" "include" "included" "includes" "specified" "required" "requires" "require" "present" "appropriate" "adequate" "sufficient" "satisfy" "satisfies" "matches" "reviewer" "writer")

fn taskWord? w: String -> Bool
  (and (or (camel? w) (>= (stringLength w) 6)) (not (listContains? (genericWords) (stringLower w))))

fn restOf s: String n: Int64 -> String
  (optionOr (stringSlice s n (stringLength s)) "")

fn pathOfLine line: String -> String
  (cond
    ((or (stringStartsWith? line "+++ b/") (stringStartsWith? line "--- a/")) (stringTrim (restOf line 6)))
    ((stringStartsWith? line "diff --git a/") (stringTrim (optionOr (listLast (stringSplit line " b/")) "")))
    (else ""))

fn changedLine? line: String -> Bool
  (and (or (stringStartsWith? line "+") (stringStartsWith? line "-")) (and (not (stringStartsWith? line "+++")) (not (stringStartsWith? line "---"))))

fn definedName line: String -> String
  (let [(ws (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim line) " ")))
        (head (optionOr (listHead ws) ""))
        (second (optionOr (listGet ws 1) ""))]
    (cond
      ((= head "fn") (if (= second "!") (optionOr (listGet ws 2) "") second))
      ((listContains? (list "(schema" "(enum" "(module") head) second)
      (else "")))

fn camel? w: String -> Bool
  (and (>= (stringLength w) 4) (!= (stringLower (restOf w 1)) (restOf w 1)))

fn wordPairs text: String -> (List String)
  (pairSecond (fold (fn [(acc (Pair String (List String))) (w String)] -> (Pair String (List String))
                      (pair w (if (and (>= (stringLength w) 4) (>= (stringLength (pairFirst acc)) 4)) (listAppend (pairSecond acc) (list (str (pairFirst acc) " " w))) (pairSecond acc))))
                    (pair "" (list)) (wordsOf (stringLower text))))

fn citeCtx task: String diff: String -> CiteCtx
  (let [(lines (stringLines diff))
        (changed (map (fn [(x String)] -> String (restOf x 1)) (filter changedLine? lines)))]
    (CiteCtx :paths (fold (fn [(acc (List String)) (x String)] -> (List String)
                            (let [(p (pathOfLine x))] (if (or (stringEmpty? p) (listContains? acc p)) acc (listAppend acc (list p)))))
                          (list) lines)
             :names (filter (fn [(n String)] -> Bool (>= (stringLength n) 3)) (map definedName changed))
             :toks (filter camel? (wordsOf (stringJoin changed "\n")))
             :pairs (wordPairs task)
             :words (map stringLower (filter taskWord? (wordsOf task)))))

fn cites? d: String c: CiteCtx -> Bool
  (or (listAny? (fn [(p String)] -> Bool
                  (let [(file (optionOr (listLast (stringSplit p "/")) p))]
                    (or (stringContains? d p) (and (>= (stringLength file) 3) (stringContains? d file)))))
                c.paths)
      (or (listAny? (fn [(w String)] -> Bool (or (listContains? c.names w) (and (camel? w) (listContains? c.toks w)))) (wordsOf d))
          (listAny? (fn [(p String)] -> Bool (listContains? c.pairs p)) (wordPairs d))
          (listAny? (fn [(w String)] -> Bool (listContains? c.words (stringLower w))) (wordsOf d))))

fn rowAtom s: String -> String
  (if (or (stringEmpty? s) (listAny? (fn [(c String)] -> Bool (stringContains? s c)) (list " " "(" ")" "\"" ";" "\n"))) (fm/asnQuote s) s)

; (:m :ref REVIEW-CRITERIA-DOCDUP :do "the model call wrapped with the citation rule: a fail whose defects all cite passes through untouched; a defect that cites nothing is taken out of the reply and written as one (:reviewNoCite :unit :reviewer :kept :text) row, :kept being the defects of that verdict that stay; a fail left with no defect is what the ladder already reads as an abstention (fail without a concrete defect), so it sends no unit back to its writer and the next reviewer is asked; a diff with no file header gives nothing to cite and is not judged; a pass is never touched")
fn ! citeCall unit: String c: CiteCtx notePath: String call: (fn ! [String String] -> (Result String String)) -> (fn ! [String String] -> (Result String String))
  (fn [(alias String) (prompt String)] -> (Result String String)
    (match (call alias prompt)
      ((err e) (err e))
      ((ok text)
        (let [(v (l/parseVerdict text alias ""))
              (bad (if (or (!= v.outcome "fail") (listEmpty? c.paths)) (list) (filter (fn [(d String)] -> Bool (not (cites? d c))) v.defects)))]
          (if (listEmpty? bad) (ok text)
            (let [(good (filter (fn [(d String)] -> Bool (cites? d c)) v.defects))
                  (_ (fileAppend notePath (str (stringJoin (map (fn [(d String)] -> String
                                                                  (str "(:reviewNoCite :unit " (rowAtom unit) " :reviewer " (rowAtom alias) " :kept " (stringFromInt64 (listLength good)) " :text " (fm/asnQuote (l/clip (stringReplace d "\n" " ") 300)) ")"))
                                                                bad)
                                                           "\n")
                                               "\n")))]
              (ok (str "(:verdict :fail :defects " (fm/asnStrings good) " :model " (fm/asnQuote alias) ")"))))))))

fn ! reviewUnit! gatewayText: String lanesText: String paces: (List sp/SubPace) root: String usagePath: String ru: l/ReviewUnit diff: String receipt: String call: (fn ! [String String] -> (Result String String)) -> (Result RevOut String)
  (let [(task (reviewTask ru.task))
        (notePath (str usagePath ".noCite"))
        (_ (pathRemove notePath))
        (ruled (l/reviewWith (reviewTableFor lanesText ru.writerAlias) (with (with ru :known (builtinNames root)) :task task) diff receipt (lanesFor gatewayText lanesText paces) (citeCall ru.id (citeCtx task diff) notePath call)))
        (notes (filter (fn [(x String)] -> Bool (stringStartsWith? x "(:reviewNoCite ")) (stringLines (resultOr (fileReadString notePath) ""))))
        (_ (pathRemove notePath))]
    (match ruled
      ((err e) (err e))
      ((ok r)
        (ok (RevOut :action r.action
                    :models (stringJoin (map (fn [(v l/Verdict)] -> String v.model) r.verdicts) "+")
                    :tokens (usageSum (resultOr (fileReadString usagePath) ""))
                    :costMicro (usageCost (resultOr (fileReadString usagePath) ""))
                    :sig (sigOf r)
                    :rows (listAppend (tokensFilled r.rows (resultOr (fileReadString usagePath) "")) notes))))))
