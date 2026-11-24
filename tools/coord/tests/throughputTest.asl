(module asl-tools/coord/tests/throughputTest
  :x [runTests]
  :i [(aslGateway/usageLedger :a ul) (asl-tools/coord/throughput :a tp)])

; (:m :ref THROUGHPUT-DAILY-TEST :do "six fixture lines through ul/callRowParse: two providers over two UTC days, one 429 row and one row with zero input, so the four grouped rows cover every field")
fn mkRow at: Int64 provider: String inT: Int64 cachedT: Int64 outT: Int64 outcome: String -> ul/CallRow
  (ul/CallRow :atMs at :profile "p1" :intent "construct" :alias "a" :provider provider :model "m"
    :inTokens inT :cachedTokens cachedT :outTokens outT :reasoningTokens 0 :ttftMs none :ms none
    :outcome outcome :charge 0 :tag none :temperature none :topP none :maxTokens none :effort none
    :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash ""
    :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn fixtureLines -> (List String)
  (list
    (ul/callRowLine (mkRow 0 "provA" 100 50 10 "ok"))
    (ul/callRowLine (mkRow 3600000 "provA" 100 50 10 "ok"))
    (ul/callRowLine (mkRow 7200000 "provB" 0 0 5 "ok"))
    (ul/callRowLine (mkRow 86400000 "provA" 100 0 10 "error-429"))
    (ul/callRowLine (mkRow 90000000 "provB" 200 50 20 "ok"))
    (ul/callRowLine (mkRow 93600000 "provB" 200 50 20 "ok")))

fn parsedRows -> (List (Result ul/CallRow String))
  (map (fn [(l String)] -> (Result ul/CallRow String) (ul/callRowParse l)) (fixtureLines))

fn fixtureRows -> (List ul/CallRow)
  (listFlatMap (fn [(r (Result ul/CallRow String))] -> (List ul/CallRow)
                 (match r ((ok x) (list x)) ((err _) (list)))) (parsedRows))

fn allParsed -> Bool
  (listAll? (fn [(r (Result ul/CallRow String))] -> Bool (ok? r)) (parsedRows))

fn emptyDay -> tp/ProviderDay
  (tp/ProviderDay :day "" :provider "" :calls 0 :ok 0 :rate429 0 :inTokens 0 :cachedTokens 0 :outTokens 0 :cacheShare 0.0)

fn rowAt rows: (List tp/ProviderDay) i: Int64 -> tp/ProviderDay
  (optionOr (listGet rows i) (emptyDay))

fn ! runTests -> Bool
  (let [(rows (tp/dailyByProvider (fixtureRows)))
        (r0 (rowAt rows 0))
        (r1 (rowAt rows 1))
        (r2 (rowAt rows 2))
        (r3 (rowAt rows 3))
        (line (tp/renderProviderDay r0))]
    (do
      (assert (allParsed) "all six fixture lines parse through ul/callRowParse")
      (assert (= (listLength rows) 4) "two providers over two UTC days make four rows")
      (assert (= r0.day "1970-01-01") "row 0 day is the first UTC day")
      (assert (= r0.provider "provA") "row 0 provider")
      (assert (= r0.calls 2) "row 0 calls")
      (assert (= r0.ok 2) "row 0 ok")
      (assert (= r0.rate429 0) "row 0 rate429")
      (assert (= r0.inTokens 200) "row 0 inTokens")
      (assert (= r0.cachedTokens 100) "row 0 cachedTokens")
      (assert (= r0.outTokens 20) "row 0 outTokens")
      (assert (= r0.cacheShare 0.5) "row 0 cacheShare is cached over input")
      (assert (= r1.day "1970-01-01") "row 1 day is the first UTC day")
      (assert (= r1.provider "provB") "row 1 provider")
      (assert (= r1.calls 1) "row 1 calls")
      (assert (= r1.ok 1) "row 1 ok")
      (assert (= r1.rate429 0) "row 1 rate429")
      (assert (= r1.inTokens 0) "row 1 inTokens is zero")
      (assert (= r1.cachedTokens 0) "row 1 cachedTokens")
      (assert (= r1.outTokens 5) "row 1 outTokens")
      (assert (= r1.cacheShare 0.0) "row 1 cacheShare is 0.0 when input is zero")
      (assert (= r2.day "1970-01-02") "row 2 day is the second UTC day")
      (assert (= r2.provider "provA") "row 2 provider")
      (assert (= r2.calls 1) "row 2 calls")
      (assert (= r2.ok 0) "row 2 ok is zero for the 429 row")
      (assert (= r2.rate429 1) "row 2 counts the 429 outcome")
      (assert (= r2.inTokens 100) "row 2 inTokens")
      (assert (= r2.cachedTokens 0) "row 2 cachedTokens")
      (assert (= r2.outTokens 10) "row 2 outTokens")
      (assert (= r2.cacheShare 0.0) "row 2 cacheShare")
      (assert (= r3.day "1970-01-02") "row 3 day is the second UTC day")
      (assert (= r3.provider "provB") "row 3 provider")
      (assert (= r3.calls 2) "row 3 calls")
      (assert (= r3.ok 2) "row 3 ok")
      (assert (= r3.rate429 0) "row 3 rate429")
      (assert (= r3.inTokens 400) "row 3 inTokens")
      (assert (= r3.cachedTokens 100) "row 3 cachedTokens")
      (assert (= r3.outTokens 40) "row 3 outTokens")
      (assert (= r3.cacheShare 0.25) "row 3 cacheShare")
      (assert (stringStartsWith? line "(:providerDay ") "renderProviderDay renders one ASN line")
      (assert (stringContains? line ":day \"1970-01-01\"") "the rendered line carries the day")
      (assert (stringContains? line ":provider \"provA\"") "the rendered line carries the provider")
      (assert (stringContains? line ":calls 2") "the rendered line carries the call count")
      (assert (stringContains? line ":cacheShare ") "the rendered line carries the cache share")
      true))
