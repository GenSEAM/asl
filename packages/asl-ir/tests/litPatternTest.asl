(module asl-ir/tests/litPatternTest :x [runTests] :i [])

(enum Shape (:c Circle [(r Int64)] "a circle") (:c Rect [(w Int64) (h Int64)] "a rectangle") (:c Named [(name String) (inner Shape)] "a named shape"))

; (:m :ref LOWER-LITPAT :do "native lowering of constructor arms with literal or constructor payload patterns, first match wins, a miss falls through to the later arms; every case runs natively under asl test")
fn tag r: (Result String String) -> String
  (mt r ((ok "0") "") ((ok m) (str ":rc=" m)) ((err _) ":rc=invalid"))

fn sizeOf o: (Option Int64) -> String
  (mt o ((some 0) "zero") ((some 1) "one") ((some n) (str "many " n)) ((none) "nothing"))

fn area s: Shape -> Int64
  (mt s
    ((Rect 0 _) 0)
    ((Rect w 1) w)
    ((Rect w h) (* w h))
    ((Named "unit" _) 1)
    ((Named _ (Circle 0)) -1)
    ((Named _ inner) (area inner))
    ((Circle r) (* 3 (* r r))))

fn pairKind p: (Option (Pair Int64 String)) -> String
  (mt p
    ((some (pair 1 "a")) "one-a")
    ((some (pair 1 b)) (str "one-" b))
    ((some (pair n _)) (str "n" n))
    (_ "empty"))

fn kw k: (Option Keyword) -> Int64
  (mt k ((some :left) 1) ((some :right) 2) (_ 0))

fn ! runTests -> Bool
  (do (assert (= (tag (ok "0")) "") "ok \"0\" takes the literal arm")
      (assert (= (tag (ok "1")) ":rc=1") "ok \"1\" falls through to the binding arm")
      (assert (= (tag (err "x")) ":rc=invalid") "err keeps its own arm")
      (assert (= (sizeOf (some 0)) "zero") "some 0 matches the first literal")
      (assert (= (sizeOf (some 1)) "one") "some 1 skips the first literal arm")
      (assert (= (sizeOf (some 7)) "many 7") "some 7 falls through both literal arms")
      (assert (= (sizeOf (none)) "nothing") "none reaches its arm past the some arms")
      (assert (= (area (Rect 0 9)) 0) "a literal first field")
      (assert (= (area (Rect 5 1)) 5) "a literal second field after a bound first")
      (assert (= (area (Rect 4 3)) 12) "all bound")
      (assert (= (area (Named "unit" (Rect 9 9))) 1) "a string literal field")
      (assert (= (area (Named "c" (Circle 0))) -1) "a nested constructor with a literal")
      (assert (= (area (Named "c" (Circle 2))) 12) "a nested miss falls through to the bound arm")
      (assert (= (area (Circle 1)) 3) "the last arm")
      (assert (= (pairKind (some (pair 1 "a"))) "one-a") "a nested pair of literals")
      (assert (= (pairKind (some (pair 1 "z"))) "one-z") "a nested pair with one literal")
      (assert (= (pairKind (some (pair 4 "z"))) "n4") "a nested pair bound")
      (assert (= (pairKind (none)) "empty") "the wildcard arm")
      (assert (= (kw (some :right)) 2) "a keyword payload literal")
      (assert (= (kw (some :up)) 0) "an unmatched keyword falls to the wildcard")
      true)
