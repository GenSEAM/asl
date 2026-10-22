(module asl-compiler/monad
  :x [optionMap option-and-then option-unwrap-or resultMap resultMapErr result-and-then result-unwrap-or]
  :i [])

fn optionMap opt: (Option A) f: (fn [A] -> B) -> (Option B)
  (match opt
    ((some v) (some (f v)))
    ((none) (none)))

fn option-and-then opt: (Option A) f: (fn [A] -> (Option B)) -> (Option B)
  (match opt
    ((some v) (f v))
    ((none) (none)))

fn option-unwrap-or opt: (Option A) fallback: A -> A
  (match opt
    ((some v) v)
    ((none) fallback))

fn resultMap res: (Result T E) f: (fn [T] -> U) -> (Result U E)
  (match res
    ((ok v) (ok (f v)))
    ((err e) (err e)))

fn resultMapErr res: (Result T E) f: (fn [E] -> F) -> (Result T F)
  (match res
    ((ok v) (ok v))
    ((err e) (err (f e))))

fn result-and-then res: (Result T E) f: (fn [T] -> (Result U E)) -> (Result U E)
  (match res
    ((ok v) (f v))
    ((err e) (err e)))

fn result-unwrap-or res: (Result T E) fallback: T -> T
  (match res
    ((ok v) v)
    ((err _) fallback))
