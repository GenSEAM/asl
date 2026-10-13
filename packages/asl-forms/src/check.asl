(module asl-forms/check
  :x [CheckVerdict
      StagedVerdict
      LeftItem
      foreignSyntax
      validateStaged
      checkFileReceipt!
      checkSemantic!
      findHostBinary!
      runHostCheck!
      runHostCheckWithBinary!
      makeLeftItem
      leftItemLine
      leftItemCol
      leftItemExpected
      leftItemNear
      leftItemKind
      formatLeftItem
      formatLeftList
      languageOf
      pathExtension]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/json :a jcst)
      (asl-syntax/js/recover :a jsrec)
      (asl-syntax/js/module :a jsm)
      (asl-syntax/ts/types :a tstypes)
      (asl-syntax/ts/module :a tsm)
      (asl-syntax/jsx :a jsx)
      (asl-syntax/tsx :a tsx)
      (asl-syntax/css/rules :a cssrules)
      (asl-syntax/html/tree :a htmltree)
      (asl-syntax/xml :a xmltree)
      (asl-forms/kernel :a k)])

(schema CheckVerdict
  (:f status String)
  (:f message String))

(schema StagedVerdict
  (:f rejectCode String)
  (:f rejectMessage String)
  (:f receiptFields String))

(schema LeftItem
  (:f line Int64)
  (:f col Int64)
  (:f expected String)
  (:f near String)
  (:f kind String))

fn makeLeftItem line: Int64 col: Int64 expected: String near: String kind: String -> LeftItem
  (LeftItem :line line :col col :expected expected :near near :kind kind)

fn leftItemLine item: LeftItem -> Int64
  item.line

fn leftItemCol item: LeftItem -> Int64
  item.col

fn leftItemExpected item: LeftItem -> String
  item.expected

fn leftItemNear item: LeftItem -> String
  item.near

fn leftItemKind item: LeftItem -> String
  item.kind

fn formatLeftItem item: LeftItem -> String
  (str "(:line " (stringFromInt64 item.line)
       " :col " (stringFromInt64 item.col)
       " :expected \"" (k/escapeAsnVal item.expected) "\""
       " :near \"" (k/escapeAsnVal item.near) "\""
       " :kind " item.kind ")")

fn formatLeftList items: (List LeftItem) -> String
  (if (listEmpty? items)
    "()"
    (let [(n (listLength items))]
      (if (<= n 5)
        (str "(" (stringJoin (map formatLeftItem items) " ") ")")
        (let [(first5 (listTake items 5))
              (rem (- n 5))]
          (str "(" (stringJoin (map formatLeftItem first5) " ") " :more " (stringFromInt64 rem) ")")))))

fn pathExtension path: String -> String
  (let [(parts (stringSplit path "/"))
        (base (optionOr (listLast parts) path))
        (dotParts (stringSplit base "."))]
    (if (or (<= (listLength dotParts) 1)
            (and (= (listLength dotParts) 2) (stringStartsWith? base ".")))
      ""
      (str "." (stringLower (optionOr (listLast dotParts) "")))))

fn languageOf path: String -> String
  (let [(ext (pathExtension path))]
    (cond
      ((= ext ".json") "json")
      ((or (= ext ".js") (= ext ".mjs") (= ext ".cjs") (= ext ".jsx")) "javascript")
      ((or (= ext ".ts") (= ext ".mts") (= ext ".cts") (= ext ".tsx")) "typescript")
      ((= ext ".css") "css")
      ((or (= ext ".html") (= ext ".htm")) "html")
      ((or (= ext ".xml") (= ext ".svg")) "xml")
      ((= ext ".asl") "asl")
      ((= ext ".asn") "asn")
      ((or (= ext ".py") (= ext ".pyw")) "python")
      (else "text")))

fn foreignSyntax path: String content: String -> CheckVerdict
  (let [(ext (pathExtension path))
        (lang (languageOf path))]
    (cond
      ((= lang "json")
       (mt (jcst/parse content)
         ((ok _) (CheckVerdict :status "ok" :message ""))
         ((err msg) (CheckVerdict :status "error" :message msg))))
      ((= ext ".jsx")
       (mt (jsx/parse content)
         ((ok root)
          (if (sym/hasErrorNode root)
            (CheckVerdict :status "error" :message "JSX syntax error")
            (CheckVerdict :status "ok" :message "")))
         ((err msg) (CheckVerdict :status "error" :message msg))))
      ((= lang "javascript")
       (mt (jsrec/check content)
         ((ok _) (CheckVerdict :status "ok" :message ""))
         ((err msg) (CheckVerdict :status "error" :message msg))))
      ((= ext ".tsx")
       (mt (tsx/parse content)
         ((ok root)
          (if (sym/hasErrorNode root)
            (CheckVerdict :status "error" :message "TSX syntax error")
            (CheckVerdict :status "ok" :message "")))
         ((err msg) (CheckVerdict :status "error" :message msg))))
      ((= lang "typescript")
       (mt (tsm/parse content)
         ((ok _) (CheckVerdict :status "ok" :message ""))
         ((err msg) (CheckVerdict :status "error" :message msg))))
      ((= lang "css")
       (let [(tree (cssrules/parseRules content))]
         (if (sym/hasErrorNode tree)
           (CheckVerdict :status "error" :message "CSS syntax error")
           (CheckVerdict :status "ok" :message ""))))
      ((= lang "html")
       (let [(tree (htmltree/parseHtml content))]
         (if (htmltree/isWellFormed tree)
           (CheckVerdict :status "ok" :message "")
           (CheckVerdict :status "error" :message "HTML syntax error"))))
      ((= lang "xml")
       (mt (xmltree/parse content)
         ((ok _) (CheckVerdict :status "ok" :message ""))
         ((err msg) (CheckVerdict :status "error" :message msg))))
      (else
       (CheckVerdict :status "skipped" :message (str "no local checker for " lang)))))

fn validateStaged path: String before: (Option String) after: String force: Bool -> StagedVerdict
  (let [(lang (languageOf path))]
    (if (or (= lang "asl") (= lang "asn"))
      (if (k/isBalanced after)
        (StagedVerdict :rejectCode "" :rejectMessage "" :receiptFields " :balanced true")
        (let [(pre (mt before
                     ((none) false)
                     ((some b) (not (k/isBalanced b)))))]
          (if (or pre force)
            (StagedVerdict :rejectCode "" :rejectMessage ""
                           :receiptFields (str " :balanced false" (if pre " :preexisting true" " :forced true")))
            (StagedVerdict :rejectCode ":ERR_UNBALANCED" :rejectMessage "Unbalanced Dyck-1 delimiters"
                           :receiptFields " :balanced false"))))
      (let [(syn (foreignSyntax path after))
            (st syn.status)]
        (if (!= st "error")
          (StagedVerdict :rejectCode "" :rejectMessage "" :receiptFields (str " :syntax :" st))
          (let [(pre (mt before
                       ((none) false)
                       ((some b) (= (foreignSyntax path b).status "error"))))]
            (if (or pre force)
              (StagedVerdict :rejectCode "" :rejectMessage ""
                             :receiptFields (str " :syntax :error" (if pre " :preexisting true" " :forced true")
                                                 " :syntaxMessage \"" (k/escapeAsnVal syn.message) "\""))
              (StagedVerdict :rejectCode ":ERR_SYNTAX" :rejectMessage syn.message
                             :receiptFields " :syntax :error")))))))

fn nearSnippet text: String s: src/Source line: Int64 col: Int64 -> String
  (mt (src/sourceLineStart s line)
    ((some start)
     (let [(end (src/sourceLineEnd s line))
           (lineStr (optionOr (stringSlice text start end) ""))
           (lineLen (stringLength lineStr))]
       (if (<= lineLen 60)
         lineStr
         (let [(startIdx (if (<= col 40)
                           0
                           (if (> (+ (- col 30) 60) lineLen)
                             (- lineLen 60)
                             (- col 30))))
               (sub (optionOr (stringSlice lineStr startIdx (+ startIdx 60)) ""))]
           sub))))
    ((none) ""))

fn parseAslDiagLine line: String text: String s: src/Source -> (Option LeftItem)
  (if (or (stringStartsWith? line "check failed:") (stringEmpty? line))
    (none)
    (mt (stringIndexOf line ": ")
      ((none) (none))
      ((some csIdx)
       (let [(prefix (optionOr (stringSlice line 0 csIdx) ""))
             (rest (optionOr (stringSlice line (+ csIdx 2) (stringLength line)) ""))
             (parts (stringSplit prefix ":"))
             (nParts (listLength parts))]
         (if (< nParts 3)
           (none)
           (let [(colStr (optionOr (listLast parts) "0"))
                 (lineStr (optionOr (listGet parts (- nParts 2)) "0"))
                 (lineNum (optionOr (stringToInt64 lineStr) 0))
                 (colNum (optionOr (stringToInt64 colStr) 0))
                 (restWords (stringSplit rest " "))
                 (code (optionOr (listHead restWords) "ERR_SEMANTIC"))
                 (near (nearSnippet text s lineNum colNum))]
             (if (stringStartsWith? code "ERR_")
               (some (LeftItem :line lineNum :col colNum :expected code :near near :kind "semantic"))
               (none))))))))

fn collectAslDiags lines: (List String) text: String s: src/Source acc: (List LeftItem) -> (List LeftItem)
  (if (listEmpty? lines)
    (listReverse acc)
    (let [(hd (optionOr (listHead lines) ""))
          (tl (optionOr (listTail lines) (list)))]
      (mt (parseAslDiagLine hd text s)
        ((some item) (collectAslDiags tl text s (cons item acc)))
        ((none) (collectAslDiags tl text s acc)))))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn walkUpHostDir! dir: String -> (Option String)
  (let [(candidate (str dir "/asl/host/out/asl-host"))]
    (if (fileExists? candidate)
      (some candidate)
      (let [(parent (pathDir dir))]
        (if (or (stringEmpty? parent) (= parent dir))
          (none)
          (walkUpHostDir! parent)))))

fn findHostFromTarget! targetPath: String -> String
  (let [(dir (pathDir targetPath))
        (startDir (if (stringEmpty? dir) "." dir))
        (absDir (mt (realPath startDir) ((ok c) c) ((err _) startDir)))]
    (mt (walkUpHostDir! absDir)
      ((some host) host)
      ((none)
       (if (fileExists? "asl/host/out/asl-host")
         "asl/host/out/asl-host"
         "asl-host"))))

fn findHostBinary! targetPath: String -> String
  (mt (envGet "ASL_HOST")
    ((some h)
     (if (and (not (stringEmpty? h)) (fileExists? h))
       h
       (findHostFromTarget! targetPath)))
    ((none)
     (findHostFromTarget! targetPath)))

fn executeHostCheckWithBinary! targetPath: String hostBin: String -> (Pair Int64 String)
  (let [(cmd (str (shellQuote hostBin) " check " (shellQuote targetPath)))
        (res (processRun cmd))]
    (pair res.exitCode res.stderr))

fn executeHostCheck! targetPath: String -> (Pair Int64 String)
  (executeHostCheckWithBinary! targetPath (findHostBinary! targetPath))

fn firstNonEmptyLine lines: (List String) -> String
  (if (listEmpty? lines)
    ""
    (let [(hd (stringTrim (optionOr (listHead lines) "")))
          (tl (optionOr (listTail lines) (list)))]
      (if (stringEmpty? hd)
        (firstNonEmptyLine tl)
        hd)))

fn runHostCheckWithBinary! targetPath: String text: String hostBin: String -> (Result (List LeftItem) String)
  (let [(execRes (executeHostCheckWithBinary! targetPath hostBin))
        (exitCode (pairFirst execRes))
        (stderrStr (pairSecond execRes))]
    (if (= exitCode 0)
      (ok (list))
      (let [(lines (stringSplit stderrStr "\n"))
            (srcObj (src/sourceFromString targetPath text))
            (diags (collectAslDiags lines text srcObj (list)))]
        (if (listEmpty? diags)
          (let [(firstLine (firstNonEmptyLine lines))]
            (err (str "hostCheck exit " (stringFromInt64 exitCode) ": " firstLine)))
          (ok diags)))))

fn runHostCheck! targetPath: String text: String -> (Result (List LeftItem) String)
  (runHostCheckWithBinary! targetPath text (findHostBinary! targetPath))

fn createAslTempFile! dir: String content: String counter: Int64 -> (Result String String)
  (if (> counter 100)
    (err "fileCreateExclusive: failed to create unique temp file after 100 tries")
    (let [(targetDir (if (stringEmpty? dir) "." dir))
          (tmpPath (str targetDir "/.asl_chk_" (stringFromInt64 (monotonicNs)) "_" (stringFromInt64 counter) ".asl"))
          (res (fileCreateExclusive tmpPath content))]
      (mt res
        ((ok _) (ok tmpPath))
        ((err e)
         (if (stringContains? e "alreadyExists")
           (createAslTempFile! dir content (+ counter 1))
           (err e))))))

fn checkAslSemantic! path: String content: String -> (Result (List LeftItem) String)
  (let [(diskMatch (mt (fileReadString path)
                     ((ok c) (= c content))
                     ((err _) false)))]
    (if diskMatch
      (runHostCheck! path content)
      (let [(dir (pathDir path))
            (cRes (createAslTempFile! dir content 0))]
        (mt cRes
          ((err e) (err (str "fileWrite failed: " e)))
          ((ok tmpPath)
           (let [(res (runHostCheck! tmpPath content))
                 (rmRes (pathRemove tmpPath))]
             (mt rmRes
               ((err e) (err (str "pathRemove failed: " e)))
               ((ok _) res))))))))

fn normStep segs: (List String) acc: (List String) -> (List String)
  (if (listEmpty? segs)
    (listReverse acc)
    (let [(h (optionOr (listHead segs) ""))
          (tl (optionOr (listTail segs) (list)))]
      (cond
        ((or (stringEmpty? h) (= h "."))
         (normStep tl acc))
        ((= h "..")
         (if (listEmpty? acc)
           (normStep tl acc)
           (normStep tl (optionOr (listTail acc) (list)))))
        (else
         (normStep tl (cons h acc))))))

fn normalizePath p: String -> String
  (let [(isAbs (stringStartsWith? p "/"))
        (segs (stringSplit p "/"))
        (res (normStep segs (list)))
        (joined (stringJoin res "/"))]
    (if isAbs
      (str "/" joined)
      joined))

fn pathDir p: String -> String
  (let [(parts (stringSplit p "/"))
        (n (listLength parts))]
    (if (<= n 1)
      ""
      (stringJoin (optionOr (listSlice parts 0 (- n 1)) (list)) "/")))

fn ! fileExists? p: String -> Bool
  (mt (fileStat p)
    ((ok st) st.isFile)
    ((err _) false))

fn checkExtensions! base: String -> Bool
  (or (fileExists? (str base ".ts"))
  (or (fileExists? (str base ".tsx"))
  (or (fileExists? (str base ".d.ts"))
  (or (fileExists? (str base ".js"))
  (or (fileExists? (str base ".jsx"))
  (or (fileExists? (str base ".mjs"))
  (or (fileExists? (str base ".cjs"))
      (fileExists? (str base ".json")))))))))

fn checkIndexFiles! dir: String -> Bool
  (or (fileExists? (str dir "/index.ts"))
  (or (fileExists? (str dir "/index.tsx"))
  (or (fileExists? (str dir "/index.d.ts"))
  (or (fileExists? (str dir "/index.js"))
  (or (fileExists? (str dir "/index.jsx"))
  (or (fileExists? (str dir "/index.mjs"))
  (or (fileExists? (str dir "/index.cjs"))
      (fileExists? (str dir "/index.json")))))))))

fn resolveRelativeTarget! target: String -> Bool
  (if (fileExists? target)
    true
    (let [(len (stringLength target))]
      (cond
        ((and (stringEndsWith? target ".js") (> len 3))
         (let [(base (optionOr (stringSlice target 0 (- len 3)) ""))]
           (or (fileExists? (str base ".ts"))
           (or (fileExists? (str base ".tsx"))
               (fileExists? (str base ".d.ts"))))))
        ((and (stringEndsWith? target ".jsx") (> len 4))
         (let [(base (optionOr (stringSlice target 0 (- len 4)) ""))]
           (fileExists? (str base ".tsx"))))
        ((and (stringEndsWith? target ".mjs") (> len 4))
         (let [(base (optionOr (stringSlice target 0 (- len 4)) ""))]
           (fileExists? (str base ".mts"))))
        ((and (stringEndsWith? target ".cjs") (> len 4))
         (let [(base (optionOr (stringSlice target 0 (- len 4)) ""))]
           (fileExists? (str base ".cts"))))
        (else
         (or (checkExtensions! target)
             (checkIndexFiles! target))))))

fn unquoteString raw: String -> String
  (let [(len (stringLength raw))]
    (if (< len 2)
      raw
      (let [(c0 (optionOr (stringSlice raw 0 1) ""))
            (cLast (optionOr (stringSlice raw (- len 1) len) ""))]
        (if (or (and (= c0 "\"") (= cLast "\""))
                (or (and (= c0 "'") (= cLast "'"))
                    (and (= c0 "`") (= cLast "`"))))
          (optionOr (stringSlice raw 1 (- len 1)) "")
          raw))))

fn isRelativeSpecifier? s: String -> Bool
  (or (stringStartsWith? s "./")
      (stringStartsWith? s "../"))


fn exportHasFrom? elems: (List tr/TreeElement) text: String -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (if (and (= (tr/tokenKind tok) "ident") (= (optionOr (stringSlice text (tr/tokenStart tok) (tr/tokenEnd tok)) "") "from"))
           true
           (exportHasFrom? tl text)))
        ((tr/elemNode _)
         (exportHasFrom? tl text)))))

fn findModuleStringTok elems: (List tr/TreeElement) text: String -> (Option tr/Token)
  (if (listEmpty? elems)
    (none)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (if (= (tr/tokenKind tok) "string")
           (let [(raw (optionOr (stringSlice text (tr/tokenStart tok) (tr/tokenEnd tok)) ""))
                 (spec (unquoteString raw))]
             (if (isRelativeSpecifier? spec)
               (some tok)
               (findModuleStringTok tl text)))
           (findModuleStringTok tl text)))
        ((tr/elemNode node)
         (if (= (tr/nodeKind node) "importAttributes")
           (findModuleStringTok tl text)
           (mt (findModuleStringTok (tr/nodeChildren node) text)
             ((some tok) (some tok))
             ((none) (findModuleStringTok tl text))))))))

fn findCalleeNode elems: (List tr/TreeElement) -> (Option tr/Node)
  (if (listEmpty? elems)
    (none)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (findCalleeNode tl))
        ((tr/elemNode node) (some node)))))

fn findFirstArgNode elems: (List tr/TreeElement) afterCallee: Bool -> (Option tr/Node)
  (if (listEmpty? elems)
    (none)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _)
         (findFirstArgNode tl afterCallee))
        ((tr/elemNode node)
         (if afterCallee
           (some node)
           (findFirstArgNode tl true))))))

fn findLiteralStringTok elems: (List tr/TreeElement) -> (Option tr/Token)
  (if (listEmpty? elems)
    (none)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (if (or (= (tr/tokenKind tok) "string") (= (tr/tokenKind tok) "templateNoSub"))
           (some tok)
           (findLiteralStringTok tl)))
        ((tr/elemNode node)
         (mt (findLiteralStringTok (tr/nodeChildren node))
           ((some tok) (some tok))
           ((none) (findLiteralStringTok tl)))))))

fn checkDynamicCall node: tr/Node text: String -> (Option tr/Token)
  (mt (findCalleeNode (tr/nodeChildren node))
    ((none) (none))
    ((some callee)
     (let [(calleeText (stringTrim (optionOr (stringSlice text (tr/nodeStart callee) (tr/nodeEnd callee)) "")))]
       (if (and (!= calleeText "import") (!= calleeText "require"))
         (none)
         (mt (findFirstArgNode (tr/nodeChildren node) false)
           ((none) (none))
           ((some argNode)
            (let [(k (tr/nodeKind argNode))]
              (if (and (!= k "literal") (!= k "templateLiteral"))
                (none)
                (mt (findLiteralStringTok (tr/nodeChildren argNode))
                  ((none) (none))
                  ((some tok)
                   (let [(raw (optionOr (stringSlice text (tr/tokenStart tok) (tr/tokenEnd tok)) ""))
                         (spec (unquoteString raw))]
                     (if (isRelativeSpecifier? spec)
                       (some tok)
                       (none)))))))))))))

fn isDynamicImportWithSub? node: tr/Node text: String -> Bool
  (mt (findCalleeNode (tr/nodeChildren node))
    ((none) false)
    ((some callee)
     (let [(calleeText (stringTrim (optionOr (stringSlice text (tr/nodeStart callee) (tr/nodeEnd callee)) "")))]
       (if (and (!= calleeText "import") (!= calleeText "require"))
         false
         (mt (findFirstArgNode (tr/nodeChildren node) false)
           ((none) false)
           ((some argNode)
            (and (= (tr/nodeKind argNode) "templateLiteral")
                 (stringContains? (optionOr (stringSlice text (tr/nodeStart argNode) (tr/nodeEnd argNode)) "") "${"))))))))

fn countSkippedInElems elems: (List tr/TreeElement) text: String acc: Int64 -> Int64
  (if (listEmpty? elems)
    acc
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (countSkippedInElems tl text acc))
        ((tr/elemNode node)
         (let [(extra (if (and (= (tr/nodeKind node) "callExpr") (isDynamicImportWithSub? node text)) 1 0))
               (kidsCount (countSkippedInElems (tr/nodeChildren node) text 0))]
           (countSkippedInElems tl text (+ acc (+ extra kidsCount))))))))

fn countSkippedImports root: tr/Node text: String -> Int64
  (countSkippedInElems (tr/nodeChildren root) text 0)

fn collectImportsInElems elems: (List tr/TreeElement) text: String acc: (List tr/Token) -> (List tr/Token)
  (if (listEmpty? elems)
    acc
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _)
         (collectImportsInElems tl text acc))
        ((tr/elemNode node)
         (let [(k (tr/nodeKind node))]
           (cond
             ((= k "importDecl")
              (let [(newAcc (mt (findModuleStringTok (tr/nodeChildren node) text)
                              ((some tok) (cons tok acc))
                              ((none) acc)))]
                (collectImportsInElems tl text newAcc)))
             ((= k "importEqualsDecl")
              (let [(newAcc (mt (findModuleStringTok (tr/nodeChildren node) text)
                              ((some tok) (cons tok acc))
                              ((none) acc)))]
                (collectImportsInElems tl text newAcc)))
             ((and (= k "exportDecl") (exportHasFrom? (tr/nodeChildren node) text))
              (let [(newAcc (mt (findModuleStringTok (tr/nodeChildren node) text)
                              ((some tok) (cons tok acc))
                              ((none) acc)))]
                (collectImportsInElems tl text newAcc)))
             ((= k "callExpr")
              (let [(accKids (collectImportsInElems (tr/nodeChildren node) text acc))
                    (newAcc (mt (checkDynamicCall node text)
                              ((some tok) (cons tok accKids))
                              ((none) accKids)))]
                (collectImportsInElems tl text newAcc)))
             (else
              (let [(accKids (collectImportsInElems (tr/nodeChildren node) text acc))]
                (collectImportsInElems tl text accKids)))))))))

fn collectModuleImports root: tr/Node text: String -> (List tr/Token)
  (listReverse (collectImportsInElems (tr/nodeChildren root) text (list)))
fn parseJsOrTs ext: String lang: String content: String -> (Result tr/Node String)
  (cond
    ((= ext ".tsx") (tsx/parse content))
    ((= ext ".jsx") (jsx/parse content))
    ((= lang "typescript") (tsm/parse content))
    ((= lang "javascript") (jsm/parse content))
    (else (err "not js or ts")))

fn resolveImportsLoop! tokens: (List tr/Token) path: String text: String s: src/Source acc: (List LeftItem) -> (List LeftItem)
  (if (listEmpty? tokens)
    (listReverse acc)
    (let [(tok (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
          (tl (optionOr (listTail tokens) (list)))
          (raw (optionOr (stringSlice text (tr/tokenStart tok) (tr/tokenEnd tok)) ""))
          (spec (unquoteString raw))
          (dir (pathDir path))
          (rawTarget (if (stringEmpty? dir) spec (str dir "/" spec)))
          (target (normalizePath rawTarget))]
      (if (resolveRelativeTarget! target)
        (resolveImportsLoop! tl path text s acc)
        (let [(pos (src/sourcePosAt s (tr/tokenStart tok)))
              (line (optionOr (mt pos ((some p) (some p.line)) ((none) (none))) 1))
              (col (optionOr (mt pos ((some p) (some p.byteCol)) ((none) (none))) 1))
              (near (nearSnippet text s line col))
              (item (LeftItem :line line :col col :expected "ERR_UNRESOLVED_IMPORT" :near near :kind "semantic"))]
          (resolveImportsLoop! tl path text s (cons item acc))))))

fn checkJsTsSemantic! path: String ext: String lang: String content: String -> (List LeftItem)
  (let [(parseRes (parseJsOrTs ext lang content))]
    (mt parseRes
      ((err _) (list))
      ((ok root)
       (let [(tokens (collectModuleImports root content))
             (srcObj (src/sourceFromString path content))]
         (resolveImportsLoop! tokens path content srcObj (list))))))

fn checkSemantic! path: String content: String -> (Result (List LeftItem) String)
  (let [(actualContent (if (stringEmpty? content) (resultOr (fileReadString path) "") content))
        (lang (languageOf path))
        (ext (pathExtension path))]
    (cond
      ((= lang "asl")
       (checkAslSemantic! path actualContent))
      ((or (= lang "javascript") (= lang "typescript"))
       (ok (checkJsTsSemantic! path ext lang actualContent)))
      (else
       (ok (list)))))

fn checkFileReceipt! id: Int64 op: String relPath: String source: String content: String -> String
  (let [(lang (languageOf relPath))]
    (cond
      ((= lang "asl")
       (if (not (k/isBalanced content))
         (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"rejected\" :error-code \":ERR_UNBALANCED_DELIMITERS\" :file \""
              (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :message \"Unbalanced Dyck-1 delimiters\")")
         (mt (checkSemantic! relPath content)
           ((err e)
            (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"rejected\" :error-code \":ERR_HOST_CHECK\" :file \""
                 (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :message \"" (k/escapeAsnVal e) "\")"))
           ((ok items)
            (if (listEmpty? items)
              (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"ok\" :file \""
                   (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :valid true :balanced true :left ())")
              (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"rejected\" :error-code \":ERR_SEMANTIC\" :file \""
                   (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :valid false :balanced true :left " (formatLeftList items) ")"))))))
      ((= lang "asn")
       (if (k/isBalanced content)
         (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"ok\" :file \""
              (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :valid true :balanced true :left ())")
         (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"rejected\" :error-code \":ERR_UNBALANCED_DELIMITERS\" :file \""
              (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :message \"Unbalanced Dyck-1 delimiters\")")))
      ((or (= lang "javascript") (= lang "typescript"))
       (let [(syn (foreignSyntax relPath content))
             (st syn.status)]
         (cond
           ((= st "error")
            (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"rejected\" :error-code \":ERR_SYNTAX\" :file \""
                 (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :syntax :error :message \""
                 (k/escapeAsnVal syn.message) "\")"))
           ((= st "ok")
            (let [(parseRes (parseJsOrTs (pathExtension relPath) lang content))
                  (skipCount (mt parseRes ((ok r) (countSkippedImports r content)) ((err _) 0)))]
              (mt (checkSemantic! relPath content)
                ((err e)
                 (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"rejected\" :error-code \":ERR_HOST_CHECK\" :file \""
                      (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :message \"" (k/escapeAsnVal e) "\")"))
                ((ok items)
                 (let [(hasLeft (not (listEmpty? items)))
                       (skipStr (str " :skipped [:dyck1Purity :syntaxIntegrity]" (if (> skipCount 0) (str " :skippedImports " (stringFromInt64 skipCount)) "")))]
                   (if (not hasLeft)
                     (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"ok\" :file \""
                          (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :syntax :ok :checked true"
                          skipStr " :left () :message \"no ASL checks apply to " lang " sources\")")
                     (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"rejected\" :error-code \":ERR_SEMANTIC\" :file \""
                          (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :syntax :ok :checked true"
                          (if (> skipCount 0) (str " :skippedImports " (stringFromInt64 skipCount)) "")
                          " :left " (formatLeftList items) ")")))))))
           (else
            (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"ok\" :file \""
                 (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :syntax :skipped :checked false :skipped [:dyck1Purity :syntaxIntegrity] :left () :message \"no ASL checks apply to "
                 lang " sources\")")))))
      (else
       (let [(syn (foreignSyntax relPath content))
             (st syn.status)]
         (cond
           ((= st "error")
            (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"rejected\" :error-code \":ERR_SYNTAX\" :file \""
                 (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :syntax :error :message \""
                 (k/escapeAsnVal syn.message) "\")"))
           ((= st "ok")
            (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"ok\" :file \""
                 (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :syntax :ok :checked true :skipped [:dyck1Purity :syntaxIntegrity] :left () :message \"no ASL checks apply to "
                 lang " sources\")"))
           (else
            (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"ok\" :file \""
                 (k/escapeAsnVal relPath) "\" :language \"" lang "\" :source " source " :syntax :skipped :checked false :skipped [:dyck1Purity :syntaxIntegrity] :left () :message \"no ASL checks apply to "
                 lang " sources\")")))))))
