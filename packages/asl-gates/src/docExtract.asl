(module asl-gates/docExtract
  :x [DocCandidate ExtractResult ledgerPathFor findCandidates! stripSource extractFile! applyExtract! main]
  :i [(asl-parser/reader :a rd) (asl-parser/ast :a ast) (asl-gates/metaAudit :a meta)])

(schema DocCandidate
  (:f symbol String)
  (:f text String)
  (:f spanStart Int64)
  (:f spanEnd Int64)
  (:f replacement String))

(schema ExtractResult
  (:f path String)
  (:f candidates (List DocCandidate))
  (:f stripped String)
  (:f ledgerText String)
  (:f unchanged Bool))

fn isSpaceByte c: Int64 -> Bool
  (or (= c 32) (or (= c 9) (or (= c 10) (= c 13))))

fn lineStartOf b: Bytes i: Int64 -> Int64
  (cond ((<= i 0) 0) ((= (bytesGet b (- i 1)) 10) i) (else (lineStartOf b (- i 1))))

fn nextNewlineOrEnd b: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet b i) 10)) i (nextNewlineOrEnd b (+ i 1) n))

fn allWsLoop b: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n) true (if (isSpaceByte (bytesGet b i)) (allWsLoop b (+ i 1) n) false))

fn allWhitespaceBetween text: String a: Int64 b: Int64 -> Bool
  (allWsLoop (stringToBytes text) a b)

fn extendRemovalSpan text: String spanStart: Int64 spanEnd: Int64 -> (Pair Int64 Int64)
  (let [(b (stringToBytes text)) (n (bytesLength b))
        (lineBegin (lineStartOf b spanStart))
        (newStart (if (allWhitespaceBetween text lineBegin spanStart) lineBegin spanStart))
        (lineEndExcl (nextNewlineOrEnd b spanEnd n))
        (hasNl (and (< lineEndExcl n) (= (bytesGet b lineEndExcl) 10)))
        (lineEndIncl (if hasNl (+ lineEndExcl 1) lineEndExcl))
        (newEnd (if (allWhitespaceBetween text spanEnd lineEndExcl) lineEndIncl spanEnd))
        (inline (and (= newStart spanStart) (and (= newEnd spanEnd) (> spanStart 0))))]
    (pair (if (and inline (= (bytesGet b (- spanStart 1)) 32)) (- spanStart 1) newStart) newEnd))

fn indexOfFrom text: String needle: String from: Int64 -> (Option Int64)
  (if (or (< from 0) (> from (stringLength text)))
    (none)
    (mt (stringIndexOf (optionOr (stringSlice text from (stringLength text)) "") needle)
      ((none) (none))
      ((some rel) (some (+ from rel)))))

fn skipSpaceBack b: Bytes i: Int64 lo: Int64 -> Int64
  (if (and (> i lo) (isSpaceByte (bytesGet b (- i 1)))) (skipSpaceBack b (- i 1) lo) i)

fn colonDBefore text: String litStart: Int64 lo: Int64 -> (Option Int64)
  (let [(b (stringToBytes text)) (j (skipSpaceBack b litStart lo))]
    (if (and (>= j (+ lo 2)) (and (= (bytesGet b (- j 2)) 58) (= (bytesGet b (- j 1)) 100)))
      (some (- j 2))
      (none)))


fn isQuoted? s: String -> Bool
  (and (>= (stringLength s) 2) (and (stringStartsWith? s "\"") (stringEndsWith? s "\"")))

fn unquoteLiteral s: String -> String
  (optionOr (stringSlice s 1 (- (stringLength s) 1)) "")

fn spanTooFar? litStart: Int64 literal: String hi: Int64 -> Bool
  (> (+ litStart (stringLength literal)) hi)

fn dDocSpanAt text: String lo: Int64 hi: Int64 literal: String litStart: Int64 -> (Option (Pair Int64 Int64))
  (if (spanTooFar? litStart literal hi)
    (none)
    (mt (colonDBefore text litStart lo)
      ((none) (none))
      ((some kwStart) (some (extendRemovalSpan text kwStart (+ litStart (stringLength literal)))))))

fn dDocSpan text: String lo: Int64 hi: Int64 literal: String -> (Option (Pair Int64 Int64))
  (mt (indexOfFrom text literal lo)
    ((none) (none))
    ((some litStart) (dDocSpanAt text lo hi literal litStart)))

fn fieldDocSpanAt text: String lo: Int64 hi: Int64 literal: String litStart: Int64 -> (Option (Pair Int64 Int64))
  (if (spanTooFar? litStart literal hi)
    (none)
    (let [(b (stringToBytes text)) (wsStart (skipSpaceBack b litStart lo))]
      (some (extendRemovalSpan text wsStart (+ litStart (stringLength literal))))))

fn fieldDocSpan text: String lo: Int64 hi: Int64 literal: String -> (Option (Pair Int64 Int64))
  (mt (indexOfFrom text literal lo)
    ((none) (none))
    ((some litStart) (fieldDocSpanAt text lo hi literal litStart)))

fn moduleSymbol path: String -> String
  (str path "#")

fn fnSymbol path: String name: String -> String
  (str path "#" name)

fn fieldSymbol path: String schemaName: String fieldName: String -> String
  (str path "#" schemaName "." fieldName)

fn lineSymbol path: String lineNo: Int64 -> String
  (str path "#L" (stringFromInt64 lineNo))

(schema LineInfo
  (:f lineNo Int64)
  (:f start Int64)
  (:f endIncl Int64)
  (:f raw String))

fn buildLineSpans b: Bytes n: Int64 pos: Int64 lineNo: Int64 acc: (List (Pair Int64 (Pair Int64 Int64))) -> (List (Pair Int64 (Pair Int64 Int64)))
  (if (>= pos n)
    (listReverse acc)
    (let [(nl (nextNewlineOrEnd b pos n))
          (endIncl (if (< nl n) (+ nl 1) nl))]
      (buildLineSpans b n endIncl (+ lineNo 1) (cons (pair lineNo (pair pos endIncl)) acc))))

fn spanToLineInfo text: String sp: (Pair Int64 (Pair Int64 Int64)) -> LineInfo
  (let [(lineNo (pairFirst sp)) (startEnd (pairSecond sp)) (start (pairFirst startEnd)) (endIncl (pairSecond startEnd))]
    (LineInfo :lineNo lineNo :start start :endIncl endIncl :raw (optionOr (stringSlice text start endIncl) "")))

fn linesOf text: String -> (List LineInfo)
  (map (fn [(sp (Pair Int64 (Pair Int64 Int64)))] -> LineInfo (spanToLineInfo text sp))
       (buildLineSpans (stringToBytes text) (stringLength text) 0 1 (list)))

fn wsEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (or (= (bytesGet b i) 32) (= (bytesGet b i) 9))) (wsEnd b n (+ i 1)) i)

fn leadingWs raw: String -> String
  (let [(b (stringToBytes raw)) (n (bytesLength b))]
    (optionOr (stringSlice raw 0 (wsEnd b n 0)) ""))

fn stripSemicolons s: String -> String
  (if (stringStartsWith? s ";") (stripSemicolons (optionOr (stringSlice s 1 (stringLength s)) "")) s)

fn commentBody trimmed: String -> String
  (stringTrim (stripSemicolons trimmed))

fn isMetaFormBody? body: String -> Bool
  (or (= body "(:m)") (or (stringStartsWith? body "(:m ") (stringStartsWith? body "(:m\t")))

fn isIdentCode c: Int64 -> Bool
  (or (and (>= c 48) (<= c 57)) (or (and (>= c 65) (<= c 90)) (or (and (>= c 97) (<= c 122)) (or (= c 95) (or (= c 45) (or (= c 63) (= c 33)))))))

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
    ((some p) (if (stringStartsWith? text p) (some p) (firstPrefix text (optionOr (listTail prefixes) (list))))))

fn aslDefHeads -> (List String)
  (list "fn ! " "fn tailrec " "fn " "(fn " "(schema " "(enum " "(module " "(def ")

fn aslDefName text: String -> String
  (mt (firstPrefix text (aslDefHeads))
    ((some p) (leadingIdent (afterPrefix text p)))
    ((none) ""))

fn nextSubstantive lines: (List LineInfo) -> (Option LineInfo)
  (mt (listHead lines)
    ((none) (none))
    ((some li)
      (let [(t (stringTrim li.raw))]
        (if (or (stringEmpty? t) (stringStartsWith? t ";"))
          (nextSubstantive (optionOr (listTail lines) (list)))
          (some li)))))

fn commentSymbol path: String commentLineNo: Int64 rest: (List LineInfo) -> String
  (mt (nextSubstantive rest)
    ((none) (lineSymbol path commentLineNo))
    ((some li)
      (let [(name (aslDefName (stringTrim li.raw)))]
        (if (stringEmpty? name) (lineSymbol path commentLineNo) (fnSymbol path name)))))

fn freeCommentCandidate path: String li: LineInfo rest: (List LineInfo) body: String -> (Option DocCandidate)
  (if (stringEmpty? body)
    (none)
    (some (DocCandidate :symbol (commentSymbol path li.lineNo rest) :text (escRow body)
                         :spanStart li.start :spanEnd li.endIncl :replacement "")))

fn dropWhyPairs items: (List rd/SExpr) acc: (List rd/SExpr) why: String -> (Pair (List rd/SExpr) String)
  (mt (listHead items)
    ((none) (pair (listReverse acc) why))
    ((some k)
      (let [(rest (optionOr (listTail items) (list)))]
        (mt (listHead rest)
          ((none) (pair (listReverse (cons k acc)) why))
          ((some v) (dropWhyStep k v (optionOr (listTail rest) (list)) acc why))))))

fn dropWhyStep k: rd/SExpr v: rd/SExpr rest2: (List rd/SExpr) acc: (List rd/SExpr) why: String -> (Pair (List rd/SExpr) String)
  (if (= (rd/sexprHead k) ":why")
    (dropWhyPairs rest2 acc (unquoteLiteral (rd/sexprHead v)))
    (dropWhyPairs rest2 (cons v (cons k acc)) why))

fn metaReplacement indent: String remaining: (List rd/SExpr) -> String
  (if (listEmpty? remaining)
    ""
    (str indent "; (:m " (stringJoin (map rd/renderSexpr remaining) " ") ")\n"))

fn metaFormCandidate path: String li: LineInfo rest: (List LineInfo) remaining: (List rd/SExpr) why: String indent: String -> (Option DocCandidate)
  (if (stringEmpty? why)
    (none)
    (some (DocCandidate :symbol (commentSymbol path li.lineNo rest) :text why
                         :spanStart li.start :spanEnd li.endIncl
                         :replacement (metaReplacement indent remaining))))

fn metaCommentCandidate path: String li: LineInfo rest: (List LineInfo) body: String indent: String -> (Option DocCandidate)
  (mt (meta/parseForms body)
    ((err _) (none))
    ((ok forms)
      (mt (listHead forms)
        ((none) (none))
        ((some form)
          (let [(items (optionOr (listTail (rd/sexprToList form)) (list)))
                (r (dropWhyPairs items (list) ""))]
            (metaFormCandidate path li rest (pairFirst r) (pairSecond r) indent))))))

fn commentCandidate path: String li: LineInfo rest: (List LineInfo) -> (Option DocCandidate)
  (let [(raw li.raw) (trimmed (stringTrim raw))]
    (if (not (stringStartsWith? trimmed ";"))
      (none)
      (let [(body (commentBody trimmed)) (indent (leadingWs raw))]
        (if (isMetaFormBody? body)
          (metaCommentCandidate path li rest body indent)
          (freeCommentCandidate path li rest body)))))

fn commentScanAll path: String lines: (List LineInfo) -> (List DocCandidate)
  (mt (listHead lines)
    ((none) (list))
    ((some li)
      (let [(rest (optionOr (listTail lines) (list)))]
        (mt (commentCandidate path li rest)
          ((none) (commentScanAll path rest))
          ((some c) (cons c (commentScanAll path rest)))))))

fn kidOf k: ast/KidForm -> (Pair Int64 Int64)
  (pair k.startOffset k.endOffset)

fn isModuleKid? k: ast/KidForm -> Bool
  (let [(e k.pf.expr)] (and (rd/isList? e) (= (rd/sexprHead e) "module")))

fn moduleKidOf kids: (List ast/KidForm) -> (Option ast/KidForm)
  (mt (listHead kids)
    ((none) (none))
    ((some k) (if (isModuleKid? k) (some k) (moduleKidOf (optionOr (listTail kids) (list))))))

fn restKids kids: (List ast/KidForm) -> (List ast/KidForm)
  (filter (fn [(k ast/KidForm)] -> Bool (not (isModuleKid? k))) kids)

(schema FieldAcc
  (:f cursor Int64)
  (:f out (List DocCandidate)))

fn fieldCandidateFound path: String schemaName: String hi: Int64 f: ast/AstField doc: String rest: (List ast/AstField) text: String acc: FieldAcc sp: (Pair Int64 Int64) -> FieldAcc
  (let [(cand (DocCandidate :symbol (fieldSymbol path schemaName f.name) :text (unquoteLiteral doc)
                             :spanStart (pairFirst sp) :spanEnd (pairSecond sp) :replacement ""))
        (nextAcc (FieldAcc :cursor (pairSecond sp) :out (cons cand acc.out)))]
    (fieldCandidates path schemaName hi rest text nextAcc))

fn fieldCandidatesStep path: String schemaName: String hi: Int64 f: ast/AstField rest: (List ast/AstField) text: String acc: FieldAcc -> FieldAcc
  (let [(doc f.docstring)]
    (if (not (isQuoted? doc))
      (fieldCandidates path schemaName hi rest text acc)
      (mt (fieldDocSpan text acc.cursor hi doc)
        ((none) (fieldCandidates path schemaName hi rest text acc))
        ((some sp) (fieldCandidateFound path schemaName hi f doc rest text acc sp)))))

fn fieldCandidates path: String schemaName: String hi: Int64 fields: (List ast/AstField) text: String acc: FieldAcc -> FieldAcc
  (mt (listHead fields)
    ((none) acc)
    ((some f) (fieldCandidatesStep path schemaName hi f (optionOr (listTail fields) (list)) text acc)))

fn candidatesFor path: String text: String top: ast/TopForm span: (Pair Int64 Int64) -> (List DocCandidate)
  (let [(lo (pairFirst span)) (hi (pairSecond span))]
    (mt top
      ((ast/topModule node)
        (let [(doc node.docstring)]
          (if (not (isQuoted? doc)) (list)
            (mt (dDocSpan text lo hi doc)
              ((none) (list))
              ((some sp) (list (DocCandidate :symbol (moduleSymbol path) :text (unquoteLiteral doc)
                                              :spanStart (pairFirst sp) :spanEnd (pairSecond sp) :replacement "")))))))
      ((ast/topDefun node)
        (let [(doc node.docstring)]
          (if (not (isQuoted? doc)) (list)
            (mt (dDocSpan text lo hi doc)
              ((none) (list))
              ((some sp) (list (DocCandidate :symbol (fnSymbol path node.name) :text (unquoteLiteral doc)
                                              :spanStart (pairFirst sp) :spanEnd (pairSecond sp) :replacement "")))))))
      ((ast/topSchema node)
        (listReverse (fieldCandidates path node.name hi node.fields text (FieldAcc :cursor lo :out (list))).out))
      ((ast/topEnum _) (list))
      ((ast/topExpr _) (list))))

fn zipTopsKids tops: (List ast/TopForm) kids: (List ast/KidForm) path: String text: String acc: (List DocCandidate) -> (List DocCandidate)
  (mt (listHead tops)
    ((none) (listReverse acc))
    ((some top)
      (mt (listHead kids)
        ((none) (listReverse acc))
        ((some k)
          (zipTopsKids (optionOr (listTail tops) (list)) (optionOr (listTail kids) (list)) path text
            (listAppend (listReverse (candidatesFor path text top (kidOf k))) acc))))))

fn candidatesFromTops path: String text: String mk: ast/KidForm rest: (List ast/KidForm) tops: (List ast/TopForm) -> (List DocCandidate)
  (let [(modTop (optionOr (listHead tops) (ast/topExpr (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0))))
        (declTops (optionOr (listTail tops) (list)))
        (modCands (candidatesFor path text modTop (kidOf mk)))
        (declCands (zipTopsKids declTops rest path text (list)))]
    (listAppend modCands declCands))

fn findCandidatesWithTops! path: String text: String allKids: (List ast/KidForm) tops: (List ast/TopForm) -> (Result (List DocCandidate) String)
  (let [(modKid (moduleKidOf allKids)) (rest (restKids allKids))]
    (mt modKid
      ((none) (ok (list)))
      ((some mk) (ok (candidatesFromTops path text mk rest tops)))))

fn withComments path: String text: String dCands: (List DocCandidate) -> (List DocCandidate)
  (listAppend dCands (commentScanAll path (linesOf text)))

fn findCandidates! path: String text: String -> (Result (List DocCandidate) String)
  (mt (ast/kidFormsFor text)
    ((err e) (err e.msg))
    ((ok allKids)
      (mt (ast/parseLegacy text)
        ((err e) (err e.msg))
        ((ok tops)
          (mt (findCandidatesWithTops! path text allKids tops)
            ((err e) (err e))
            ((ok dCands) (ok (withComments path text dCands))))))))

fn escRow s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn rowLine c: DocCandidate -> String
  (str "(:doc :symbol \"" (escRow c.symbol) "\" :text \"" c.text "\")")

fn ledgerLines cs: (List DocCandidate) -> String
  (stringJoin (map rowLine cs) "\n")

fn sortedSpans cs: (List DocCandidate) -> (List DocCandidate)
  (listSortBy (fn [(c DocCandidate)] -> Int64 c.spanStart) cs)

fn buildStripped text: String spans: (List DocCandidate) cursor: Int64 acc: String -> String
  (mt (listHead spans)
    ((none) (str acc (optionOr (stringSlice text cursor (stringLength text)) "")))
    ((some c)
      (let [(rest (optionOr (listTail spans) (list)))
            (piece (optionOr (stringSlice text cursor c.spanStart) ""))]
        (buildStripped text rest c.spanEnd (str acc piece c.replacement)))))

fn stripSource text: String candidates: (List DocCandidate) -> String
  (buildStripped text (sortedSpans candidates) 0 "")

fn pkgOf path: String -> (Option String)
  (let [(parts (stringSplit path "/"))]
    (if (and (>= (listLength parts) 3) (and (= (optionOr (listGet parts 0) "") "asl") (= (optionOr (listGet parts 1) "") "packages")))
      (some (optionOr (listGet parts 2) ""))
      (none)))


fn secondSeg path: String -> String
  (optionOr (listGet (stringSplit path "/") 1) "misc")

fn firstSeg path: String -> String
  (optionOr (listGet (stringSplit path "/") 0) "misc")

fn ledgerPathFor path: String -> String
  (mt (pkgOf path)
    ((some pkg) (str "asl/packages/" pkg "/doc.asn"))
    ((none)
      (if (stringStartsWith? path "asl/")
        (str "asl/doc/" (secondSeg path) ".asn")
        (str ".asl/mem/docs/" (firstSeg path) ".asn"))))

fn extractFile! root: String relPath: String -> (Result ExtractResult String)
  (mt (fileReadString (str root "/" relPath))
    ((err e) (err e))
    ((ok text)
      (mt (findCandidates! relPath text)
        ((err e) (err e))
        ((ok cands)
          (ok (ExtractResult :path relPath :candidates cands
                             :stripped (stripSource text cands)
                             :ledgerText (ledgerLines cands)
                             :unchanged (listEmpty? cands)))))))

fn dirOf p: String -> String
  (let [(parts (stringSplit p "/")) (n (listLength parts))]
    (if (<= n 1) "" (stringJoin (listTake parts (- n 1)) "/")))

fn appendToFile! path: String rows: String -> (Result Unit String)
  (let [(existing (mt (fileReadString path) ((ok t) t) ((err _) "")))
        (sep (if (or (stringEmpty? existing) (stringEndsWith? existing "\n")) "" "\n"))
        (next (str existing sep rows "\n"))]
    (fileWrite path next))

fn ensureLedgerDir! ledgerPath: String -> (Result Unit String)
  (let [(dir (dirOf ledgerPath))]
    (if (stringEmpty? dir) (ok ()) (dirCreate dir)))

fn writeFiles! srcPath: String stripped: String ledgerPath: String ledgerText: String ledgerRel: String -> (Result String String)
  (mt (fileWrite srcPath stripped)
    ((err e) (err e))
    ((ok _) (writeLedger! ledgerPath ledgerText ledgerRel)))

fn writeLedger! ledgerPath: String ledgerText: String ledgerRel: String -> (Result String String)
  (mt (appendToFile! ledgerPath ledgerText)
    ((err e) (err e))
    ((ok _) (ok ledgerRel)))

fn writeStrippedAndLedger! root: String r: ExtractResult ledgerRel: String -> (Result String String)
  (let [(ledgerPath (str root "/" ledgerRel)) (srcPath (str root "/" r.path))]
    (mt (ensureLedgerDir! ledgerPath)
      ((err e) (err e))
      ((ok _) (writeFiles! srcPath r.stripped ledgerPath r.ledgerText ledgerRel))))

fn applyExtract! root: String r: ExtractResult -> (Result String String)
  (if r.unchanged (ok "") (writeStrippedAndLedger! root r (ledgerPathFor r.path)))

fn reportApplied! r: ExtractResult root: String n: Int64 -> Int64
  (mt (applyExtract! root r)
    ((err e) (do (println (str "(:docExtract :file \"" r.path "\" :status :error :message \"" e "\")")) 1))
    ((ok ledgerPath) (do (println (str "(:docExtract :file \"" r.path "\" :found " (stringFromInt64 n) " :applied true :ledger \"" ledgerPath "\")")) 0)))

fn reportDry! r: ExtractResult n: Int64 -> Int64
  (do (println (str "(:docExtract :file \"" r.path "\" :found " (stringFromInt64 n) " :applied false :ledger \"" (ledgerPathFor r.path) "\")")) 0)

fn printResult! r: ExtractResult apply: Bool root: String -> Int64
  (let [(n (listLength r.candidates))]
    (cond
      (r.unchanged (do (println (str "(:docExtract :file \"" r.path "\" :found 0)")) 0))
      (apply (reportApplied! r root n))
      (else (reportDry! r n))))

fn runFiles! root: String apply: Bool files: (List String) status: Int64 -> Int64
  (mt (listHead files)
    ((none) status)
    ((some f)
      (mt (extractFile! root f)
        ((err e) (do (println (str "(:docExtract :file \"" f "\" :status :error :message \"" e "\")")) (runFiles! root apply (optionOr (listTail files) (list)) 1)))
        ((ok r)
          (let [(rc (printResult! r apply root))]
            (runFiles! root apply (optionOr (listTail files) (list)) (max status rc)))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(apply (listContains? args "--apply"))
        (files (filter (fn [(a String)] -> Bool (!= a "--apply")) args))]
    (if (listEmpty? files)
      (do (println "(:docExtract :status :error :message \"usage: docExtract.asl [--apply] FILE...\")") (ok 64))
      (ok (runFiles! "." apply files 0))))
