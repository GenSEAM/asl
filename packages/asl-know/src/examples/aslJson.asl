(module asl-know/examples/aslJson :x [intField emitPair selfTest] :i [(asl-json/json :a j)])

fn intField src: String key: String -> Int64
  (mt (j/jsonParse src)
    ((err _) -1)
    ((ok v)
      (mt (j/jsonGet v key)
        ((none) -2)
        ((some x) (mt x ((j/jint n) n) (_ -3))))))

fn emitPair k: String v: String -> String
  (j/jsonEmit (j/jobj [(pair k (j/jstr v))]))

fn selfTest -> Bool
  (and (= (intField "{\"a\": 4}" "a") 4) (= (intField "{" "a") -1) (= (intField "{\"a\": 4}" "b") -2)
       (ok? (j/jsonParse (emitPair "k" "v"))))
