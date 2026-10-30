(module aslGateway/tests/limitClassifyTest
  :x [runTests]
  :i [(upstream :a u)
      (breaker :a b)
      (aslGateway/tests/limitFixtures :a fx)])

fn flag v: Bool -> String
  (if v "true" "false")

; (:m :ref GW-429-BODY-SAMPLES :do "every limit fixture gets the class the pool must act on: provider-wide or model-scoped (upstream and breaker copies must agree), daily-cap kind, retry or not, and the park seconds of a daily cap; a gemini 429 carries the words 'check your plan and billing details' on every quota error, which must not trip the whole provider; returns the empty string when all agree, else one line per disagreement so a red run names every misclassified shape")
fn mismatches f: fx/Fx -> String
  (let [(wideU (u/looksProviderWideQuota? f.body))
        (wideB (b/breakerIsProviderWideQuota f.body))
        (kind (u/dailyCapKind f.status f.body))
        (retry (u/retryableHttpStatus? f.status f.body))
        (park (if (stringEmpty? kind) 0 (u/dailyCapParkSec kind f.headers f.body (fx/nowSec))))]
    (str (if (= wideU f.wide) "" (str f.id ": upstream wide " (flag wideU) " want " (flag f.wide) "; "))
         (if (= wideB f.wide) "" (str f.id ": breaker wide " (flag wideB) " want " (flag f.wide) "; "))
         (if (= kind f.daily) "" (str f.id ": daily '" kind "' want '" f.daily "'; "))
         (if (= retry f.retry) "" (str f.id ": retry " (flag retry) " want " (flag f.retry) "; "))
         (if (= park f.park) "" (str f.id ": park " (stringFromInt64 park) " want " (stringFromInt64 f.park) "; "))))

fn ! runTests -> Bool
  (let [(bad (fold (fn [acc f] (str acc (mismatches f))) "" (fx/fixtures)))]
    (do
      (assert (>= (listLength (fx/fixtures)) 10) "the fixture set is not empty")
      (assert (stringEmpty? bad) (str "misclassified: " bad))
      true))
