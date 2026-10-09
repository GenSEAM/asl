(module aslMem/testCompact :x [runTests] :i [(aslMem/compact :a c)])

fn ! runTests -> Bool
  (let [(vRec (c/encodeVectorFrame "v1" "hello" (list 1.0 2.0 3.0)))] (assert (= vRec.id "v1") "id is v1") (assert (= vRec.frameType "vector") "type is vector") (assert (stringContains? vRec.payload "(:vector") "payload is asn") (println vRec.payload) (assert (stringContains? vRec.payload "1.0 2.0 3.0") "payload has dense list") true)
