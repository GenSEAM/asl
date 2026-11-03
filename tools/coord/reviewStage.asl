(module asl-tools/coord/reviewStage
  :x [LaneRow RevOut tableFor modelRows costRows usageCost laneTable laneRowsOf unknownOf paceAllowance lanesFor startupProblems usageSum tokenSum callModelFor! reviewUnit! allowanceMap risingLanes]
  :i [(asl-tools/coord/ladder :a l) (tools/fleet/model :a fm) (aslGateway/subPace :a sp) (asl-parser/reader :a rd) (aslAgent/providers :a prov) (asl-json/json :a j)])

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

fn ! reviewUnit! gatewayText: String lanesText: String paces: (List sp/SubPace) root: String usagePath: String ru: l/ReviewUnit diff: String receipt: String call: (fn ! [String String] -> (Result String String)) -> (Result RevOut String)
  (match (l/reviewWith (tableFor lanesText) ru diff receipt (lanesFor gatewayText lanesText paces) call)
    ((err e) (err e))
    ((ok r)
      (ok (RevOut :action r.action
                  :models (stringJoin (map (fn [(v l/Verdict)] -> String v.model) r.verdicts) "+")
                  :tokens (usageSum (resultOr (fileReadString usagePath) ""))
                  :costMicro (usageCost (resultOr (fileReadString usagePath) ""))
                  :sig (cond ((= r.action "fix") (stringJoin r.defects "; ")) ((= r.action "await") r.awaitLane) ((= r.action "blocked") r.why) (else ""))
                  :rows r.rows))))
