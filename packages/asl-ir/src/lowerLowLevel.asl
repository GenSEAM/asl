(module asl-ir/lowerLowLevel
  :x [kindOfAnnotation sizedOpName sizedBuiltins sizedKindName opBase sizedOps sizedKinds]
  :i [(asl-checker/numKinds :a nk)])

; (:m :do "first pure slice of the sized lowering: kindOfAnnotation reads a type annotation through numKinds intKindCode with Int32 folded to I32, sizedOpName names the builtin asl-target-llvm/lowLevelRoute routes for an op and kind; the hub's sizedRt table is empty at LL-ROUTE-HUB, so sizedBuiltins mirrors the op-base plus kind-name convention and the test compares the mirror with the hub's sized table")

fn sizedKindName kind: Int64 -> (Option String)
  (cond
    ((= kind 1) (some "U8"))
    ((= kind 2) (some "I8"))
    ((= kind 3) (some "U16"))
    ((= kind 4) (some "I16"))
    ((= kind 5) (some "U32"))
    ((= kind 6) (some "I32"))
    ((= kind 7) (some "U64"))
    ((= kind 0) (some "I64"))
    (else (none)))

fn opBase op: String -> (Option String)
  (cond
    ((= op "+") (some "add"))
    ((= op "-") (some "sub"))
    ((= op "*") (some "mul"))
    ((= op "&") (some "and"))
    ((= op "|") (some "or"))
    ((= op "^") (some "xor"))
    ((= op "~") (some "not"))
    ((= op "<<") (some "shl"))
    ((= op ">>") (some "shr"))
    ((= op "addWrap") (some "addWrap"))
    ((= op "subWrap") (some "subWrap"))
    ((= op "mulWrap") (some "mulWrap"))
    ((= op "rotateLeft") (some "rotateLeft"))
    ((= op "rotateRight") (some "rotateRight"))
    (else (none)))

fn sizedOps -> (List String)
  (list "+" "-" "*" "&" "|" "^" "~" "<<" ">>" "addWrap" "subWrap" "mulWrap" "rotateLeft" "rotateRight")

fn sizedKinds -> (List Int64)
  (list 0 1 2 3 4 5 6 7)

fn kindOfAnnotation typeText: String -> (Option Int64)
  (let [(t (if (= typeText "Int32") "I32" typeText))
        (c (nk/intKindCode t))]
    (if (>= c 0) (some c) (none)))

fn sizedOpName op: String kind: Int64 -> (Option String)
  (match (opBase op)
    ((none) (none))
    ((some b) (optionMap (fn [(k String)] -> String (str b k)) (sizedKindName kind))))

fn sizedBuiltins -> (List (Pair String (Pair Int64 String)))
  (fold (fn [(acc (List (Pair String (Pair Int64 String)))) (op String)] -> (List (Pair String (Pair Int64 String)))
          (fold (fn [(acc2 (List (Pair String (Pair Int64 String)))) (k Int64)] -> (List (Pair String (Pair Int64 String)))
                  (match (sizedOpName op k)
                    ((some n) (listAppend acc2 (list (pair op (pair k n)))))
                    ((none) acc2)))
                acc (sizedKinds)))
        (list) (sizedOps))
