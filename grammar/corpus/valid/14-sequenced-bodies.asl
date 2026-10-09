"A multi-expression body in every position the grammar admits one: a function"

"body, a `let` body, a `cond` clause, an `:else` clause, a `match` arm and a"

"lambda body. Each non-final expression is a `println`, so an evaluator that"

"skips one without emitting it prints a line short."

(module seqDemo :x [main tally])

fn tally xs: (List Int64) -> Int64
  (fold (fn [(acc Int64) (n Int64)] (+ acc n)) 0 xs)

fn ! inFunction -> (Result Int64 IoError)
  (do (println "function-1") (ok 1))

fn ! inLet -> (Result Int64 IoError)
  (let [(n 2)] (println "let-1") (ok n))

fn ! inCond flag: Bool -> (Result Int64 IoError)
  (cond (flag (println "cond-1") (ok 3)) (else (println "else-1") (ok 4)))

fn ! inCondBare flag: Bool -> Int64
  (cond (flag (println "cond-bare") 6) (else (println "else-bare") 7))

fn ! inMatch r: (Result Int64 String) -> (Result Int64 IoError)
  (match r ((ok n) (println "match-ok-1") (ok n)) ((err e) (println "match-err-1") (ok 0)))

fn ! inLambda xs: (List Int64) -> (List Int64)
  (map (fn [(x Int64)] (println "lambda-1") (* x 10)) xs)

fn ! main args: (List String) -> (Result Unit IoError)
  (let [(a (resultOr (inFunction) 0)) (b (resultOr (inLet) 0)) (c (resultOr (inCond true) 0)) (d (resultOr (inCond false) 0)) (e (resultOr (inMatch (ok 5)) 0)) (f (resultOr (inMatch (err "no")) 0)) (g (inLambda (list 1 2))) (h (inCondBare true)) (i (inCondBare false))] (println (stringFromInt64 (+ a (+ b (+ c (+ d (+ e f))))))) (println (stringFromInt64 (+ h i))) (println (stringFromInt64 (tally g))) (ok ()))
