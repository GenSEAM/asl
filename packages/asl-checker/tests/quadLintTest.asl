(module asl-checker/tests/quadLintTest
  :x [runTests]
  :i [(asl-parser/ast :a a) (asl-checker/lint :a lint)])

fn quadraticSrc -> String
  "(module q/quad :x [walkByIndex])

fn walkByIndex xs: (List Int64) i: Int64 -> Int64
  (if (>= i (listLength xs)) 0
    (+ (optionOr (listGet xs i) 0) (walkByIndex xs (+ i 1))))
"

fn headTailSrc -> String
  "(module q/walk :x [sumList])

fn sumList xs: (List Int64) -> Int64
  (mt (listHead xs)
    ((none) 0)
    ((some h) (+ h (sumList (optionOr (listTail xs) (list))))))
"

fn singleGetSrc -> String
  "(module q/one :x [third])

fn third xs: (List Int64) n: Int64 -> Int64
  (optionOr (listGet xs n) 0)
"

fn hitsFor src: String -> (List lint/LintHit)
  (mt (a/parseForChecker src)
    ((ok forms) (lint/lintModule forms "probe.asl"))
    ((err _) (list)))

fn ! testFlagsListGetByCounter -> Bool
  (let [(hits (hitsFor (quadraticSrc)))]
    (do (assert (= (listLength hits) 1) (str "exactly one hit on the counter-walk fn, got " (listLength hits)))
        (mt (listHead hits)
          ((some h) (do (assert (= h.code "LINT_QUADRATIC_LISTGET") (str "code is LINT_QUADRATIC_LISTGET, got " h.code))
                        (assert (= h.fnName "walkByIndex") (str "names the offending fn, got " h.fnName))
                        (assert (stringContains? h.message "listGet") "message mentions listGet")
                        (assert (stringContains? h.message "rewrite") "message suggests a rewrite")
                        true))
          ((none) (do (assert false "a hit is present") false)))
        true))

fn ! testDoesNotFlagHeadTailWalk -> Bool
  (let [(hits (hitsFor (headTailSrc)))]
    (do (assert (listEmpty? hits) (str "a listHead/listTail walk is not flagged, got " (listLength hits)))
        true))

fn ! testDoesNotFlagSingleListGet -> Bool
  (let [(hits (hitsFor (singleGetSrc)))]
    (do (assert (listEmpty? hits) (str "a single non-recursive listGet is not flagged, got " (listLength hits)))
        true))

fn ! runTests -> Bool
  (do (assert (testFlagsListGetByCounter) "flags the synthetic listGet-by-counter fn")
      (assert (testDoesNotFlagHeadTailWalk) "does not flag a listHead/listTail walk")
      (assert (testDoesNotFlagSingleListGet) "does not flag a single listGet")
      true)
