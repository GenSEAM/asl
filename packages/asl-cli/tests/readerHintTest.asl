(module asl-cli/tests/readerHintTest :x [runTests] :i [(asl/packages/asl-cli/src/verify :a verify) (asl-checker/checkCached :a cc)])

fn ! tempRoot -> String
  (str "/tmp/readerHintTest_" (stringFromInt64 (monotonicNs)))

; (:m :do "renders what asl check and the asl test/run checker gate print for a file: the checker's own diagnostics through formatDiagsHinted!")
fn ! rendered! dir: String name: String text: String -> String
  (let [(p (str dir "/" name))
        (_ (fileWrite p text))]
    (match (pairFirst (cc/checkFileCached! p (verify/checkRoots) (cc/emptyCache)))
      ((err e) (str "ERR " e))
      ((ok v) (verify/formatDiagsHinted! v.diags))))

fn strayText -> String
  "(module t/stray :x [f g] :i [])\n\nfn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0)))\n\nfn g x: Int64 -> Int64\n  (+ x 1)\n"

fn typeErrText -> String
  "(module t/typed :x [f] :i [])\n\nfn f x: Int64 -> Int64\n  (stringLength x)\n"

fn checkStray dir: String r: String -> Bool
  (do
    (assert (stringContains? r (str dir "/stray.asl:5:")) (str "the reader diagnostic keeps its path:line:col form: " r))
    (assert (stringContains? r "unmatched ')'") (str "the checker reports the reader's balance error: " r))
    (assert (stringContains? r (str "(:indentFix :file \"" dir "/stray.asl\" :indent ((:delete \")\" :line 5 :col 22 :stray true))")) (str "followed by the closer edit indentation implies: " r))
    (assert (stringContains? r ":by :indent :apply true)") (str "and the form that stages it: " r))
    true)

fn checkTyped r: String -> Bool
  (do
    (assert (not (stringEmpty? r)) (str "a type error is still reported: " r))
    (refute (stringContains? r ":indentFix") (str "a file that reads has no indent hint: " r))
    true)

fn ! runTests -> Bool
  (let [(dir (tempRoot))
        (_ (dirCreate dir))
        (r1 (rendered! dir "stray.asl" (strayText)))
        (r2 (rendered! dir "typed.asl" (typeErrText)))
        (_ (pathRemove dir))]
    (do
      (refute (fileExists? dir) "the scratch directory is removed before any assert can stop the test")
      (assert (checkStray dir r1) "checkStray")
      (assert (checkTyped r2) "checkTyped")
      true))
