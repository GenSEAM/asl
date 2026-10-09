(module aslGateway/breaker
  :x [ProviderStatus
      BreakerState
      BreakerEvent
      BreakerDecision
      BreakerStepResult
      defaultCooldownSec
      providerCooldownSec
      makeBreakerState
      defaultBreakerState
      touchSeen
      breakerDownFor
      breaker_down_for
      breakerMarkDown
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
  :i [])

(schema ProviderStatus
  (:f down Bool)
  (:f secondsLeft Int64))

(schema BreakerState
  (:f cooldownSec Int64)
  (:f breakers (Map String Int64))
  (:f count503 (Map String Int64))
  (:f countTimeout (Map String Int64))
  (:f seen (Map String Bool)))

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
  (let [(cd (if (> cooldown 0) cooldown 600))
        (initSeen (mapSet (mapSet (mapSet (mapEmpty) "agy" true) "codex" true) "claude" true))]
    (BreakerState
      :cooldownSec cd
      :breakers (mapEmpty)
      :count503 (mapEmpty)
      :countTimeout (mapEmpty)
      :seen initSeen))

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

fn breakerDownFor st: BreakerState provider: String now: Int64 -> (Pair BreakerState Int64)
  (if (stringEmpty? provider)
    (pair st 0)
    (let [(stSeen (touchSeen st provider))]
      (mt (mapGet stSeen.breakers provider)
        ((none) (pair stSeen 0))
        ((some until)
         (let [(left (- until now))]
           (if (<= left 0)
             (let [(pruned (BreakerState
                             :cooldownSec stSeen.cooldownSec
                             :breakers (mapRemove stSeen.breakers provider)
                             :count503 stSeen.count503
                             :countTimeout stSeen.countTimeout
                             :seen stSeen.seen))]
               (pair pruned 0))
             (pair stSeen left)))))))

fn breaker_down_for st: BreakerState provider: String now: Int64 -> (Pair BreakerState Int64)
  (breakerDownFor st provider now)

fn breakerMarkDown st: BreakerState provider: String now: Int64 -> BreakerState
  (if (stringEmpty? provider)
    st
    (let [(until (+ now st.cooldownSec))]
      (with st :breakers (mapSet st.breakers provider until) :count503 (mapSet st.count503 provider 0) :countTimeout (mapSet st.countTimeout provider 0) :seen (mapSet st.seen provider true))))

fn breaker_mark_down st: BreakerState provider: String now: Int64 -> BreakerState
  (breakerMarkDown st provider now)

fn breakerClear st: BreakerState provider: String -> BreakerState
  (if (stringEmpty? provider)
    st
    (with st :breakers (mapRemove st.breakers provider) :count503 (mapSet st.count503 provider 0) :countTimeout (mapSet st.countTimeout provider 0) :seen (mapSet st.seen provider true)))

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
                        :seen stSeen.seen))]
          (pair nextSt true))
        (let [(nextSt (BreakerState
                        :cooldownSec stSeen.cooldownSec
                        :breakers stSeen.breakers
                        :count503 (mapSet stSeen.count503 provider cnt)
                        :countTimeout stSeen.countTimeout
                        :seen stSeen.seen))]
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
                        :seen stSeen.seen))]
          (pair nextSt true))
        (let [(nextSt (BreakerState
                        :cooldownSec stSeen.cooldownSec
                        :breakers stSeen.breakers
                        :count503 stSeen.count503
                        :countTimeout (mapSet stSeen.countTimeout provider cnt)
                        :seen stSeen.seen))]
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
  (mt event
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
