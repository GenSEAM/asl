(module asl-syntax/tests/core/symbolsTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)])

fn testSymbolDefConstruction -> Bool
  (let [(s1 (sym/makeSymbolDef "greet" "fn" 10 35))
        (s2 (sym/makeScopedSymbolDef "run" "method" 40 80 "Worker" 2))]
    (assert (= (sym/symbolName s1) "greet") "s1 name is greet")
    (assert (= (sym/symbolKind s1) "fn") "s1 kind is fn")
    (assert (= (sym/symbolStart s1) 10) "s1 start is 10")
    (assert (= (sym/symbolEnd s1) 35) "s1 end is 35")
    (assert (= (sym/symbolContainer s1) "") "s1 container is empty")
    (assert (= (sym/symbolDepth s1) 0) "s1 depth is 0")
    (assert (= (sym/symbolName s2) "run") "s2 name is run")
    (assert (= (sym/symbolKind s2) "method") "s2 kind is method")
    (assert (= (sym/symbolStart s2) 40) "s2 start is 40")
    (assert (= (sym/symbolEnd s2) 80) "s2 end is 80")
    (assert (= (sym/symbolContainer s2) "Worker") "s2 container is Worker")
    (assert (= (sym/symbolDepth s2) 2) "s2 depth is 2")
    true)

fn testDottedLookup -> Bool
  (let [(s1 (sym/makeScopedSymbolDef "App" "class" 0 200 "" 0))
        (s2 (sym/makeScopedSymbolDef "init" "method" 20 80 "App" 1))
        (s3 (sym/makeScopedSymbolDef "run" "method" 90 180 "App" 1))
        (s4 (sym/makeScopedSymbolDef "Helper" "class" 210 400 "" 0))
        (s5 (sym/makeScopedSymbolDef "run" "method" 230 350 "Helper" 1))
        (syms (list s1 s2 s3 s4 s5))]
    (assert (= (sym/findSymbol syms "App") (some s1)) "find App")
    (assert (= (sym/findSymbol syms ":App") (some s1)) "find :App with leading colon")
    (assert (= (sym/findSymbol syms "App.init") (some s2)) "find App.init")
    (assert (= (sym/findSymbol syms "App.run") (some s3)) "find App.run inside App")
    (assert (= (sym/findSymbol syms "Helper.run") (some s5)) "find Helper.run inside Helper")
    (assert (= (sym/findSymbol syms "Helper.missing") (none)) "Helper.missing returns none")
    (assert (= (sym/findSymbol syms "NoSuchClass") (none)) "NoSuchClass returns none")
    true)

fn testNearestNames -> Bool
  (let [(names (list "apple" "application" "apply" "banana" "orange"))
        (near1 (sym/nearestNames "app" names 3))
        (near2 (sym/nearestNames "ban" names 2))]
    (assert (listContains? near1 "apple") "near app contains apple")
    (assert (listContains? near1 "apply") "near app contains apply")
    (assert (<= (listLength near1) 3) "near app length <= 3")
    (assert (listContains? near2 "banana") "near ban contains banana")
    (assert (<= (listLength near2) 2) "near ban length <= 2")
    true)

fn testAnchorResolutionUnique -> Bool
  (let [(text "line 1\nlet targetValue = 42;\nline 3\n")
        (res (sym/resolveAnchor text "targetValue"))]
    (assert (ok? res) "resolve unique anchor succeeds")
    (mt res
      ((ok span)
       (do
         (assert (= span.start 11) "anchor start is 11")
         (assert (= span.end 22) "anchor end is 22")
         (assert (= (sym/spanLength span) 11) "span length is 11")))
      ((err _) (assert false "expected ok")))
    true)

fn testAnchorResolutionAmbiguous -> Bool
  (let [(text "foo bar foo baz foo qux")
        (res (sym/resolveAnchor text "foo"))]
    (assert (err? res) "ambiguous anchor is rejected")
    (mt res
      ((ok _) (assert false "expected ambiguity error"))
      ((err msg)
       (do
         (assert (stringContains? msg "ambiguous") "error message contains ambiguous")
         (assert (stringContains? msg "3") "error message contains count 3"))))
    true)

fn testAnchorResolutionNotFound -> Bool
  (let [(text "alpha beta gamma")
        (res (sym/resolveAnchor text "delta"))]
    (assert (err? res) "not found anchor rejected")
    (mt res
      ((ok _) (assert false "expected not found error"))
      ((err msg)
       (assert (stringContains? msg "not found") "error message contains not found")))
    true)

fn testAnchorResolutionOccurrence -> Bool
  (let [(text "item item item")
        (r1 (sym/resolveAnchorOccurrence text "item" 1))
        (r2 (sym/resolveAnchorOccurrence text "item" 2))
        (r3 (sym/resolveAnchorOccurrence text "item" 3))
        (r4 (sym/resolveAnchorOccurrence text "item" 4))]
    (assert (ok? r1) "occurrence 1 succeeds")
    (assert (ok? r2) "occurrence 2 succeeds")
    (assert (ok? r3) "occurrence 3 succeeds")
    (assert (err? r4) "occurrence 4 out of bounds rejected")
    (mt r1
      ((ok s) (assert (= s.start 0) "occ 1 start is 0"))
      ((err _) (assert false "occ 1 failed")))
    (mt r2
      ((ok s) (assert (= s.start 5) "occ 2 start is 5"))
      ((err _) (assert false "occ 2 failed")))
    (mt r3
      ((ok s) (assert (= s.start 10) "occ 3 start is 10"))
      ((err _) (assert false "occ 3 failed")))
    true)

fn toyParse text: String -> (Result tr/Node String)
  (let [(len (stringLength text))]
    (cond
      ((stringContains? text "BAD")
       (let [(errTok (tr/makeToken "error" 0 len))
             (errNode (tr/makeErrorNode 0 len (list (tr/elemToken errTok))))]
         (ok errNode)))
      ((stringContains? text "FAIL")
       (err "syntax error"))
      (else
       (let [(tok (tr/makeToken "ident" 0 len))
             (node (tr/makeNode "expr" 0 len (list (tr/elemToken tok))))]
         (ok node)))))

fn testReparseGuardCleanEdit -> Bool
  (let [(text "hello WORLD end")
        (res (sym/applySpanEdit text 6 11 "EVERYONE" toyParse))]
    (assert (ok? res) "clean edit succeeds")
    (mt res
      ((ok editRes)
       (do
         (assert (= editRes.newText "hello EVERYONE end") "new text matches")
         (assert (not (sym/hasErrorNode editRes.root)) "root has no error node")))
      ((err _) (assert false "expected ok edit")))
    true)

fn testReparseGuardErrorNodeRejected -> Bool
  (let [(text "hello WORLD end")
        (res (sym/applySpanEdit text 6 11 "BAD" toyParse))]
    (assert (err? res) "edit introducing Error node is rejected")
    (mt res
      ((ok _) (assert false "expected rejection"))
      ((err msg)
       (assert (stringContains? msg "Error node") "error names Error node")))
    true)

fn testReparseGuardParseFailureRejected -> Bool
  (let [(text "hello WORLD end")
        (res (sym/applySpanEdit text 6 11 "FAIL" toyParse))]
    (assert (err? res) "edit causing parse failure is rejected")
    (mt res
      ((ok _) (assert false "expected parse failure"))
      ((err msg)
       (assert (stringContains? msg "parse") "error message names parse")))
    true)

fn testApplyAnchorEdit -> Bool
  (let [(text "one target two")
        (rClean (sym/applyAnchorEdit text "target" "REPLACEMENT" toyParse))
        (multiText "one dup two dup three")
        (rAmb (sym/applyAnchorEdit multiText "dup" "REPLACEMENT" toyParse))]
    (assert (ok? rClean) "anchor edit on unique anchor succeeds")
    (mt rClean
      ((ok editRes) (assert (= editRes.newText "one REPLACEMENT two") "anchor edit replaced"))
      ((err _) (assert false "expected ok anchor edit")))
    (assert (err? rAmb) "anchor edit on ambiguous anchor rejected")
    (mt rAmb
      ((ok _) (assert false "expected ambiguous anchor error"))
      ((err msg) (assert (stringContains? msg "ambiguous") "error names ambiguous")))
    true)

fn testOutlineReceiptEmpty -> Bool
  (let [(src (src/sourceFromString "empty.js" ""))
        (receipt (out/formatOutlineReceipt "empty.js" "javascript" (list) src))
        (expected "(:outline :status :ok :file \"empty.js\" :language \"javascript\" :itemsCount 0 :items [])")]
    (assert (= receipt expected) "empty outline receipt matches")
    true)

fn ! runTests -> Bool
  (and (testSymbolDefConstruction)
  (and (testDottedLookup)
  (and (testNearestNames)
  (and (testAnchorResolutionUnique)
  (and (testAnchorResolutionAmbiguous)
  (and (testAnchorResolutionNotFound)
  (and (testAnchorResolutionOccurrence)
  (and (testReparseGuardCleanEdit)
  (and (testReparseGuardErrorNodeRejected)
  (and (testReparseGuardParseFailureRejected)
  (and (testApplyAnchorEdit)
       (testOutlineReceiptEmpty))))))))))))
