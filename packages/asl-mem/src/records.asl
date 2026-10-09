(module aslMem/records :x [ShortcodeType Shortcode AdrRule RecordsLedger ScanResult makeShortcode makeRule makeLedger makeScanResult shortcodeTypeToString stringToShortcodeType isValidShortcode? normalizeShortcode scanShortcodes findRule queryRule isInvariantRule? checkInvariants verifyModule LifecycleKind ClosureCondition LifecycleRecord makeClosureCondition makeLifecycleRecord lifecycleKindToString stringToLifecycleKind validateClosureCondition isClosureEvaluable? refuseUnevaluableClosure closeGoalByEvaluation evaluateClosure])

(enum ShortcodeType (:c pDec [] "Architectural Decision Record (e.g., d-xxxx)") (:c pCrit [] "Architecture Critic Rule (e.g., c-xxxx)") (:c pLaw [] "System Invariant or Non-negotiable Law (e.g., l-xxxx)") (:c pReq [] "Functional or Architectural Requirement (e.g., r-xxxx)"))

(schema Shortcode (:f kind ShortcodeType) (:f code Str))

(schema AdrRule (:f code Str) (:f title Str) (:f why Str) (:f basis Str) (:f status Str))

(schema RecordsLedger (:f rules (List AdrRule)) (:f shortcodes (List Str)))

(schema ScanResult (:f module Str) (:f referenced (List Str)) (:f missing (List Str)))

fn makeShortcode kind: ShortcodeType code: Str -> Shortcode
  (Shortcode :kind kind :code code)

fn makeRule code: Str title: Str why: Str basis: Str status: Str -> AdrRule
  (AdrRule :code code :title title :why why :basis basis :status status)

fn makeLedger rules: (List AdrRule) shortcodes: (List Str) -> RecordsLedger
  (RecordsLedger :rules rules :shortcodes shortcodes)

fn makeScanResult modName: Str referenced: (List Str) missing: (List Str) -> ScanResult
  (ScanResult :module modName :referenced referenced :missing missing)

fn shortcodeTypeToString st: ShortcodeType -> Str
  (mt st ((pDec) "d") ((pCrit) "c") ((pLaw) "l") ((pReq) "r"))

fn stringToShortcodeType prefix: Str -> (Option ShortcodeType)
  (cond ((= prefix "d") (some (pDec))) ((= prefix "c") (some (pCrit))) ((= prefix "l") (some (pLaw))) ((= prefix "r") (some (pReq))) ((= prefix "p-dec") (some (pDec))) ((= prefix "p-crit") (some (pCrit))) ((= prefix "p-law") (some (pLaw))) ((= prefix "p-req") (some (pReq))) (else (none)))

fn isHexDigit? c: Str -> Bool
  (if (stringEmpty? c) false (if (> (stringLength c) 1) false (stringContains? "0123456789abcdefABCDEF" c)))

fn checkHexStep ok: Bool ch: Str -> Bool
  (if ok (isHexDigit? ch) false)

fn isValidHex4? hex: Str -> Bool
  (if (= (stringLength hex) 4) (fold checkHexStep true (stringChars hex)) false)

fn isValidShortcode? code: Str -> Bool
  (if (= (stringLength code) 6) (mt (stringSlice code 0 1) ((none) false) ((some pre) (mt (stringSlice code 1 2) ((none) false) ((some hyp) (mt (stringSlice code 2 6) ((none) false) ((some hexPart) (and (stringContains? "dclr" pre) (and (= hyp "-") (isValidHex4? hexPart))))))))) false)

fn normalizeShortcode raw: Str -> Str
  (let [(trimmed (stringTrim raw))] (if (stringStartsWith? trimmed "@adr:") (optionOr (stringSlice trimmed 5 (stringLength trimmed)) "") (if (stringStartsWith? trimmed "@rule:") (optionOr (stringSlice trimmed 6 (stringLength trimmed)) "") (if (stringStartsWith? trimmed "@pcp:") (optionOr (stringSlice trimmed 5 (stringLength trimmed)) "") (if (stringStartsWith? trimmed "@") (optionOr (stringSlice trimmed 1 (stringLength trimmed)) "") trimmed)))))

fn replaceDelimChar ch: Str -> Str
  (if (stringContains? " \t\n\r,;:()[]{}\"'" ch) " " ch)

fn sanitizeDelimiters raw: Str -> Str
  (stringJoin (map replaceDelimChar (stringChars raw)) "")

fn isNonEmptyTok? t: Str -> Bool
  (not (stringEmpty? (stringTrim t)))

fn extractTokenShortcode tok: Str -> (Option Str)
  (let [(norm (normalizeShortcode tok))] (if (isValidShortcode? norm) (some norm) (none)))

fn scanShortcodes text: Str -> (List Str)
  (let [(sanitized (sanitizeDelimiters text)) (tokens (filter isNonEmptyTok? (stringSplit sanitized " ")))] (fold (fn [(acc (List Str)) (tok Str)] -> (List Str) (mt (extractTokenShortcode tok) ((some sc) (if (listContains? acc sc) acc (listAppend acc (list sc)))) ((none) acc))) (list) tokens))

fn tailRules rules: (List AdrRule) -> (List AdrRule)
  (mt (listTail rules) ((some tl) tl) ((none) (list)))

fn headRuleOrDefault rules: (List AdrRule) -> AdrRule
  (mt (listHead rules) ((some h) h) ((none) (makeRule "" "" "" "" "")))

fn findRule rules: (List AdrRule) target: Str -> (Option AdrRule)
  (if (listEmpty? rules) (none) (let [(r (headRuleOrDefault rules))] (if (= r.code target) (some r) (findRule (tailRules rules) target))))

fn queryRule ledger: RecordsLedger code: Str -> (Option AdrRule)
  (let [(norm (normalizeShortcode code))] (findRule ledger.rules norm))

fn isInvariantRule? r: AdrRule -> Bool
  (and (= r.status "active") (stringStartsWith? r.code "l-"))

fn findMissingInvariants rules: (List AdrRule) active: (List Str) -> (List Str)
  (fold (fn [(acc (List Str)) (r AdrRule)] -> (List Str) (if (isInvariantRule? r) (let [(c r.code)] (if (listContains? active c) acc (listAppend acc (list c)))) acc)) (list) rules)

fn findUnregisteredRefs ledger: RecordsLedger refs: (List Str) -> (List Str)
  (fold (fn [(acc (List Str)) (code Str)] -> (List Str) (if (listContains? ledger.shortcodes code) acc (if (listContains? acc code) acc (listAppend acc (list code))))) (list) refs)

fn checkInvariants ledger: RecordsLedger active: (List Str) -> (List Str)
  (findMissingInvariants ledger.rules active)

fn verifyModule ledger: RecordsLedger modName: Str sourceText: Str -> ScanResult
  (let [(refs (scanShortcodes sourceText)) (missing (findMissingInvariants ledger.rules refs)) (unreg (findUnregisteredRefs ledger refs)) (allMissing (fold (fn [(acc (List Str)) (u Str)] -> (List Str) (if (listContains? acc u) acc (listAppend acc (list u)))) missing unreg))] (makeScanResult modName refs allMissing))

(enum LifecycleKind (:c lkIntent [] "intent lifecycle kind: why work is done; closes when reason no longer holds") (:c lkGoal [] "goal lifecycle kind: what done looks like; closes when observable predicate evaluates to true") (:c lkPractice [] "practice lifecycle kind: how work is done; closes when contradictory measurement emerges"))

(schema ClosureCondition (:f kind Str) (:f predicate Str) (:f observable Str) (:f evaluable Bool))

(schema LifecycleRecord (:f id Str) (:f kind Str) (:f title Str) (:f description Str) (:f closure ClosureCondition) (:f status Str))

fn makeClosureCondition kind: Str predicate: Str observable: Str evaluable: Bool -> ClosureCondition
  (ClosureCondition :kind kind :predicate predicate :observable observable :evaluable evaluable)

fn makeLifecycleRecord id: Str kind: Str title: Str desc: Str closure: ClosureCondition status: Str -> LifecycleRecord
  (LifecycleRecord :id id :kind kind :title title :description desc :closure closure :status status)

fn lifecycleKindToString k: LifecycleKind -> Str
  (mt k ((lkIntent) "intent") ((lkGoal) "goal") ((lkPractice) "practice"))

fn stringToLifecycleKind s: Str -> (Option LifecycleKind)
  (cond ((= s "intent") (some (lkIntent))) ((= s "goal") (some (lkGoal))) ((= s "practice") (some (lkPractice))) (else (none)))

fn isClosureEvaluable? cond: ClosureCondition -> Bool
  (if (not cond.evaluable) false (let [(p (stringTrim cond.predicate)) (obs (stringTrim cond.observable))] (if (or (stringEmpty? p) (stringEmpty? obs)) false (if (or (stringContains? p "unevaluable") (stringContains? obs "unevaluable")) false true))))

fn validateClosureCondition cond: ClosureCondition -> Bool
  (and (not (stringEmpty? (stringTrim cond.kind))) (isClosureEvaluable? cond))

fn refuseUnevaluableClosure reason: Str -> Str
  (str "refused: unevaluable closure condition: " reason)

fn closeGoalByEvaluation rec: LifecycleRecord observableSatisfied: Bool -> LifecycleRecord
  (if (not (= rec.kind "goal")) rec (if (not (isClosureEvaluable? rec.closure)) rec (if observableSatisfied (with rec :status "fulfilled") rec)))

fn evaluateClosure rec: LifecycleRecord observableSatisfied: Bool -> LifecycleRecord
  (let [(c rec.closure)] (if (not (isClosureEvaluable? c)) rec (if observableSatisfied (let [(newStatus (if (= rec.kind "goal") "fulfilled" (if (= rec.kind "intent") "closed" "retired")))] (with rec :closure c :status newStatus)) rec)))
