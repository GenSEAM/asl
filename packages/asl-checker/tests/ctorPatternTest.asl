(module asl-checker/tests/ctorPatternTest
  :x [runTests]
  :i [])

fn host -> String
  "asl/host/out/asl-host"

fn asl1 -> String
  "asl/host/out/asl-host run asl/packages/asl-compiler/src/asl1.asl"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn moduleSource name: String decls: (List String) body: String -> String
  (stringJoin (listAppend (listAppend (list (str "(module " name) "  :x [main]" "  :i [])" "") decls)
                          (list "" "fn ! main -> (Result Int64 String)" (str "  (do (println " body ") (ok 0))")))
              "\n")

fn shapeDecls -> (List String)
  (list "(enum Shape (:c circle [(r Int64)] \"round\") (:c square [(s Int64)] \"box\"))"
        ""
        "fn area s: Shape -> Int64"
        "  (mt s ((circle r) (* r r)) ((square q) (* q q)))")

fn colorDecls arms: String -> (List String)
  (list "(enum Color (:c red [] \"r\") (:c green [] \"g\") (:c blue [] \"b\"))"
        ""
        "fn code c: Color -> Int64"
        (str "  (mt c " arms ")"))

fn fixtures -> (List (Pair String String))
  (list (pair "foreignBinder" (moduleSource "foreignBinder" (listAppend (shapeDecls) (list "" "fn pick s: Shape -> Int64" "  (mt s ((circle r) r) (other 7))"))
                                            "(str (pick (square 3)) \" \" (pick (circle 2)))"))
        (pair "foreignBinderUsed" (moduleSource "foreignBinderUsed" (listAppend (shapeDecls) (list "" "fn pick s: Shape -> Int64" "  (mt s ((circle r) r) (other (area other)))"))
                                                "(str (pick (square 3)) \" \" (pick (circle 2)))"))
        (pair "ownBare" (moduleSource "ownBare" (colorDecls "(red 1) (green 2) (blue 3)") "(str (code (red)) \" \" (code (green)) \" \" (code (blue)))"))
        (pair "ownBareMissing" (moduleSource "ownBareMissing" (colorDecls "(red 1) (green 2)") "(str (code (red)))"))
        (pair "optionBare" (moduleSource "optionBare" (list "fn get o: (Option Int64) -> Int64" "  (mt o ((some x) x) (none 0))")
                                         "(str (get (some 4)) \" \" (get (none)))"))
        (pair "unreachableNoneFirst" (moduleSource "unreachableNoneFirst" (listAppend (shapeDecls) (list "" "fn pick2 s: Shape -> Int64" "  (mt s (none 9) ((circle r) r) ((square q) q))"))
                                                    "(str (pick2 (circle 2)))"))
        (pair "unreachablePlainFirst" (moduleSource "unreachablePlainFirst" (listAppend (shapeDecls) (list "" "fn pick3 s: Shape -> Int64" "  (mt s (x 1) ((circle r) r) ((square q) q))"))
                                                     "(str (pick3 (circle 2)))"))
        (pair "noneBindsLabel" (moduleSource "noneBindsLabel" (list "fn label o: (Option String) -> String" "  \"lbl\"" "" "fn run x: (Option Int64) -> String" "  (mt x (none (label (none))) ((some v) (label (some \"x\"))))")
                                            "(run (none))"))
        (pair "unreachableSingle" (moduleSource "unreachableSingle" (listAppend (shapeDecls) (list "" "fn pick4 s: Shape -> Int64" "  (mt s (x 1) ((circle r) r))"))
                                                 "(str (pick4 (circle 2)))"))
        (pair "keywordLiteralNotCatchall" (moduleSource "keywordLiteralNotCatchall" (listAppend (shapeDecls) (list "" "fn pick5 s: Shape -> Int64" "  (mt s (:foo 1) ((circle r) r) ((square q) q))"))
                                                           "(str (pick5 (circle 2)) \" \" (pick5 (square 3)))"))
        (pair "elseKeywordRejected" (moduleSource "elseKeywordRejected" (listAppend (shapeDecls) (list "" "fn pick6 s: Shape -> Int64" "  (mt s (:else 1) ((circle r) r) ((square q) q))"))
                                                    "(str (pick6 (circle 2)) \" \" (pick6 (square 3)))")))

fn ! runsAs work: String name: String want: String -> Bool
  (let [(src (str work "/" name ".asl"))
        (checked (sh (str (host) " check " src)))
        (ran (sh (str (host) " run " src)))
        (checked1 (sh (str (asl1) " check " src)))
        (built (sh (str (asl1) " build " src " -o " work "/" name ".ll")))
        (linked (sh (str "/usr/bin/clang -Wno-override-module -x ir " work "/" name ".ll -x none asl/host/out/libaslrt.a -lm -o " work "/" name)))
        (native (sh (str work "/" name)))]
    (do
      (assert (= checked.exitCode 0) (str name ": asl-host check accepts it; " checked.stdout checked.stderr))
      (assert (= ran.exitCode 0) (str name ": asl-host run exits 0; " ran.stderr))
      (assert (= ran.stdout want) (str name ": asl-host run prints " want "; got " ran.stdout))
      (assert (= checked1.exitCode 0) (str name ": asl1 check accepts it; " checked1.stdout checked1.stderr))
      (assert (= built.exitCode 0) (str name ": asl1 builds it; " built.stdout built.stderr))
      (assert (= linked.exitCode 0) (str name ": clang links it; " linked.stderr))
      (assert (= native.stdout want) (str name ": the native binary prints " want "; got " native.stdout native.stderr))
      true))

fn ! checksAndRuns work: String name: String want: String -> Bool
  (let [(src (str work "/" name ".asl"))
        (checked (sh (str (host) " check " src)))
        (ran (sh (str (host) " run " src)))
        (checked1 (sh (str (asl1) " check " src)))]
    (do
      (assert (= checked.exitCode 0) (str name ": asl-host check accepts it; " checked.stdout checked.stderr))
      (assert (= ran.exitCode 0) (str name ": asl-host run exits 0; " ran.stderr))
      (assert (= ran.stdout want) (str name ": asl-host run prints " want "; got " ran.stdout))
      (assert (= checked1.exitCode 0) (str name ": asl1 check accepts it; " checked1.stdout checked1.stderr))
      true))

fn ! rejects label: String cmd: String text: String -> Bool
  (let [(r (sh cmd))
        (out (str r.stdout r.stderr))]
    (do
      (assert (!= r.exitCode 0) (str label ": exits non-zero"))
      (assert (stringContains? out text) (str label ": reports " text "; got " out))
      true))

fn countOccurrences out: String text: String -> Int64
  (- (listLength (stringSplit out text)) 1)

fn ! rejectsOnce label: String cmd: String text: String -> Bool
  (let [(r (sh cmd))
        (out (str r.stdout r.stderr))]
    (do
      (assert (!= r.exitCode 0) (str label ": exits non-zero"))
      (assert (= (countOccurrences out text) 1) (str label ": reports " text " exactly once; got " (stringFromInt64 (countOccurrences out text)) " in " out))
      true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (map (fn [(f (Pair String String))] -> Bool
             (do (assert (ok? (fileWrite (str work "/" (pairFirst f) ".asl") (pairSecond f))) (str (pairFirst f) ": source written")) true))
           (fixtures))
      (runsAs work "foreignBinder" "7 2\n")
      (runsAs work "foreignBinderUsed" "9 2\n")
      (runsAs work "ownBare" "1 2 3\n")
      (runsAs work "optionBare" "4 0\n")
      (runsAs work "noneBindsLabel" "lbl\n")
      (checksAndRuns work "keywordLiteralNotCatchall" "2 3\n")
      (rejects "ownBareMissing: asl-host check" (str (host) " check " work "/ownBareMissing.asl") "misses variant(s): blue")
      (rejects "ownBareMissing: asl1 check" (str (asl1) " check " work "/ownBareMissing.asl") "blue unhandled")
      (rejects "unreachableNoneFirst: asl-host check" (str (host) " check " work "/unreachableNoneFirst.asl") "ERR_UNREACHABLE_ARM")
      (rejects "unreachableNoneFirst: asl1 check" (str (asl1) " check " work "/unreachableNoneFirst.asl") "unreachable-arm")
      (rejects "unreachablePlainFirst: asl-host check" (str (host) " check " work "/unreachablePlainFirst.asl") "ERR_UNREACHABLE_ARM")
      (rejects "unreachablePlainFirst: asl1 check" (str (asl1) " check " work "/unreachablePlainFirst.asl") "unreachable-arm")
      (rejectsOnce "unreachableSingle: asl1 check" (str (asl1) " check " work "/unreachableSingle.asl") "unreachable-arm")
      (rejects "elseKeywordRejected: asl-host check" (str (host) " check " work "/elseKeywordRejected.asl") "ERR_ELSE_KEYWORD")
      (rejects "elseKeywordRejected: asl1 check" (str (asl1) " check " work "/elseKeywordRejected.asl") "else-keyword")
      (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
      true))
