(module asl-gates/metaAudit
  :x [MetaSpec Violation FileScan Ctx Audit parseForms loadSpec loadCtx! fileLang scanText! scanFile! auditPaths! tally receipt baselineText parseBaseline seedCaseReceipts main]
  :i [(asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast)])

(schema MetaSpec
  (:f keys (List String))
  (:f tags (List String))
  (:f effects (List String))
  (:f whyWords Int64)
  (:f pragmas (List String)))

(schema Ctx
  (:f root String)
  (:f spec MetaSpec)
  (:f rules String)
  (:f principles String)
  (:f decisions String)
  (:f decisionFiles (List String))
  (:f tests (List String))
  (:f tracked (List String)))

(schema Violation
  (:f file String)
  (:f line Int64)
  (:f kind String)
  (:f ev String))

(schema Pending
  (:f line Int64)
  (:f gate String))

(schema Scan
  (:f plain Int64)
  (:f metas Int64)
  (:f violations (List Violation))
  (:f pending (Option Pending))
  (:f quote String)
  (:f docstring Bool))

(schema FileScan
  (:f path String)
  (:f plain Int64)
  (:f metas Int64)
  (:f violations (List Violation)))

(schema Audit
  (:f files (List FileScan))
  (:f violations (List Violation))
  (:f plain Int64)
  (:f baselinePlain Int64)
  (:f lowerable Int64))

fn esc text: String -> String
  (stringReplace (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn tailOf xs: (List String) -> (List String)
  (optionOr (listTail xs) (list))

fn parseForms src: String -> (Result (List rd/SExpr) String)
  (mt (ast/readForms (lx/tokenize src))
    ((err e) (err e.msg))
    ((ok pfs) (ok (map (fn [(pf ast/PosForm)] -> rd/SExpr pf.expr) pfs))))

fn atomText s: rd/SExpr -> String
  (mt s ((rd/sexprAtom v) v) (_ ""))

fn itemsOf s: rd/SExpr -> (List rd/SExpr)
  (mt s ((rd/sexprList xs) xs) ((rd/sexprVect xs) xs) (_ (list)))

fn isSeq s: rd/SExpr -> Bool
  (mt s ((rd/sexprAtom _) false) (_ true))

fn unquote v: String -> String
  (if (and (stringStartsWith? v "\"") (and (stringEndsWith? v "\"") (>= (stringLength v) 2)))
    (optionOr (stringSlice v 1 (- (stringLength v) 1)) v)
    v)

fn stripColon v: String -> String
  (if (stringStartsWith? v ":") (optionOr (stringSlice v 1 (stringLength v)) v) v)

fn kvGet items: (List rd/SExpr) key: String -> (Option rd/SExpr)
  (mt (listHead items)
    ((none) (none))
    ((some it)
      (let [(rest (optionOr (listTail items) (list)))]
        (if (= (atomText it) key)
          (listHead rest)
          (kvGet rest key)))))

fn atomsOf s: rd/SExpr -> (List String)
  (map (fn [(x rd/SExpr)] -> String (stripColon (unquote (atomText x)))) (itemsOf s))

fn keyIds forms: (List rd/SExpr) -> (List String)
  (map (fn [(k rd/SExpr)] -> String (stripColon (atomText (optionOr (listGet (itemsOf k) 1) (rd/makeAtom ""))))) forms)

fn loadSpec text: String -> (Result MetaSpec String)
  (mt (parseForms text)
    ((err e) (err (str "meta.asn does not read: " e)))
    ((ok forms)
      (mt (listHead forms)
        ((none) (err "meta.asn is empty"))
        ((some top)
          (let [(items (itemsOf top))]
            (if (!= (atomText (optionOr (listHead items) (rd/makeAtom ""))) ":meta")
              (err "meta.asn is not a (:meta ...) form")
              (let [(keys (keyIds (itemsOf (optionOr (kvGet items ":keys") (rd/makeList (list))))))
                    (tags (atomsOf (optionOr (kvGet items ":tags") (rd/makeList (list)))))
                    (effects (atomsOf (optionOr (kvGet items ":effects") (rd/makeList (list)))))
                    (why (optionOr (stringToInt64 (atomText (optionOr (kvGet items ":whyWords") (rd/makeAtom "")))) 0))
                    (pragmas (atomsOf (optionOr (kvGet items ":pragmas") (rd/makeList (list)))))]
                (cond
                  ((listEmpty? keys) (err "meta.asn has no :keys"))
                  ((listEmpty? tags) (err "meta.asn has no :tags"))
                  ((listEmpty? effects) (err "meta.asn has no :effects"))
                  ((<= why 0) (err "meta.asn has no positive :whyWords"))
                  (else (ok (MetaSpec :keys keys :tags tags :effects effects :whyWords why :pragmas pragmas)))))))))))

fn readOr! path: String fallback: String -> String
  (mt (fileRead path) ((ok s) s) ((err _) fallback))

fn joinPath dir: String name: String -> String
  (if (or (stringEmpty? dir) (= dir ".")) name (str dir "/" name))

fn walkEntries! dir: String names: (List String) depth: Int64 acc: (List String) -> (List String)
  (mt (listHead names)
    ((none) acc)
    ((some n) (walkEntries! dir (tailOf names) depth (walkEntry! (joinPath dir n) n depth acc))))

fn walkEntry! path: String name: String depth: Int64 acc: (List String) -> (List String)
  (if (or (stringStartsWith? name ".") (= name "node_modules"))
    acc
    (mt (fileStat path)
      ((err _) acc)
      ((ok st)
        (cond
          (st.isDir (walkDir! path (+ depth 1) acc))
          (st.isFile (cons path acc))
          (else acc)))))

fn walkDir! dir: String depth: Int64 acc: (List String) -> (List String)
  (if (>= depth 32)
    acc
    (mt (dirList dir) ((err _) acc) ((ok names) (walkEntries! dir names depth acc))))

fn packageTests! root: String -> (List String)
  (let [(pkgDir (joinPath root "asl/packages"))]
    (mt (dirList pkgDir)
      ((err _) (list))
      ((ok names) (fold (fn [(acc (List String)) (n String)] -> (List String) (walkDir! (str pkgDir "/" n "/tests") 0 acc)) (list) names))))

fn listLines text: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map (fn [(l String)] -> String (stringTrim l)) (splitLines (stringToBytes text) text)))

fn loadCtx! root: String spec: MetaSpec tracked: (List String) -> Ctx
  (Ctx :root root :spec spec
       :rules (readOr! (joinPath root "asl/grammar/rules.asn") "")
       :principles (readOr! (joinPath root ".asl/mem/principles.asn") "")
       :decisions (readOr! (joinPath root ".asl/mem/decisions/decisions.asn") "")
       :decisionFiles (mt (dirList (joinPath root ".asl/mem/decisions")) ((ok ns) ns) ((err _) (list)))
       :tests (walkDir! (joinPath root "tests") 0 (packageTests! root))
       :tracked tracked)

fn isDigitCode c: Int64 -> Bool
  (and (>= c 48) (<= c 57))

fn allDigitsFrom bs: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n) true (if (isDigitCode (bytesGet bs i)) (allDigitsFrom bs (+ i 1) n) false))

fn isDecisionId v: String -> Bool
  (let [(bs (stringToBytes v))]
    (and (>= (bytesLength bs) 2) (and (= (bytesGet bs 0) 68) (allDigitsFrom bs 1 (bytesLength bs)))))

fn decisionFileMatches id: String name: String -> Bool
  (and (stringStartsWith? name id)
       (and (stringEndsWith? name ".asn")
            (let [(bs (stringToBytes name)) (k (stringLength id))]
              (not (isDigitCode (bytesGet bs k))))))

fn refResolves! ctx: Ctx v: String -> Bool
  (cond
    ((isDecisionId v)
      (or (listAny? (fn [(n String)] -> Bool (decisionFileMatches v n)) ctx.decisionFiles)
          (stringContains? ctx.decisions (str ":id \"" v "\""))))
    ((stringEndsWith? v ".asn")
      (if (listEmpty? ctx.tracked)
        (fileExists? (joinPath ctx.root v))
        (listContains? ctx.tracked v)))
    (else (stringContains? ctx.rules (str "(:rule :id " v " "))))

fn lastSegment path: String -> String
  (optionOr (listLast (stringSplit path "/")) path)

fn baseName path: String -> String
  (let [(last (lastSegment path))
        (dot (optionOr (stringIndexOf last ".") -1))]
    (if (> dot 0) (optionOr (stringSlice last 0 dot) last) last))

fn gateFiles ctx: Ctx gate: String -> (List String)
  (filter (fn [(p String)] -> Bool (= (baseName p) gate)) ctx.tests)

fn countWords text: String -> Int64
  (listLength (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace (stringReplace text "\t" " ") "\n" " ") " ")))

fn violation path: String line: Int64 kind: String ev: String -> Violation
  (Violation :file path :line line :kind kind :ev ev)

fn checkValue! ctx: Ctx path: String line: Int64 key: String val: rd/SExpr -> (List Violation)
  (let [(spec ctx.spec) (text (atomText val))]
    (cond
      ((= key "ref")
        (cond
          ((isSeq val) (list (violation path line "refNotAtom" (rd/renderSexpr val))))
          ((refResolves! ctx text) (list))
          (else (list (violation path line "refUnresolved" text)))))
      ((= key "gate")
        (if (or (isSeq val) (stringStartsWith? text "\""))
          (list (violation path line "gateNotAtom" (rd/renderSexpr val)))
          (list)))
      ((= key "tags")
        (if (not (isSeq val))
          (list (violation path line "tagsNotList" text))
          (let [(words (map (fn [(x rd/SExpr)] -> String (atomText x)) (itemsOf val)))]
            (if (listEmpty? words)
              (list (violation path line "tagsEmpty" "()"))
              (map (fn [(w String)] -> Violation (violation path line "tagUnknown" w))
                   (filter (fn [(w String)] -> Bool (not (listContains? spec.tags w))) words))))))
      ((= key "effect")
        (if (and (not (isSeq val)) (listContains? spec.effects text))
          (list)
          (list (violation path line "effectUnknown" (rd/renderSexpr val)))))
      ((= key "adopted")
        (if (and (not (isSeq val)) (stringContains? ctx.principles (str ":id \"" text "\"")))
          (list)
          (list (violation path line "adoptedUnknown" (rd/renderSexpr val)))))
      ((= key "why")
        (cond
          ((or (isSeq val) (not (stringStartsWith? text "\""))) (list (violation path line "whyNotString" (rd/renderSexpr val))))
          ((= (countWords (unquote text)) 0) (list (violation path line "whyEmpty" text)))
          ((> (countWords (unquote text)) spec.whyWords) (list (violation path line "whyTooLong" text)))
          (else (list))))
      (else (list (violation path line "keyUnchecked" key)))))

fn checkPairs! ctx: Ctx path: String line: Int64 items: (List rd/SExpr) seen: (List String) acc: (List Violation) gate: String -> (Pair (List Violation) String)
  (mt (listHead items)
    ((none) (pair acc gate))
    ((some k)
      (let [(rest (optionOr (listTail items) (list)))
            (kt (atomText k))
            (key (stripColon kt))]
        (cond
          ((not (stringStartsWith? kt ":"))
            (pair (cons (violation path line "keyExpected" (rd/renderSexpr k)) acc) gate))
          ((not (listContains? ctx.spec.keys key))
            (checkPairs! ctx path line (optionOr (listTail rest) (list)) seen (cons (violation path line "keyUnknown" kt) acc) gate))
          ((listContains? seen key)
            (checkPairs! ctx path line (optionOr (listTail rest) (list)) seen (cons (violation path line "keyRepeated" kt) acc) gate))
          (else
            (mt (listHead rest)
              ((none) (pair (cons (violation path line "valueMissing" kt) acc) gate))
              ((some v)
                (checkPairs! ctx path line (optionOr (listTail rest) (list)) (cons key seen)
                  (listAppend (listReverse (checkValue! ctx path line key v)) acc)
                  (if (= key "gate") (atomText v) gate)))))))))

fn checkMeta! ctx: Ctx path: String line: Int64 body: String -> (Pair (List Violation) String)
  (mt (parseForms body)
    ((err e) (pair (list (violation path line "formUnreadable" body)) ""))
    ((ok forms)
      (if (!= (listLength forms) 1)
        (pair (list (violation path line "formNotOne" body)) "")
        (let [(items (itemsOf (optionOr (listHead forms) (rd/makeAtom ""))))]
          (cond
            ((!= (atomText (optionOr (listHead items) (rd/makeAtom ""))) ":m")
              (pair (list (violation path line "formNotMeta" body)) ""))
            ((= (listLength items) 1)
              (pair (list (violation path line "formEmpty" body)) ""))
            (else
              (let [(r (checkPairs! ctx path line (tailOf2 items) (list) (list) ""))]
                (pair (listReverse (pairFirst r)) (pairSecond r)))))))))

fn tailOf2 xs: (List rd/SExpr) -> (List rd/SExpr)
  (optionOr (listTail xs) (list))

fn isIdentCode c: Int64 -> Bool
  (or (isDigitCode c) (or (and (>= c 65) (<= c 90)) (or (and (>= c 97) (<= c 122)) (or (= c 95) (or (= c 45) (or (= c 63) (= c 33)))))))

fn identEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (isIdentCode (bytesGet bs i))) (identEnd bs (+ i 1) n) i)

fn leadingIdent text: String -> String
  (let [(bs (stringToBytes text)) (e (identEnd bs 0 (bytesLength bs)))]
    (optionOr (stringSlice text 0 e) ""))

fn afterPrefix text: String prefix: String -> String
  (stringTrim (optionOr (stringSlice text (stringLength prefix) (stringLength text)) ""))

fn firstPrefix text: String prefixes: (List String) -> (Option String)
  (mt (listHead prefixes)
    ((none) (none))
    ((some p) (if (stringStartsWith? text p) (some p) (firstPrefix text (tailOf prefixes)))))

fn assignedName text: String -> String
  (let [(name (leadingIdent text))
        (rest (stringTrim (optionOr (stringSlice text (stringLength name) (stringLength text)) "")))]
    (cond
      ((stringEmpty? name) "")
      ((and (stringStartsWith? rest "=") (not (stringStartsWith? rest "=="))) name)
      ((stringStartsWith? rest ":") name)
      (else "")))

fn definedSymbol lang: String text: String -> String
  (cond
    ((= lang "python")
      (mt (firstPrefix text (list "async def " "def " "class "))
        ((some p) (leadingIdent (afterPrefix text p)))
        ((none) (assignedName text))))
    ((= lang "shell")
      (let [(t (mt (firstPrefix text (list "function " "readonly " "export " "local " "declare "))
                 ((some p) (afterPrefix text p))
                 ((none) text)))
            (name (leadingIdent t))
            (rest (optionOr (stringSlice t (stringLength name) (stringLength t)) ""))]
        (cond
          ((stringEmpty? name) "")
          ((stringStartsWith? text "function ") name)
          ((stringStartsWith? rest "=") name)
          ((stringStartsWith? (stringTrim rest) "()") name)
          (else ""))))
    ((= lang "asl")
      (mt (firstPrefix text (list "fn ! " "fn " "(fn " "(schema " "(enum " "(module " "(def "))
        ((some p) (leadingIdent (afterPrefix text p)))
        ((none) "")))
    (else ""))

fn fileLang path: String firstLine: String -> String
  (cond
    ((stringEndsWith? path ".py") "python")
    ((or (stringEndsWith? path ".sh") (stringEndsWith? path ".bash")) "shell")
    ((stringEndsWith? path ".asl") "asl")
    ((not (stringStartsWith? firstLine "#!")) "")
    ((stringContains? firstLine "python") "python")
    ((or (stringContains? firstLine "sh") (stringContains? firstLine "zsh")) "shell")
    (else ""))

fn marker lang: String -> String
  (if (= lang "asl") ";" "#")

fn stripMarker text: String m: String -> String
  (if (stringStartsWith? text m)
    (stripMarker (optionOr (stringSlice text (stringLength m) (stringLength text)) "") m)
    (stringTrim text))

fn isPragma spec: MetaSpec body: String -> Bool
  (listAny? (fn [(p String)] -> Bool (stringContains? body p)) spec.pragmas)

fn isMetaBody body: String -> Bool
  (or (= body "(:m)") (or (stringStartsWith? body "(:m ") (stringStartsWith? body "(:m\t")))

fn countOf text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

fn gateViolations! ctx: Ctx path: String p: Pending symbol: String -> (List Violation)
  (if (stringEmpty? p.gate)
    (list)
    (let [(files (gateFiles ctx p.gate))]
      (cond
        ((listEmpty? files) (list (violation path p.line "gateMissing" p.gate)))
        ((listAny? (fn [(f String)] -> Bool (stringContains? (readOr! f "") symbol)) files) (list))
        (else (list (violation path p.line "gateSilent" (str p.gate " " symbol)))))))

fn withViolations st: Scan vs: (List Violation) -> Scan
  (with st :violations (listAppend (listReverse vs) st.violations))

fn setPending st: Scan p: (Option Pending) -> Scan
  (with st :pending p)

fn addPlain st: Scan -> Scan
  (with st :plain (+ st.plain 1))

fn setQuote st: Scan q: String doc: Bool -> Scan
  (with st :quote q :docstring doc)

fn openQuote text: String -> String
  (let [(d (countOf text "\"\"\"")) (s (countOf text "'''"))]
    (cond
      ((= (mod d 2) 1) "\"\"\"")
      ((= (mod s 2) 1) "'''")
      (else "")))

fn resolvePending! ctx: Ctx path: String lang: String st: Scan text: String -> Scan
  (mt st.pending
    ((none) st)
    ((some p)
      (cond
        ((and (= lang "python") (stringStartsWith? text "@")) st)
        (else
          (let [(symbol (definedSymbol lang text))
                (cleared (setPending st (none)))]
            (if (stringEmpty? symbol)
              (withViolations cleared (list (violation path p.line "definitionMissing" text)))
              (withViolations cleared (gateViolations! ctx path p symbol))))))))

fn scanComment! ctx: Ctx path: String lang: String lineNo: Int64 st: Scan text: String -> Scan
  (let [(body (stripMarker text (marker lang)))]
    (cond
      ((and (= lineNo 1) (stringStartsWith? text "#!")) st)
      ((isMetaBody body)
        (let [(r (checkMeta! ctx path lineNo body))
              (st1 (withViolations st (pairFirst r)))
              (counted (Scan :plain st1.plain :metas (+ st1.metas 1) :violations st1.violations
                             :pending st1.pending :quote st1.quote :docstring st1.docstring))]
          (setPending counted (some (Pending :line lineNo :gate (pairSecond r))))))
      ((isPragma ctx.spec body) st)
      (else (addPlain st))))

fn scanLine! ctx: Ctx path: String lang: String lineNo: Int64 st: Scan raw: String -> Scan
  (let [(text (stringTrim raw))]
    (cond
      ((not (stringEmpty? st.quote))
        (let [(closes (= (mod (countOf text st.quote) 2) 1))
              (st1 (if st.docstring (addPlain st) st))]
          (if closes (setQuote st1 "" false) st1)))
      ((stringEmpty? text)
        (mt st.pending
          ((none) st)
          ((some p) (withViolations (setPending st (none)) (list (violation path p.line "definitionMissing" "blank line"))))))
      ((stringStartsWith? text (marker lang))
        (let [(st0 (mt st.pending
                     ((none) st)
                     ((some p) (withViolations (setPending st (none)) (list (violation path p.line "definitionMissing" text))))))]
          (scanComment! ctx path lang lineNo st0 text)))
      ((and (= lang "python") (or (stringStartsWith? text "\"\"\"") (stringStartsWith? text "'''")))
        (let [(st1 (addPlain (resolvePending! ctx path lang st text)))
              (q (openQuote text))]
          (if (stringEmpty? q) st1 (setQuote st1 q true))))
      (else
        (let [(st1 (resolvePending! ctx path lang st text))]
          (if (= lang "python")
            (let [(q (openQuote text))] (if (stringEmpty? q) st1 (setQuote st1 q false)))
            st1)))))

fn lineEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 10)) i (lineEnd bs (+ i 1) n))

fn splitLoop bs: Bytes text: String i: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [(e (lineEnd bs i n))]
      (splitLoop bs text (+ e 1) n (cons (optionOr (stringSlice text i e) "") acc))))

fn splitLines bs: Bytes text: String -> (List String)
  (splitLoop bs text 0 (bytesLength bs) (list))

fn scanLines! ctx: Ctx path: String lang: String lines: (List String) lineNo: Int64 st: Scan -> Scan
  (mt (listHead lines)
    ((none) st)
    ((some l) (scanLines! ctx path lang (tailOf lines) (+ lineNo 1) (scanLine! ctx path lang lineNo st l))))

fn scanText! ctx: Ctx path: String lang: String text: String -> FileScan
  (let [(st0 (Scan :plain 0 :metas 0 :violations (list) :pending (none) :quote "" :docstring false))
        (st (scanLines! ctx path lang (splitLines (stringToBytes text) text) 1 st0))
        (final (mt st.pending
                 ((none) st)
                 ((some p) (withViolations (setPending st (none)) (list (violation path p.line "definitionMissing" "end of file"))))))]
    (FileScan :path path :plain final.plain :metas final.metas :violations (listReverse final.violations)))

fn firstLineOf text: String -> String
  (optionOr (stringSlice text 0 (optionOr (stringIndexOf (optionOr (stringSlice text 0 (min 256 (stringLength text))) "") "\n") (min 256 (stringLength text)))) "")

fn scanFile! ctx: Ctx path: String -> (Option (Result FileScan String))
  (let [(extLang (fileLang path ""))]
    (if (and (stringEmpty? extLang)
             (or (stringContains? (lastSegment path) ".")
                 (mt (fileStat path) ((ok st) (not st.isFile)) ((err _) true))))
      (none)
      (mt (fileRead path)
        ((err _) (some (err path)))
        ((ok text)
          (let [(lang (if (stringEmpty? extLang) (fileLang path (firstLineOf text)) extLang))]
            (if (stringEmpty? lang) (none) (some (ok (scanText! ctx path lang text)))))))))

fn parseBaseline text: String -> (Result (List (Pair String Int64)) String)
  (mt (parseForms text)
    ((err e) (err (str "baseline does not read: " e)))
    ((ok forms)
      (mt (listHead forms)
        ((none) (ok (list)))
        ((some top)
          (ok (fold (fn [(acc (List (Pair String Int64))) (f rd/SExpr)] -> (List (Pair String Int64))
                      (let [(items (itemsOf f))]
                        (if (= (atomText (optionOr (listHead items) (rd/makeAtom ""))) ":file")
                          (cons (pair (unquote (atomText (optionOr (kvGet items ":path") (rd/makeAtom ""))))
                                      (optionOr (stringToInt64 (atomText (optionOr (kvGet items ":plain") (rd/makeAtom "")))) 0))
                                acc)
                          acc)))
                    (list) (itemsOf top)))))))

fn rowFor rows: (List (Pair String Int64)) path: String -> (Option Int64)
  (mt (listHead rows)
    ((none) (none))
    ((some r) (if (= (pairFirst r) path) (some (pairSecond r)) (rowFor (optionOr (listTail rows) (list)) path))))

fn ratchet row: (Option Int64) fs: FileScan -> (List Violation)
  (let [(n fs.plain)]
    (mt row
      ((none) (if (> n 0) (list (violation fs.path 0 "plainGrowth" (str (stringFromInt64 n) " over none"))) (list)))
      ((some b) (if (> n b) (list (violation fs.path 0 "plainGrowth" (str (stringFromInt64 n) " over " (stringFromInt64 b)))) (list)))))

fn auditPaths! ctx: Ctx rows: (List (Pair String Int64)) paths: (List String) -> Audit
  (let [(results (fold (fn [(acc (List (Result FileScan String))) (p String)] -> (List (Result FileScan String))
                         (mt (scanFile! ctx p) ((none) acc) ((some r) (cons r acc))))
                       (list) paths))
        (scans (fold (fn [(acc (List FileScan)) (r (Result FileScan String))] -> (List FileScan)
                       (mt r ((ok s) (cons s acc)) ((err _) acc))) (list) results))
        (unreadable (fold (fn [(acc (List Violation)) (r (Result FileScan String))] -> (List Violation)
                            (mt r ((err p) (cons (violation p 0 "unreadable" p) acc)) ((ok _) acc))) (list) results))]
    (tally rows scans unreadable))

fn tally rows: (List (Pair String Int64)) scans: (List FileScan) unreadable: (List Violation) -> Audit
  (let [(withRows (map (fn [(s FileScan)] -> (Pair FileScan (Option Int64)) (pair s (rowFor rows s.path))) scans))
        (formViolations (fold (fn [(acc (List Violation)) (s FileScan)] -> (List Violation) (listAppend (listReverse s.violations) acc)) (list) scans))
        (growth (fold (fn [(acc (List Violation)) (sr (Pair FileScan (Option Int64)))] -> (List Violation) (listAppend (ratchet (pairSecond sr) (pairFirst sr)) acc)) (list) withRows))
        (baseSum (fold (fn [(acc Int64) (sr (Pair FileScan (Option Int64)))] -> Int64 (+ acc (optionOr (pairSecond sr) 0))) 0 withRows))
        (lower (listLength (filter (fn [(sr (Pair FileScan (Option Int64)))] -> Bool (< (pairFirst sr).plain (optionOr (pairSecond sr) 0))) withRows)))]
    (Audit :files scans
           :violations (listAppend unreadable (listAppend (listReverse formViolations) (listReverse growth)))
           :plain (fold (fn [(acc Int64) (s FileScan)] -> Int64 (+ acc s.plain)) 0 scans)
           :baselinePlain baseSum
           :lowerable lower))

fn violationText v: Violation -> String
  (str "(:violation :file \"" (esc v.file) "\" :line " (stringFromInt64 v.line) " :kind :" v.kind " :ev \"" (esc v.ev) "\")")

fn receipt a: Audit -> String
  (let [(vs a.violations)
        (metas (fold (fn [(acc Int64) (s FileScan)] -> Int64 (+ acc s.metas)) 0 a.files))]
    (str "(:metaAudit :status :" (if (listEmpty? vs) "pass" "fail")
         " :files " (stringFromInt64 (listLength a.files))
         " :metaForms " (stringFromInt64 metas)
         " :plain " (stringFromInt64 a.plain)
         " :baselinePlain " (stringFromInt64 a.baselinePlain)
         " :lowerable " (stringFromInt64 a.lowerable)
         " :violations " (stringFromInt64 (listLength vs))
         (stringJoin (map (fn [(v Violation)] -> String (str " " (violationText v))) vs) "")
         ")"))

fn baselineText a: Audit date: String -> String
  (let [(rows (filter (fn [(s FileScan)] -> Bool (> s.plain 0)) a.files))]
    (str "(:metaBaseline :v 1 :date \"" (esc date) "\" :plain " (stringFromInt64 a.plain)
         "\n  :doc \"plain comment lines per file, read by asl/packages/asl-gates/src/metaAudit.asl; a file above its row or without a row fails; rows may only be lowered (asl/grammar/meta.asn)\""
         (stringJoin (map (fn [(s FileScan)] -> String (str "\n  (:file :path \"" (esc s.path) "\" :plain " (stringFromInt64 s.plain) ")")) rows) "")
         ")\n"))

(schema Args
  (:f root String)
  (:f meta String)
  (:f baseline String)
  (:f list String)
  (:f seed String)
  (:f paths (List String)))

fn parseArgs args: (List String) a: Args -> (Result Args String)
  (mt (listHead args)
    ((none) (ok a))
    ((some x)
      (let [(rest (tailOf args)) (v (optionOr (listHead (tailOf args)) "")) (rest2 (tailOf (tailOf args)))]
        (cond
          ((and (stringStartsWith? x "--") (listEmpty? rest)) (err (str x " needs a value")))
          ((= x "--root") (parseArgs rest2 (with a :root v)))
          ((= x "--meta") (parseArgs rest2 (with a :meta v)))
          ((= x "--baseline") (parseArgs rest2 (with a :baseline v)))
          ((= x "--list") (parseArgs rest2 (with a :list v)))
          ((= x "--seed") (parseArgs rest2 (with a :seed v)))
          ((stringStartsWith? x "--") (err (str "unknown option " x)))
          (else (parseArgs rest (with a :paths (cons x a.paths))))))))

fn orDefault v: String d: String -> String
  (if (stringEmpty? v) d v)

fn fail! message: String code: Int64 -> (Result Int64 String)
  (do (println (str "(:metaAudit :status :error :ev \"" (esc message) "\")")) (ok code))

fn caseValue items: (List rd/SExpr) key: String -> String
  (unquote (atomText (optionOr (kvGet items key) (rd/makeAtom ""))))

fn seedCaseLine item: rd/SExpr -> String
  (let [(fields (itemsOf item))
        (id (caseValue fields ":id"))
        (expect (caseValue fields ":expect"))
        (token (caseValue fields ":token"))
        (also (caseValue fields ":also"))]
    (str "(:seed :id " id " :expect " expect
         (if (stringEmpty? token) "" (str " :token \"" token "\""))
         (if (stringEmpty? also) "" (str " :also \"" also "\""))
         ")"))

fn seedCaseItems items: (List rd/SExpr) acc: (List String) -> (List String)
  (mt (listHead items)
    ((none) (listReverse acc))
    ((some item)
      (let [(isCase (= (atomText (optionOr (listHead (itemsOf item)) (rd/makeAtom ""))) ":case"))]
        (seedCaseItems (optionOr (listTail items) (list)) (if isCase (cons (seedCaseLine item) acc) acc)))))

fn seedCaseReceipts cases: String -> (Result String String)
  (mt (parseForms cases)
    ((err e) (err (str "cases.asn does not read: " e)))
    ((ok forms)
      (mt (listHead forms)
        ((none) (err "cases.asn is empty"))
        ((some top)
          (let [(rows (seedCaseItems (itemsOf top) (list)))]
            (if (listEmpty? rows)
              (err "cases.asn has no :case rows")
              (ok (fold (fn [(acc String) (row String)] -> String (str acc row "\n")) "" rows))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (parseArgs args (Args :root "." :meta "" :baseline "" :list "" :seed "" :paths (list)))
    ((err e) (fail! (str e "; usage: metaAudit.asl [--root DIR] [--meta FILE] [--baseline FILE] [--list FILE] [--seed DATE] PATH...") 64))
    ((ok a)
      (let [(root a.root)
            (listed (if (stringEmpty? a.list) (ok (list)) (mt (fileRead a.list) ((ok t) (ok (listLines t))) ((err _) (err a.list)))))]
        (mt listed
          ((err p) (fail! (str "cannot read list file " p) 2))
          ((ok tracked)
            (let [(paths (listAppend tracked (listReverse a.paths)))]
              (if (listEmpty? paths)
                (fail! "no paths; usage: metaAudit.asl [--root DIR] [--meta FILE] [--baseline FILE] [--list FILE] [--seed DATE] PATH..." 64)
                (mt (fileRead (orDefault a.meta (joinPath root "asl/grammar/meta.asn")))
                  ((err _) (fail! "cannot read meta.asn" 2))
                  ((ok metaText)
                    (mt (loadSpec metaText)
                      ((err e) (fail! e 2))
                      ((ok spec)
                        (let [(ctx (loadCtx! root spec tracked))]
                          (if (not (stringEmpty? a.seed))
                            (do (print (baselineText (auditPaths! ctx (list) paths) a.seed)) (ok 0))
                            (mt (fileRead (orDefault a.baseline (joinPath root "scripts/audit/metaBaseline.asn")))
                              ((err _) (fail! "cannot read the baseline" 2))
                              ((ok baseText)
                                (mt (parseBaseline baseText)
                                  ((err e) (fail! e 2))
                                  ((ok rows)
                                    (let [(audit (auditPaths! ctx rows paths))]
                                      (do (println (receipt audit))
                                          (ok (if (listEmpty? audit.violations) 0 1)))))))))))))))))))))
