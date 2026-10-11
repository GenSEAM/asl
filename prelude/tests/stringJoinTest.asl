(module prelude/tests/stringJoinTest :x [runTests] :i [])

fn joinLoop parts: (List String) sep: String k: Int64 total: Int64 -> Int64
  (if (= k 0) total
    (joinLoop parts sep (- k 1) (+ total (stringLength (stringJoin parts sep)))))

fn pairwisePass xs: (List String) -> (List String)
  (let [(folded (fold
                  (fn [(acc (Pair (List String) (Option String))) (x String)] -> (Pair (List String) (Option String))
                    (mt (pairSecond acc)
                      ((some left) (pair (cons (stringConcat left x) (pairFirst acc)) none))
                      ((none) (pair (pairFirst acc) (some x)))))
                  (pair (list) none)
                  xs))
        (merged (listReverse (pairFirst folded)))]
    (mt (pairSecond folded)
      ((some leftover) (listAppend merged (list leftover)))
      ((none) merged)))

fn pairwiseAll xs: (List String) -> String
  (if (listEmpty? xs) ""
    (if (listEmpty? (preludeTail xs)) (preludeHead xs) (pairwiseAll (pairwisePass xs))))

fn pairwiseJoin xs: (List String) sep: String -> String
  (if (listEmpty? xs) ""
    (pairwiseAll (cons (preludeHead xs) (map (fn [(x String)] -> String (stringConcat sep x)) (preludeTail xs)))))

fn pairwiseLoop parts: (List String) sep: String k: Int64 total: Int64 -> Int64
  (if (= k 0) total
    (pairwiseLoop parts sep (- k 1) (+ total (stringLength (pairwiseJoin parts sep)))))

fn ! elapsed f: (fn [] -> Int64) -> (Pair Int64 Int64)
  (let [(t0 (monotonicNs)) (v (f))] (pair (- (monotonicNs) t0) v))

fn ! runTests -> Bool
  (let [(parts (map (fn [i] (str "p" i)) (range 0 100000)))
        (chars (map (fn [i] (if (= (mod i 2) 0) "x" "y")) (range 0 100000)))
        (commaBytes (+ (fold (fn [acc p] (+ acc (stringLength p))) 0 parts) 99999))
        (commaTotal (joinLoop parts "," 2 0))
        (j1 (elapsed (fn [] (joinLoop chars "" 5 0))))
        (p1 (elapsed (fn [] (pairwiseLoop chars "" 5 0))))
        (p2 (elapsed (fn [] (pairwiseLoop chars "" 5 0))))
        (j2 (elapsed (fn [] (joinLoop chars "" 5 0))))
        (charTotal (pairSecond j1))
        (joinNs (min (pairFirst j1) (pairFirst j2)))
        (pairNs (max 1 (min (pairFirst p1) (pairFirst p2))))
        (seventeen (map (fn [i] (str i)) (range 0 17)))]
    (do
      (assert (= (stringJoin (list) ",") "") "joining no parts gives the empty string")
      (assert (= (stringJoin (list "solo") ",") "solo") "one part is returned without a separator")
      (assert (= (stringJoin (list "a" "b") ", ") "a, b") "two parts get one separator")
      (assert (= (stringJoin seventeen "-") "0-1-2-3-4-5-6-7-8-9-10-11-12-13-14-15-16") "17 parts cross a sixteen-part run and keep every separator")
      (assert (= (stringJoin (listTake parts 40) "") (fold (fn [acc p] (stringConcat acc p)) "" (listTake parts 40))) "40 parts with an empty separator equal the left-fold concatenation")
      (assert (= (stringJoin (list "" "x" "" "") "|") "|x||") "empty parts keep their separators")
      (assert (= (stringJoin (list "é" "ü" "ß") "→") "é→ü→ß") "multibyte parts and separator join bytewise")
      (assert (= (stringReplace "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r" "." "::") "a::b::c::d::e::f::g::h::i::j::k::l::m::n::o::p::q::r") "stringReplace joins through stringJoin")
      (assert (= (stringReverse "abcdefghijklmnopqrstuvwxyz") "zyxwvutsrqponmlkjihgfedcba") "stringReverse joins through stringJoin")
      (assert (= (stringUpper "join me") "JOIN ME") "stringUpper joins through stringJoin")
      (assert (= commaTotal (* 2 commaBytes)) (str "two 1e5-part comma joins give " (* 2 commaBytes) " bytes, got " commaTotal))
      (assert (= charTotal 500000) (str "five 1e5-char joins give 500000 bytes, got " charTotal))
      (assert (= (pairSecond p1) charTotal) "the pairwise reference builds the same 500000 bytes")
      (assert (< (* 2 joinNs) pairNs) (str "five 1e5-part joins take under half the pairwise fold's time (measured about a quarter on host, a third native), best of two in ABBA order: join " (/ joinNs 1000000) "ms pairwise " (/ pairNs 1000000) "ms"))
      true))
