(module aslGateway/learn
  :x [LearnedRow CapRow Refusals defaultLearnWindows defaultLearnRampPct learnWindowMs learnRows mergeLearned rampPass rampedLimits
      learnedLine learnedParse capLine capParse refusalsOf refusalLine learnedPath learnedCapsPath readLearned! writeLearned! readCaps! writeCaps!
      learnWindowsFromText learnRampFromText learnRampPctFromText rampedLimitsFor!]
  :i [(aslGateway/usageLedger :a ul)
      (aslGateway/limits :a lim)
      (aslGateway/config :a c)
      (aslGateway/usage :a g)
      (aslGateway/wire :a wire)
      (asl-parser/reader :a rd)])

; (:m :ref GW-LIMIT-LEARN :do "what the usage ledger shows a provider or one of its aliases reached per window (minute hour fiveHour day week, trailing, resolved to a quarter of the window): the most sent calls and tokens in any span with no upstream 429 inside it, and the fewest sent calls (429 call included) in the span that ended at an upstream 429; our own refusals (breaker, throttled, pace, limit) are no call and never lower a peak; alias empty is the whole provider")
(schema LearnedRow
  (:f provider String)
  (:f alias String)
  (:f window String)
  (:f peakCalls Int64)
  (:f peakTokens Int64)
  (:f first429Calls (Option Int64))
  (:f first429Tokens (Option Int64))
  (:f rows429 Int64)
  (:f seenMs Int64))

; (:m :ref GW-LIMIT-LEARN :do "a ramped call cap for the configured limit row of provider and alias (alias empty for an account row) in a window; it only ever sits above the configured value")
(schema CapRow
  (:f provider String)
  (:f alias String)
  (:f window String)
  (:f calls Int64))

; (:m :ref GW-LIMIT-LEARN :do "per provider, own refusals (rows that sent nothing: breaker, throttled, pace, limit, skipped, daily) against what the provider itself answered: ok, 429 and other failures")
(schema Refusals
  (:f provider String)
  (:f ok Int64)
  (:f own Int64)
  (:f up429 Int64)
  (:f upOther Int64))

(schema Tally
  (:f calls (Map String Int64))
  (:f tokens (Map String Int64))
  (:f bad (Map String Int64)))

fn defaultLearnWindows -> (List String)
  (list "minute" "hour" "fiveHour" "day" "week")

fn defaultLearnRampPct -> Int64
  25

fn learnWindowMs window: String -> Int64
  (cond
    ((= window "minute") 60000)
    ((= window "hour") 3600000)
    ((= window "fiveHour") 18000000)
    ((= window "day") 86400000)
    ((= window "week") 604800000)
    (else 0))

fn slotAt m: (Map String Int64) k: Int64 -> Int64
  (optionOr (mapGet m (stringFromInt64 k)) 0)

fn slotBump m: (Map String Int64) k: Int64 n: Int64 -> (Map String Int64)
  (mapSet m (stringFromInt64 k) (+ (slotAt m k) n))

fn spanSum m: (Map String Int64) k: Int64 -> Int64
  (+ (+ (slotAt m k) (slotAt m (- k 1))) (+ (slotAt m (- k 2)) (slotAt m (- k 3))))

fn tallyFor rows: (List ul/CallRow) quarterMs: Int64 -> Tally
  (fold (fn [(t Tally) (r ul/CallRow)] -> Tally
          (if (lim/sentRow? r)
            (let [(k (/ r.atMs quarterMs))]
              (Tally :calls (slotBump t.calls k 1)
                     :tokens (slotBump t.tokens k (+ r.inTokens r.outTokens))
                     :bad (if (= r.outcome "429") (slotBump t.bad k 1) t.bad)))
            t))
        (Tally :calls (mapEmpty) :tokens (mapEmpty) :bad (mapEmpty)) rows)

fn slotKeys m: (Map String Int64) -> (List Int64)
  (map (fn [(k String)] -> Int64 (optionOr (stringToInt64 k) 0)) (mapKeys m))

fn minOpt a: (Option Int64) b: Int64 -> (Option Int64)
  (match a ((some x) (some (min x b))) ((none) (some b)))

fn learnOne provider: String alias: String window: String rows: (List ul/CallRow) -> LearnedRow
  (let [(q (/ (learnWindowMs window) 4))
        (t (tallyFor rows q))
        (clean (filter (fn [(k Int64)] -> Bool (= (spanSum t.bad k) 0)) (slotKeys t.calls)))
        (hit (slotKeys t.bad))]
    (LearnedRow :provider provider :alias alias :window window
      :peakCalls (fold (fn [(m Int64) (k Int64)] -> Int64 (max m (spanSum t.calls k))) 0 clean)
      :peakTokens (fold (fn [(m Int64) (k Int64)] -> Int64 (max m (spanSum t.tokens k))) 0 clean)
      :first429Calls (fold (fn [(m (Option Int64)) (k Int64)] -> (Option Int64) (minOpt m (spanSum t.calls k))) none hit)
      :first429Tokens (fold (fn [(m (Option Int64)) (k Int64)] -> (Option Int64) (minOpt m (spanSum t.tokens k))) none hit)
      :rows429 (fold (fn [(n Int64) (k Int64)] -> Int64 (+ n (slotAt t.bad k))) 0 hit)
      :seenMs (fold (fn [(m Int64) (r ul/CallRow)] -> Int64 (max m r.atMs)) 0 rows)))

; (:m :ref GW-LIMIT-LEARN :do "learned rows from ledger rows: one per provider and window, and one per provider alias and window, for the windows given; a group with no sent call yields none")
fn learnGroup rs: (List ul/CallRow) windows: (List String) byAlias: Bool -> (List LearnedRow)
  (if (listEmpty? (filter lim/sentRow? rs))
    (list)
    (match (listHead rs)
      ((none) (list))
      ((some first) (map (fn [(w String)] -> LearnedRow (learnOne first.provider (if byAlias first.alias "") w rs)) windows))))

fn learnGroups groups: (Map String (List ul/CallRow)) windows: (List String) byAlias: Bool -> (List LearnedRow)
  (listFlatMap (fn [(k String)] -> (List LearnedRow) (learnGroup (optionOr (mapGet groups k) (list)) windows byAlias)) (mapKeys groups))

fn learnRows rows: (List ul/CallRow) windows: (List String) -> (List LearnedRow)
  (listAppend (learnGroups (groupBy rows (fn [(r ul/CallRow)] -> String r.provider)) windows false)
              (learnGroups (groupBy rows (fn [(r ul/CallRow)] -> String (str r.provider "\n" r.alias))) windows true))

fn sameKey a: LearnedRow b: LearnedRow -> Bool
  (and (= a.provider b.provider) (and (= a.alias b.alias) (= a.window b.window)))

fn minOptOpt a: (Option Int64) b: (Option Int64) -> (Option Int64)
  (match a ((none) b) ((some x) (match b ((none) a) ((some y) (some (min x y))))))

fn mergeTwo a: LearnedRow b: LearnedRow -> LearnedRow
  (LearnedRow :provider a.provider :alias a.alias :window a.window
    :peakCalls (max a.peakCalls b.peakCalls) :peakTokens (max a.peakTokens b.peakTokens)
    :first429Calls (minOptOpt a.first429Calls b.first429Calls) :first429Tokens (minOptOpt a.first429Tokens b.first429Tokens)
    :rows429 (max a.rows429 b.rows429) :seenMs (max a.seenMs b.seenMs))

; (:m :ref GW-LIMIT-LEARN :do "stored rows folded with fresh ones, repeatable on the same ledger: peaks and the 429 count take the larger, the count at the first 429 the smaller, so a second pass over the same rows changes nothing and a lower fresh peak never erases a higher stored one")
fn mergeLearned stored: (List LearnedRow) fresh: (List LearnedRow) -> (List LearnedRow)
  (let [(kept (map (fn [(s LearnedRow)] -> LearnedRow
                     (fold (fn [(acc LearnedRow) (f LearnedRow)] -> LearnedRow (if (sameKey acc f) (mergeTwo acc f) acc)) s fresh))
                   stored))
        (added (filter (fn [(f LearnedRow)] -> Bool (not (listAny? (fn [(s LearnedRow)] -> Bool (sameKey s f)) stored))) fresh))]
    (listAppend kept added))

fn capKeyOf l: c/GatewayLimit -> (Option (Pair String String))
  (cond
    ((= l.scope "account") (some (pair l.provider "")))
    ((= l.scope "model") (some (pair l.provider l.model)))
    (else none))

fn learnedFor learned: (List LearnedRow) provider: String alias: String window: String -> (Option LearnedRow)
  (listHead (filter (fn [(r LearnedRow)] -> Bool (and (= r.provider provider) (and (= r.alias alias) (= r.window window)))) learned))

fn capFor caps: (List CapRow) provider: String alias: String window: String -> Int64
  (fold (fn [(m Int64) (r CapRow)] -> Int64 (if (and (= r.provider provider) (and (= r.alias alias) (= r.window window))) (max m r.calls) m)) 0 caps)

; (:m :ref GW-LIMIT-LEARN :do "one ramp step per call: a configured call cap (account or model scope, a learned window) whose current cap the provider has been driven up to with no upstream 429 ever seen in that window rises by pct percent (at least 1); a cap never falls, a 429 or a peak under the cap stops the ramp, and our own refusals count for nothing")
fn rampPass limits: (List c/GatewayLimit) learned: (List LearnedRow) caps: (List CapRow) pct: Int64 -> (List CapRow)
  (listFlatMap (fn [(l c/GatewayLimit)] -> (List CapRow)
                 (match (capKeyOf l)
                   ((none) (list))
                   ((some k)
                     (let [(cur (max l.calls (capFor caps (pairFirst k) (pairSecond k) l.window)))
                           (next (+ cur (max 1 (/ (* cur pct) 100))))
                           (row (learnedFor learned (pairFirst k) (pairSecond k) l.window))
                           (rise (and (> l.calls 0)
                                      (match row
                                        ((some r) (and (none? r.first429Calls) (>= r.peakCalls cur)))
                                        ((none) false)))
                           )]
                       (if (> (if rise next cur) l.calls)
                         (list (CapRow :provider (pairFirst k) :alias (pairSecond k) :window l.window :calls (if rise next cur)))
                         (list))))))
               limits)

; (:m :ref GW-LIMIT-LEARN :do "the limit rows with each ramped call cap swapped in where one matches provider, alias and window; a cap below the configured value is ignored")
fn rampedLimits limits: (List c/GatewayLimit) caps: (List CapRow) -> (List c/GatewayLimit)
  (map (fn [(l c/GatewayLimit)] -> c/GatewayLimit
         (match (capKeyOf l)
           ((none) l)
           ((some k) (with l :calls (max l.calls (capFor caps (pairFirst k) (pairSecond k) l.window))))))
       limits)

fn optIntAsn name: String v: (Option Int64) -> String
  (match v ((some n) (str " :" name " " (stringFromInt64 n))) ((none) ""))

fn learnedLine r: LearnedRow -> String
  (str "(:learned :provider \"" (wire/asnEscape r.provider) "\" :alias \"" (wire/asnEscape r.alias) "\" :window \"" r.window "\" :peakCalls " (stringFromInt64 r.peakCalls)
       " :peakTokens " (stringFromInt64 r.peakTokens) (optIntAsn "first429Calls" r.first429Calls) (optIntAsn "first429Tokens" r.first429Tokens)
       " :rows429 " (stringFromInt64 r.rows429) " :seenMs " (stringFromInt64 r.seenMs) ")")

fn capLine r: CapRow -> String
  (str "(:cap :provider \"" (wire/asnEscape r.provider) "\" :alias \"" (wire/asnEscape r.alias) "\" :window \"" r.window "\" :calls " (stringFromInt64 r.calls) ")")

fn propInt props: (Map String rd/SExpr) key: String -> (Option Int64)
  (match (mapGet props key)
    ((none) none)
    ((some e) (match (c/asnScalar e) ((c/scalarInt n) (some n)) (_ none)))) 

fn propStr props: (Map String rd/SExpr) key: String -> (Option String)
  (match (mapGet props key)
    ((none) none)
    ((some e) (match (c/asnScalar e) ((c/scalarStr s) (some s)) (_ none))))

fn learnedParse line: String -> (Result LearnedRow String)
  (match (c/asnProps (rd/parseSexpr (stringTrim line)) (some ":learned"))
    ((err e) (err (str "corrupt learned row: " e)))
    ((ok p)
      (match (propStr p "provider")
        ((none) (err (str "corrupt learned row: no provider in " line)))
        ((some provider)
          (match (propStr p "window")
            ((none) (err (str "corrupt learned row: no window in " line)))
            ((some window)
              (match (propInt p "peakCalls")
                ((none) (err (str "corrupt learned row: no peakCalls in " line)))
                ((some peak)
                  (ok (LearnedRow :provider provider :alias (optionOr (propStr p "alias") "") :window window :peakCalls peak
                        :peakTokens (optionOr (propInt p "peakTokens") 0) :first429Calls (propInt p "first429Calls")
                        :first429Tokens (propInt p "first429Tokens") :rows429 (optionOr (propInt p "rows429") 0)
                        :seenMs (optionOr (propInt p "seenMs") 0)))))))))))

fn capParse line: String -> (Result CapRow String)
  (match (c/asnProps (rd/parseSexpr (stringTrim line)) (some ":cap"))
    ((err e) (err (str "corrupt cap row: " e)))
    ((ok p)
      (match (propStr p "provider")
        ((none) (err (str "corrupt cap row: no provider in " line)))
        ((some provider)
          (match (propStr p "window")
            ((none) (err (str "corrupt cap row: no window in " line)))
            ((some window)
              (match (propInt p "calls")
                ((none) (err (str "corrupt cap row: no calls in " line)))
                ((some n) (ok (CapRow :provider provider :alias (optionOr (propStr p "alias") "") :window window :calls n))))))))))

; (:m :ref GW-LIMIT-LEARN :do "own refusals against what the provider itself answered, per provider, from ledger rows: a row that sent nothing is ours, a sent row is ok, a 429 or another failure")
fn refusalsOf rows: (List ul/CallRow) -> (List Refusals)
  (let [(byProvider (groupBy rows (fn [(r ul/CallRow)] -> String r.provider)))]
    (map (fn [(p String)] -> Refusals
           (let [(rs (optionOr (mapGet byProvider p) (list)))
                 (sent (filter lim/sentRow? rs))]
             (Refusals :provider p
               :ok (listLength (filter (fn [(r ul/CallRow)] -> Bool (= r.outcome "ok")) sent))
               :own (- (listLength rs) (listLength sent))
               :up429 (listLength (filter (fn [(r ul/CallRow)] -> Bool (= r.outcome "429")) sent))
               :upOther (listLength (filter (fn [(r ul/CallRow)] -> Bool (and (!= r.outcome "ok") (!= r.outcome "429"))) sent)))))
         (mapKeys byProvider)))

fn refusalLine r: Refusals -> String
  (str "(:refusals :provider \"" (wire/asnEscape r.provider) "\" :ok " (stringFromInt64 r.ok) " :own " (stringFromInt64 r.own)
       " :up429 " (stringFromInt64 r.up429) " :upOther " (stringFromInt64 r.upOther) ")")

fn learnedPath home: String -> String
  (g/posixJoin home ".asl/run/usage/learned.asn")

fn learnedCapsPath home: String -> String
  (g/posixJoin home ".asl/run/usage/learnedCaps.asn")

fn nonEmpty text: String -> (List String)
  (filter (fn [(s String)] -> Bool (not (stringEmpty? (stringTrim s)))) (stringSplit text "\n"))

fn ! readLearned! path: String -> (Result (List LearnedRow) String)
  (if (not (fileExists? path))
    (ok (list))
    (match (fileReadString path)
      ((err e) (err (str "read " path ": " e)))
      ((ok text) (learnedAll (nonEmpty text) (list))))) 

fn ! readCaps! path: String -> (Result (List CapRow) String)
  (if (not (fileExists? path))
    (ok (list))
    (match (fileReadString path)
      ((err e) (err (str "read " path ": " e)))
      ((ok text) (capsAll (nonEmpty text) (list))))) 

fn ! replaceFile! path: String text: String -> (Result Bool String)
  (match (dirCreate (g/posixDirname path))
    ((err e) (err (str "dir for " path ": " e)))
    ((ok _)
      (let [(tmp (str path ".tmp"))]
        (match (fileWrite tmp text)
          ((err e) (err (str "write " tmp ": " e)))
          ((ok _) (match (pathRename tmp path) ((err e) (err (str "rename " tmp ": " e))) ((ok _) (ok true))))))))

fn ! writeLearned! path: String rows: (List LearnedRow) -> (Result Bool String)
  (replaceFile! path (str (stringJoin (map learnedLine rows) "\n") "\n"))

fn ! writeCaps! path: String rows: (List CapRow) -> (Result Bool String)
  (replaceFile! path (str (stringJoin (map capLine rows) "\n") "\n"))

; (:m :ref GW-LIMIT-LEARN :do "(:gateway ... :learnWindows \"minute hour fiveHour day week\") names the windows a learn pass tracks; an unknown name is dropped, none left means all five")
fn learnWindowsFromText text: String -> (List String)
  (match (c/gatewayTopScalarOverride text "learnWindows")
    ((some (c/scalarStr s))
      (let [(named (filter (fn [(w String)] -> Bool (> (learnWindowMs w) 0)) (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit s " "))))]
        (if (listEmpty? named) (defaultLearnWindows) named)))
    (_ (defaultLearnWindows)))

; (:m :ref GW-LIMIT-LEARN :do "(:gateway ... :learnRamp true) lets the gateway use the ramped call caps a learn pass stored; off by default, so the configured caps stay the only ones until it is switched on")
fn learnRampFromText text: String -> Bool
  (match (c/gatewayTopScalarOverride text "learnRamp")
    ((some (c/scalarBool b)) b)
    (_ false))

fn learnRampPctFromText text: String -> Int64
  (match (c/gatewayTopIntOverride text "learnRampPct")
    ((some n) (if (and (>= n 5) (<= n 100)) n (defaultLearnRampPct)))
    ((none) (defaultLearnRampPct)))

; (:m :ref GW-LIMIT-LEARN :do "the limit rows a call is judged against: the configured ones, or with :learnRamp true those with the stored ramped call caps swapped in; an unreadable caps file leaves the configured rows")
fn ! rampedLimitsFor! home: String text: String limits: (List c/GatewayLimit) -> (List c/GatewayLimit)
  (if (not (learnRampFromText text))
    limits
    (match (readCaps! (learnedCapsPath home))
      ((ok caps) (rampedLimits limits caps))
      ((err _) limits))) 

fn learnedAll lines: (List String) acc: (List LearnedRow) -> (Result (List LearnedRow) String)
  (match (listHead lines)
    ((none) (ok (listReverse acc)))
    ((some l)
      (match (learnedParse l)
        ((err e) (err e))
        ((ok row) (learnedAll (optionOr (listTail lines) (list)) (cons row acc)))))) 

fn capsAll lines: (List String) acc: (List CapRow) -> (Result (List CapRow) String)
  (match (listHead lines)
    ((none) (ok (listReverse acc)))
    ((some l)
      (match (capParse l)
        ((err e) (err e))
        ((ok row) (capsAll (optionOr (listTail lines) (list)) (cons row acc)))))) 

fn groupBy rows: (List ul/CallRow) keyFn: (fn [ul/CallRow] -> String) -> (Map String (List ul/CallRow))
  (fold (fn [(m (Map String (List ul/CallRow))) (r ul/CallRow)] -> (Map String (List ul/CallRow))
          (let [(k (keyFn r))] (mapSet m k (cons r (optionOr (mapGet m k) (list))))))
        (mapEmpty) rows)
