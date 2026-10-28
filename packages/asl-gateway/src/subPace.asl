(module aslGateway/subPace
  :x [PaceWin SubPace parseStampMs noData kindOf tokAfter quotedAfter parseTimeMs fixed1 groupsOf windowsSegment subLines subId windowsOf ledgerUse subProviders rollReset providerSub subCapacity paceSubs
      factorsFromPaces adjustSpread statusLine providerOf paceCacheKey paceCacheFresh? paceCacheMs
      winFactor staleAfterMs hardPoints softPoints]
  :i [(localTime :a lt)])

; (:m :ref SUBPACE :do "pure pacing core: subscriptions text + ledger text + now give, per subscription, the used percent of its most binding window against an even pace to its reset, with a soft and a hard limit; no model call, no clock, no file here")

(schema PaceWin
  (:f kind String)
  (:f lenMs Int64)
  (:f resetsMs Int64)
  (:f used Float64)
  (:f src String)
  (:f atMs Int64))

(schema SubPace
  (:f id String)
  (:f window String)
  (:f used Float64)
  (:f known Bool)
  (:f allowance Float64)
  (:f pace Float64)
  (:f factor Float64)
  (:f src String)
  (:f atMs Int64)
  (:f stale Bool)
  (:f expired Bool)
  (:f over Bool)
  (:f hard Bool)
  (:f calls Int64)
  (:f tokens Int64))

; (:m :do "adopted pacing limits in percentage points over the even pace: over softPoints the weight falls linearly, at hardPoints or at 95 percent used the subscription drops out of the spread")
fn softPoints -> Float64
  5.0

fn hardPoints -> Float64
  20.0

; (:m :do "adopted: a window figure older than this is stale; entered-by-hand figures keep two days, api and event figures six hours, a ledger estimate is always fresh")
fn staleAfterMs src: String -> Int64
  (cond
    ((= src "ledger") 0)
    ((= src "principal") 172800000)
    (else 21600000))

fn paceCacheKey -> String
  "~subPace"

fn paceCacheMs -> Int64
  60000

fn fmin a: Float64 b: Float64 -> Float64
  (if (< a b) a b)

fn fmax a: Float64 b: Float64 -> Float64
  (if (> a b) a b)

fn toInt f: Float64 -> Int64
  (optionOr (float64ToInt64 (round f)) 0)

fn chAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

; (:m :do "a number with one decimal for status rows")
fn fixed1 f: Float64 -> String
  (let [(tenths (toInt (* f 10.0)))
        (neg (< tenths 0))
        (a (if neg (- 0 tenths) tenths))]
    (str (if neg "-" "") (stringFromInt64 (/ a 10)) "." (stringFromInt64 (mod a 10))))

; (:m :do "UTC epoch ms of 2026-11-13, 2026-11-22 18:00 or 2026-11-13T19:46:51.000Z; 0 when the text is not a date. Hand-entered local dates read as UTC, an error of hours on windows of days")
fn parseTimeMs text: String -> Int64
  (let [(t (stringTrim text))
        (norm (stringReplace t "T" " "))
        (parts (stringSplit norm " "))
        (dparts (stringSplit (optionOr (listHead parts) "") "-"))
        (y (stringToInt64 (optionOr (listGet dparts 0) "")))
        (m (stringToInt64 (optionOr (listGet dparts 1) "")))
        (d (stringToInt64 (optionOr (listGet dparts 2) "")))
        (clock (stringSplit (optionOr (listGet parts 1) "00:00:00") ":"))
        (hh (optionOr (stringToInt64 (optionOr (listGet clock 0) "0")) 0))
        (mm (optionOr (stringToInt64 (optionOr (listGet clock 1) "0")) 0))
        (ss (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (listGet clock 2) "0") ".")) "0")) 0))]
    (match y
      ((none) 0)
      ((some yy)
        (match m
          ((none) 0)
          ((some mo)
            (match d
              ((none) 0)
              ((some dd) (+ (* (lt/daysFromCivil yy mo dd) 86400000) (* hh 3600000) (* mm 60000) (* ss 1000)))))))))

; (:m :do "the top-level parenthesised groups of a text, each as its own text; quotes are honoured so a paren inside a string does not count")
fn groupsScan s: String i: Int64 n: Int64 depth: Int64 start: Int64 inq: Bool acc: (List String) -> (List String)
  (if (>= i n) (listReverse acc)
    (let [(c (chAt s i))]
      (cond
        (inq (cond ((= c "\\") (groupsScan s (+ i 2) n depth start true acc))
                   ((= c "\"") (groupsScan s (+ i 1) n depth start false acc))
                   (else (groupsScan s (+ i 1) n depth start true acc))))
        ((= c "\"") (groupsScan s (+ i 1) n depth start true acc))
        ((= c "(") (groupsScan s (+ i 1) n (+ depth 1) (if (= depth 0) i start) false acc))
        ((= c ")") (if (= depth 1)
                     (groupsScan s (+ i 1) n 0 start false (cons (optionOr (stringSlice s start (+ i 1)) "") acc))
                     (groupsScan s (+ i 1) n (max 0 (- depth 1)) start false acc)))
        (else (groupsScan s (+ i 1) n depth start false acc)))))

fn groupsOf s: String -> (List String)
  (groupsScan s 0 (stringLength s) 0 0 false (list))

; (:m :do "the text of the (...) after :windows in a sub line, or empty")
fn windowsSegment line: String -> String
  (match (stringIndexOf line ":windows (")
    ((none) "")
    ((some i)
      (let [(rest (optionOr (stringSlice line (+ i 9) (stringLength line)) ""))]
        (optionOr (listHead (groupsOf rest)) ""))))

fn subLines text: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringContains? l "(:sub :id ")) (stringSplit text "\n"))

fn tokAfter s: String key: String -> String
  (match (stringIndexOf s (str key " "))
    ((none) "")
    ((some i)
      (let [(rest (optionOr (stringSlice s (+ i (stringLength key) 1) (stringLength s)) ""))]
        (stringReplace (optionOr (listHead (stringSplit rest " ")) "") ")" ""))))

fn quotedAfter s: String key: String -> String
  (match (stringIndexOf s (str key " \""))
    ((none) "")
    ((some i)
      (optionOr (listHead (stringSplit (optionOr (stringSlice s (+ i (stringLength key) 2) (stringLength s)) "") "\"")) "")))

fn subId line: String -> String
  (tokAfter line ":id")

fn floatTok s: String key: String d: Float64 -> Float64
  (optionOr (stringToFloat64 (tokAfter s key)) d)

; (:m :ref SUBPACE :do "a stamp read at its own offset: Z or +hh:mm says it, a stamp with none is hand-entered local time and is read in the given zone, so a reset is the right instant on a machine that is not on UTC")
fn parseStampMs z: lt/Zone text: String -> Int64
  (let [(t (stringTrim text))
        (n (stringLength t))
        (tail (if (>= n 6) (optionOr (stringSlice t (- n 6) n) "") ""))
        (signCh (optionOr (stringSlice tail 0 1) ""))
        (hasOff (and (or (= signCh "+") (= signCh "-")) (= (optionOr (stringSlice tail 3 4) "") ":") (stringContains? t ":") (> n 10)))
        (base (if hasOff (optionOr (stringSlice t 0 (- n 6)) t) t))
        (asIf (parseTimeMs base))]
    (cond
      ((= asIf 0) 0)
      (hasOff (let [(mins (+ (* 60 (optionOr (stringToInt64 (optionOr (stringSlice tail 1 3) "0")) 0)) (optionOr (stringToInt64 (optionOr (stringSlice tail 4 6) "0")) 0)))]
                (- asIf (* (if (= signCh "-") -1 1) mins 60000))))
      ((stringEndsWith? t "Z") asIf)
      (else (let [(off1 (lt/localOffset z (/ asIf 1000)))
                  (off2 (lt/localOffset z (/ (- asIf (* off1 1000)) 1000)))]
              (- asIf (* off2 1000))))))

; (:m :do "a time field written either as epoch ms or as a quoted date")
fn timeField z: lt/Zone s: String key: String -> Int64
  (let [(q (quotedAfter s key))]
    (if (stringEmpty? q)
      (optionOr (stringToInt64 (tokAfter s key)) 0)
      (parseStampMs z q)))

fn kindOf g: String -> String
  (let [(body (optionOr (stringSlice g 2 (stringLength g)) ""))]
    (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit body " ")) "") ")")) ""))

fn lenOf kind: String g: String -> Int64
  (cond
    ((= kind "rolling")
      (let [(t (tokAfter g "rolling"))
            (num (optionOr (stringToInt64 (stringReplace (stringReplace t "h" "") "d" "")) 5))]
        (if (stringEndsWith? t "d") (* num 86400000) (* num 3600000))))
    ((= kind "weekly") 604800000)
    ((= kind "daily") 86400000)
    ((or (= kind "primary") (= kind "secondary"))
      (* (optionOr (stringToInt64 (tokAfter g ":minutes")) 43200) 60000))
    (else 2592000000))

fn winOf z: lt/Zone g: String fileAtMs: Int64 subSrc: String -> PaceWin
  (let [(kind (kindOf g))
        (src (let [(s (tokAfter g ":src"))] (if (stringEmpty? s) subSrc s)))
        (at (let [(a (timeField z g ":at"))] (if (= a 0) fileAtMs a)))]
    (PaceWin :kind kind :lenMs (lenOf kind g) :resetsMs (timeField z g ":resets") :used (floatTok g ":usedPercent" 0.0) :src src :atMs at))

fn firstWord s: String -> String
  (optionOr (listHead (stringSplit (stringTrim s) " ")) "")

; (:m :do "the windows of one sub line; a window without its own :src takes the first word of the sub's :src, one without :at takes the file's :updated date")
fn windowsOf z: lt/Zone line: String fileAtMs: Int64 -> (List PaceWin)
  (let [(subSrcQ (quotedAfter line ":src"))
        (subSrc (if (stringEmpty? subSrcQ) (tokAfter line ":src") (firstWord subSrcQ)))]
    (map (fn [(g String)] -> PaceWin (winOf z g fileAtMs subSrc)) (groupsOf (let [(seg (windowsSegment line))] (optionOr (stringSlice seg 1 (- (stringLength seg) 1)) "")))))

; (:m :do "gateway provider id to the subscription id it draws on; a provider with no entry is its own subscription id")
fn providerSub provider: String -> String
  (cond
    ((= provider "codex") "codexLuna")
    ((= provider "claude") "claudeCodeMax")
    ((= provider "anthropic") "claudeCodeMax")
    ((= provider "agy") "agyGoogle")
    ((= provider "gemini-cli") "agyGoogle")
    (else provider))

; (:m :do "requests per month of a subscription with no usage endpoint: its :capacity field, else 0, which means unknown: no percent is shown and no ledger estimate is made")
fn subCapacity line: String id: String -> Float64
  (let [(c (floatTok line ":capacity" 0.0))]
    (if (> c 0.0) c 0.0))

; (:m :do "calls and in+out tokens the ledger text holds for the providers of a subscription since startMs; a line scan, no row parse, so a 10MB ledger costs one pass")
fn subProviders id: String -> (List String)
  (cond
    ((= id "codexLuna") (list "codexLuna" "codex"))
    ((= id "claudeCodeMax") (list "claudeCodeMax" "claude" "anthropic"))
    ((= id "agyGoogle") (list "agyGoogle" "agy" "gemini-cli"))
    (else (list id)))

fn ledgerUse ledgerText: String id: String startMs: Int64 -> (Pair Int64 Int64)
  (let [(needles (map (fn [(p String)] -> String (str ":provider \"" p "\"")) (subProviders id)))
        (lines (filter (fn [(l String)] -> Bool (listAny? (fn [(n String)] -> Bool (stringContains? l n)) needles)) (stringSplit ledgerText "\n")))
        (mine (filter (fn [(l String)] -> Bool (>= (optionOr (stringToInt64 (tokAfter l ":at")) 0) startMs)) lines))]
    (pair (listLength mine)
          (fold (fn [(acc Int64) (l String)] -> Int64
                  (+ acc (optionOr (stringToInt64 (tokAfter l ":in")) 0) (optionOr (stringToInt64 (tokAfter l ":out")) 0)))
                0 mine)))

; (:m :do "the next reset at or after nowMs: a reset in the past rolls forward by whole windows, which is how a passed reset recovers")
fn rollReset resetsMs: Int64 lenMs: Int64 nowMs: Int64 -> Int64
  (if (or (<= resetsMs 0) (<= lenMs 0) (> resetsMs nowMs)) resetsMs
    (+ resetsMs (* (+ (/ (- nowMs resetsMs) lenMs) 1) lenMs)))

; (:m :do "weight factor in 0..1.5 from used percent against the allowance: 1 within softPoints over, linear to 0.2 at hardPoints, 0 at hardPoints over or 95 percent used, up to 1.5 when well under pace")
fn winFactor used: Float64 allowance: Float64 -> Float64
  (let [(over (- used allowance))]
    (cond
      ((>= used 95.0) 0.0)
      ((>= over (hardPoints)) 0.0)
      ((> over (softPoints)) (- 1.0 (* 0.8 (/ (- over (softPoints)) (- (hardPoints) (softPoints))))))
      ((< over 0.0) (+ 1.0 (fmin 0.5 (/ (- 0.0 over) 100.0))))
      (else 1.0)))

; (:m :do "a window under two days is a burst window and has no even pace: its allowance is 80 percent; longer windows allow the elapsed share of the window")
fn allowanceOf lenMs: Int64 resetsMs: Int64 nowMs: Int64 -> Float64
  (if (or (< lenMs 172800000) (<= resetsMs 0)) 80.0
    (let [(start (- resetsMs lenMs))
          (f (/ (int64ToFloat64 (- nowMs start)) (int64ToFloat64 lenMs)))]
      (* 100.0 (fmin 1.0 (fmax 0.02 f)))))

fn evalWin id: String w: PaceWin nowMs: Int64 calls: Int64 tokens: Int64 -> SubPace
  (let [(rolled (rollReset w.resetsMs w.lenMs nowMs))
        (expired (and (> w.resetsMs 0) (<= w.resetsMs nowMs) (!= w.src "ledger")))
        (used (if expired 0.0 w.used))
        (allowance (allowanceOf w.lenMs rolled nowMs))
        (age (- nowMs w.atMs))
        (limit (staleAfterMs w.src))
        (stale (and (> limit 0) (or (<= w.atMs 0) (> age limit))))
        (factor (winFactor used allowance))]
    (SubPace :id id :window w.kind :used used :known true :allowance allowance :pace (/ used (fmax 1.0 allowance)) :factor factor :src w.src :atMs w.atMs
             :stale stale :expired expired :over (> (- used allowance) (softPoints)) :hard (= factor 0.0) :calls calls :tokens tokens))

fn noData id: String calls: Int64 tokens: Int64 -> SubPace
  (SubPace :id id :window "none" :used 0.0 :known false :allowance 100.0 :pace 0.0 :factor 1.0 :src "none" :atMs 0 :stale true :expired false :over false :hard false :calls calls :tokens tokens)

fn moreBinding a: SubPace b: SubPace -> SubPace
  (if (< b.factor a.factor) b a)

; (:m :ref SUBPACE :do "a subscription with no figure and no capacity: its even time pace to the renews date, used and capacity unknown, never penalised; the ledger calls and tokens are still counted")
fn timePace id: String monthStart: Int64 nowMs: Int64 calls: Int64 tokens: Int64 -> SubPace
  (SubPace :id id :window "monthly" :used 0.0 :known false :allowance (allowanceOf 2592000000 (+ monthStart 2592000000) nowMs) :pace 0.0 :factor 1.0 :src "ledger" :atMs nowMs :stale false :expired false :over false :hard false :calls calls :tokens tokens)

; (:m :do "one SubPace per subscription line: the most binding window (lowest factor); a subscription with a :capacity (or the commandCode default) and no fresh api window also gets a ledger-estimate window ending at its renews date; :pace exhaust means never limited")
fn subPace z: lt/Zone line: String fileAtMs: Int64 ledgerText: String nowMs: Int64 -> SubPace
  (let [(id (subId line))
        (wins (windowsOf z line fileAtMs))
        (monthStart (- (rollReset (parseStampMs z (quotedAfter line ":renews")) 2592000000 nowMs) 2592000000))
        (cap (subCapacity line id))
        (use (if (> monthStart 0) (ledgerUse ledgerText id monthStart) (pair 0 0)))
        (fresh? (fn [(w PaceWin)] -> Bool (and (!= w.src "ledger") (not (and (> (staleAfterMs w.src) 0) (> (- nowMs w.atMs) (staleAfterMs w.src)))) (= w.kind "monthly"))))
        (needEst (and (> cap 0.0) (> monthStart 0) (not (listAny? fresh? wins))))
        (est (PaceWin :kind "monthly" :lenMs 2592000000 :resetsMs (+ monthStart 2592000000)
                      :used (/ (* 100.0 (int64ToFloat64 (pairFirst use))) cap) :src "ledger" :atMs nowMs))
        (all (if needEst (listAppend wins (list est)) wins))
        (evals (map (fn [(w PaceWin)] -> SubPace (evalWin id w nowMs (pairFirst use) (pairSecond use))) all))]
    (cond
      ((= (tokAfter line ":pace") "exhaust") (SubPace :id id :window "exhaust" :used 0.0 :known false :allowance 100.0 :pace 0.0 :factor 1.0 :src "principal" :atMs fileAtMs :stale false :expired false :over false :hard false :calls (pairFirst use) :tokens (pairSecond use)))
      ((listEmpty? evals) (if (> monthStart 0) (timePace id monthStart nowMs (pairFirst use) (pairSecond use)) (noData id (pairFirst use) (pairSecond use))))
      (else (fold moreBinding (optionOr (listHead evals) (noData id 0 0)) (optionOr (listTail evals) (list))))))

; (:m :do "every subscription of a subscriptions.asn text, in file order")
fn paceSubs z: lt/Zone subsText: String ledgerText: String nowMs: Int64 -> (List SubPace)
  (let [(fileAt (let [(u (quotedAfter subsText ":updated"))] (parseStampMs z u)))]
    (map (fn [(l String)] -> SubPace (subPace z l fileAt ledgerText nowMs)) (subLines subsText)))

fn permille f: Float64 -> Int64
  (toInt (* f 1000.0))

; (:m :do "the cache entries for the server: subscription id to factor permille, plus the time they were made; the server keeps them in its spread state under paceCacheKey")
fn factorsFromPaces paces: (List SubPace) nowMs: Int64 -> (Map String Int64)
  (fold (fn [(m (Map String Int64)) (p SubPace)] -> (Map String Int64) (mapSet m p.id (permille p.factor)))
        (mapSet (mapEmpty) "~at" nowMs) paces)

fn paceCacheFresh? cache: (Map String Int64) nowMs: Int64 -> Bool
  (match (mapGet cache "~at")
    ((some at) (< (- nowMs at) (paceCacheMs)))
    ((none) false))

; (:m :do "the provider of a pool key such as commandCode:ccLingFlash")
fn providerOf poolKey: String -> String
  (optionOr (listHead (stringSplit poolKey ":")) "")

; (:m :do "route spread under pace: each member's weight times 10 times its subscription factor; a member whose factor is 0 leaves the spread, so it falls behind the members left in the chain; members with no subscription row or no factor keep factor 1")
fn adjustSpread factors: (Map String Int64) pools: (List (Pair String String)) spread: (List (Pair String Int64)) -> (List (Pair String Int64))
  (let [(poolMap (mapFromPairs pools))
        (factorOf (fn [(alias String)] -> Int64
                    (let [(provider (providerOf (optionOr (mapGet poolMap alias) "")))]
                      (optionOr (mapGet factors (providerSub provider)) 1000))))]
    (if (<= (listLength (mapKeys factors)) 1) spread
      (map (fn [(m (Pair String Int64))] -> (Pair String Int64)
             (pair (pairFirst m) (max 1 (/ (* (pairSecond m) 10 (factorOf (pairFirst m))) 1000))))
           (filter (fn [(m (Pair String Int64))] -> Bool (> (factorOf (pairFirst m)) 0)) spread))))

; (:m :do "one status row per subscription: used and allowance in percent of the binding window, pace = used / allowance, value is the caller's multiplier, share is this subscription's part of the ledger calls in the share window, stale and expired say how old the figure is")
fn statusLine p: SubPace value: Float64 share: Float64 nowMs: Int64 -> String
  (str "(:subStatus :sub " p.id " :window " p.window " :used " (if p.known (fixed1 p.used) "unknown") " :allowance " (fixed1 p.allowance) " :pace " (if p.known (fixed1 p.pace) "unknown") (if (or p.known (= p.window "exhaust")) "" " :capacity unknown")
       " :factor " (fixed1 p.factor) " :value " (fixed1 value) " :share " (fixed1 (* 100.0 share))
       " :src " p.src " :ageMin " (stringFromInt64 (if (> p.atMs 0) (/ (- nowMs p.atMs) 60000) -1))
       " :stale " (if p.stale "true" "false") " :expired " (if p.expired "true" "false")
       " :over " (if p.over "true" "false") " :hard " (if p.hard "true" "false")
       " :calls " (stringFromInt64 p.calls) " :tokens " (stringFromInt64 p.tokens) ")")
