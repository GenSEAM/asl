(module asl/agentLoop/retry
  :x [buildRetryBrief costForm batchingRates reinforceWhyFor escalationNear nowForm noWriteNudge gateNow
      advisorSummary advisorSkip parseAdvice parseSpecVerdict digestLine evidenceDigest advisorGateOutput advisorOpLine
      makeGateRec makeReceiptRec verdictMet verdictMissing adviceNext adviceWhy adviceAvoid escapeAsn
      providerRetryPause retryTurn! GateRec ReceiptRec AdviceRec SpecVerdict]
  :i [(asl/agentLoop/context :a ctx) (asl/agentLoop/providers :a pv)])

fn providerRetryPause errorCode: String retryCount: Int64 configured: (List Int64) budgetLeft: (Option Int64) -> Int64
  (let [transient (listContains? (list "ERR_VENDOR" "ERR_QUEUE_TIMEOUT" "ERR_GATEWAY_OFFLINE") errorCode)
        slot (min retryCount (listLength configured))
        pause (if (and transient (> slot 0)) (optionOr (listGet configured (- slot 1)) 0) 0)]
    (mt budgetLeft ((some left) (max 0 (min pause left))) ((none) pause)))

fn ! retryTurn! provider: pv/Provider call: (fn [pv/Provider Int64] -> pv/Turn) maxRetries: Int64 configured: (List Int64) budgetLeft: (Option Int64) sleep: (fn [Int64] -> Bool) -> (Pair pv/Turn Int64)
  (retryTurnLoop! provider call (max 0 maxRetries) configured budgetLeft sleep 0)

fn ! retryTurnLoop! provider: pv/Provider call: (fn [pv/Provider Int64] -> pv/Turn) maxRetries: Int64 configured: (List Int64) budgetLeft: (Option Int64) sleep: (fn [Int64] -> Bool) retries: Int64 -> (Pair pv/Turn Int64)
  (let [turn (call provider retries)]
    (mt turn.reply
      ((ok _) (pair turn retries))
      ((err error)
        (let [code (pv/errorCode error)
              pause (providerRetryPause code (+ retries 1) configured budgetLeft)]
          (if (and (< retries maxRetries) (listContains? (list "ERR_VENDOR" "ERR_QUEUE_TIMEOUT" "ERR_GATEWAY_OFFLINE") code))
            (let [waited (if (> pause 0) (sleep pause) true)
                  left (mt budgetLeft ((some n) (some (max 0 (- n pause)))) ((none) none))]
              (if waited
                (retryTurnLoop! turn.provider call maxRetries configured left sleep (+ retries 1))
                (pair turn retries)))
            (pair turn retries))))))

enum GateRec
  (gateRec cmd: String exit: (Option Int64) timeout: Bool seconds: (Option Int64) stdout: String stderr: String)

enum ReceiptRec
  (receiptRec id: String op: (Option String) kind: (Option String) cmd: (Option String) stdout: (Option String)
              file: (Option String) path: (Option String) symbol: (Option String) query: (Option String)
              topic: (Option String) url: (Option String) exit: (Option Int64) status: (Option String) error: (Option String)
              content: (Option String))

enum AdviceRec
  (adviceRec next: String why: (Option String) avoid: (Option String))

enum SpecVerdict
  (specVerdict met: Bool missing: (List String))


fn slice s: String i: Int64 j: Int64 -> String
  (optionOr (stringSlice s i j) "")

fn charAt s: String i: Int64 -> String
  (slice s i (+ i 1))

fn isDigitChar c: String -> Bool
  (and (>= c "0") (<= c "9"))

fn isWordChar c: String -> Bool
  (or (isDigitChar c)
    (or (and (>= c "a") (<= c "z"))
      (or (and (>= c "A") (<= c "Z")) (= c "_"))))

fn isSpaceChar c: String -> Bool
  (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))

fn wordBoundaryOk s: String i: Int64 n: Int64 -> Bool
  (or (>= i n) (not (isWordChar (charAt s i))))

fn skipSpaces s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (isSpaceChar (charAt s i))) (skipSpaces s (+ i 1) n) i)

fn skipSpacesRequireOne s: String i: Int64 n: Int64 -> (Option Int64)
  (let [j (skipSpaces s i n)] (if (= j i) none (some j)))

fn wordRunEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (isWordChar (charAt s i))) (wordRunEnd s (+ i 1) n) i)

fn digitRunEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (isDigitChar (charAt s i))) (digitRunEnd s (+ i 1) n) i)

fn strBodyEnd s: String i: Int64 n: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (charAt s i) "\"") i)
    ((= (charAt s i) "\\") (if (< (+ i 1) n) (strBodyEnd s (+ i 2) n) -1))
    (else (strBodyEnd s (+ i 1) n)))

fn charLen s: String -> Int64
  (listLength (stringChars s))

fn charPrefix s: String k: Int64 -> String
  (stringJoin (listTake (stringChars s) k) "")

fn charSuffix s: String k: Int64 -> String
  (let [cs (stringChars s) n (listLength cs)] (stringJoin (listDrop cs (max 0 (- n k))) ""))

fn pySplitLines s: String -> (List String)
  (let [parts (stringSplit s "\n")]
    (mt (listLast parts)
      ((some last) (if (stringEmpty? last) (listTake parts (- (listLength parts) 1)) parts))
      ((none) parts)))

fn escapeAsn s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn specUnescape s: String -> String
  (stringReplace (stringReplace s "\\\"" "\"") "\\\\" "\\")

fn stripLeadingColons s: String -> String
  (if (and (> (stringLength s) 0) (= (charAt s 0) ":")) (stripLeadingColons (slice s 1 (stringLength s))) s)

fn firstSomeStr xs: (List (Option String)) -> (Option String)
  (fold (fn [acc o] (mt acc ((some _) acc) ((none) o))) none xs)

fn assocLookup xs: (List (Pair String Int64)) k: String -> (Option Int64)
  (fold (fn [acc p] (mt acc ((some _) acc) ((none) (if (= (pairFirst p) k) (some (pairSecond p)) none)))) none xs)

fn maxOfPairs xs: (List (Pair String Int64)) -> Int64
  (optionOr (listMax (map pairSecond xs)) 0)


fn findTagStart s: String tag: String from: Int64 -> (Option Int64)
  (let [n (stringLength s)]
    (mt (stringIndexOf (slice s from n) "(")
      ((none) none)
      ((some relIdx)
        (let [openIdx (+ from relIdx)
              afterOpen (+ openIdx 1)
              afterSpace (skipSpaces s afterOpen n)
              tagLen (stringLength tag)
              tagEnd (+ afterSpace tagLen)]
          (if (and (<= tagEnd n) (and (= (slice s afterSpace tagEnd) tag) (wordBoundaryOk s tagEnd n)))
            (some openIdx)
            (findTagStart s tag afterOpen))))))

fn lastCloseParenScan text: String i: Int64 start: Int64 -> (Option Int64)
  (if (< i start) none
    (if (= (charAt text i) ")") (some i) (lastCloseParenScan text (- i 1) start)))

fn lastCloseParenFrom text: String start: Int64 -> (Option Int64)
  (lastCloseParenScan text (- (stringLength text) 1) start)

fn findQuotedField s: String key: String from: Int64 -> (Option String)
  (let [n (stringLength s) pat (str ":" key)]
    (mt (stringIndexOf (slice s from n) pat)
      ((none) none)
      ((some relIdx)
        (let [idx (+ from relIdx) after (+ idx (stringLength pat))]
          (mt (skipSpacesRequireOne s after n)
            ((none) (findQuotedField s key (+ idx 1)))
            ((some q)
              (if (and (< q n) (= (charAt s q) "\""))
                (let [bodyEnd (strBodyEnd s (+ q 1) n)]
                  (if (< bodyEnd 0) (findQuotedField s key (+ idx 1)) (some (slice s (+ q 1) bodyEnd))))
                (findQuotedField s key (+ idx 1)))))))))

fn findWordFieldFrom s: String tag: String from: Int64 -> (Option String)
  (let [n (stringLength s)]
    (mt (stringIndexOf (slice s from n) tag)
      ((none) none)
      ((some relIdx)
        (let [idx (+ from relIdx) after (+ idx (stringLength tag))]
          (mt (skipSpacesRequireOne s after n)
            ((none) (findWordFieldFrom s tag (+ idx 1)))
            ((some q)
              (let [wEnd (wordRunEnd s q n)]
                (if (= wEnd q) (findWordFieldFrom s tag (+ idx 1)) (some (slice s q wEnd))))))))))

fn findMetValue form: String from: Int64 -> (Option Bool)
  (let [n (stringLength form)]
    (mt (stringIndexOf (slice form from n) ":met")
      ((none) none)
      ((some relIdx)
        (let [idx (+ from relIdx) after (+ idx 4)]
          (mt (skipSpacesRequireOne form after n)
            ((none) (findMetValue form (+ idx 1)))
            ((some q)
              (cond
                ((and (<= (+ q 4) n) (= (slice form q (+ q 4)) "true")) (some true))
                ((and (<= (+ q 5) n) (= (slice form q (+ q 5)) "false")) (some false))
                (else (findMetValue form (+ idx 1))))))))))

fn extractDepthStrings form: String i: Int64 n: Int64 depth: Int64 acc: (List String) -> (List String)
  (if (or (>= i n) (= depth 0))
    (listReverse acc)
    (let [c (charAt form i)]
      (cond
        ((= c "\"")
          (let [bodyEnd (strBodyEnd form (+ i 1) n)]
            (if (< bodyEnd 0)
              (listReverse acc)
              (let [content (slice form (+ i 1) bodyEnd)
                    newAcc (if (= depth 1) (cons (specUnescape content) acc) acc)]
                (extractDepthStrings form (+ bodyEnd 1) n depth newAcc)))))
        ((= c "(") (extractDepthStrings form (+ i 1) n (+ depth 1) acc))
        ((= c ")") (extractDepthStrings form (+ i 1) n (- depth 1) acc))
        (else (extractDepthStrings form (+ i 1) n depth acc)))))

fn scanMissingOccurrences form: String from: Int64 -> (List String)
  (let [n (stringLength form)]
    (mt (stringIndexOf (slice form from n) ":missing")
      ((none) (list))
      ((some relIdx)
        (let [idx (+ from relIdx) afterKey (+ idx 8) afterSpace (skipSpaces form afterKey n)]
          (if (and (< afterSpace n) (= (charAt form afterSpace) "("))
            (listAppend (extractDepthStrings form (+ afterSpace 1) n 1 (list)) (scanMissingOccurrences form (+ afterSpace 1)))
            (scanMissingOccurrences form (+ idx 1)))))))


fn roundRatioEven numer: Int64 denom: Int64 scale: Int64 -> Float64
  (let [scaled (* numer scale)
        q (/ scaled denom)
        r (mod scaled denom)
        twice (* r 2)
        resultInt (cond
                    ((< twice denom) q)
                    ((> twice denom) (+ q 1))
                    (else (if (= (mod q 2) 0) q (+ q 1))))]
    (/ (int64ToFloat64 resultInt) (int64ToFloat64 scale)))

fn roundFloatEven x: Float64 -> Float64
  (ctx/pyRound x 1)


; (:m :tags (budget))
fn batchingRates turns: Int64 ops: Int64 single: Int64 -> (Pair Float64 Float64)
  (if (= turns 0)
    (pair 0.0 0.0)
    (pair (roundRatioEven ops turns 100) (roundRatioEven single turns 100)))

; (:m :tags (budget))
fn costForm turns: Int64 ops: Int64 single: Int64 tokens: Int64 wallSec: Float64 turnsDone: Int64 -> String
  (let [rates (batchingRates turns ops single)
        pace (if (> turnsDone 0) (roundFloatEven (/ wallSec (int64ToFloat64 turnsDone))) 0.0)]
    (str "(:turns " (stringFromInt64 turns) " :tokens " (stringFromInt64 tokens)
         " :opsPerTurn " (stringFromFloat64 (pairFirst rates))
         " :singleOpShare " (stringFromFloat64 (pairSecond rates))
         " :secPerTurn " (stringFromFloat64 pace) ")"))

fn escalationStopThreshold budget: Int64 -> Float64
  (let [bf (* (int64ToFloat64 budget) 0.5)]
    (if (< bf 20.0) bf 20.0))

; (:m :tags (signals))
fn escalationNear turnNum: Int64 budget: Int64 retries: (List (Pair String Int64)) maxRetries: Int64
                   failureCounts: (List (Pair String Int64)) stalled: Int64 parseDefects: Int64 noWrite: Bool
                   readStreak: Int64 redGate: Bool -> String
  (if (<= turnNum 1)
    ""
    (let [spent (filter (fn [p] (>= (pairSecond p) maxRetries)) retries)]
      (cond
        ((not (listEmpty? spent)) (str "one more " (pairFirst (firstOfPairs spent)) " miss escalates"))
        ((and (not (listEmpty? failureCounts)) (>= (maxOfPairs failureCounts) 2)) "one more repeat of the same failure escalates")
        ((>= stalled 2) "one more turn without new evidence escalates")
        ((>= parseDefects maxRetries) "one more parse defect escalates")
        ((and redGate (>= readStreak 11)) "one more turn without a write while a gate is red escalates")
        ((and noWrite (>= (int64ToFloat64 turnNum) (escalationStopThreshold budget))) "the run stops without a write after this turn")
        (else ""))))

fn firstOfPairs xs: (List (Pair String Int64)) -> (Pair String Int64)
  (mt (listHead xs) ((some x) x))

fn lastTwoIntersectionSorted history: (List (List String)) -> (List String)
  (let [n (listLength history)]
    (if (< n 2)
      (list)
      (let [a (optionOr (listGet history (- n 1)) (list))
            b (optionOr (listGet history (- n 2)) (list))]
        (listSort (filter (fn [x] (listContains? b x)) a)))))

; (:m :tags (reinforce))
fn reinforceWhyFor parseDefect: Bool gateSigHistory: (List (List String)) deliver: String writesPersisted: Bool
                    turnsWithoutEvidence: Int64 turnNum: Int64 budget: Int64 retries: (List (Pair String Int64))
                    maxRetries: Int64 failureCounts: (List (Pair String Int64)) parseDefectCount: Int64
                    readStreak: Int64 redGate: (Option String) -> String
  (let [twice (lastTwoIntersectionSorted gateSigHistory)]
    (cond
      ((not (listEmpty? twice)) (str "same gate failure twice in a row: " (charPrefix (optionOr (listHead twice) "") 160)))
      (parseDefect "the last reply was a parse defect")
      ((and (some? redGate) (>= readStreak 6))
        (str (stringFromInt64 readStreak) " turns without a write while gate " (optionOr redGate "") " is red"))
      ((and (= deliver "patch") (and (not writesPersisted) (>= turnsWithoutEvidence 2)))
        (str "patch deliverable and nothing written after " (stringFromInt64 (- turnNum 1)) " turns"))
      (else (escalationNear turnNum budget retries maxRetries failureCounts turnsWithoutEvidence parseDefectCount
                             (and (= deliver "patch") (not writesPersisted)) readStreak (some? redGate)))))

fn gCmd g: GateRec -> String (mt g ((gateRec c _ _ _ _ _) c))
fn gExit g: GateRec -> (Option Int64) (mt g ((gateRec _ e _ _ _ _) e))
fn gTimeout g: GateRec -> Bool (mt g ((gateRec _ _ t _ _ _) t))
fn gSeconds g: GateRec -> (Option Int64) (mt g ((gateRec _ _ _ s _ _) s))
fn gStdout g: GateRec -> String (mt g ((gateRec _ _ _ _ o _) o))
fn gStderr g: GateRec -> String (mt g ((gateRec _ _ _ _ _ e) e))

fn makeGateRec cmd: String exit: Int64 timeout: Bool seconds: Int64 stdout: String stderr: String -> GateRec
  (gateRec cmd (if (< exit 0) none (some exit)) timeout (if (< seconds 0) none (some seconds)) stdout stderr)

fn optDisplayInt o: (Option Int64) -> String
  (mt o ((some v) (stringFromInt64 v)) ((none) "None"))

fn gateOutcome g: GateRec -> String
  (if (gTimeout g)
    (str ":timeout true :seconds " (optDisplayInt (gSeconds g)))
    (str ":exit " (optDisplayInt (gExit g))))

fn assertsFailedOnLine line: String -> (Option (Pair String String))
  (mt (stringIndexOf line ":asserts ")
    ((none) none)
    ((some idx)
      (let [n (stringLength line) digStart (+ idx 9) digEnd (digitRunEnd line digStart n)]
        (if (= digEnd digStart)
          none
          (let [asserts (slice line digStart digEnd) sepEnd (+ digEnd 9)]
            (if (and (<= sepEnd n) (= (slice line digEnd sepEnd) " :failed "))
              (let [dig2Start sepEnd dig2End (digitRunEnd line dig2Start n)]
                (if (= dig2End dig2Start) none (some (pair asserts (slice line dig2Start dig2End)))))
              none))))))

fn gateNowCounts stdoutText: String -> (Option (Pair String String))
  (fold (fn [acc line] (if (stringStartsWith? line "(:gate ") (mt (assertsFailedOnLine line) ((some m) (some m)) ((none) acc)) acc))
    none (stringSplit stdoutText "\n"))

fn gateNow turn: Int64 g: GateRec -> String
  (let [countsOpt (gateNowCounts (gStdout g))
        tail (mt countsOpt ((some cp) (str " :asserts " (pairFirst cp) " :failed " (pairSecond cp))) ((none) ""))]
    (str "(:cmd \"" (escapeAsn (gCmd g)) "\" :turn " (stringFromInt64 turn) " " (gateOutcome g) tail ")"))

; (:m :tags (leon signals))
fn noWriteNudge deliver: String wrote: Bool done: Int64 files: (List String) winWhole: (List Int64)
                readStreak: Int64 redGate: (Option String) -> String
  (cond
    ((and (some? redGate) (>= readStreak 6))
      (str (stringFromInt64 readStreak) " turns without a write while gate " (optionOr redGate "")
           " is red: write the fix you have, or escalate naming what is missing"))
    ((or (!= deliver "patch") (or wrote (< done 10))) "")
    (else
      (let [wholeStr (stringJoin (map stringFromInt64 winWhole) " ")
            filesStr (if (listEmpty? files) "none" (stringJoin files ", "))]
        (str (stringFromInt64 done) " turns and nothing written; files read: " filesStr
             "; receipts still whole: turns " wholeStr "; the run stops at turn 20 without a write"))))

fn nowForm turn: Int64 contextTokens: Int64 win: (Option (Pair Int64 String)) written: (List String)
           lastGates: (List (Pair Int64 GateRec)) retriesLeft: (List (Pair String Int64))
           nudge: String cost: String plan: String -> String
  (let [usedBytes (mt win ((some p) (pairFirst p)) ((none) 0))
        head (str "(:now :turn " (stringFromInt64 turn) " :context (:tokens " (stringFromInt64 contextTokens)
                  " :usedBytes " (stringFromInt64 usedBytes) ")")
        costPart (if (stringEmpty? cost) "" (str " :cost " cost))
        planPart (if (stringEmpty? plan) "" (str " :plan " plan))
        nudgePart (if (stringEmpty? nudge) "" (str " :noWrite \"" (escapeAsn nudge) "\""))
        writtenPart (if (listEmpty? written) "" (str " :written (" (stringJoin (map (fn [p] (str "\"" (escapeAsn p) "\"")) written) " ") ")"))
        gatesPart (if (listEmpty? lastGates) "" (str " :gates (" (stringJoin (map (fn [tg] (gateNow (pairFirst tg) (pairSecond tg))) lastGates) " ") ")"))
        retriesPart (str " :retriesLeft (" (stringJoin (map (fn [p] (str ":" (pairFirst p) " " (stringFromInt64 (max 0 (pairSecond p))))) retriesLeft) " ") ")")
        lastPart (mt win ((some p) (str " :last " (pairSecond p))) ((none) ""))]
    (str head costPart planPart nudgePart writtenPart gatesPart retriesPart lastPart ")"))

fn gateFailingBool g: GateRec -> Bool
  (mt (gExit g) ((some e) (!= e 0)) ((none) true))

fn gateTail g: GateRec -> String
  (let [combined (stringTrim (str (gStdout g) "\n" (gStderr g)))
        lines (pySplitLines combined)
        n (listLength lines)
        kept (listDrop lines (max 0 (- n 20)))]
    (charSuffix (stringJoin kept "\n") 2000))

fn gateFailLine i: Int64 total: Int64 g: GateRec -> (List String)
  (let [name (str "gate " (stringFromInt64 i) " of " (stringFromInt64 total) ": \"" (gCmd g) "\"")
        line1 (if (gTimeout g)
                (str name ", timed out after " (optDisplayInt (gSeconds g))
                     " s (:timeout true :seconds " (optDisplayInt (gSeconds g))
                     "): killed by the run's :gateTimeout, not a failing exit")
                (str name ", exit code: " (optDisplayIntDefault (gExit g) 1)))
        tail (gateTail g)]
    (if (stringEmpty? tail)
      (list line1)
      (list line1 (str "gate " (stringFromInt64 i) " output (last 20 lines, at most 2000 chars):\n" tail))))

fn optDisplayIntDefault o: (Option Int64) d: Int64 -> String
  (stringFromInt64 (optionOr o d))

fn gateOkLine i: Int64 total: Int64 g: GateRec -> String
  (str "gate " (stringFromInt64 i) " of " (stringFromInt64 total) ": \"" (gCmd g) "\", exit code: " (optDisplayIntDefault (gExit g) 0))

fn gateResultParts gates: (List GateRec) -> (List String)
  (let [indexed (enumerate gates)
        total (listLength gates)
        failing (filter (fn [p] (gateFailingBool (pairSecond p))) indexed)]
    (cond
      ((not (listEmpty? failing)) (fold (fn [acc p] (listAppend acc (gateFailLine (+ (pairFirst p) 1) total (pairSecond p)))) (list) failing))
      ((not (listEmpty? gates)) (map (fn [p] (gateOkLine (+ (pairFirst p) 1) total (pairSecond p))) indexed))
      (else (list))))

fn missingGateFileLine p: (Pair Int64 String) -> String
  (str "gate " (stringFromInt64 (pairFirst p)) " runs " (pairSecond p) ", which does not exist: create it (a real test first, red on the missing behaviour)")

fn buildRetryBrief retryCount: Int64 truncated: Bool parseDefectReply: (Option String) parseFailureWhere: (Option String)
                    swallowedFile: (Option String) swallowedLine: Int64 swallowedRule: (Option String)
                    gates: (List GateRec)
                    placeholderFile: (Option String) placeholderLine: Int64 placeholderText: (Option String)
                    missingGateFiles: (List (Pair Int64 String))
                    turnReceiptLines: (List String)
                    unbackedCount: Int64 unbackedItems: (List String)
                    undeclaredLines: (List String)
                    acceptedOpShapesJoined: String -> String
  (let [head (str "Retry " (stringFromInt64 retryCount) ":")
        parseParts (cond
                     (truncated (list "your reply was cut at the output token ceiling: send fewer steps and less prose"))
                     ((some? parseDefectReply)
                       (let [quoted (charPrefix (optionOr parseDefectReply "") 200)
                             base (list (str "reply was not parseable ASN: \"" quoted "\""))]
                         (mt parseFailureWhere ((some w) (listAppend base (list w))) ((none) base))))
                     (else (list)))
        swallowedParts (mt swallowedFile
                          ((some f) (list (str "swallowed error in " f " line " (stringFromInt64 swallowedLine) ": " (optionOr swallowedRule ""))))
                          ((none) (list)))
        gateParts (gateResultParts gates)
        placeholderParts (mt placeholderFile
                            ((some f) (list (str "the failing assert is one this run wrote in " f " line " (stringFromInt64 placeholderLine)
                                                  ": " (optionOr placeholderText "") "; if it is a placeholder, replace it with a real check of the behaviour")))
                            ((none) (list)))
        missingParts (map missingGateFileLine missingGateFiles)
        turnReceiptParts (if (listEmpty? turnReceiptLines) (list) (list (str "turn op receipts:\n" (stringJoin turnReceiptLines "\n"))))
        unbackedParts (if (> unbackedCount 0)
                        (let [itemsStr (if (listEmpty? unbackedItems) (stringFromInt64 unbackedCount) (stringJoin unbackedItems "; "))]
                          (list (str "unbacked claims (" (stringFromInt64 unbackedCount) "): " itemsStr)))
                        (list))
        acceptedParts (if (or (some? parseDefectReply) (not (listEmpty? undeclaredLines)))
                        (list (str "accepted op forms:\n  " acceptedOpShapesJoined "\n"
                                   "for code with quotes, backslashes or many lines, use :raw and a fenced block; nothing inside the block is escaped."))
                        (list))
        allParts (cons head (listAppend parseParts (listAppend swallowedParts (listAppend gateParts
                    (listAppend placeholderParts (listAppend missingParts (listAppend turnReceiptParts
                      (listAppend unbackedParts (listAppend undeclaredLines acceptedParts)))))))))]
    (stringJoin allParts "\n\n"))

; (:m :tags (reinforce advisor))
fn matchOneMoreMiss why: String -> (Option String)
  (let [n (stringLength why) pre "one more " suf " miss escalates" preLen (stringLength pre) sufLen (stringLength suf)]
    (if (and (>= n (+ preLen sufLen)) (and (stringStartsWith? why pre) (stringEndsWith? why suf)))
      (let [mid (slice why preLen (- n sufLen))]
        (if (and (not (stringEmpty? mid)) (listAll? isWordChar (stringChars mid))) (some mid) none))
      none))

fn advisorSkipParseCheck why: String parseDefectCount: Int64 -> String
  (if (and (= why "one more parse defect escalates") (= parseDefectCount 0))
    "parse-defect cap reached with no parse defect: a provider or retry limit, not the model"
    "")

fn advisorSkip why: String retries: (List (Pair String Int64)) parseDefectCount: Int64 -> String
  (mt (matchOneMoreMiss why)
    ((some kind)
      (if (= (optionOr (assocLookup retries kind) 0) 0)
        (str kind " retry cap reached with no " kind " miss: a provider or retry limit, not the model")
        (advisorSkipParseCheck why parseDefectCount)))
    ((none) (advisorSkipParseCheck why parseDefectCount)))

fn parseAdviceField form: String key: String -> (Option String)
  (mt (findQuotedField form key 0)
    ((some raw) (some (charPrefix (stringTrim (specUnescape raw)) 400)))
    ((none) none))

; (:m :tags (reinforce advisor))
fn parseAdvice text: String -> (Option AdviceRec)
  (mt (findTagStart text ":advice" 0)
    ((none) none)
    ((some start)
      (let [form (slice text start (stringLength text)) nextOpt (parseAdviceField form "next")]
        (mt nextOpt
          ((none) none)
          ((some nextVal)
            (if (stringEmpty? nextVal)
              none
              (some (adviceRec nextVal (parseAdviceField form "why") (parseAdviceField form "avoid")))))))))

fn adviceNext a: AdviceRec -> String (mt a ((adviceRec n _ _) n))
fn adviceWhy a: AdviceRec -> (Option String) (mt a ((adviceRec _ w _) w))
fn adviceAvoid a: AdviceRec -> (Option String) (mt a ((adviceRec _ _ av) av))

fn parseSpecVerdict text: String -> (Option SpecVerdict)
  (if (stringEmpty? (stringTrim text))
    none
    (mt (findTagStart text ":verdict" 0)
      ((none) none)
      ((some start)
        (mt (lastCloseParenFrom text start)
          ((none) none)
          ((some lastP)
            (let [form (slice text start (+ lastP 1))]
              (mt (findMetValue form 0)
                ((none) none)
                ((some met)
                  (let [missing (scanMissingOccurrences form 0)]
                    (if (and (not met) (listEmpty? missing)) none (some (specVerdict met missing))))))))))))

fn verdictMet v: SpecVerdict -> Bool (mt v ((specVerdict m _) m))
fn verdictMissing v: SpecVerdict -> (List String) (mt v ((specVerdict _ m) m))

fn recId r: ReceiptRec -> String (mt r ((receiptRec i _ _ _ _ _ _ _ _ _ _ _ _ _ _) i))
fn recOp r: ReceiptRec -> (Option String) (mt r ((receiptRec _ o _ _ _ _ _ _ _ _ _ _ _ _ _) o))
fn recKind r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ k _ _ _ _ _ _ _ _ _ _ _ _) k))
fn recCmd r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ c _ _ _ _ _ _ _ _ _ _ _) c))
fn recStdout r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ _ o _ _ _ _ _ _ _ _ _ _) o))
fn recFile r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ _ _ f _ _ _ _ _ _ _ _ _) f))
fn recPath r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ _ _ _ p _ _ _ _ _ _ _ _) p))
fn recSymbol r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ _ _ _ _ s _ _ _ _ _ _ _) s))
fn recQuery r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ _ _ _ _ _ q _ _ _ _ _ _) q))
fn recTopic r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ _ _ _ _ _ _ t _ _ _ _ _) t))
fn recUrl r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ _ _ _ _ _ _ _ u _ _ _ _) u))
fn recExit r: ReceiptRec -> (Option Int64) (mt r ((receiptRec _ _ _ _ _ _ _ _ _ _ _ e _ _ _) e))
fn recStatus r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ _ _ _ _ _ _ _ _ _ s _ _) s))
fn recError r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ _ _ _ _ _ _ _ _ _ _ e _) e))
fn recContent r: ReceiptRec -> (Option String) (mt r ((receiptRec _ _ _ _ _ _ _ _ _ _ _ _ _ _ c) c))

fn optStr s: String -> (Option String)
  (if (stringEmpty? s) none (some s))

fn makeReceiptRec id: String op: String kind: String cmd: String stdout: String file: String path: String
                   symbol: String query: String topic: String url: String exit: Int64 status: String error: String
                   content: String -> ReceiptRec
  (receiptRec id (optStr op) (optStr kind) (optStr cmd) (optStr stdout) (optStr file) (optStr path) (optStr symbol)
              (optStr query) (optStr topic) (optStr url) (if (< exit 0) none (some exit)) (optStr status) (optStr error)
              (optStr content))

fn opOf r: ReceiptRec -> String
  (mt (recOp r) ((some o) o) ((none) (mt (recKind r) ((some k) k) ((none) (if (some? (recCmd r)) "gate" "")))))

fn outOf r: ReceiptRec -> String
  (optionOr (recStdout r) "")

fn hasDimCallersFrom out: String from: Int64 -> Bool
  (let [n (stringLength out)]
    (mt (stringIndexOf (slice out from n) ":dim")
      ((none) false)
      ((some relIdx)
        (let [idx (+ from relIdx) after (+ idx 4)]
          (mt (skipSpacesRequireOne out after n)
            ((none) (hasDimCallersFrom out (+ idx 1)))
            ((some q)
              (let [wEnd (wordRunEnd out q n)]
                (if (= (slice out q wEnd) "callers") true (hasDimCallersFrom out (+ idx 1))))))))))

fn findFirstCharFrom s: String ch: String from: Int64 -> (Option Int64)
  (let [n (stringLength s)] (mt (stringIndexOf (slice s from n) ch) ((none) none) ((some r) (some (+ from r)))))

fn findCountContent out: String from: Int64 -> (Option String)
  (let [n (stringLength out) tag ":count"]
    (mt (stringIndexOf (slice out from n) tag)
      ((none) none)
      ((some relIdx)
        (let [idx (+ from relIdx) after (+ idx (stringLength tag))]
          (mt (skipSpacesRequireOne out after n)
            ((none) (findCountContent out (+ idx 1)))
            ((some q)
              (if (and (< q n) (= (charAt out q) "("))
                (mt (findFirstCharFrom out ")" (+ q 1))
                  ((none) none)
                  ((some cIdx) (some (slice out (+ q 1) cIdx))))
                (findCountContent out (+ idx 1)))))))))

fn scanWordDigitPairs content: String from: Int64 -> (List (Pair String String))
  (let [n (stringLength content)]
    (mt (stringIndexOf (slice content from n) ":")
      ((none) (list))
      ((some relIdx)
        (let [idx (+ from relIdx) wStart (+ idx 1) wEnd (wordRunEnd content wStart n)]
          (if (= wEnd wStart)
            (scanWordDigitPairs content (+ idx 1))
            (mt (skipSpacesRequireOne content wEnd n)
              ((none) (scanWordDigitPairs content (+ idx 1)))
              ((some dStart)
                (let [dEnd (digitRunEnd content dStart n)]
                  (if (= dEnd dStart)
                    (scanWordDigitPairs content (+ idx 1))
                    (cons (pair (slice content wStart wEnd) (slice content dStart dEnd)) (scanWordDigitPairs content dEnd)))))))))))

fn lookupOr pairs: (List (Pair String String)) key: String default: String -> String
  (optionOr (fold (fn [acc p] (if (= (pairFirst p) key) (some (pairSecond p)) acc)) none pairs) default)

fn countBlock out: String -> String
  (mt (findCountContent out 0)
    ((none) "")
    ((some content)
      (let [pairs (scanWordDigitPairs content 0)]
        (str " :count (:calls " (lookupOr pairs "calls" "0")
             " :possible " (lookupOr pairs "possible" "0")
             " :excluded " (lookupOr pairs "excluded" "0") ")"))))

fn observeDimSymbol out: String -> String
  (stringJoin (filterSomeStr (list (findWordFieldFrom out ":dim" 0) (findQuotedField out "symbol" 0))) " ")

fn filterSomeStr xs: (List (Option String)) -> (List String)
  (fold (fn [acc o] (mt o ((some v) (listAppend acc (list v))) ((none) acc))) (list) xs)

fn firstTruthyField r: ReceiptRec -> String
  (optionOr (firstSomeStr (list (recFile r) (recPath r) (recSymbol r) (recQuery r) (recTopic r) (recUrl r) (recCmd r))) "")

fn digestTarget r: ReceiptRec op: String out: String -> String
  (let [observeTarget (if (= op "observe") (observeDimSymbol out) "")]
    (if (not (stringEmpty? observeTarget)) observeTarget (firstTruthyField r)))

fn collapseWsLoop cs: (List String) acc: (List String) inWs: Bool -> String
  (mt (listHead cs)
    ((some c)
      (if (isSpaceChar c)
        (collapseWsLoop (optionOr (listTail cs) (list)) (if inWs acc (cons " " acc)) true)
        (collapseWsLoop (optionOr (listTail cs) (list)) (cons c acc) false)))
    ((none) (stringJoin (listReverse acc) "")))

fn collapseWs s: String -> String
  (collapseWsLoop (stringChars s) (list) false)

fn digestExcerptSrc r: ReceiptRec op: String -> (Option String)
  (cond
    ((= op "read") (recContent r))
    ((= op "run") (recStdout r))
    (else none))

; (:m :tags (findingsCheck))
fn digestExcerptPart r: ReceiptRec op: String -> String
  (mt (digestExcerptSrc r op)
    ((none) "")
    ((some src)
      (let [excerpt (charPrefix (stringTrim (collapseWs src)) 100)]
        (if (stringEmpty? excerpt) "" (str " :excerpt \"" (escapeAsn excerpt) "\"")))))

; (:m :tags (owns))
fn digestLine r: ReceiptRec -> String
  (let [op (opOf r)
        out (outOf r)
        target (charPrefix (stringReplace (digestTarget r op out) "\n" " ") 200)
        idPart (str "(:receipt :id \"" (escapeAsn (recId r)) "\" :op \"" (escapeAsn op) "\"")
        targetPart (if (stringEmpty? target) "" (str " :target \"" (escapeAsn target) "\""))
        statusPart (mt (recExit r)
                     ((some e) (str " :exit " (stringFromInt64 e)))
                     ((none) (str " :" (stripLeadingColons (optionOr (recStatus r) "ok")))))
        countPart (if (and (= op "observe") (hasDimCallersFrom out 0)) (countBlock out) "")
        excerptPart (digestExcerptPart r op)]
    (str idPart targetPart statusPart countPart excerptPart ")"))

fn sumLinePlus1 lines: (List String) -> Int64
  (fold (fn [acc l] (+ acc (+ (charLen l) 1))) 0 lines)

fn findDropStart lines: (List String) budget: Int64 total: Int64 start: Int64 -> Int64
  (if (and (< start (listLength lines)) (> total budget))
    (findDropStart lines budget (- total (+ (charLen (optionOr (listGet lines start) "")) 1)) (+ start 1))
    start)

fn evidenceDigest receipts: (List ReceiptRec) cap: Int64 -> String
  (let [lines (map digestLine receipts)
        budget (- cap 64)
        start (findDropStart lines budget (sumLinePlus1 lines) 0)
        kept (listDrop lines start)
        head (if (> start 0) (str "[" (stringFromInt64 start) " older receipt lines cut]\n") "")]
    (str head (stringJoin kept "\n")))

fn advisorGateOutput g: GateRec -> String
  (stringJoin (filter (fn [s] (not (stringEmpty? s))) (list (gStdout g) (gStderr g))) "\n")

fn opLineOp r: ReceiptRec -> String
  (mt (recOp r) ((some o) o) ((none) (if (and (some? (recCmd r)) (some? (recExit r))) "gate" (optionOr (recKind r) "?"))))

fn opLineTarget r: ReceiptRec -> String
  (optionOr (firstSomeStr (list (recFile r) (recCmd r) (recPath r) (recQuery r) (recSymbol r))) "")

fn opLineOutcome r: ReceiptRec -> String
  (let [base (mt (recExit r) ((some e) (str ":exit " (stringFromInt64 e))) ((none) (str ":" (optionOr (recStatus r) "ok"))))]
    (mt (recError r) ((some e) (str base " " e)) ((none) base)))

fn advisorOpLine r: ReceiptRec -> String
  (let [op (opLineOp r) target (charPrefix (opLineTarget r) 120) outcome (opLineOutcome r)]
    (stringJoin (filter (fn [s] (not (stringEmpty? s))) (list op target outcome)) " "))

fn lookupLastGate lastGates: (List (Pair String (Pair Int64 GateRec))) cmd: String -> (Option (Pair Int64 GateRec))
  (fold (fn [acc p] (mt acc ((some _) acc) ((none) (if (= (pairFirst p) cmd) (some (pairSecond p)) none)))) none lastGates)

fn advisorGateLine i: Int64 g: String lastGates: (List (Pair String (Pair Int64 GateRec))) -> String
  (let [seen (lookupLastGate lastGates g)
        exStr (mt seen ((some sp) (mt (gExit (pairSecond sp)) ((some e) (stringFromInt64 e)) ((none) "not run"))) ((none) "not run"))]
    (str (stringFromInt64 i) " " g " :exit " exStr))

fn isRedGate seen: (Option (Pair Int64 GateRec)) -> Bool
  (mt seen ((some sp) (mt (gExit (pairSecond sp)) ((some e) (!= e 0)) ((none) true))) ((none) false))

fn advisorRedFold acc: (Option (Pair Int64 GateRec)) g: String lastGates: (List (Pair String (Pair Int64 GateRec))) -> (Option (Pair Int64 GateRec))
  (let [seen (lookupLastGate lastGates g)]
    (if (isRedGate seen)
      (mt seen ((some sp) (mt acc ((none) (some sp)) ((some accSp) (if (>= (pairFirst sp) (pairFirst accSp)) (some sp) acc)))) ((none) acc))
      acc))

fn advisorRedTail rp: (Pair Int64 GateRec) -> String
  (let [g (pairSecond rp)
        allLines (pySplitLines (advisorGateOutput g))
        n (listLength allLines)
        kept (listDrop allLines (max 0 (- n 40)))
        truncatedLines (map (fn [l] (charPrefix l 200)) kept)
        body (charSuffix (stringJoin truncatedLines "\n") 3000)]
    (str "last red gate output (" (gCmd g) "), last " (stringFromInt64 (listLength truncatedLines)) " lines:\n" body "\n"))

; (:m :tags (reinforce advisor))
fn advisorSummary task: String deliver: String why: String gates: (List String)
                   lastGates: (List (Pair String (Pair Int64 GateRec))) written: (List String)
                   receipts: (List ReceiptRec) lastBrief: String -> String
  (let [indexedGates (enumerate gates)
        gateLines (map (fn [ig] (advisorGateLine (+ (pairFirst ig) 1) (pairSecond ig) lastGates)) indexedGates)
        redSel (fold (fn [acc ig] (advisorRedFold acc (pairSecond ig) lastGates)) none indexedGates)
        tail (mt redSel ((none) "") ((some rp) (advisorRedTail rp)))
        n (listLength receipts)
        lastOps (listDrop receipts (max 0 (- n 8)))
        opsText (stringJoin (map advisorOpLine lastOps) "\n")
        gatesText (let [t (stringJoin gateLines "\n")] (if (stringEmpty? t) "(none declared)" t))
        writtenText (charPrefix (if (listEmpty? written) "(none)" (stringJoin written " ")) 600)
        briefHead (if (stringContains? why "parse defect") (str "last retry brief head: " (charPrefix lastBrief 200) "\n") "")
        headStr (str "deliverable: " (if (stringEmpty? deliver) "not stated" deliver) "\n"
                     "stuck because: " why "\n" briefHead
                     "gates:\n" gatesText "\n" tail
                     "files written: " writtenText "\n"
                     "last ops, oldest first:\n" (if (stringEmpty? opsText) "(none)" opsText) "\n")
        room (max 0 (- (- 8000 (charLen headStr)) (charLen "task:\n\n")))
        full (str "task:\n" (charPrefix task room) "\n\n" headStr)]
    (charPrefix full 8000))
