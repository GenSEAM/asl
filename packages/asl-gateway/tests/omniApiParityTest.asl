(module aslGateway/tests/omniApiParityTest
  :x [runTests]
  :i [(omniApi :a om)
      (cockpit :a ck)
      (asl-http/http11 :a h)])

(schema Exchange
  (:f n Int64) (:f method String) (:f target String) (:f nowMs Int64) (:f body String)
  (:f status Int64) (:f headers (List (Pair String String))) (:f response String))

fn check! b: Bool msg: String -> Bool
  (if b (do (assert b msg) true) (do (eprintln (str "FAIL: " msg)) (assert false msg) false))

fn fixturePath -> String
  "asl/packages/asl-gateway/tests/omniApiFixture.asn"

fn propIn props: (List (Pair String ck/AsnVal)) key: String -> (Option ck/AsnVal)
  (mt (listHead props)
    ((none) (none))
    ((some p) (if (= (pairFirst p) key) (some (pairSecond p)) (propIn (preludeTail props) key))))

fn textOf v: (Option ck/AsnVal) -> String
  (mt v ((some x) (mt x ((ck/asnText s) s) (_ ""))) ((none) ""))

fn intOf v: (Option ck/AsnVal) -> Int64
  (mt v ((some x) (mt x ((ck/asnAtom s) (optionOr (stringToInt64 s) -1)) (_ -1))) ((none) -1))

fn headerPairs v: (Option ck/AsnVal) -> (List (Pair String String))
  (mt v
    ((some x)
      (mt x
        ((ck/asnList items)
          (map (fn [(item ck/AsnVal)] -> (Pair String String)
                 (mt item
                   ((ck/asnList kv) (pair (textOf (listGet kv 0)) (textOf (listGet kv 1))))
                   (_ (pair "" ""))))
               items))
        (_ (list))))
    ((none) (list)))

fn headed? v: ck/AsnVal head: String -> Bool
  (mt v
    ((ck/asnList items) (mt (listHead items) ((some x) (mt x ((ck/asnAtom a) (= a head)) (_ false))) ((none) false)))
    (_ false))

fn toExchange v: ck/AsnVal -> Exchange
  (let [(p (mt (ck/asnProps v (some ":exchange")) ((ok ps) ps) ((err _) (list))))]
    (Exchange :n (intOf (propIn p "n")) :method (textOf (propIn p "method")) :target (textOf (propIn p "target"))
              :nowMs (intOf (propIn p "nowMs")) :body (textOf (propIn p "body")) :status (intOf (propIn p "status"))
              :headers (headerPairs (propIn p "headers")) :response (textOf (propIn p "response"))))

fn headersText hs: (List (Pair String String)) -> String
  (stringJoin (map (fn [(p (Pair String String))] -> String (str (pairFirst p) ": " (pairSecond p))) hs) " | ")

fn replay! s: om/OmniState xs: (List Exchange) -> Bool
  (mt (listHead xs)
    ((none) true)
    ((some x)
      (let [(id (str "exchange " (stringFromInt64 x.n) " " x.method " " x.target))]
        (mt (om/omniDispatch s x.method x.target x.body x.nowMs)
          ((none) (check! false (str id " is routed")))
          ((some r)
            (mt r
              ((err e) (check! false (str id " answers: " e)))
              ((ok reply)
                (let [(resp reply.response)
                      (gotHeaders resp.headers.entries)
                      (okStatus (check! (= resp.statusCode x.status) (str id " status " (stringFromInt64 resp.statusCode) " = " (stringFromInt64 x.status))))
                      (okHeaders (check! (= (headersText gotHeaders) (headersText x.headers)) (str id " headers [" (headersText gotHeaders) "] = [" (headersText x.headers) "]")))
                      (okBody (check! (= resp.body x.response) (str id " body " resp.body " = " x.response)))]
                  (and (and okStatus okHeaders) (and okBody (replay! reply.state (preludeTail xs))))))))))))

fn zeroKey -> om/Word64
  (om/Word64 :hi 0 :lo 0)

fn testForeignRoutes! -> Bool
  (let [(s (om/emptyOmniState (zeroKey) (zeroKey)))
        (foreign (list (pair "GET" "/v1/models") (pair "GET" "/api/asl/status") (pair "GET" "/cockpit/api/mem")
                       (pair "POST" "/api/asl/update") (pair "POST" "/api/asl/search") (pair "POST" "/v1/chat/completions")
                       (pair "POST" "/api/asl/project/p1") (pair "GET" "/api/asl/browser/session/spawn")
                       (pair "GET" "/api/asl/ingest") (pair "PUT" "/api/asl/ingest")))
        (unrouted (filter (fn [(p (Pair String String))] -> Bool (none? (om/omniDispatch s (pairFirst p) (pairSecond p) "(:x)" 0))) foreign))]
    (check! (= (listLength unrouted) (listLength foreign)) (str (stringFromInt64 (listLength unrouted)) " of " (stringFromInt64 (listLength foreign)) " foreign routes unrouted")))

fn ! runTests -> Bool
  (mt (fileReadString (fixturePath))
    ((err e) (check! false (str "read fixture: " e)))
    ((ok text)
      (mt (ck/asnReadText text)
        ((err e) (check! false (str "parse fixture: " e)))
        ((ok forms)
          (let [(header (listHead (filter (fn [(v ck/AsnVal)] -> Bool (headed? v ":omniApiFixture")) forms)))
                (declared (mt header
                            ((some hv) (intOf (propIn (mt (ck/asnProps hv (some ":omniApiFixture")) ((ok ps) ps) ((err _) (list))) "exchanges")))
                            ((none) -1)))
                (xs (map toExchange (filter (fn [(v ck/AsnVal)] -> Bool (headed? v ":exchange")) forms)))
                (okCount (check! (and (> (listLength xs) 0) (= (listLength xs) declared))
                                (str (stringFromInt64 (listLength xs)) " exchanges read, header declares " (stringFromInt64 declared))))
                (okReplay (replay! (om/emptyOmniState (zeroKey) (zeroKey)) xs))
                (okForeign (testForeignRoutes!))]
            (and (and okCount okReplay) okForeign))))))
