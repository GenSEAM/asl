(module aslGateway/breaker
  :x [ProviderStatus
      BreakerState
      BreakerEvent
      BreakerDecision
      BreakerStepResult
      defaultCooldownSec
      providerCooldownSec
      makeBreakerState
      makeBreakerStateWith
      QuotaPolicy
      quotaPolicy
      defaultQuotaPolicy
      quotaCooldownSec
      quotaHintSec
      breakerNote429
      defaultBreakerState
      touchSeen
      breakerDownFor
      breaker_down_for
      breakerMarkDown
      breakerMarkDownFor
      breaker_mark_down
      breakerClear
      breaker_clear
      breakerNote503
      breaker_note_503
      breakerReset503
      breaker_reset_503
      breakerNoteTimeout
      breaker_note_timeout
      breakerResetTimeout
      breaker_reset_timeout
      breakerIsQuotaError
      breaker_is_quota_error
      breakerIsProviderWideQuota
      breakerScope
      breakerSnapshot
      breaker_snapshot
      formatBreakerSnapshotAsn
      stepBreaker
      stepBreakerResult
      breaker503Count
      breakerTimeoutCount
      breakerUntil
      breakerSeenProviders
      evMarkDown
      evClear
      evNote503
      evReset503
      evNoteTimeout
      evResetTimeout
      evCheckDown
      evSnapshot
      decOk
      decTripped
      decDownFor
      decSnapshot]
  :i [(aslGateway/localTime :a lt)])

(schema ProviderStatus
  (:f down Bool)
  (:f secondsLeft Int64))

; (:m :ref GW-429-WINDOW-WAIT :do "how long a member waits after a 429 that is not a daily cap: :cooldown429Sec (default 15), doubled on each further 429 in a row up to :cooldown429MaxSec (default 600), and :cooldownSlackSec (default 1) added past a minute window's end; all three are (:gateway ...) config rows, out-of-range values fall back to these defaults")
(schema QuotaPolicy
  (:f baseSec Int64)
  (:f maxSec Int64)
  (:f slackSec Int64))

fn quotaPolicy baseSec: Int64 maxSec: Int64 slackSec: Int64 -> QuotaPolicy
  (let [(b (if (> baseSec 0) baseSec 15))
        (m (if (> maxSec 0) (max maxSec b) (max 600 b)))
        (s (if (>= slackSec 0) slackSec 1))]
    (QuotaPolicy :baseSec b :maxSec m :slackSec s))

fn defaultQuotaPolicy -> QuotaPolicy
  (quotaPolicy 15 600 1)

(schema BreakerState
  (:f cooldownSec Int64)
  (:f breakers (Map String Int64))
  (:f count503 (Map String Int64))
  (:f countTimeout (Map String Int64))
  (:f seen (Map String Bool))
  (:f quota QuotaPolicy)
  (:f count429 (Map String Int64)))

(enum BreakerEvent
  (:c evMarkDown [(provider String)])
  (:c evClear [(provider String)])
  (:c evNote503 [(provider String)])
  (:c evReset503 [(provider String)])
  (:c evNoteTimeout [(provider String)])
  (:c evResetTimeout [(provider String)])
  (:c evCheckDown [(provider String)])
  (:c evSnapshot []))

(enum BreakerDecision
  (:c decOk [])
  (:c decTripped [(tripped Bool)])
  (:c decDownFor [(secondsLeft Int64)])
  (:c decSnapshot [(snapshot (Map String ProviderStatus))]))

(schema BreakerStepResult
  (:f state BreakerState)
  (:f decision BreakerDecision))

fn defaultCooldownSec -> Int64
  600

fn providerCooldownSec -> Int64
  600

fn makeBreakerState cooldown: Int64 -> BreakerState
  (makeBreakerStateWith cooldown (defaultQuotaPolicy))

fn makeBreakerStateWith cooldown: Int64 policy: QuotaPolicy -> BreakerState
  (let [(cd (if (> cooldown 0) cooldown 600))
        (initSeen (mapSet (mapSet (mapSet (mapEmpty) "agy" true) "codex" true) "claude" true))]
    (BreakerState
      :cooldownSec cd
      :breakers (mapEmpty)
      :count503 (mapEmpty)
      :countTimeout (mapEmpty)
      :seen initSeen
      :quota policy
      :count429 (mapEmpty)))

fn defaultBreakerState -> BreakerState
  (makeBreakerState 600)

fn touchSeen st: BreakerState provider: String -> BreakerState
  (if (stringEmpty? provider)
    st
    (with st :seen (mapSet st.seen provider true)))

fn breakerIsQuotaError text: String -> Bool
  (let [(t (stringUpper text))]
    (or (stringContains? t "429")
      (or (stringContains? t "RESOURCE_EXHAUSTED")
        (stringContains? t "QUOTA"))))

fn breaker_is_quota_error text: String -> Bool
  (breakerIsQuotaError text)

; (:m :ref GW-429-BODY-SAMPLES :do "copy of upstream.modelScopedQuota?: a body naming one model's own limit is not provider-wide; keep in sync")
fn breakerModelScopedQuota text: String -> Bool
  (or (stringContains? text "Quota exceeded for metric")
    (or (stringContains? text "Rate limit reached for model")
      (or (stringContains? text "free_model_daily_requests") (stringContains? text "free-models-per-day"))))

; (:m :tags (breaker pool) :do "a 429 is per-model by default (each free model on a shared provider has its own upstream limit); these markers mean the account itself is out, so the whole provider pool trips instead of just the one model")
fn breakerIsProviderWideQuota text: String -> Bool
  (let [(t (stringUpper text))]
    (or (stringContains? t "INSUFFICIENT_QUOTA")
      (and (not (breakerModelScopedQuota text))
        (or (stringContains? t "BILLING")
          (and (stringContains? t "ACCOUNT") (stringContains? t "QUOTA"))))))

; (:m :ref PAIDCHEAP-BREAKER-ALL-OPEN :do "the key a failure counts under: an account-wide failure (401, 402, a provider-wide quota body) trips the provider pool; every other failure (429, 503, 5xx, 4xx) counts on the member's own providerPool:alias key, so one member's 503 streak never closes its siblings on the same provider")
fn breakerScope status: Int64 body: String providerPool: String pool: String -> String
  (if (or (= status 401) (or (= status 402) (breakerIsProviderWideQuota body))) providerPool pool)

fn grownSec base: Int64 cap: Int64 streak: Int64 -> Int64
  (if (or (<= streak 0) (>= base cap))
    (min base cap)
    (grownSec (* base 2) cap (- streak 1)))

; (:m :ref GW-429-WINDOW-WAIT :do "a hint is delta seconds, or an epoch in seconds or milliseconds (openrouter X-RateLimit-Reset), read against now")
fn hintLeftSec hint: Int64 now: Int64 -> Int64
  (cond
    ((> hint 1000000000000) (- (/ hint 1000) now))
    ((> hint 1000000000) (- hint now))
    (else hint))

; (:m :ref GW-429-WINDOW-WAIT :do "the cooldown after a 429: the provider's own hint when it names one (capped at a day and an hour), else the end of the member's aligned window (its :rpm minute, or a :limits minute, hour or day) plus slack, never past the window, else the base doubled per 429 in a row up to the max")
fn quotaCooldownSec p: QuotaPolicy hintSec: Int64 windowSec: Int64 now: Int64 streak: Int64 -> Int64
  (let [(left (if (> hintSec 0) (hintLeftSec hintSec now) 0))]
    (cond
      ((> left 0) (min left 90000))
      ((> windowSec 0) (min windowSec (+ (- windowSec (mod now windowSec)) p.slackSec)))
      (else (grownSec p.baseSec p.maxSec streak))))

fn ceilSec f: Float64 -> Int64
  (optionOr (float64ToInt64 (+ f 0.999)) 0)

fn durationNumber buf: String -> Float64
  (optionOr (stringToFloat64 buf) 0.0)

; (:m :ref GW-429-WINDOW-WAIT :do "an x-ratelimit-reset duration as OpenAI-style providers send it (6m0s, 2.5s, 850ms, 1h2m); -1 when the text is not one")
fn durationSecAt t: String i: Int64 buf: String total: Float64 -> Float64
  (if (>= i (stringLength t))
    (if (stringEmpty? buf) total -1.0)
    (let [(c (optionOr (stringSlice t i (+ i 1)) ""))
          (next (optionOr (stringSlice t (+ i 1) (+ i 2)) ""))]
      (cond
        ((stringContains? "0123456789." c) (durationSecAt t (+ i 1) (str buf c) total))
        ((stringEmpty? buf) -1.0)
        ((and (= c "m") (= next "s")) (durationSecAt t (+ i 2) "" (+ total (/ (durationNumber buf) 1000.0))))
        ((= c "h") (durationSecAt t (+ i 1) "" (+ total (* (durationNumber buf) 3600.0))))
        ((= c "m") (durationSecAt t (+ i 1) "" (+ total (* (durationNumber buf) 60.0))))
        ((= c "s") (durationSecAt t (+ i 1) "" (+ total (durationNumber buf))))
        (else -1.0))))

fn hintOfText text: String -> Int64
  (match (stringToFloat64 text)
    ((some f) (if (> f 0.0) (ceilSec f) 0))
    ((none) (let [(d (durationSecAt text 0 "" 0.0))] (if (> d 0.0) (ceilSec d) 0))))

fn headerText headers: (List (Pair String String)) name: String -> String
  (match (listFind (fn [(h (Pair String String))] -> Bool (= (stringLower (pairFirst h)) name)) headers)
    ((some h) (stringTrim (pairSecond h)))
    ((none) ""))

; (:m :ref GW-429-WINDOW-WAIT :do "the wait a 429's headers name: Retry-After delta seconds first, else the longest of x-ratelimit-reset-requests, x-ratelimit-reset-tokens and x-ratelimit-reset; an IMF-fixdate Retry-After ending GMT counts from the clock; 0 when none parses, so the window or the base applies")
fn retryAfterHintSec text: String nowSec: Float64 -> Int64
  (let [(delta (hintOfText text))]
    (if (> delta 0) delta
      (match (if (stringEndsWith? text " GMT") (lt/parseHttpDateEpochSeconds text) none)
        ((some epoch) (if (> epoch nowSec) (ceilSec (- epoch nowSec)) 0))
        ((none) 0))))

fn quotaHintSec headers: (List (Pair String String)) nowSec: Float64 -> Int64
  (let [(retry (retryAfterHintSec (headerText headers "retry-after") nowSec))]
    (if (> retry 0)
      retry
      (max (hintOfText (headerText headers "x-ratelimit-reset-requests"))
           (max (hintOfText (headerText headers "x-ratelimit-reset-tokens"))
                (hintOfText (headerText headers "x-ratelimit-reset"))))))

; (:m :ref GW-429-WINDOW-WAIT :do "a 429 opens the member for quotaCooldownSec and counts toward its streak; breakerClear (a success) ends the streak")
fn breakerNote429 st: BreakerState provider: String now: Int64 hintSec: Int64 windowSec: Int64 -> BreakerState
  (if (stringEmpty? provider)
    st
    (let [(streak (optionOr (mapGet st.count429 provider) 0))
          (cd (quotaCooldownSec st.quota hintSec windowSec now streak))]
      (with st :breakers (mapSet st.breakers provider (+ now cd)) :count429 (mapSet st.count429 provider (+ streak 1))
               :count503 (mapSet st.count503 provider 0) :countTimeout (mapSet st.countTimeout provider 0) :seen (mapSet st.seen provider true))))

fn breakerDownFor st: BreakerState provider: String now: Int64 -> (Pair BreakerState Int64)
  (if (stringEmpty? provider)
    (pair st 0)
    (let [(stSeen (touchSeen st provider))]
      (match (mapGet stSeen.breakers provider)
        ((none) (pair stSeen 0))
        ((some until)
         (let [(left (- until now))]
           (if (<= left 0)
             (let [(pruned (BreakerState
                             :cooldownSec stSeen.cooldownSec
                             :breakers (mapRemove stSeen.breakers provider)
                             :count503 stSeen.count503
                             :countTimeout stSeen.countTimeout
                             :seen stSeen.seen
                             :quota stSeen.quota
                             :count429 stSeen.count429))]
               (pair pruned 0))
             (pair stSeen left)))))))

fn breaker_down_for st: BreakerState provider: String now: Int64 -> (Pair BreakerState Int64)
  (breakerDownFor st provider now)

fn breakerMarkDown st: BreakerState provider: String now: Int64 -> BreakerState
  (breakerMarkDownFor st provider now 0)

; (:m :ref GW-PARK-TYPED :do "a daily-cap 429 parks the pool for parkSec seconds (its provider's reset) instead of the fixed cooldown; parkSec 0 keeps the cooldown")
fn breakerMarkDownFor st: BreakerState provider: String now: Int64 parkSec: Int64 -> BreakerState
  (if (stringEmpty? provider)
    st
    (let [(until (+ now (if (> parkSec 0) parkSec st.cooldownSec)))]
      (with st :breakers (mapSet st.breakers provider until) :count503 (mapSet st.count503 provider 0) :countTimeout (mapSet st.countTimeout provider 0) :seen (mapSet st.seen provider true))))

fn breaker_mark_down st: BreakerState provider: String now: Int64 -> BreakerState
  (breakerMarkDown st provider now)

fn breakerClear st: BreakerState provider: String -> BreakerState
  (if (stringEmpty? provider)
    st
    (with st :breakers (mapRemove st.breakers provider) :count429 (mapSet st.count429 provider 0) :count503 (mapSet st.count503 provider 0) :countTimeout (mapSet st.countTimeout provider 0) :seen (mapSet st.seen provider true)))

fn breaker_clear st: BreakerState provider: String -> BreakerState
  (breakerClear st provider)

fn breakerNote503 st: BreakerState provider: String now: Int64 -> (Pair BreakerState Bool)
  (if (stringEmpty? provider)
    (pair st false)
    (let [(prevCnt (optionOr (mapGet st.count503 provider) 0))
          (cnt (+ prevCnt 1))
          (stSeen (touchSeen st provider))]
      (if (>= cnt 3)
        (let [(until (+ now stSeen.cooldownSec))
              (nextSt (BreakerState
                        :cooldownSec stSeen.cooldownSec
                        :breakers (mapSet stSeen.breakers provider until)
                        :count503 (mapSet stSeen.count503 provider 0)
                        :countTimeout stSeen.countTimeout
                        :seen stSeen.seen
                        :quota stSeen.quota
                        :count429 stSeen.count429))]
          (pair nextSt true))
        (let [(nextSt (BreakerState
                        :cooldownSec stSeen.cooldownSec
                        :breakers stSeen.breakers
                        :count503 (mapSet stSeen.count503 provider cnt)
                        :countTimeout stSeen.countTimeout
                        :seen stSeen.seen
                        :quota stSeen.quota
                        :count429 stSeen.count429))]
          (pair nextSt false)))))

fn breaker_note_503 st: BreakerState provider: String now: Int64 -> (Pair BreakerState Bool)
  (breakerNote503 st provider now)

fn breakerReset503 st: BreakerState provider: String -> BreakerState
  (if (stringEmpty? provider)
    st
    (with st :count503 (mapSet st.count503 provider 0)))

fn breaker_reset_503 st: BreakerState provider: String -> BreakerState
  (breakerReset503 st provider)

fn breakerNoteTimeout st: BreakerState provider: String now: Int64 -> (Pair BreakerState Bool)
  (if (stringEmpty? provider)
    (pair st false)
    (let [(prevCnt (optionOr (mapGet st.countTimeout provider) 0))
          (cnt (+ prevCnt 1))
          (stSeen (touchSeen st provider))]
      (if (>= cnt 3)
        (let [(until (+ now stSeen.cooldownSec))
              (nextSt (BreakerState
                        :cooldownSec stSeen.cooldownSec
                        :breakers (mapSet stSeen.breakers provider until)
                        :count503 stSeen.count503
                        :countTimeout (mapSet stSeen.countTimeout provider 0)
                        :seen stSeen.seen
                        :quota stSeen.quota
                        :count429 stSeen.count429))]
          (pair nextSt true))
        (let [(nextSt (BreakerState
                        :cooldownSec stSeen.cooldownSec
                        :breakers stSeen.breakers
                        :count503 stSeen.count503
                        :countTimeout (mapSet stSeen.countTimeout provider cnt)
                        :seen stSeen.seen
                        :quota stSeen.quota
                        :count429 stSeen.count429))]
          (pair nextSt false)))))

fn breaker_note_timeout st: BreakerState provider: String now: Int64 -> (Pair BreakerState Bool)
  (breakerNoteTimeout st provider now)

fn breakerResetTimeout st: BreakerState provider: String -> BreakerState
  (if (stringEmpty? provider)
    st
    (with st :countTimeout (mapSet st.countTimeout provider 0)))

fn breaker_reset_timeout st: BreakerState provider: String -> BreakerState
  (breakerResetTimeout st provider)

fn breakerSnapshot st: BreakerState now: Int64 -> (Pair BreakerState (Map String ProviderStatus))
  (let [(breakerKeys (mapKeys st.breakers))
        (allSeen (fold (fn [(acc (Map String Bool)) (k String)] -> (Map String Bool)
                         (mapSet acc k true))
                       st.seen
                       breakerKeys))
        (sortedNames (mapKeys allSeen))
        (initPair (pair (with st :seen allSeen)
                        (mapEmpty)))]
    (fold (fn [(acc (Pair BreakerState (Map String ProviderStatus))) (name String)] -> (Pair BreakerState (Map String ProviderStatus))
            (let [(curSt (pairFirst acc))
                  (curMap (pairSecond acc))
                  (downRes (breakerDownFor curSt name now))
                  (nextSt (pairFirst downRes))
                  (secLeft (pairSecond downRes))
                  (isDown (> secLeft 0))
                  (status (ProviderStatus :down isDown :secondsLeft secLeft))
                  (nextMap (mapSet curMap name status))]
              (pair nextSt nextMap)))
          initPair
          sortedNames))

fn breaker_snapshot st: BreakerState now: Int64 -> (Pair BreakerState (Map String ProviderStatus))
  (breakerSnapshot st now)

fn formatBreakerSnapshotAsn snapshot: (Map String ProviderStatus) -> String
  (let [(keys (mapKeys snapshot))
        (entries (map (fn [(k String)] -> String
                        (let [(status (optionOr (mapGet snapshot k) (ProviderStatus :down false :secondsLeft 0)))
                              (downStr (if status.down "true" "false"))
                              (secStr (stringFromInt64 status.secondsLeft))]
                          (str ":" k " (:down " downStr " :secondsLeft " secStr ")")))
                      keys))]
    (str "(:breaker (" (stringJoin entries " ") "))"))

fn stepBreaker st: BreakerState event: BreakerEvent now: Int64 -> (Pair BreakerState BreakerDecision)
  (match event
    ((evMarkDown p)
     (let [(nextSt (breakerMarkDown st p now))]
       (pair nextSt (decOk))))
    ((evClear p)
     (let [(nextSt (breakerClear st p))]
       (pair nextSt (decOk))))
    ((evNote503 p)
     (let [(res (breakerNote503 st p now))]
       (pair (pairFirst res) (decTripped (pairSecond res)))))
    ((evReset503 p)
     (let [(nextSt (breakerReset503 st p))]
       (pair nextSt (decOk))))
    ((evNoteTimeout p)
     (let [(res (breakerNoteTimeout st p now))]
       (pair (pairFirst res) (decTripped (pairSecond res)))))
    ((evResetTimeout p)
     (let [(nextSt (breakerResetTimeout st p))]
       (pair nextSt (decOk))))
    ((evCheckDown p)
     (let [(res (breakerDownFor st p now))]
       (pair (pairFirst res) (decDownFor (pairSecond res)))))
    ((evSnapshot)
     (let [(res (breakerSnapshot st now))]
       (pair (pairFirst res) (decSnapshot (pairSecond res))))))

fn stepBreakerResult st: BreakerState event: BreakerEvent now: Int64 -> BreakerStepResult
  (let [(step (stepBreaker st event now))]
    (BreakerStepResult :state (pairFirst step) :decision (pairSecond step)))

fn breaker503Count st: BreakerState provider: String -> Int64
  (optionOr (mapGet st.count503 provider) 0)

fn breakerTimeoutCount st: BreakerState provider: String -> Int64
  (optionOr (mapGet st.countTimeout provider) 0)

fn breakerUntil st: BreakerState provider: String -> (Option Int64)
  (mapGet st.breakers provider)

fn breakerSeenProviders st: BreakerState -> (List String)
  (mapKeys st.seen)
