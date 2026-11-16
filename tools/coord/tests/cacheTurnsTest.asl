(module asl-tools/coord/tests/cacheTurnsTest
  :x [runTests]
  :i [(aslGateway/usageLedger :a ul) (asl-tools/coord/cacheTurns :a ct)])

; (:m :ref CACHE-BY-TURN-TEST :do "eleven fixture lines through ul/callRowParse: nine attributed calls over two providers and all three buckets, two of the buckets even-count, plus two rows that carry no session or no turn and so must land in the unattributed total")
fn mkRow provider: String session: (Option String) turn: (Option Int64) inT: Int64 cachedT: Int64 -> ul/CallRow
  (ul/CallRow :atMs 1000 :profile "p1" :intent "construct" :alias "a" :provider provider :model "m"
    :inTokens inT :cachedTokens cachedT :outTokens 1 :reasoningTokens 0 :ttftMs none :ms none
    :outcome "ok" :charge 0 :tag none :temperature none :topP none :maxTokens none :effort none
    :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash ""
    :session session :turn turn :consumer none :cacheWriteTokens none :status 0 :reason none)

fn fixtureLines -> (List String)
  (list
    (ul/callRowLine (mkRow "or" (some "s1") (some 1) 100 50))
    (ul/callRowLine (mkRow "or" (some "s1") (some 2) 100 20))
    (ul/callRowLine (mkRow "or" (some "s1") (some 3) 100 40))
    (ul/callRowLine (mkRow "or" (some "s1") (some 15) 100 10))
    (ul/callRowLine (mkRow "agy" (some "s2") (some 1) 100 60))
    (ul/callRowLine (mkRow "agy" (some "s2") (some 1) 100 80))
    (ul/callRowLine (mkRow "agy" (some "s2") (some 9) 100 25))
    (ul/callRowLine (mkRow "agy" (some "s2") (some 16) 100 90))
    (ul/callRowLine (mkRow "agy" (some "s2") (some 20) 100 30))
    (ul/callRowLine (mkRow "or" none (some 4) 100 70))
    (ul/callRowLine (mkRow "agy" (some "s3") none 100 35)))

fn parsedRows -> (List (Result ul/CallRow String))
  (map (fn [(l String)] -> (Result ul/CallRow String) (ul/callRowParse l)) (fixtureLines))

fn fixtureRows -> (List ul/CallRow)
  (listFlatMap (fn [(r (Result ul/CallRow String))] -> (List ul/CallRow)
                 (match r ((ok x) (list x)) ((err _) (list)))) (parsedRows))

fn allParsed -> Bool
  (listAll? (fn [(r (Result ul/CallRow String))] -> Bool (ok? r)) (parsedRows))

fn turnResult -> (Pair (List ct/TurnBucket) Int64)
  (ct/cacheByTurn (fixtureRows))

fn findRow provider: String bucket: String -> (Option ct/TurnBucket)
  (listHead (filter (fn [(r ct/TurnBucket)] -> Bool (and (= r.provider provider) (= r.bucket bucket)))
                    (pairFirst (turnResult))))

fn callsOf provider: String bucket: String -> Int64
  (match (findRow provider bucket) ((some r) r.calls) ((none) -1))

fn medianOfBucket provider: String bucket: String -> Float64
  (match (findRow provider bucket) ((some r) r.medianCachedShare) ((none) -1.0))

fn approx a: Float64 b: Float64 -> Bool
  (let [(d (if (< a b) (- b a) (- a b)))] (< d 0.000000001))

fn parseChecks -> Bool
  (do
    (assert (= (listLength (fixtureLines)) 11) "eleven fixture lines")
    (assert (allParsed) "every fixture line parses through ul/callRowParse")
    (assert (= (listLength (fixtureRows)) 11) "every parsed fixture row survives")
    true)

fn bucketChecks -> Bool
  (do
    (assert (= (ct/bucketOf 1) "turn1") "turn 1 is the turn1 bucket")
    (assert (= (ct/bucketOf 2) "turns2to14") "turn 2 opens turns2to14")
    (assert (= (ct/bucketOf 14) "turns2to14") "turn 14 closes turns2to14")
    (assert (= (ct/bucketOf 15) "turns15plus") "turn 15 opens turns15plus")
    (assert (= (ct/bucketOf 40) "turns15plus") "a later turn stays in turns15plus")
    (assert (approx (ct/shareOf (mkRow "or" (some "s") (some 1) 100 50)) 0.5) "share is cachedTokens over inTokens")
    (assert (= (ct/shareOf (mkRow "or" (some "s") (some 1) 0 0)) 0.0) "a call with no input tokens has share 0, not a division by zero")
    true)

fn metricChecks -> Bool
  (do
    (assert (= (listLength (pairFirst (turnResult))) 6) "one row per provider and bucket, six in total")
    (assert (= (pairSecond (turnResult)) 2) "the row with no session and the row with no turn are the unattributed total")
    (assert (= (callsOf "or" "turn1") 1) "or/turn1 has one call")
    (assert (approx (medianOfBucket "or" "turn1") 0.5) "or/turn1 median share")
    (assert (= (callsOf "or" "turns2to14") 2) "or/turns2to14 has two calls")
    (assert (approx (medianOfBucket "or" "turns2to14") 0.3) "even-count bucket: the median is the mean of the middle shares 0.2 and 0.4")
    (assert (= (callsOf "or" "turns15plus") 1) "or/turns15plus has one call")
    (assert (approx (medianOfBucket "or" "turns15plus") 0.1) "or/turns15plus median share")
    (assert (= (callsOf "agy" "turn1") 2) "agy/turn1 has two calls")
    (assert (approx (medianOfBucket "agy" "turn1") 0.7) "agy/turn1 even-count median of 0.6 and 0.8")
    (assert (= (callsOf "agy" "turns2to14") 1) "agy/turns2to14 has one call")
    (assert (approx (medianOfBucket "agy" "turns2to14") 0.25) "agy/turns2to14 median share")
    (assert (= (callsOf "agy" "turns15plus") 2) "agy/turns15plus has two calls")
    (assert (approx (medianOfBucket "agy" "turns15plus") 0.6) "agy/turns15plus even-count median of 0.3 and 0.9")
    (assert (= (+ (+ (+ (+ (+ (callsOf "or" "turn1") (callsOf "or" "turns2to14")) (callsOf "or" "turns15plus"))
                        (callsOf "agy" "turn1")) (callsOf "agy" "turns2to14")) (callsOf "agy" "turns15plus")) 9)
            "nine attributed calls, the two unattributed rows counted nowhere else")
    (assert (stringContains? (ct/cacheByTurnText (fixtureRows)) "(:unattributed 2)") "the text form reports the unattributed total")
    true)

fn runTests -> Bool
  (do
    (assert (parseChecks) "fixtures parse")
    (assert (bucketChecks) "bucket boundaries and share")
    (assert (metricChecks) "cacheByTurn metric")
    true)
