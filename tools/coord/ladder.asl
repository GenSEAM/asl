(module asl-tools/coord/ladder
  :x [tokensOf joinAwait familiesIn coverageProblems rankLanes Lane ReviewUnit Verdict Ruling Pick Step familyTableAsn familyRows familyIn reviewWriter selectFree selectOne parseVerdict gatesProven decide permanentError? causeOf absent? starved? scrubLines reviewBrief reviewWith review]
  :i [(asl-tools/coord/egress :a eg) (asl-tools/coord/grade :a g) (asl-tools/fleet/model :a fm) (asl-parser/reader :a rd)])

; (:m :ref COND2 :do "review ladder for the conductor: R1 two free reviewers of two families, R2 one paid-cheap, R3 one strong; verdicts merge by tally; the family map is the ASN table familyTableAsn; the model call is injected")

(schema Lane
  (:f alias String)
  (:f tier String)
  (:f allowance Int64)
  (:f quality Int64))

(schema Verdict
  (:f outcome String)
  (:f defects (List String))
  (:f model String)
  (:f rung String))

(schema ReviewUnit
  (:f id String)
  (:f task String)
  (:f risk String)
  (:f closureChanged Bool)
  (:f writerAlias String)
  (:f writerChannel String)
  (:f startRung String)
  (:f fixesUsed Int64)
  (:f prior (List Verdict)))

(schema Ruling
  (:f action String)
  (:f rung String)
  (:f defects (List String))
  (:f awaitLane String)
  (:f rows (List String))
  (:f verdicts (List Verdict))
  (:f why String))

(enum Pick
  (:c pickOk [(lanes (List Lane))] "the lanes to call on this rung")
  (:c pickAwait [(lane String) (why String)] "no lane fits; lane is the one whose allowance the rung waits for"))

(enum Step
  (:c stepMerge [] "merge")
  (:c stepFix [(defects (List String))] "back to the writer for one fix round")
  (:c stepEscalate [] "run the next rung")
  (:c stepBlocked [(why String)] "waits for Claude")
  (:c stepDefer [(lanes String) (why String)] "fewer reviewers answered than the quorum needs: wait for those lanes, never block"))

; (:m :ref COND2 :do "family map: a row matches when its :match, one or more space-separated tokens, is a whole token run of the alias or model name (camelCase, digit and separator boundaries); an alias with zero or several distinct families has no family")
fn familyTableAsn -> String
  (str "(:families"
       " (:f :match nemotron :family nvidia)"
       " (:f :match kimi :family moonshot)"
       " (:f :match moonshotai :family moonshot)"
       " (:f :match deepseek :family deepseek)"
       " (:f :match ds :family deepseek)"
       " (:f :match glm :family zhipu)"
       " (:f :match minimax :family minimax)"
       " (:f :match qwen :family alibaba)"
       " (:f :match mimo :family xiaomi)"
       " (:f :match xiaomi :family xiaomi)"
       " (:f :match laguna :family poolside)"
       " (:f :match longcat :family meituan)"
       " (:f :match meituan :family meituan)"
       " (:f :match ling :family inclusionai)"
       " (:f :match gemini :family google)"
       " (:f :match gemma :family google)"
       " (:f :match google :family google)"
       " (:f :match \"flash low\" :family google)"
       " (:f :match \"flash medium\" :family google)"
       " (:f :match \"flash high\" :family google)"
       " (:f :match claude :family anthropic)"
       " (:f :match opus :family anthropic)"
       " (:f :match sonnet :family anthropic)"
       " (:f :match haiku :family anthropic)"
       " (:f :match gpt :family openai)"
       " (:f :match luna :family openai)"
       " (:f :match astra :family openai)"
       " (:f :match codex :family openai)"
       " (:f :match beam :family reflection)"
       " (:f :match muse :family meta)"
       " (:f :match grok :family xai)"
       " (:f :match hy :family tencent)"
       " (:f :match tencent :family tencent)"
       " (:f :match ifm :family ifm)"
       " (:f :match bonsai :family prism)"
       " (:f :match north :family cohere)"
       " (:f :match mistral :family mistral)"
       " (:f :match step :family stepfun)"
       " (:f :match stepfun :family stepfun))")

fn rowText r: rd/SExpr key: String -> String
  (fm/textOf (optionOr (fm/kvGet (fm/itemsOf r) key) (fm/makeEmpty)))

fn familyRows table: String -> (List rd/SExpr)
  (match (fm/parseForms table)
    ((err e) (list))
    ((ok forms)
      (match (listHead forms)
        ((none) (list))
        ((some f) (filter (fn [(r rd/SExpr)] -> Bool (not (stringEmpty? (rowText r ":match")))) (fm/itemsOf f))))))

fn cls c: String -> Int64
  (cond
    ((stringContains? "0123456789" c) 3)
    ((and (= c (stringUpper c)) (!= c (stringLower c))) 2)
    ((and (= c (stringLower c)) (!= c (stringUpper c))) 1)
    (else 0))

fn flush cur: String toks: (List String) -> (List String)
  (if (stringEmpty? cur) toks (listAppend toks (list cur)))

fn tokGo cs: (List String) i: Int64 cur: String toks: (List String) -> (List String)
  (if (>= i (listLength cs))
    (flush cur toks)
    (let [(c (optionOr (listGet cs i) ""))
          (k (cls c))
          (pk (if (> i 0) (cls (optionOr (listGet cs (- i 1)) "")) 0))
          (nk (cls (optionOr (listGet cs (+ i 1)) "")))
          (lc (stringLower c))]
      (cond
        ((= k 0) (tokGo cs (+ i 1) "" (flush cur toks)))
        ((and (not (stringEmpty? cur))
              (or (!= (= k 3) (= pk 3)) (or (and (= k 2) (= pk 1)) (and (= k 2) (and (= pk 2) (= nk 1))))))
          (tokGo cs (+ i 1) lc (flush cur toks)))
        (else (tokGo cs (+ i 1) (str cur lc) toks)))))

; (:m :ref COND2 :do "alias or model name to lowercase whole tokens: ocDeepseekFlash -> oc deepseek flash, claude-opus-5-5 -> claude opus 5 5")
fn tokensOf name: String -> (List String)
  (tokGo (stringChars name) 0 "" (list))

fn runText name: String -> String
  (str " " (stringJoin (tokensOf name) " ") " ")

fn familiesIn rows: (List rd/SExpr) name: String -> (List String)
  (let [(t (runText name))]
    (fold (fn [(acc (List String)) (r rd/SExpr)] -> (List String)
            (if (and (stringContains? t (str " " (rowText r ":match") " ")) (not (listContains? acc (rowText r ":family"))))
              (listAppend acc (list (rowText r ":family")))
              acc))
          (list) rows))

; (:m :ref COND2 :do "exactly one distinct family or empty; zero and several both mean unknown, so the lane is never chosen")
fn familyIn rows: (List rd/SExpr) name: String -> String
  (let [(fs (familiesIn rows name))]
    (if (= (listLength fs) 1) (optionOr (listHead fs) "") ""))

; (:m :ref COND2 :do "coverage gate: every alias resolves to exactly one family or is listed unknown; a listed unknown that resolves is stale")
fn coverageProblems rows: (List rd/SExpr) aliases: (List String) unknown: (List String) -> (List String)
  (fold (fn [(acc (List String)) (a String)] -> (List String)
          (let [(fs (familiesIn rows a))
                (n (listLength fs))
                (listed (listContains? unknown a))]
            (cond
              ((> n 1) (listAppend acc (list (str a ": several families " (stringJoin fs ",")))))
              ((and (= n 0) (not listed)) (listAppend acc (list (str a ": no family and not listed unknown"))))
              ((and (= n 1) listed) (listAppend acc (list (str a ": listed unknown but resolves to " (optionOr (listHead fs) "")))))
              (else acc))))
        (list) aliases)

fn laneFamily rows: (List rd/SExpr) lane: Lane -> String
  (familyIn rows lane.alias)

fn eligible rows: (List rd/SExpr) wfams: (List String) tier: String lane: Lane -> Bool
  (and (= lane.tier tier)
       (and (> lane.allowance 0)
            (let [(f (laneFamily rows lane))]
              (and (not (stringEmpty? f)) (not (listContains? wfams f))))))

; (:m :ref COND2 :do "the lanes a rung waits for: every lane of the tier that is out of allowance and would be eligible, space-separated in lane order, else the tier name")
; (:m :ref REVIEW-STRONG-STARVED :do "node2 2026-11-12: the await named only the first such lane, so 20 units sat on ocDeepseekPro while ocGlm53 and synKimiK31Pro of the same tier regained allowance; wake! matches any name of a space-separated await, so naming every candidate lane wakes the unit on the first of them to rise")
fn insertRanked l: Lane sorted: (List Lane) -> (List Lane)
  (match (listHead (filter (fn [(x Lane)] -> Bool (< x.quality l.quality)) sorted))
    ((none) (listAppend sorted (list l)))
    ((some first) (let [(i (optionOr (listIndexOf sorted first) 0))]
                    (listAppend (listTake sorted i) (listAppend (list l) (listDrop sorted i))))))

; (:m :ref COND2 :do "within a tier, higher caller-supplied review quality first; equal quality keeps the caller order; quality 0 means no calibration row")
fn rankLanes lanes: (List Lane) -> (List Lane)
  (fold (fn [(acc (List Lane)) (l Lane)] -> (List Lane) (insertRanked l acc)) (list) lanes)

fn waitLane rows: (List rd/SExpr) wfams: (List String) tier: String skipFamily: String lanes: (List Lane) -> String
  (let [(waits (filter (fn [(l Lane)] -> Bool
                         (let [(f (laneFamily rows l))]
                           (and (= l.tier tier) (and (not (stringEmpty? f)) (and (not (listContains? wfams f)) (!= f skipFamily))))))
                       lanes))]
    (if (listEmpty? waits) tier (stringJoin (map (fn [(l Lane)] -> String l.alias) waits) " ")))

fn selectOne rows: (List rd/SExpr) writerAlias: String tier: String lanes: (List Lane) -> Pick
  (let [(wfams (familiesIn rows writerAlias))
        (wfam (stringJoin wfams "+"))]
    (cond
      ((and (listEmpty? wfams) (not (stringEmpty? writerAlias))) (pickAwait "writerFamily" (str "writer " writerAlias ": unknown model family")))
      (else
        (match (listHead (rankLanes (filter (fn [(l Lane)] -> Bool (eligible rows wfams tier l)) lanes)))
          ((some l) (pickOk (list l)))
          ((none) (pickAwait (waitLane rows wfams tier "" lanes) (str "no " tier " lane with allowance outside family " wfam)))))))

fn selectFree rows: (List rd/SExpr) writerAlias: String lanes: (List Lane) -> Pick
  (let [(wfams (familiesIn rows writerAlias))
        (wfam (stringJoin wfams "+"))
        (els (rankLanes (filter (fn [(l Lane)] -> Bool (eligible rows wfams "free" l)) lanes)))]
    (cond
      ((and (listEmpty? wfams) (not (stringEmpty? writerAlias))) (pickAwait "writerFamily" (str "writer " writerAlias ": unknown model family")))
      (else
        (match (listHead els)
          ((none) (pickAwait (waitLane rows wfams "free" "" lanes) (str "no free lane with allowance outside family " wfam)))
          ((some a)
            (let [(af (laneFamily rows a))]
              (match (listHead (filter (fn [(l Lane)] -> Bool (!= (laneFamily rows l) af)) els))
                ((none) (pickAwait (waitLane rows wfams "free" af lanes) (str "no second free lane of a family other than " af " and " wfam)))
                ((some b) (pickOk (list a b))))))))))

fn dropFence s: String -> String
  (stringJoin (filter (fn [(l String)] -> Bool (not (stringStartsWith? (stringTrim l) "```"))) (stringLines s)) "\n")

fn abstain model: String rung: String why: String -> Verdict
  (Verdict :outcome "abstain" :defects (list why) :model model :rung rung)

fn verdictFrom items: (List rd/SExpr) model: String rung: String -> Verdict
  (let [(atoms (map fm/atomText items))
        (hasPass (listContains? atoms ":pass"))
        (hasFail (listContains? atoms ":fail"))
        (defects (filter (fn [(d String)] -> Bool (not (stringEmpty? (stringTrim d))))
                         (fm/atomsOf (optionOr (fm/kvGet items ":defects") (fm/makeEmpty)))))]
    (cond
      ((and hasPass hasFail) (abstain model rung "verdict names both pass and fail"))
      (hasPass (Verdict :outcome "pass" :defects defects :model model :rung rung))
      ((and hasFail (not (listEmpty? defects))) (Verdict :outcome "fail" :defects defects :model model :rung rung))
      (hasFail (abstain model rung "fail without a concrete defect"))
      (else (abstain model rung "verdict is neither pass nor fail"))))

; (:m :ref COND2 :do "malformed or missing output is abstain, never pass")
fn parseVerdict text: String model: String rung: String -> Verdict
  (match (fm/parseForms (dropFence text))
    ((err e) (abstain model rung "reply does not parse"))
    ((ok forms)
      (match (listHead (filter (fn [(f rd/SExpr)] -> Bool (= (fm/atomText (optionOr (listHead (fm/itemsOf f)) (fm/makeEmpty))) ":verdict")) forms))
        ((none) (abstain model rung "reply holds no (:verdict ...) form"))
        ((some f) (verdictFrom (fm/itemsOf f) model rung)))))

fn rowsAt items: (List rd/SExpr) key: String -> (List rd/SExpr)
  (fm/itemsOf (optionOr (fm/kvGet items key) (fm/makeEmpty)))

fn gateGreen g: rd/SExpr -> Bool
  (let [(gi (fm/itemsOf g))
        (exit (fm/intOf (fm/kvGet gi ":exit")))
        (executed (fm/intOf (fm/kvGet gi ":executed")))]
    (and (= (optionOr exit 1) 0) (> (optionOr executed 0) 0)))

; (:m :ref COND2 :do "gates proven: every gate exited 0 with executed assertions, and a redBefore receipt exists")
fn gatesProven receipt: String -> Bool
  (match (fm/parseForms receipt)
    ((err e) false)
    ((ok forms)
      (match (listHead forms)
        ((none) false)
        ((some form)
          (let [(items (fm/itemsOf form))
                (gates (rowsAt items ":gates"))]
            (and (not (listEmpty? (rowsAt items ":redBefore")))
                 (and (not (listEmpty? gates)) (listAll? gateGreen gates))))))))

fn rungNum rung: String -> Int64
  (cond ((= rung "R1") 1) ((= rung "R2") 2) ((= rung "R3") 3) (else 0))

fn nextRung rung: String -> String
  (cond ((= rung "R1") "R2") ((= rung "R2") "R3") (else ""))

fn countOf outcome: String vs: (List Verdict) -> Int64
  (listLength (filter (fn [(v Verdict)] -> Bool (= v.outcome outcome)) vs))

fn defectsOf vs: (List Verdict) -> (List String)
  (fold (fn [(acc (List String)) (v Verdict)] -> (List String)
          (if (= v.outcome "fail") (listAppend acc (map (fn [(d String)] -> String (str v.model ": " d)) v.defects)) acc))
        (list) vs)

; (:m :ref COND2 :do "tally over every verdict of this review cycle (all) and the latest rung (cur); abstain counts for nothing, so a reviewer with no verdict is absent and not a vote: at the last rung a split needs a pass and a fail, and fewer answers than the quorum with no fail (node2: pass 1 fail 0, pass 0 fail 0 from lanes without credits or on 429) defer to those lanes instead of blocking")
; (:m :ref CONDWIRE-A :do "a reviewer is absent when it gave no answer: the call failed (rate limit, no credit, timeout) or the reply was blank; a garbled reply, a fail without a defect and a reply naming both outcomes are answers that carry no vote, not absences; only a cur of abstentions that are all absent defers, anything else at the last rung keeps the tiebreak block")
fn absent? v: Verdict -> Bool
  (and (= v.outcome "abstain")
       (let [(why (optionOr (listHead v.defects) ""))]
         (or (stringStartsWith? why "call failed") (stringStartsWith? why "no answer"))))

fn starved? cur: (List Verdict) -> Bool
  (let [(abst (filter (fn [(v Verdict)] -> Bool (= v.outcome "abstain")) cur))]
    (and (not (listEmpty? abst)) (listAll? absent? abst)))

fn decide rung: String cur: (List Verdict) all: (List Verdict) priorEmpty: Bool finalRung: String fixesUsed: Int64 gatesOk: Bool -> Step
  (let [(p (countOf "pass" all))
        (f (countOf "fail" all))
        (curFail (> (countOf "fail" cur) 0))
        (needed (if (and priorEmpty (!= rung "R1")) 1 2))
        (last (= rung "R3"))
        (fixOr (fn [(why String)] -> Step
                 (if (< fixesUsed 1) (stepFix (defectsOf all)) (if last (stepBlocked why) (stepEscalate)))))]
    (cond
      ((and (> p f) (and (>= p needed) (not curFail)))
        (cond
          ((not gatesOk) (if (< fixesUsed 1) (stepFix (list "gates not proven red-before with executed assertions")) (stepBlocked "gates not proven after a fix round")))
          ((< (rungNum rung) (rungNum finalRung)) (stepEscalate))
          (else (stepMerge))))
      ((> f p) (fixOr "fail after the fix round at the last rung"))
      ((and last (and (= f 0) (starved? cur)))
        (let [(absent (map (fn [(v Verdict)] -> String v.model) (filter (fn [(v Verdict)] -> Bool (= v.outcome "abstain")) cur)))]
          (stepDefer (if (listEmpty? absent) rung (stringJoin absent " ")) (str "quorumStarved: reviewers did not answer at the last rung (pass " (stringFromInt64 p) " fail 0, quorum " (stringFromInt64 needed) "): " (stringJoin (map (fn [(v Verdict)] -> String (str v.model " " (stringJoin v.defects "; "))) (filter (fn [(v Verdict)] -> Bool (= v.outcome "abstain")) cur)) ", ")))))
      (last (stepBlocked (str "tiebreak: reviewers split at the last rung (pass " (stringFromInt64 p) " fail " (stringFromInt64 f) ")")))
      (else (stepEscalate))))

; (:m :ref SECRET-SCRUB :do "the review brief is stricter than egress, never weaker: any egress hit, plus the bare words below; only the identifiers tokenize and tokensOf are blanked before that match")
fn secretLike? l: String -> Bool
  (or (eg/secretLike? l) (strictHit? l))

fn strictHit? l: String -> Bool
  (let [(s (stringReplace (stringReplace (stringLower l) "tokeniz" "") "tokensof" ""))]
    (listAny? (fn [(n String)] -> Bool (stringContains? s n))
              (list ".asl/mem" "secret" "token" "password" "apikey" "api_key" "api-key" "_key" "bearer" "\"sk-" " sk-" "=sk-" ":sk-" "sk-or-" "sk-ant-" "sk-proj-" "aizasy" "github_pat_" "ghp_" "xoxb-" "xoxp-" "xoxa-" "passwd" "private key" "authorization:")))

; (:m :ref AHEAD-WRITER-UNKNOWN :do "an empty writer alias means no writer evidence exists at all (no write row of the unit, no unit model, no configured alias), so there is no family to stay independent of and any lane may review; the literal unknown, a writer the journal names but nobody can place, and an alias with no family still wait, so a misconfigured family table never reviews its own work (superseded in part by NODE2-WRITER-LITERAL-UNKNOWN: the conductor resolves the literal unknown to its write profiles families before selection; selectOne and selectFree still wait on it when none can be derived)")
; (:m :ref WRITER-UNKNOWN :do "the writer a review excludes: the unit's model, else the configured writer alias; an unknown writer stays unknown so selection waits instead of guessing a family NODE2-WRITER-LITERAL-UNKNOWN: the write stage now journals the dispatched model when the receipt names none, and realReview resolves a literal unknown writer to the + join of the tier write profiles (unknownWriterFor), so this function only returns unknown for a unit whose profiles name no family; selection then still waits.")
fn reviewWriter model: String fallback: String -> String
  (cond
    ((and (= model "unknown") (stringEmpty? fallback)) "unknown")
    ((or (stringEmpty? model) (= model "unknown")) fallback)
    (else model))

fn clip s: String n: Int64 -> String
  (if (> (stringLength s) n) (optionOr (stringSlice s 0 n) s) s)

; (:m :ref COND2 :do "lines that may go to an external model: no memory contents, no secret-looking lines, bounded count and width")
fn scrubLines text: String maxLines: Int64 width: Int64 -> (List String)
  (eg/scrubLinesBy (fn [(l String)] -> Bool (secretLike? l)) text maxLines width)

; (:m :ref REVIEW-DIFF-INCOMPLETE :do "the brief held only 60 diff lines of 200 chars, so reviewers saw half a test file or none and failed green units for missing tests and bodiless functions; 800 lines of 400 chars fits a 120k-token reviewer, and a longer diff ends with a note naming the cut lines so the reviewer does not judge code it was not shown")
fn reviewDiffLines -> Int64
  800

fn withheldLine -> String
  "(one line withheld by the secret filter; it exists, so do not fail on its absence)"

; (:m :ref REVIEW-SCRUB-SILENT :do "node2 2026-11-11: the filter dropped every diff line naming token or secret, so aggRow lost its inTokens and cachedTokens lines and synDs41Flash failed THROUGHPUT-DAILY for indices it was not shown; a withheld line now leaves a marker in its place")
fn reviewScrub diff: String maxLines: Int64 width: Int64 -> (List String)
  (eg/scrubLinesBy (fn [(l String)] -> Bool false)
                   (stringJoin (map (fn [(l String)] -> String (if (secretLike? l) (withheldLine) l)) (stringLines diff)) "\n")
                   maxLines width)

fn reviewDiffPart diff: String -> (List String)
  (let [(shown (reviewScrub diff (reviewDiffLines) 400))
        (total (listLength (stringLines diff)))]
    (if (> total (reviewDiffLines))
      (listAppend shown (list (str "(diff clipped: " (stringFromInt64 (- total (reviewDiffLines))) " more lines not shown; do not fail on code you were not shown)")))
      shown))

fn reviewBrief u: ReviewUnit diff: String gates: String -> String
  (str "(:review :unit " (fm/asnQuote u.id) " :risk " u.risk
       " :task " (fm/asnQuote (stringJoin (scrubLines u.task 12 240) " "))
       " :diff " (fm/asnStrings (reviewDiffPart diff))
       " :gates " (fm/asnStrings (scrubLines gates 20 200))
       " :reply \"one form only: (:verdict :pass|:fail :defects (\\\"concrete defect with path and symbol\\\") :model name); :fail needs a concrete defect\")")

fn finalRungOf u: ReviewUnit -> String
  (if (or u.closureChanged (= u.risk "high")) "R2" "R1")

fn startRungOf u: ReviewUnit -> String
  (cond ((!= u.startRung "") u.startRung) ((= u.risk "high") "R2") (else "R1"))

fn nameList vs: (List Verdict) -> (List String)
  (map (fn [(v Verdict)] -> String (str v.rung " " v.model " " v.outcome (if (listEmpty? v.defects) "" (str ": " (stringJoin v.defects "; "))))) vs)

fn atomOf s: String -> String
  (if (or (stringEmpty? s) (listAny? (fn [(c String)] -> Bool (stringContains? s c)) (list " " "(" ")" "\"" ";" "\n"))) (fm/asnQuote s) s)

; (:m :ref REVIEW-TIEBREAK :do "a split at the last rung is not a verdict anyone can act on: its escalation row carries :need tiebreak and the families that already voted, so the lead or the Claude tier decides with a reviewer family not yet used instead of finding a bare blocked unit")
fn tiebreakNeed why: String vs: (List Verdict) -> String
  (if (stringStartsWith? why "tiebreak: ")
    (str " :need tiebreak :usedModels " (fm/asnStrings (map (fn [(v Verdict)] -> String v.model) vs)))
    "")

; (:m :ref COND3 :do "an escalation goes to the queue (the autonomous conductor has no one to page), with the tiers still to try in order: the strong lane unless R3 already asked it, and Claude only last")
fn escalateRow u: ReviewUnit rung: String vs: (List Verdict) why: String -> String
  (str "(:escalate :unit " (atomOf u.id) " :rung " rung " :to queue :tiers " (if (listAny? (fn [(v Verdict)] -> Bool (= v.rung "R3")) vs) "(claude)" "(strong claude)") " :why " (fm/asnQuote why) (tiebreakNeed why vs)
       " :seen " (fm/asnStrings (nameList vs))
       " :tried " (fm/asnStrings (map (fn [(v Verdict)] -> String (str v.rung " " v.model)) vs))
       " :disagree " (fm/asnStrings (nameList (filter (fn [(v Verdict)] -> Bool (!= v.outcome "abstain")) vs))) ")")

fn modelsOf vs: (List Verdict) -> String
  (stringJoin (map (fn [(v Verdict)] -> String v.model) vs) "+")

fn ruling action: String rung: String defects: (List String) awaitLane: String rows: (List String) vs: (List Verdict) why: String -> Ruling
  (Ruling :action action :rung rung :defects defects :awaitLane awaitLane :rows rows :verdicts vs :why why)

; (:m :ref TRIAL-REVIEW-ROWS :do "one (:reviewCall :unit :rung :alias :verdict :defects N :tokens :ms :empty BOOL) row per reviewer call, so per-reviewer verdicts no longer sit inside the one (:grade :note); :empty is true when the reply was blank or the call said empty; :tokens is 0 here, the call has no usage channel in the ladder, and the review stage fills it from its usage rows")
; (:m :ref LANE-PERMANENT-ERROR :do "a call failure is permanent when the provider says it will not answer this lane at all: HTTP 400 insufficient credits, 401, 403, 404 (bad key, no access, unknown model); every other failure (429, 5xx, timeout, blank) is transient and stays absence; the status code must be a whole number token of the error text")
fn codeTokens e: String -> (List String)
  (filter (fn [(t String)] -> Bool (not (stringEmpty? t)))
          (stringSplit (fold (fn [(a String) (c String)] -> String (stringReplace a c " ")) (stringLower e) (list ":" "/" "," ";" "(" ")" "\"" "=" "-" "_")) " "))

; (:m :ref LANE-PERMANENT-ERROR-FIX :do "a status counts only as a status: 401, 403 or 404 right after http, status, code or error, or as the first token of the message; a number elsewhere (retry after 403 s, req-404-ab, timeout after 401 ms) is no status, and a message that also carries a transient mark (429, a 5xx, timeout, rate limit, overloaded, retry) is transient whatever else it says")
fn transientMark? toks: (List String) low: String -> Bool
  (or (listAny? (fn [(t String)] -> Bool (or (= t "429") (and (= (stringLength t) 3) (and (stringStartsWith? t "5") (some? (stringToInt64 t)))))) toks)
      (listAny? (fn [(m String)] -> Bool (stringContains? low m)) (list "timeout" "timed out" "rate limit" "overloaded" "retry")))

fn statusIdx? toks: (List String) i: Int64 -> Bool
  (and (listContains? (list "401" "403" "404") (optionOr (listGet toks i) ""))
       (or (= i 0) (listContains? (list "http" "status" "code" "error") (optionOr (listGet toks (- i 1)) ""))))

fn statusAt toks: (List String) -> Bool
  (listAny? (fn [(i Int64)] -> Bool (statusIdx? toks i)) (range 0 (listLength toks)))

; (:m :ref LANE-UNAVAILABLE-MEMORY-FIX :do "the cause word of a permanent lane error from the same reading permanentError? uses: credits for an insufficient-credit message, else the first token that counts as a status (401 403 404), else permanent; a number inside a message is not a cause")
fn causeOf why: String -> String
  (let [(toks (codeTokens why))
        (hits (filter (fn [(i Int64)] -> Bool (statusIdx? toks i)) (range 0 (listLength toks))))]
    (cond ((stringContains? (stringLower why) "credit") "credits")
          ((not (listEmpty? hits)) (optionOr (listGet toks (optionOr (listHead hits) 0)) "permanent"))
          (else "permanent")))

fn permanentError? e: String -> Bool
  (let [(low (stringLower e))
        (toks (codeTokens e))]
    (and (not (transientMark? toks low))
         (or (stringContains? low "insufficient credit") (statusAt toks))))

; (:m :ref LANE-PERMANENT-ERROR-FIX :do "an await whose target names no live lane (a tier name, because the permanent errors left the tier empty) is one wake! cannot resolve and the starved cap never counts: the ruling blocks at once with the sig review: no live lane on tier T (permanent: alias cause), the escalate row and the laneUnavailable rows, so it is bounded and the lead sees it")
fn unresolvable? r: Ruling live: (List Lane) -> Bool
  (and (= r.action "await")
       (not (listAny? (fn [(a String)] -> Bool (listAny? (fn [(l Lane)] -> Bool (= l.alias a)) live)) (stringSplit r.awaitLane " "))))

fn tierOfRung rung: String -> String
  (cond ((= rung "R1") "free") ((= rung "R2") "paid") (else "strong"))

fn blockedNoLane u: ReviewUnit rung: String prior: (List Verdict) dead: (List Verdict) earlier: (List String) -> Ruling
  (let [(why (str "review: no live lane on tier " (tierOfRung rung) " (permanent: " (stringJoin (map (fn [(v Verdict)] -> String (str v.model " " (causeOf (optionOr (listHead v.defects) "")))) dead) ", ") ")"))]
    (ruling "blocked" rung (defectsOf prior) ""
            (listAppend (list (g/gradeRow u.id "none" (modelsOf prior) u.writerChannel "pending" why) (escalateRow u rung prior why)) earlier)
            prior why))

fn unavailable? v: Verdict -> Bool
  (and (= v.outcome "abstain") (stringStartsWith? (optionOr (listHead v.defects) "") "lane unavailable"))

; (:m :ref LANE-PERMANENT-ERROR :do "one (:laneUnavailable ... :sev warn) row per lane that failed permanently in this review; the lane leaves the pool for the rest of the review and the rung is picked again from the lanes that remain")
fn unavailableRow u: ReviewUnit rung: String v: Verdict -> String
  (str "(:laneUnavailable :unit " (atomOf u.id) " :rung " rung " :lane " (atomOf v.model) " :sev warn :why " (fm/asnQuote (optionOr (listHead v.defects) "")) ")")

fn reviewCallRow u: ReviewUnit v: Verdict ms: Int64 empty: Bool -> String
  (str "(:reviewCall :unit " (atomOf u.id) " :rung " v.rung " :alias " (atomOf v.model) " :verdict " v.outcome " :defects " (stringFromInt64 (if (= v.outcome "abstain") 0 (listLength v.defects))) " :tokens 0 :ms " (stringFromInt64 ms) " :empty " (if empty "true" "false") ")")

fn ! askLaneRow u: ReviewUnit callModel: (fn ! [String String] -> (Result String String)) prompt: String rung: String lane: Lane -> (Pair Verdict String)
  (let [(t0 (/ (nowNs) 1000000))
        (reply (callModel lane.alias prompt))
        (ms (- (/ (nowNs) 1000000) t0))
        (empty (match reply ((err e) (stringContains? (stringLower e) "empty")) ((ok text) (stringEmpty? (stringTrim text)))))
        (v (match reply
             ((err e) (abstain lane.alias rung (str (if (permanentError? e) "lane unavailable: " "call failed: ") (clip e 160))))
             ((ok text) (if (stringEmpty? (stringTrim text)) (abstain lane.alias rung "no answer: empty reply") (parseVerdict text lane.alias rung)))))]
    (pair v (reviewCallRow u v ms empty)))

; (:m :ref LANE-PERMANENT-ERROR :do "rows of an earlier attempt join a ruling after its head rows (grade, await, escalate) and before the review calls of the later attempt, so the head row stays first and calls keep their order")
fn withEarlier r: Ruling earlier: (List String) -> Ruling
  (ruling r.action r.rung r.defects r.awaitLane
          (listAppend (filter (fn [(x String)] -> Bool (not (stringStartsWith? x "(:reviewCall "))) r.rows)
                      (listAppend earlier (filter (fn [(x String)] -> Bool (stringStartsWith? x "(:reviewCall ")) r.rows)))
          r.verdicts r.why)

; (:m :ref REVIEW-DEFER :do "an await is one (:await :unit :rung :lane ...) row with its reason, which the conductor journals, so a parked review says what it waits for")
fn awaitRow u: ReviewUnit rung: String lane: String why: String -> String
  (str "(:await :unit " (atomOf u.id) " :rung " rung " :lane " (atomOf lane) " :why " (fm/asnQuote why) ")")

; (:m :ref WAKE-LOWS :do "the R2 and R3 wake sets join as a union in first-seen order, so a lane named by both (an alias in both tiers) appears once in the await")
fn joinAwait a: String b: String -> String
  (stringJoin (fold (fn [(acc (List String)) (nm String)] -> (List String) (if (or (stringEmpty? nm) (listContains? acc nm)) acc (listAppend acc (list nm))))
                    (list) (listAppend (stringSplit a " ") (stringSplit b " ")))
              " ")

; (:m :ref REVIEW-DEFER :do "a paid rung with no lane falls through to the strong rung with the verdicts so far (node2 2026-11-04: every paid lane outside the writer family was out of allowance and the unit parked on a lane whose window resets in nine days); when the strong rung has no lane either the R2 await stands at R2 with both lanes, space-separated, as its wake set and a reason naming both rungs")
fn ! runRung u: ReviewUnit rows: (List rd/SExpr) lanes: (List Lane) prompt: String receipt: String callModel: (fn ! [String String] -> (Result String String)) rung: String prior: (List Verdict) fixesUsed: Int64 -> (Result Ruling String)
  (let [(pick (cond ((= rung "R1") (selectFree rows u.writerAlias lanes))
                    ((= rung "R2") (selectOne rows u.writerAlias "paid" lanes))
                    (else (selectOne rows u.writerAlias "strong" lanes))))]
    (match pick
      ((pickAwait lane why)
        (let [(here (ruling "await" rung (list) lane (list (awaitRow u rung lane why)) prior why))]
          (if (!= rung "R2") (ok here)
            (match (runRung u rows lanes prompt receipt callModel "R3" prior fixesUsed)
              ((err e) (err e))
              ((ok r3) (if (= r3.action "await")
                         (let [(both (str why "; R3: " r3.why))
                               (lanes2 (joinAwait lane r3.awaitLane))]
                           (ok (ruling "await" rung (list) lanes2 (list (awaitRow u rung lanes2 both)) prior both)))
                         (ok r3)))))))
      ((pickOk ls)
        (let [(asked (map (fn [(l Lane)] -> (Pair Verdict String) (askLaneRow u callModel prompt rung l)) ls))
              (dead (filter unavailable? (map pairFirst asked)))]
         (if (not (listEmpty? dead))
          (let [(deadAliases (map (fn [(v Verdict)] -> String v.model) dead))
                (live (filter (fn [(l Lane)] -> Bool (not (listContains? deadAliases l.alias))) lanes))
                (earlier (listAppend (map pairSecond asked) (map (fn [(v Verdict)] -> String (unavailableRow u rung v)) dead)))]
            (match (runRung u rows live prompt receipt callModel rung prior fixesUsed)
              ((err e) (err e))
              ((ok next) (ok (if (unresolvable? next live) (blockedNoLane u rung prior dead earlier) (withEarlier next earlier))))))
           (let [(cur (map pairFirst asked))
                 (calls (map pairSecond asked))
                 (all (listAppend prior cur))
                 (step (decide rung cur all (listEmpty? prior) (finalRungOf u) fixesUsed (gatesProven receipt)))
                 (grade (fn [(verdict String) (note String)] -> String (g/gradeRow u.id "none" (modelsOf all) u.writerChannel verdict note)))]
             (match step
               ((stepMerge) (ok (ruling "merge" rung (list) "" (listAppend (list (grade "accept" (str "ladder " rung))) calls) all "")))
               ((stepFix ds) (ok (ruling "fix" rung ds "" (listAppend (list (grade "reject" (clip (stringJoin ds "; ") 300))) calls) all "")))
               ((stepDefer ls why) (ok (ruling "await" rung (list) ls (listAppend (list (awaitRow u rung ls why)) calls) all why)))
               ((stepBlocked why) (ok (ruling "blocked" rung (defectsOf all) "" (listAppend (list (grade "pending" why) (escalateRow u rung all why)) calls) all why)))
               ((stepEscalate) (match (runRung u rows lanes prompt receipt callModel (nextRung rung) all 0)
                                 ((err e) (err e))
                                 ((ok next) (ok (withEarlier next calls))))))))))))

; (:m :ref COND2 :do "the conductor's review stage: (review unit diff gates lanes callModel) -> Ruling.")
; (:m :ref COND2 :do "callModel takes a lane alias and a prompt and returns the reply text; ruling.action is merge | fix | await | blocked.")
fn ! reviewWith table: String u: ReviewUnit diff: String gates: String lanes: (List Lane) callModel: (fn ! [String String] -> (Result String String)) -> (Result Ruling String)
  (let [(rows (familyRows table))]
    (cond
      ((listEmpty? rows) (err "family table does not parse or is empty"))
      ((not (listContains? (list "low" "med" "high") u.risk)) (err (str "risk " u.risk " is not low, med or high")))
      ((= (rungNum (startRungOf u)) 0) (err (str "startRung " u.startRung " is not R1, R2 or R3")))
      (else (runRung u rows lanes (reviewBrief u diff gates) gates callModel (startRungOf u) u.prior u.fixesUsed))))

fn ! review u: ReviewUnit diff: String gates: String lanes: (List Lane) callModel: (fn ! [String String] -> (Result String String)) -> (Result Ruling String)
  (reviewWith (familyTableAsn) u diff gates lanes callModel)
