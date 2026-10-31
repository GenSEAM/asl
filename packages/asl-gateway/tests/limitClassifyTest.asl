(module aslGateway/tests/limitClassifyTest
  :x [runTests]
  :i [(upstream :a u)
      (breaker :a b)
      (config :a c)
      (aslGateway/tests/limitFixtures :a fx)])

fn flag v: Bool -> String
  (if v "true" "false")

; (:m :ref GW-429-BODY-SAMPLES :do "every limit fixture gets the class the pool must act on: provider-wide or model-scoped (upstream and breaker copies must agree), daily-cap kind, retry or not, and the park seconds of a daily cap; a gemini 429 carries the words 'check your plan and billing details' on every quota error, which must not trip the whole provider; returns the empty string when all agree, else one line per disagreement so a red run names every misclassified shape")
fn mismatches f: fx/Fx -> String
  (let [(wideU (u/looksProviderWideQuota? f.body))
        (wideB (b/breakerIsProviderWideQuota f.body))
        (kind (u/dailyCapKind f.status f.body))
        (retry (u/retryableHttpStatus? f.status f.body))
        (park (if (stringEmpty? kind) 0 (u/dailyCapParkSec kind f.headers f.body (fx/nowSec))))
        (scope (b/breakerScope f.status f.body "p" "p:m"))
        (wantScope (if (or f.wide (= f.daily "monthly")) "p" "p:m"))]
    (str (if (= wideU f.wide) "" (str f.id ": upstream wide " (flag wideU) " want " (flag f.wide) "; "))
         (if (= wideB f.wide) "" (str f.id ": breaker wide " (flag wideB) " want " (flag f.wide) "; "))
         (if (= kind f.daily) "" (str f.id ": daily '" kind "' want '" f.daily "'; "))
         (if (= retry f.retry) "" (str f.id ": retry " (flag retry) " want " (flag f.retry) "; "))
         (if (= park f.park) "" (str f.id ": park " (stringFromInt64 park) " want " (stringFromInt64 f.park) "; "))
         (if (= scope wantScope) "" (str f.id ": scope " scope " want " wantScope "; "))))

; (:m :ref OLLAMA-MONTHLY-EXHAUSTED :do "a monthly-limit 429 parks the provider pool, not the one model, until the next month starts at 00:00 UTC, read from the clock it is handed: the breaker reports the provider down one second before that and up at it; the year rollover and a leap February land on the first of the next month; a (:gateway :parkMaxSec N) row read as config text clamps the park, default 32 days")
fn monthlyParkChain -> String
  (let [(f (optionOr (listHead (filter (fn [(x fx/Fx)] -> Bool (= x.daily "monthly")) (fx/fixtures))) (optionOr (listHead (fx/fixtures)) (fx/Fx :id "" :provider "" :src "" :status 0 :headers (list) :body "" :wide false :daily "" :retry false :park 0))))
        (now (optionOr (float64ToInt64 (fx/nowSec)) 0))
        (scope (b/breakerScope f.status f.body "ollama" "ollama:gptOss120b"))
        (park (u/dailyCapParkSec (u/dailyCapKind f.status f.body) f.headers f.body (fx/nowSec)))
        (st (b/breakerMarkDownFor (b/defaultBreakerState) scope now park))
        (before (pairSecond (b/breakerDownFor st "ollama" (+ now (- park 1)))))
        (at (pairSecond (b/breakerDownFor st "ollama" (+ now park))))
        (yearEnd (u/dailyCapParkSec "monthly" (list) "" 1798758000.0))
        (leapFeb (u/dailyCapParkSec "monthly" (list) "" 1834185600.0))
        (rowSec (optionOr (c/gatewayTopIntOverride "(:gateway :parkMaxSec 86400)" "parkMaxSec") 0))
        (capped (b/breakerMarkDownFor (b/withParkMax (b/defaultBreakerState) rowSec) scope now park))
        (cappedLeft (pairSecond (b/breakerDownFor capped "ollama" now)))]
    (str (if (= f.daily "monthly") "" "no monthly fixture; ")
         (if (= scope "ollama") "" (str "scope " scope " want ollama; "))
         (if (> before 0) "" "provider not down one second before the month start; ")
         (if (= at 0) "" (str "provider still down at the month start: " (stringFromInt64 at) "; "))
         (if (= yearEnd 3600) "" (str "2026-12-31T23:00Z parks " (stringFromInt64 yearEnd) " want 3600; "))
         (if (= leapFeb 1296000) "" (str "2028-02-15T00:00Z parks " (stringFromInt64 leapFeb) " want 1296000; "))
         (if (= (b/defaultParkMaxSec) 2764800) "" "default parkMaxSec is not 32 days; ")
         (if (= rowSec 86400) "" (str "the :parkMaxSec row reads " (stringFromInt64 rowSec) " want 86400; "))
         (if (= cappedLeft 86400) "" (str "a :parkMaxSec 86400 row parks the month for " (stringFromInt64 cappedLeft) " want 86400; "))))

fn ! runTests -> Bool
  (let [(bad (fold (fn [acc f] (str acc (mismatches f))) "" (fx/fixtures)))]
    (do
      (assert (>= (listLength (fx/fixtures)) 10) "the fixture set is not empty")
      (assert (stringEmpty? bad) (str "misclassified: " bad))
      (assert (stringEmpty? (monthlyParkChain)) (str "monthly park: " (monthlyParkChain)))
      true))
