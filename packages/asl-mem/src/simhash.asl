(module aslMem/simhash :x [fnv1a64 simhash64 hammingDistance simhashSimilarity stripPunct tokenizeWords] :i [(vfs :a v)])

fn toU64 x: I64 -> I64
  x

fn bitXor64 a: I64 b: I64 -> I64
  (^ a b)

fn fnv1a64 s: Str -> I64
  (let [bs (stringToBytes s)] (preludeFnvStep bs 0 (bytesLength bs) -3750763034362895579))

fn hammingDistance h1: I64 h2: I64 -> I64
  (popcount64 (^ h1 h2))

fn simhashSimilarity h1: I64 h2: I64 -> F64
  (let [(dist (hammingDistance h1 h2)) (distF (int64ToFloat64 dist))] (- 1.0 (/ distF 64.0)))

fn stripPunct text: Str -> Str
  (let [(s1 (stringReplace text "." " ")) (s2 (stringReplace s1 "," " ")) (s3 (stringReplace s2 ";" " ")) (s4 (stringReplace s3 ":" " ")) (s5 (stringReplace s4 "!" " ")) (s6 (stringReplace s5 "?" " ")) (s7 (stringReplace s6 "\"" " ")) (s8 (stringReplace s7 "'" " ")) (s9 (stringReplace s8 "(" " ")) (s10 (stringReplace s9 ")" " ")) (s11 (stringReplace s10 "[" " ")) (s12 (stringReplace s11 "]" " ")) (s13 (stringReplace s12 "{" " ")) (s14 (stringReplace s13 "}" " ")) (s15 (stringReplace s14 "-" " ")) (s16 (stringReplace s15 "_" " ")) (s17 (stringReplace s16 "/" " ")) (s18 (stringReplace s17 "\\" " ")) (s19 (stringReplace s18 "\n" " "))] (stringReplace s19 "\t" " "))

fn tokenizeWords text: Str -> (List Str)
  (let [(cleaned (stripPunct text)) (lowered (stringLower cleaned)) (rawTokens (stringSplit lowered " ")) (trimmed (map (fn [(t Str)] -> Str (stringTrim t)) rawTokens))] (filter (fn [(t Str)] -> Bool (> (stringLength t) 0)) trimmed))

fn bitPower b: Int64 -> Int64
  (cond
    ((<= b 0) 1)
    ((>= b 63) -9223372036854775808)
    (else (* 2 (bitPower (- b 1)))))

fn simhashAccumulate hashes: (List I64) bit: Int64 -> Int64
  (fold (fn [acc h]
    (let [isSet (!= (& h (bitPower bit)) 0)]
      (+ acc (if isSet 1 -1)))) 0 hashes)

fn simhashStep hashes: (List I64) bit: Int64 acc: Int64 -> Int64
  (if (>= bit 64) acc
    (let [weight (simhashAccumulate hashes bit)
          nextAcc (cond
                    ((<= weight 0) acc)
                    ((= bit 63) (+ acc -9223372036854775808))
                    (else (+ acc (bitPower bit))))]
      (simhashStep hashes (+ bit 1) nextAcc)))

fn simhash64 text: Str -> I64
  (let [tokens (tokenizeWords text)]
    (if (listEmpty? tokens) 0
      (let [hashes (map (fn [(t Str)] -> I64 (fnv1a64 t)) tokens)]
        (simhashStep hashes 0 0))))

