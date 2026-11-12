(module aslGateway/tests/gwErrFixTest
  :x [runTests]
  :i [(asl-json/json :a j)
      (pyText :a pt)
      (search :a srch)
      (research :a rs)])

fn noteOf v: j/Json -> String
  (match (pt/jget v "note")
    ((some x) (match x ((j/jstr s) s) (_ "")))
    ((none) ""))

fn crawledOf v: j/Json -> Bool
  (match (pt/jget v "crawled")
    ((some x) (match x ((j/jbool b) b) (_ true)))
    ((none) true))

fn ! runTests -> Bool
  (let [(fallback (j/jstr ""))
        (transport (rs/fetchResult "http://example.invalid/x" fallback
                    (srch/httpFail (pt/pyErr "URLError" "connection refused") false)
                    (err (pt/pyErr "URLError" "connection refused"))))
        (decode (rs/fetchResult "http://example.invalid/y" fallback
                  (srch/httpResp 200 "OK" (list) "body")
                  (err (pt/pyErr "UnicodeDecodeError" "invalid utf-8"))))]
    (do
      (assert (not (crawledOf transport)) "a transport failure is not reported as a crawled page")
      (assert (stringContains? (noteOf transport) "connection refused") (str "the transport error text is carried into the note: " (noteOf transport)))
      (assert (stringContains? (noteOf transport) "fetchTimeoutOrError") "the transport note keeps its reason prefix")
      (assert (not (crawledOf decode)) "a decode failure is not reported as a crawled page")
      (assert (stringContains? (noteOf decode) "invalid utf-8") (str "the decode error text is carried into the note: " (noteOf decode)))
      true))
