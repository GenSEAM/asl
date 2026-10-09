(module asl-parser/tests/printReparseLib
  :x [allCorpusFiles!
      shardFiles
      expectedShardCount
      emptyCorpusStats!
      emptyCorpusStatsWith
      verifyCorpusFile!
      reportCorpusStats!
      testMutantGuards
      isPrintReparseFile!
      knownMisparseReason
      CorpusStats]
  :i [(ast :a a)
      (astConverter :a ac)
      (astPrinter :a ap)
      (reader :a rd)
      (asl-syntax/tests/asl/layoutCorpusLib :a lib)
      (asl-syntax/tests/asl/corpusCache :a cc)
      (asl-parser/tests/printHostValidScope :a scope)])

fn knownMisparseReason path: String -> (Option String)
  (cond
    ((= path "asl/grammar/tests/corpusTest.asl")
     (some "reference parser misparses: dedent defect merges scanChar body into schema Scan field list"))
    ((= path "asl/packages/asl-regex/src/regex.asl")
     (some "reference parser misparses: dedent defect corrupts enum Ast case list"))
    ((= path "asl/packages/asl-syntax/src/core/corpus.asl")
     (some "reference parser misparses: dedent defect swaps fn runCorpusOnFiles body with an adjacent fn"))
    ((= path "asl/packages/asl-syntax/src/xml.asl")
     (some "reference parser misparses: dedent defect swaps fn parseTag body with an adjacent fn"))
    ((= path "asl/packages/asl-transpile/src/yamlTranspile.asl")
     (some "reference parser misparses: dedent defect corrupts enum YamlLineKind case list"))
    ((= path "tests/acceptance/r1Host/reader/surfaceTest.asl")
     (some "reference parser misparses: dedent defect drops enum Shape case list and schema Pt fields, collapsing 8 top forms into 3"))
    (else (none)))

fn isPrintReparseFile! path: String -> Bool
  (and (not (lib/isParenOrInvalidFile path))
       (and (not (intentionallyHostRejected? path))
            (none? (knownMisparseReason path))))

fn intentionallyHostRejected? path: String -> Bool
  (scope/intentionallyRejected? path)

fn parseFileList stdout: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit stdout "\n"))

fn allCorpusFiles! -> (Result (List String) String)
  (let [(cmdRes (processRun "git ls-files '*.asl'"))]
    (if (!= cmdRes.exitCode 0)
      (err (str "git ls-files exited " (stringFromInt64 cmdRes.exitCode)))
      (ok (filter (fn [(p String)] -> Bool (isPrintReparseFile! p)) (parseFileList cmdRes.stdout)))))

fn shardFiles files: (List String) n: Int64 k: Int64 -> (List String)
  (lib/shardFiles files n k)

fn expectedShardCount total: Int64 n: Int64 k: Int64 -> Int64
  (lib/expectedShardCount total n k)

fn hasDigit? s: String -> Bool
  (fold (fn [(acc Bool) (c String)] -> Bool (or acc (stringContains? "0123456789" c))) false (stringChars s))

fn isFloatStr? s: String -> Bool
  (and (hasDigit? s) (or (stringContains? s ".") (or (stringContains? s "e") (stringContains? s "E"))))

fn atomEquivalent? x: String y: String -> Bool
  (or (= x y)
      (and (isFloatStr? x)
           (and (isFloatStr? y)
                (and (some? (stringToFloat64 x)) (= (stringToFloat64 x) (stringToFloat64 y))))))

fn itemsEquivalent? xs: (List rd/SExpr) ys: (List rd/SExpr) -> Bool
  (if (!= (listLength xs) (listLength ys))
    false
    (fold (fn [(acc Bool) (p (Pair rd/SExpr rd/SExpr))] -> Bool
            (and acc (sexprEquivalent? (pairFirst p) (pairSecond p))))
          true (zip xs ys)))

fn dropListHead items: (List rd/SExpr) -> (Option (List rd/SExpr))
  (mt (listHead items)
    ((some h) (if (and (rd/isAtom? h) (= (rd/sexprHead h) "list")) (some (optionOr (listTail items) (list))) (none)))
    ((none) (none)))

fn vectListEquivalent? vItems: (List rd/SExpr) lItems: (List rd/SExpr) -> Bool
  (mt (dropListHead lItems)
    ((some rest) (itemsEquivalent? vItems rest))
    ((none) false))

fn sexprEquivalent? x: rd/SExpr y: rd/SExpr -> Bool
  (mt x
    ((rd/sexprAtom vx)
     (mt y
       ((rd/sexprAtom vy) (atomEquivalent? vx vy))
       (_ false)))
    ((rd/sexprList lx)
     (mt y
       ((rd/sexprList ly) (itemsEquivalent? lx ly))
       ((rd/sexprVect vy) (vectListEquivalent? vy lx))
       (_ false)))
    ((rd/sexprVect vx)
     (mt y
       ((rd/sexprVect vy) (itemsEquivalent? vx vy))
       ((rd/sexprList ly) (vectListEquivalent? vx ly))
       (_ false))))

fn getModule forms: (List a/TopForm) -> (Option a/ModuleNode)
  (mt (listHead forms)
    ((some tf) (mt tf ((a/topModule m) (some m)) (_ (none))))
    ((none) (none)))

fn firstDiffIndexLoop xs: (List a/TopForm) ys: (List a/TopForm) i: Int64 -> Int64
  (mt (listHead xs)
    ((none) -1)
    ((some x)
     (mt (listHead ys)
       ((none) i)
       ((some y)
        (if (sexprEquivalent? (ac/topFormToSexpr x) (ac/topFormToSexpr y))
          (firstDiffIndexLoop (optionOr (listTail xs) (list)) (optionOr (listTail ys) (list)) (+ i 1))
          i)))))

fn diffSummary orig: (List a/TopForm) reparsed: (List a/TopForm) -> String
  (if (!= (listLength orig) (listLength reparsed))
    (str "form count " (stringFromInt64 (listLength orig)) " vs " (stringFromInt64 (listLength reparsed)))
    (let [(i (firstDiffIndexLoop orig reparsed 0))]
      (if (< i 0)
        "no divergence found"
        (let [(ox (listGet orig i)) (oy (listGet reparsed i))]
          (str "form " (stringFromInt64 i) " diff:\n  ORIG: "
               (mt ox ((some t) (rd/renderSexpr (ac/topFormToSexpr t))) ((none) "?"))
               "\n  REPARSED: "
               (mt oy ((some t) (rd/renderSexpr (ac/topFormToSexpr t))) ((none) "?")))))))

fn topFormsEquivalent? xs: (List a/TopForm) ys: (List a/TopForm) -> Bool
  (if (!= (listLength xs) (listLength ys))
    false
    (fold (fn [(acc Bool) (p (Pair a/TopForm a/TopForm))] -> Bool
            (and acc (sexprEquivalent? (ac/topFormToSexpr (pairFirst p)) (ac/topFormToSexpr (pairSecond p)))))
          true (zip xs ys)))

(schema CorpusStats
  (:f checked Int64)
  (:f passed Int64)
  (:f bugs Int64)
  (:f cached Int64)
  (:f cache cc/Cache))

fn emptyCorpusStats! -> CorpusStats
  (emptyCorpusStatsWith (cc/cacheFromEnv!))

fn emptyCorpusStatsWith cache: cc/Cache -> CorpusStats
  (CorpusStats :checked 0 :passed 0 :bugs 0 :cached 0 :cache cache)

fn bumpPassed s: CorpusStats -> CorpusStats
  (with s :checked (+ s.checked 1) :passed (+ s.passed 1))

fn bumpBug s: CorpusStats -> CorpusStats
  (with s :checked (+ s.checked 1) :bugs (+ s.bugs 1))

fn bumpCached s: CorpusStats -> CorpusStats
  (with s :cached (+ s.cached 1))

fn reparseCheck path: String orig: (List a/TopForm) printed: String stats: CorpusStats -> CorpusStats
  (mt (a/parse printed)
    ((err e)
     (do
       (assert false (str path " printed output failed to reparse: " e.msg))
       (bumpBug stats)))
    ((ok reForms)
     (let [(equiv? (topFormsEquivalent? orig reForms))]
       (do
         (assert equiv? (if equiv? (str path " print/reparse SExpr identity") (str path " print/reparse SExpr identity: " (diffSummary orig reForms))))
         (if equiv? (bumpPassed stats) (bumpBug stats))))))

fn moduleCheck path: String forms: (List a/TopForm) stats: CorpusStats -> CorpusStats
  (let [(printed (mt (getModule forms)
                   ((some m) (ap/printAstModule m))
                   ((none) (stringJoin (map (fn [(tf a/TopForm)] -> String (ap/printTopForm tf)) forms) "\n\n"))))]
    (reparseCheck path forms printed stats))

fn parseCheck path: String src: String stats: CorpusStats -> CorpusStats
  (mt (a/parse src)
    ((err e)
     (do
       (assert false (str path " initial parse error: " e.msg))
       (bumpBug stats)))
    ((ok forms) (moduleCheck path forms stats)))

fn verifyCorpusFile! path: String stats: CorpusStats -> CorpusStats
  (mt (fileRead path)
    ((err e)
     (do
       (assert false (str path " read error: " e))
       (bumpBug stats)))
    ((ok src)
     (mt (cc/lookupVerdict! stats.cache "printReparse" path src (list "passed"))
       ((some outcome)
        (do
          (assert (= outcome "passed") (str path " print/reparse SExpr identity (cached)"))
          (bumpCached (bumpPassed stats))))
       ((none) (checkAndStore! path src stats)))))

fn checkAndStore! path: String src: String stats: CorpusStats -> CorpusStats
  (let [(after (parseCheck path src stats))]
    (do
      (if (> after.passed stats.passed)
        (cc/storeVerdict! stats.cache "printReparse" path src "passed")
        false)
      after))

fn reportCorpusStats! label: String s: CorpusStats -> Bool
  (do
    (print (str label ": checked=" (stringFromInt64 s.checked)
                " passed=" (stringFromInt64 s.passed)
                " bugs=" (stringFromInt64 s.bugs)
                " cached=" (stringFromInt64 s.cached) "\n"))
    (assert (= s.bugs 0) (str label " zero print/reparse bugs"))
    (= s.bugs 0))

fn testIfLetPrinting -> Bool
  (let [(letAsElse (a/exprIf (a/exprIdent "cond") (a/exprLit (a/litInt 1)) (a/exprLet (list (pair (a/patVar "x") (a/exprLit (a/litInt 2)))) (list (a/exprIdent "x")))))
        (printed (ap/printAstExpr letAsElse 1))
        (parseRes (a/parse (str "fn probe -> Int64\n" printed)))]
    (do
      (assert (stringContains? printed "\n") "an if with a let branch must print the let on its own line, not glued inline")
      (assert (ok? parseRes)
        (mt parseRes
          ((ok _) "if/let printer reparses cleanly")
          ((err e) (str "if/let printer must reparse: " e.msg))))
      (ok? parseRes)))

fn testCondPrinting -> Bool
  (let [(condExpr (a/exprCond (list (pair (a/exprIdent "a") (list (a/exprIdent "b"))))))
        (condPrinted (ap/printAstExpr condExpr 0))
        (parseRes (a/parse (str "fn probe2 -> Int64\n  " condPrinted)))]
    (do
      (assert (stringStartsWith? condPrinted "(cond") "a cond expression must print as a canonical parenthesized form")
      (assert (ok? parseRes)
        (mt parseRes
          ((ok _) "cond printer reparses cleanly")
          ((err e) (str "cond printer must reparse: " e.msg))))
      (ok? parseRes)))

fn testEquivalenceGuards -> Bool
  (let [(mismatchedLengths (topFormsEquivalent? (list) (list (a/topDefun (a/DefunNode :name "x" :typeVars (list) :isExported false :effect false :params (list) :retType "Int64" :docstring "" :body (list (rd/makeAtom "1")) :bodyPos (list))))))]
    (do
      (assert (not (sexprEquivalent? (rd/makeAtom "1") (rd/makeAtom "2"))) "sexprEquivalent? must refute distinct atoms")
      (assert (sexprEquivalent? (rd/makeAtom "1.50") (rd/makeAtom "1.5")) "sexprEquivalent? must accept float reformatting")
      (assert (not mismatchedLengths) "topFormsEquivalent? must refute mismatched lengths")
      true))

fn testMutantGuards -> Bool
  (and (testIfLetPrinting) (and (testCondPrinting) (testEquivalenceGuards)))
