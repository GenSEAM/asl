(module asl-syntax/js/recover
  :x [CheckVerdict
      check
      checkScript
      checkModule
      checkVerdict
      isSyntaxValid
      parseWithRecovery
      parseScriptWithRecovery
      parseModuleWithRecovery
      isStatementBoundary
      isStatementStartKeyword]
  :i [(asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/stmt :a stmt)
      (asl-syntax/js/module :a mod)])

(schema CheckVerdict
  (:f ok Bool)
  (:f message String)
  (:f errorOffset (Option Int64))
  (:f root (Option tr/Node)))

fn isTriviaTok tok: tr/Token -> Bool
  (let [(k tok.kind)]
    (or (= k "whitespace")
    (or (= k "newline")
        (= k "comment"))))

fn skipTriviaLoop toks: (List tr/Token) acc: (List tr/TreeElement) -> (Pair (List tr/TreeElement) (List tr/Token))
  (if (listEmpty? toks)
    (pair (listReverse acc) toks)
    (let [(hd (optionOr (listHead toks) (tr/Token :kind "" :start 0 :end 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (isTriviaTok hd)
        (skipTriviaLoop tl (cons (tr/elemToken hd) acc))
        (pair (listReverse acc) toks))))

fn skipTrivia toks: (List tr/Token) -> (Pair (List tr/TreeElement) (List tr/Token))
  (skipTriviaLoop toks (list))

fn tokenSlice tok: tr/Token text: String -> String
  (let [(st tok.start)
        (en tok.end)]
    (if (or (< st 0) (> en (stringLength text)))
      ""
      (optionOr (stringSlice text st en) "")))

fn isStatementStartKeyword tok: tr/Token text: String -> Bool
  (if (!= tok.kind "keyword")
    false
    (let [(s (tokenSlice tok text))]
      (or (= s "var")
      (or (= s "let")
      (or (= s "const")
      (or (= s "function")
      (or (= s "class")
      (or (= s "if")
      (or (= s "while")
      (or (= s "do")
      (or (= s "for")
      (or (= s "return")
      (or (= s "throw")
      (or (= s "break")
      (or (= s "continue")
      (or (= s "debugger")
      (or (= s "switch")
      (or (= s "try")
      (or (= s "with")
      (or (= s "import")
          (= s "export")))))))))))))))))))))

fn isStatementBoundary tok: tr/Token -> Bool
  (let [(k tok.kind)]
    (or (= k "semicolon")
    (or (= k "rbrace")
        (= k "newline"))))

fn tokensToElements toks: (List tr/Token) -> (List tr/TreeElement)
  (if (listEmpty? toks)
    (list)
    (let [(hd (optionOr (listHead toks) (tr/Token :kind "" :start 0 :end 0)))
          (tl (optionOr (listTail toks) (list)))]
      (cons (tr/elemToken hd) (tokensToElements tl))))

fn makeRecoveryErrorNodeFromTokens toks: (List tr/Token) -> tr/TreeElement
  (if (listEmpty? toks)
    (tr/elemNode (tr/makeErrorNode 0 0 (list)))
    (let [(firstTok (optionOr (listHead toks) (tr/Token :kind "" :start 0 :end 0)))
          (lastTok (optionOr (listLast toks) (tr/Token :kind "" :start 0 :end 0)))
          (elems (tokensToElements toks))]
      (tr/elemNode (tr/makeErrorNode firstTok.start lastTok.end elems))))

fn nextNonTriviaTok toks: (List tr/Token) -> (Option tr/Token)
  (if (listEmpty? toks)
    (none)
    (let [(hd (optionOr (listHead toks) (tr/Token :kind "" :start 0 :end 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (isTriviaTok hd)
        (nextNonTriviaTok tl)
        (some hd))))

fn scanStatementTokensLoop toks: (List tr/Token) text: String parenDepth: Int64 braceDepth: Int64 bracketDepth: Int64 startKw: String acc: (List tr/Token) -> (Pair (List tr/Token) (List tr/Token))
  (if (listEmpty? toks)
    (pair (listReverse acc) toks)
    (let [(hd (optionOr (listHead toks) (tr/Token :kind "" :start 0 :end 0)))
          (tl (optionOr (listTail toks) (list)))
          (k hd.kind)
          (s (tokenSlice hd text))
          (isTriv (isTriviaTok hd))
          (newStartKw (if (and (stringEmpty? startKw) (not isTriv)) s startKw))
          (atZero (and (= parenDepth 0) (and (= braceDepth 0) (= bracketDepth 0))))]
      (cond
        ((and atZero (= k "semicolon"))
         (pair (listReverse (cons hd acc)) tl))
        ((and (and (= parenDepth 0) (= bracketDepth 0)) (and (= braceDepth 1) (= k "rbrace")))
         (let [(nextOpt (nextNonTriviaTok tl))
               (nextSlice (mt nextOpt ((some nt) (tokenSlice nt text)) ((none) "")))]
           (if (or (and (= newStartKw "if") (= nextSlice "else"))
               (or (and (= newStartKw "try") (or (= nextSlice "catch") (= nextSlice "finally")))
               (or (and (= newStartKw "do") (= nextSlice "while"))
                   (and (or (= newStartKw "var") (or (= newStartKw "let") (= newStartKw "const"))) (= nextSlice ";")))))
             (scanStatementTokensLoop tl text parenDepth 0 bracketDepth newStartKw (cons hd acc))
             (pair (listReverse (cons hd acc)) tl))))
        ((and (and atZero (not (listEmpty? acc))) (= k "newline"))
         (let [(nextOpt (nextNonTriviaTok tl))]
           (mt nextOpt
             ((none)
              (pair (listReverse (cons hd acc)) tl))
             ((some nt)
              (if (or (isStatementStartKeyword nt text) (= nt.kind "rbrace"))
                (pair (listReverse (cons hd acc)) tl)
                (scanStatementTokensLoop tl text parenDepth braceDepth bracketDepth newStartKw (cons hd acc)))))))
        ((and (and atZero (not (listEmpty? acc))) (and (not isTriv) (isStatementStartKeyword hd text)))
         (pair (listReverse acc) toks))
        (else
         (let [(newParen (cond ((= k "lparen") (+ parenDepth 1)) ((= k "rparen") (if (> parenDepth 0) (- parenDepth 1) 0)) (else parenDepth)))
               (newBrace (cond ((= k "lbrace") (+ braceDepth 1)) ((= k "rbrace") (if (> braceDepth 0) (- braceDepth 1) 0)) (else braceDepth)))
               (newBracket (cond ((= k "lbracket") (+ bracketDepth 1)) ((= k "rbracket") (if (> bracketDepth 0) (- bracketDepth 1) 0)) (else bracketDepth)))]
           (scanStatementTokensLoop tl text newParen newBrace newBracket newStartKw (cons hd acc)))))))

fn scanStatementTokens toks: (List tr/Token) text: String -> (Pair (List tr/Token) (List tr/Token))
  (scanStatementTokensLoop toks text 0 0 0 "" (list))

fn hasLexError toks: (List tr/Token) -> (Option tr/Token)
  (if (listEmpty? toks)
    (none)
    (let [(hd (optionOr (listHead toks) (tr/Token :kind "" :start 0 :end 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (= hd.kind "error")
        (some hd)
        (hasLexError tl))))

fn hasHashbangError toks: (List tr/Token) text: String -> Bool
  (if (listEmpty? toks)
    false
    (let [(hd (optionOr (listHead toks) (tr/Token :kind "" :start 0 :end 0)))
          (tl (optionOr (listTail toks) (list)))]
      (if (and (= hd.kind "comment") (stringStartsWith? (tokenSlice hd text) "#!"))
        (if (!= hd.start 0)
          true
          (hasHashbangError tl text))
        (hasHashbangError tl text))))

fn hasParamAfterRest elems: (List tr/TreeElement) foundRest: Bool -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (let [(k tok.kind)]
           (if (or (isTriviaTok tok) (or (= k "lparen") (= k "rparen")))
             (hasParamAfterRest tl foundRest)
             (if (= k "ellipsis")
               (hasParamAfterRest tl true)
               (if foundRest
                 (if (= k "comma")
                   true
                   (hasParamAfterRest tl true))
                 (hasParamAfterRest tl false))))))
        ((tr/elemNode n)
         (let [(nk n.kind)]
           (if (= nk "restElement")
             (hasParamAfterRest tl true)
             (if foundRest
               true
               (hasParamAfterRest tl false))))))))

fn checkAnyParamAfterRest node: tr/Node -> Bool
  (if (= node.kind "parameters")
    (if (hasParamAfterRest node.children false)
      true
      (checkAnyParamAfterRestElems node.children))
    (checkAnyParamAfterRestElems node.children))

fn checkAnyParamAfterRestElems elems: (List tr/TreeElement) -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (checkAnyParamAfterRestElems tl))
        ((tr/elemNode n)
         (if (checkAnyParamAfterRest n)
           true
           (checkAnyParamAfterRestElems tl))))))

fn hasSemiInFieldKids kids: (List tr/TreeElement) -> Bool
  (if (listEmpty? kids)
    false
    (let [(hd (optionOr (listLast kids) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))]
      (mt hd
        ((tr/elemToken tok) (= tok.kind "semicolon"))
        ((tr/elemNode _) false))))

fn checkClassBodyASI elements: (List tr/TreeElement) text: String inMember: Bool needsTerm: Bool -> Bool
  (if (listEmpty? elements)
    false
    (let [(hd (optionOr (listHead elements) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tl (optionOr (listTail elements) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (let [(k tok.kind)]
           (if (= k "newline")
             (checkClassBodyASI tl text inMember false)
             (if (= k "semicolon")
               (checkClassBodyASI tl text inMember false)
               (if (= k "comment")
                 (if (stringContains? (optionOr (stringSlice text tok.start tok.end) "") "\n")
                   (checkClassBodyASI tl text inMember false)
                   (checkClassBodyASI tl text inMember needsTerm))
                 (checkClassBodyASI tl text inMember needsTerm))))))
        ((tr/elemNode n)
         (let [(nk n.kind)]
           (if (or (= nk "classField") (or (= nk "classMethod") (= nk "classStaticBlock")))
             (if needsTerm
               true
               (let [(hasSemi (if (= nk "classField") (hasSemiInFieldKids n.children) false))]
                 (checkClassBodyASI tl text true (not hasSemi))))
             (checkClassBodyASI tl text inMember needsTerm)))))))

fn checkClassAsiEarlyError node: tr/Node text: String -> Bool
  (if (= node.kind "classBody")
    (if (checkClassBodyASI node.children text false false)
      true
      (checkClassAsiEarlyErrorElems node.children text))
    (checkClassAsiEarlyErrorElems node.children text))

fn checkClassAsiEarlyErrorElems elems: (List tr/TreeElement) text: String -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (checkClassAsiEarlyErrorElems tl text))
        ((tr/elemNode n)
         (if (checkClassAsiEarlyError n text)
           true
           (checkClassAsiEarlyErrorElems tl text))))))

fn isReservedWord s: String -> Bool
  (or (= s "else")
  (or (= s "if")
  (or (= s "while")
  (or (= s "for")
  (or (= s "return")
  (or (= s "throw")
  (or (= s "break")
  (or (= s "continue")
  (or (= s "function")
  (or (= s "class")
  (or (= s "var")
  (or (= s "let")
  (or (= s "const")
  (or (= s "try")
  (or (= s "catch")
  (or (= s "finally")
  (or (= s "switch")
  (or (= s "case")
  (or (= s "default")
  (or (= s "do")
  (or (= s "in")
  (or (= s "instanceof")
  (or (= s "typeof")
  (or (= s "void")
  (or (= s "delete")
  (or (= s "new")
  (or (= s "this")
  (or (= s "super")
  (or (= s "with")
  (or (= s "import")
      (= s "export")))))))))))))))))))))))))))))))

fn checkDeclaratorReservedWord node: tr/Node text: String -> Bool
  (if (= node.kind "declarator")
    (let [(kids node.children)]
      (if (listEmpty? kids)
        false
        (let [(firstElem (optionOr (listHead kids) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))]
          (mt firstElem
            ((tr/elemToken tok)
             (isReservedWord (tokenSlice tok text)))
            ((tr/elemNode _) false)))))
    false)

fn checkReservedWords node: tr/Node text: String -> Bool
  (if (checkDeclaratorReservedWord node text)
    true
    (checkReservedWordsElems node.children text))

fn checkReservedWordsElems elems: (List tr/TreeElement) text: String -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (checkReservedWordsElems tl text))
        ((tr/elemNode n)
         (if (checkReservedWords n text)
           true
           (checkReservedWordsElems tl text))))))

fn hasInvalidAwaitToken toks: (List tr/Token) text: String inAsync: Bool prevIsBad: Bool -> Bool
  (if (listEmpty? toks)
    false
    (let [(hd (optionOr (listHead toks) (tr/Token :kind "" :start 0 :end 0)))
          (tl (optionOr (listTail toks) (list)))
          (k hd.kind)]
      (if (isTriviaTok hd)
        (hasInvalidAwaitToken tl text inAsync prevIsBad)
        (let [(s (tokenSlice hd text))]
          (if (and inAsync (and prevIsBad (= s "await")))
            true
            (let [(nowBad (or (= s "var") (or (= s "let") (or (= s "const") (= s "void")))))]
              (hasInvalidAwaitToken tl text inAsync nowBad)))))))

fn checkInvalidAwait toks: (List tr/Token) text: String -> Bool
  (if (and (stringContains? text "async") (stringContains? text "await"))
    (hasInvalidAwaitToken toks text true false)
    false)

fn hasInInKids kids: (List tr/TreeElement) text: String -> Bool
  (if (listEmpty? kids)
    false
    (let [(hd (optionOr (listHead kids) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tl (optionOr (listTail kids) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (if (= (tokenSlice tok text) "in")
           true
           (hasInInKids tl text)))
        ((tr/elemNode n)
         (or (hasInInKids n.children text)
             (hasInInKids tl text))))))

fn checkYieldInForIn node: tr/Node text: String -> Bool
  (if (= node.kind "forStmt")
    (let [(kids node.children)]
      (hasInInKids kids text))
    (checkYieldInForInElems node.children text))

fn checkYieldInForInElems elems: (List tr/TreeElement) text: String -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (checkYieldInForInElems tl text))
        ((tr/elemNode n)
         (if (checkYieldInForIn n text)
           true
           (checkYieldInForInElems tl text))))))

fn checkEarlyErrors root: tr/Node text: String -> (Option String)
  (let [(toks (lx/tokenize text))]
    (if (checkAnyParamAfterRest root)
      (some "Rest parameter must be last formal parameter")
      (if (checkClassAsiEarlyError root text)
        (some "Unexpected token in class body: missing semicolon or line terminator")
        (if (checkReservedWords root text)
          (some "Reserved word used as identifier")
          (if (checkInvalidAwait toks text)
            (some "Cannot use 'await' as identifier inside async function")
            (if (checkYieldInForIn root text)
              (some "Yield expression not allowed in iteration header")
              (none)))))))

fn parseStatementsWithRecovery toks: (List tr/Token) text: String inAsync: Bool inGen: Bool isMod: Bool acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (let [(sp (skipTrivia toks))
        (triv (pairFirst sp))
        (rem (pairSecond sp))]
    (if (listEmpty? rem)
      (listAppend acc triv)
      (let [(accWithTriv (listAppend acc triv))
            (firstTok (optionOr (listHead rem) (tr/Token :kind "" :start 0 :end 0)))
            (firstSlice (tokenSlice firstTok text))
            (stmtRes (cond
                       ((and isMod (= firstSlice "import"))
                        (mt (mod/parseImportDecl rem text)
                          ((ok pr) pr)
                          ((err _) (stmt/parseStatement rem text inAsync inGen))))
                       ((and isMod (= firstSlice "export"))
                        (mt (mod/parseExportDecl rem text)
                          ((ok pr) pr)
                          ((err _) (stmt/parseStatement rem text inAsync inGen))))
                       (else
                        (stmt/parseStatement rem text inAsync inGen))))
            (stmtNode stmtRes.node)
            (remToks stmtRes.rest)
            (advanced (> (listLength rem) (listLength remToks)))
            (hasErr (or (tr/isErrorNode stmtNode) (sym/hasErrorNode stmtNode)))
            (hasEarly (some? (checkEarlyErrors stmtNode text)))
            (tiles (if (and advanced (not hasErr)) (ok? (tr/checkTiling stmtNode stmtNode.end)) false))]
        (if (and (and advanced (not hasErr)) (and (not hasEarly) tiles))
          (parseStatementsWithRecovery remToks text inAsync inGen isMod (listAppend accWithTriv (list (tr/elemNode stmtNode))))
          (let [(stmtPair (scanStatementTokens rem text))
                (stmtToks (pairFirst stmtPair))
                (restToks (pairSecond stmtPair))
                (actualToks (if (listEmpty? stmtToks) (list firstTok) stmtToks))
                (actualRest (if (listEmpty? stmtToks) (optionOr (listTail rem) (list)) restToks))
                (advRest (if (= (listLength actualRest) (listLength rem)) (optionOr (listTail rem) (list)) actualRest))
                (errElem (makeRecoveryErrorNodeFromTokens actualToks))]
            (parseStatementsWithRecovery advRest text inAsync inGen isMod (listAppend accWithTriv (list errElem))))))))

fn parseScriptWithRecovery text: String -> tr/Node
  (let [(toks (lx/tokenize text))
        (elems (parseStatementsWithRecovery toks text false false false (list)))]
    (tr/makeNode "script" 0 (stringLength text) elems))

fn parseModuleWithRecovery text: String -> tr/Node
  (let [(toks (lx/tokenize text))
        (elems (parseStatementsWithRecovery toks text true false true (list)))]
    (tr/makeNode "module" 0 (stringLength text) elems))

fn isModuleText text: String -> Bool
  (or (stringContains? text "import ")
  (or (stringContains? text "import{")
  (or (stringContains? text "export ")
  (or (stringContains? text "export{")
      (stringContains? text "export default")))))

fn parseWithRecovery text: String -> tr/Node
  (if (isModuleText text)
    (parseModuleWithRecovery text)
    (parseScriptWithRecovery text))

fn checkScript text: String -> (Result tr/Node String)
  (let [(toks (lx/tokenize text))]
    (mt (hasLexError toks)
      ((some errTok)
       (err (str "Lexical syntax error at offset " (stringFromInt64 errTok.start))))
      ((none)
       (if (hasHashbangError toks text)
         (err "Hashbang comment only allowed at start of file")
         (mt (stmt/parseScript text)
           ((err msg) (err msg))
           ((ok root)
            (mt (checkEarlyErrors root text)
              ((some earlyMsg) (err earlyMsg))
              ((none)
               (if (sym/hasErrorNode root)
                 (err "Syntax error in script")
                 (ok root))))))))))

fn checkModule text: String -> (Result tr/Node String)
  (let [(toks (lx/tokenize text))]
    (mt (hasLexError toks)
      ((some errTok)
       (err (str "Lexical syntax error at offset " (stringFromInt64 errTok.start))))
      ((none)
       (if (hasHashbangError toks text)
         (err "Hashbang comment only allowed at start of file")
         (mt (mod/parseModule text)
           ((err msg) (err msg))
           ((ok root)
            (mt (checkEarlyErrors root text)
              ((some earlyMsg) (err earlyMsg))
              ((none)
               (if (sym/hasErrorNode root)
                 (err "Syntax error in module")
                 (ok root))))))))))

fn check text: String -> (Result tr/Node String)
  (if (isModuleText text)
    (checkModule text)
    (mt (checkScript text)
      ((ok root) (ok root))
      ((err scriptErr)
       (if (or (stringContains? text "import") (stringContains? text "export"))
         (checkModule text)
         (err scriptErr)))))

fn checkVerdict text: String -> CheckVerdict
  (mt (check text)
    ((ok root)
     (CheckVerdict :ok true :message "OK" :errorOffset (none) :root (some root)))
    ((err msg)
     (let [(rootRec (parseWithRecovery text))]
       (CheckVerdict :ok false :message msg :errorOffset (none) :root (some rootRec)))))

fn isSyntaxValid text: String -> Bool
  (ok? (check text))
