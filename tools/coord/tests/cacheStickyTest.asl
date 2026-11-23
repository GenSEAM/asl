(module asl-tools/coord/tests/cacheStickyTest
  :x [runTests]
  :i [(aslGateway/usageLedger :a ul) (asl-tools/coord/cacheTurns :a ct)])

; (:m :ref CACHE-STICKY-TEST :do "three sessions with a turn 1: one fully sticky over three turns, one that switches alias once, one that alternates provider and alias every turn; plus a session whose first row is turn 2 and so cannot be attributed. Totals: 3 sessions, 7 turns after the first, 4 of them on turn 1's provider and alias, so the share is exactly 4/7")
fn mkRow provider: String alias: String session: String turn: Int64 -> ul/CallRow
  (ul/CallRow :atMs 1000 :profile "p1" :intent "construct" :alias alias :provider provider :model "m"
    :inTokens 100 :cachedTokens 50 :outTokens 1 :reasoningTokens 0 :ttftMs none :ms none
    :outcome "ok" :charge 0 :tag none :temperature none :topP none :maxTokens none :effort none
    :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash ""
    :session (some session) :turn (some turn) :consumer none :cacheWriteTokens none :status 0 :reason none)

fn fixture -> (List ul/CallRow)
  (list
    (mkRow "or" "a1" "sticky" 1)
    (mkRow "or" "a1" "sticky" 2)
    (mkRow "or" "a1" "sticky" 3)
    (mkRow "or" "a1" "oneSwitch" 1)
    (mkRow "or" "a1" "oneSwitch" 2)
    (mkRow "or" "a2" "oneSwitch" 3)
    (mkRow "or" "a1" "alt" 1)
    (mkRow "agy" "a2" "alt" 2)
    (mkRow "or" "a1" "alt" 3)
    (mkRow "agy" "a2" "alt" 4)
    (mkRow "or" "a1" "late" 2)
    (mkRow "or" "a1" "late" 3))

fn noRows -> (List ul/CallRow)
  (filter (fn [(r ul/CallRow)] -> Bool false) (fixture))

fn approx a: Float64 b: Float64 -> Bool
  (let [(d (if (< a b) (- b a) (- a b)))] (< d 0.000000001))

fn shareChecks -> Bool
  (let [(s (ct/stickyShare (fixture)))]
    (do
      (assert (= s.sessions 3) "three sessions have a turn 1")
      (assert (= s.turnsAfterFirst 7) "seven turns after the first")
      (assert (= s.sameProvider 4) "four of them stay on turn 1's provider and alias")
      (assert (approx s.share 0.5714285714285714) "the share is 4/7")
      (assert (approx (* s.share 7.0) 4.0) "share times seven is four within 1e-9")
      true))

fn switchChecks -> Bool
  (let [(xs (ct/perSessionSwitches (fixture)))]
    (do
      (assert (= (listLength xs) 2) "two sessions switch")
      (assert (listContains? xs "oneSwitch") "the alias switch is listed")
      (assert (listContains? xs "alt") "the alternating session is listed")
      (assert (not (listContains? xs "sticky")) "the fully sticky session is not listed")
      (assert (not (listContains? xs "late")) "a session without a turn 1 is not listed")
      true))

fn textChecks -> Bool
  (do
    (assert (stringContains? (ct/stickyShareText (fixture)) "(:sessions 3") "the text form names the session count")
    (assert (stringContains? (ct/stickyShareText (fixture)) ":sameProvider 4") "the text form names the sticky count")
    true)

fn emptyChecks -> Bool
  (let [(s (ct/stickyShare (noRows)))]
    (do
      (assert (= s.sessions 0) "no sessions")
      (assert (= s.turnsAfterFirst 0) "no turns after the first")
      (assert (= s.sameProvider 0) "no sticky turns")
      (assert (= s.share 0.0) "an empty input has share 0.0, not a division by zero")
      (assert (= (listLength (ct/perSessionSwitches (noRows))) 0) "no switches")
      true))

fn runTests -> Bool
  (do
    (assert (shareChecks) "sticky share totals")
    (assert (switchChecks) "per-session switches")
    (assert (textChecks) "text form")
    (assert (emptyChecks) "empty input")
    true)
