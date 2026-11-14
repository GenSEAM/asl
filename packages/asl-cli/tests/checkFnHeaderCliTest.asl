(module asl-cli/tests/checkFnHeaderCliTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a run)])

; (:m :ref FABLE-LANG-02 :do "real asl check on each non-canonical fn header shape exits non-zero and prints the (:headerFix) line of that very function; a correct file prints none")

fn ! scratchDir! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/checkFnHeaderCliTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn ! checkFile! binary: String root: String dir: String name: String text: String -> run/Done
  (let [(path (str dir "/" name))
        (_ (fileWrite path text))]
    (run/runOneLimited (run/job (list binary "check" path) root (list "PATH=/usr/bin:/bin" (str "HOME=" root) "TMPDIR=/tmp")) (run/limits 120 16)))

fn expectFix d: run/Done header: String -> Bool
  (do (assert (= d.verdict "exit") (str "check ended on its own: " d.out))
      (assert (!= d.exit 0) (str "check exits non-zero: " d.out))
      (assert (stringContains? d.out (str "(:headerFix :file \"") ) (str "a headerFix line is printed: " d.out))
      (assert (stringContains? d.out (str " :line 1 :header \"" header "\" ")) (str "the canonical header of that function on line 1, wanted " header ", got: " d.out))
      true)

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (dir (scratchDir!))
        (made (dirCreate dir))
        (built (nt/prepareRun "asl/packages/asl-cli/src/native.asl" (nt/fingerprint)))]
    (do
      (assert (some? built.binary) (str "the native cli builds: " built.reason))
      (assert (ok? made) "scratch dir created")
      (let [(bin (optionOr built.binary ""))
            (dDefn (checkFile! bin root dir "defn.asl" "(defn add [a b]\n  (+ a b))\n"))
            (dDefine (checkFile! bin root dir "define.asl" "(define (add a b)\n  (+ a b))\n"))
            (dDef (checkFile! bin root dir "def.asl" "(def add [a b]\n  (+ a b))\n"))
            (dWrapped (checkFile! bin root dir "wrapped.asl" "(fn add [a: Int64 b: String] -> Bool\n  true)\n"))
            (dPy (checkFile! bin root dir "py.asl" "def add(a: Int64, b: String) -> Bool:\n  return true\n"))
            (dBody (checkFile! bin root dir "body0.asl" "fn add a: Int64 b: String -> Bool\nreturn true\n"))
            (dGood (checkFile! bin root dir "good.asl" "(module test/clean :x [good] :i [])\n\nfn good a: Int64 -> Int64\n  a\n"))
            (removed (pathRemove dir))]
        (do
          (assert (ok? removed) "scratch dir removed")
          (assert (expectFix dDefn "fn add a: T b: T -> R") "defn")
          (assert (expectFix dDefine "fn add a: T b: T -> R") "define")
          (assert (expectFix dDef "fn add a: T b: T -> R") "def")
          (assert (expectFix dWrapped "fn add a: Int64 b: String -> Bool") "wrapped")
          (assert (expectFix dPy "fn add a: Int64 b: String -> Bool") "python")
          (assert (expectFix dBody "fn add a: Int64 b: String -> Bool") "column-0 body")
          (assert (= dGood.exit 0) (str "a correct file passes check: " dGood.out))
          (refute (stringContains? dGood.out "headerFix") (str "a correct file prints no headerFix line: " dGood.out))
          true))))
