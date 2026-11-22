(module asl-gates/docLedger
  :x [DocRow RowFinding loadLedger! findBySymbol! findByFile! renderText unresolvedSymbols! checkLedger! exportsOf aslFilesUnder! rowCap contentWords nameEcho? paraphrase? nameLead? metaEcho? sentenceCount textReasons kindReason testSource? metaOf ledgerPath? ledgerFiles! treeRows! localFindings! crossUsed! addedRows rowFindings! looseAdded rowKey autodropPlan! dropFromText dropRowsText dropRows! treeFindings! main]
  :i [(asl-parser/reader :a rd) (asl-parser/ast :a ast) (asl-syntax/asl/asn :a asn) (asl-gates/metaAudit :a meta) (asl-gates/docExtract :a dx)])

(schema DocRow
  (:f symbol String)
  (:f text String))

fn isQuotedAtom? v: rd/SExpr -> Bool
  (and (rd/isAtom? v) (let [(s (rd/sexprHead v))] (and (>= (stringLength s) 2) (and (stringStartsWith? s "\"") (stringEndsWith? s "\"")))))

fn unquote s: String -> String
  (optionOr (stringSlice s 1 (- (stringLength s) 1)) "")

fn kwName v: rd/SExpr -> (Option String)
  (if (and (rd/isAtom? v) (stringStartsWith? (rd/sexprHead v) ":")) (some (optionOr (stringSlice (rd/sexprHead v) 1 (stringLength (rd/sexprHead v))) "")) (none))

(schema KvAcc
  (:f symbol (Option String))
  (:f text (Option String))
  (:f bad Bool))

fn kvStep acc: KvAcc key: String val: rd/SExpr -> KvAcc
  (cond
    ((not (isQuotedAtom? val)) (with acc :bad true))
    ((= key "symbol") (with acc :symbol (some (unquote (rd/sexprHead val)))))
    ((= key "text") (with acc :text (some (unquote (rd/sexprHead val)))))
    (else (with acc :bad true)))

fn kvLoop items: (List rd/SExpr) acc: KvAcc -> KvAcc
  (match (listHead items)
    ((none) acc)
    ((some k)
      (let [(tail (optionOr (listTail items) (list)))]
        (match (kwName k)
          ((none) (with acc :bad true))
          ((some key)
            (match (listHead tail)
              ((none) (with acc :bad true))
              ((some v) (kvLoop (optionOr (listTail tail) (list)) (kvStep acc key v)))))))))

fn rowFromSym acc: KvAcc sym: String -> (Result DocRow String)
  (match acc.text
    ((none) (err "doc ledger row is missing :text"))
    ((some txt) (ok (DocRow :symbol sym :text txt))))

fn rowFromAcc acc: KvAcc -> (Result DocRow String)
  (if acc.bad (err "doc ledger row has an unknown key or a non-string value")
    (match acc.symbol
      ((none) (err "doc ledger row is missing :symbol"))
      ((some sym) (rowFromSym acc sym))))

fn rowFromForm f: rd/SExpr -> (Result DocRow String)
  (if (not (rd/isList? f)) (err "doc ledger row must be a list")
    (if (!= (rd/sexprHead f) ":doc") (err (str "doc ledger row must start with :doc, found " (rd/sexprHead f)))
      (rowFromAcc (kvLoop (optionOr (listTail (rd/sexprToList f)) (list)) (KvAcc :symbol (none) :text (none) :bad false)))))

fn rowsAppend row: DocRow restResult: (Result (List DocRow) String) -> (Result (List DocRow) String)
  (match restResult
    ((err e) (err e))
    ((ok rest) (ok (cons row rest))))

fn rowsStep form: rd/SExpr rest: (List rd/SExpr) -> (Result (List DocRow) String)
  (match (rowFromForm form)
    ((err e) (err e))
    ((ok row) (rowsAppend row (rowsFromForms rest))))

fn rowsFromForms forms: (List rd/SExpr) -> (Result (List DocRow) String)
  (match (listHead forms)
    ((none) (ok (list)))
    ((some f) (rowsStep f (optionOr (listTail forms) (list)))))

fn parseLedgerText text: String -> (Result (List DocRow) String)
  (match (meta/parseForms text)
    ((err e) (err e))
    ((ok forms) (rowsFromForms forms)))

fn loadLedgerFile! path: String -> (Result (List DocRow) String)
  (match (fileReadString path)
    ((err e) (err e))
    ((ok text) (parseLedgerText text)))

fn loadLedger! path: String -> (Result (List DocRow) String)
  (if (not (fileExists? path)) (ok (list)) (loadLedgerFile! path))

fn findRowBySymbol rows: (List DocRow) symbol: String -> (Option DocRow)
  (match (listHead rows)
    ((none) (none))
    ((some r) (if (= r.symbol symbol) (some r) (findRowBySymbol (optionOr (listTail rows) (list)) symbol))))

fn hashIdx symbol: String -> Int64
  (optionOr (stringIndexOf symbol "#") (- 0 1))

fn relPathOf symbol: String -> String
  (let [(idx (hashIdx symbol))] (if (< idx 0) symbol (optionOr (stringSlice symbol 0 idx) "")))

fn findBySymbol! root: String symbol: String -> (Result (Option DocRow) String)
  (let [(idx (hashIdx symbol))]
    (if (< idx 0) (err "symbol must contain '#' separating its file path from its name")
      (let [(relPath (relPathOf symbol)) (ledgerPath (str root "/" (dx/ledgerPathFor relPath)))]
        (match (loadLedger! ledgerPath)
          ((err e) (err e))
          ((ok rows) (ok (findRowBySymbol rows symbol)))))))

fn findByFile! root: String file: String -> (Result (List DocRow) String)
  (let [(ledgerPath (str root "/" (dx/ledgerPathFor file))) (prefix (str file "#"))]
    (match (loadLedger! ledgerPath)
      ((err e) (err e))
      ((ok rows) (ok (filter (fn [(r DocRow)] -> Bool (stringStartsWith? r.symbol prefix)) rows)))))

fn renderText t: String -> String
  (resultOr (asn/asnUnescape t) t)

fn escRow s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn digitChar? c: String -> Bool
  (and (>= (charCode c) 48) (<= (charCode c) 57))

fn isLineSymbol? name: String -> Bool
  (let [(rest (optionOr (stringSlice name 1 (stringLength name)) ""))]
    (and (stringStartsWith? name "L") (and (not (stringEmpty? rest)) (listAll? digitChar? (stringChars rest)))))

fn defNamesMatch? tops: (List ast/TopForm) name: String -> Bool
  (listAny? (fn [(t ast/TopForm)] -> Bool
    (match t
      ((ast/topDefun n) (= n.name name))
      ((ast/topSchema n) (= n.name name))
      ((ast/topEnum n) (= n.name name))
      (_ false)))
    tops)

fn fieldExists? tops: (List ast/TopForm) schemaName: String fieldName: String -> Bool
  (listAny? (fn [(t ast/TopForm)] -> Bool
    (match t
      ((ast/topSchema n) (and (= n.name schemaName) (listAny? (fn [(f ast/AstField)] -> Bool (= f.name fieldName)) n.fields)))
      (_ false)))
    tops)

fn fieldSymbolResolves? tops: (List ast/TopForm) name: String -> Bool
  (let [(dotIdx (optionOr (stringIndexOf name ".") (- 0 1)))]
    (if (< dotIdx 0) false
      (fieldExists? tops (optionOr (stringSlice name 0 dotIdx) "") (optionOr (stringSlice name (+ dotIdx 1) (stringLength name)) ""))))

fn nameResolves? tops: (List ast/TopForm) name: String -> Bool
  (cond
    ((stringEmpty? name) true)
    ((isLineSymbol? name) true)
    ((stringContains? name ".") (fieldSymbolResolves? tops name))
    (else (defNamesMatch? tops name)))

fn ! resolveParsed! text: String name: String -> Bool
  (match (ast/parse text)
    ((err _) false)
    ((ok tops) (nameResolves? tops name)))

fn ! resolveFileText! full: String name: String -> Bool
  (match (fileReadString full)
    ((err _) false)
    ((ok text) (resolveParsed! text name)))

fn ! resolveFile! full: String name: String -> Bool
  (if (not (fileExists? full)) false (resolveFileText! full name))

fn ! rowResolvesAt! root: String symbol: String idx: Int64 -> Bool
  (let [(relPath (relPathOf symbol)) (name (optionOr (stringSlice symbol (+ idx 1) (stringLength symbol)) ""))
        (full (str root "/" relPath))]
    (resolveFile! full name))

fn ! rowResolves! root: String row: DocRow -> Bool
  (let [(symbol row.symbol) (idx (hashIdx symbol))]
    (if (< idx 0) false (rowResolvesAt! root symbol idx)))

fn ! unresolvedSymbols! root: String rows: (List DocRow) -> (List String)
  (match (listHead rows)
    ((none) (list))
    ((some r)
      (let [(tail (optionOr (listTail rows) (list)))]
        (if (rowResolves! root r) (unresolvedSymbols! root tail) (cons r.symbol (unresolvedSymbols! root tail))))))

fn ! checkLedger! root: String ledgerPath: String -> (Result (List String) String)
  (match (loadLedger! (str root "/" ledgerPath))
    ((err e) (err e))
    ((ok rows) (ok (unresolvedSymbols! root rows))))

; (:m :ref DOCLEDGER-TOOLS-COVERAGE :do "the :x names of a file's module form; a file that does not parse yields the one name !parse, so a gap is reported for it rather than its exports being skipped")
fn exportsOf text: String -> (List String)
  (match (ast/parse text)
    ((err _) (list "!parse"))
    ((ok tops) (fold (fn [(acc (List String)) (t ast/TopForm)] -> (List String)
                       (match t ((ast/topModule n) (listAppend acc n.exported)) (_ acc)))
                     (list) tops)))

fn skipDir? name: String -> Bool
  (or (stringStartsWith? name ".") (or (= name "out") (= name "fixtures")))

fn ! filesUnder! dir: String rel: String names: (List String) acc: (List String) -> (Result (List String) String)
  (match (listHead names)
    ((none) (ok acc))
    ((some name)
      (let [(rest (listDrop names 1)) (path (str rel "/" name))]
        (match (fileStat (str dir "/" path))
          ((err e) (err (str path ": " e)))
          ((ok st) (cond
            ((and st.isDir (skipDir? name)) (filesUnder! dir rel rest acc))
            (st.isDir (match (aslFilesUnder! dir path)
                        ((err e) (err e))
                        ((ok sub) (filesUnder! dir rel rest (listAppend acc sub)))))
            ((stringStartsWith? name ".") (filesUnder! dir rel rest acc))
            ((stringEndsWith? name ".asl") (filesUnder! dir rel rest (listAppend acc (list path))))
            (else (filesUnder! dir rel rest acc))))))))

; (:m :ref DOCLEDGER-TOOLS-COVERAGE :do "every .asl file under root/rel, as root-relative paths sorted by name, skipping dot dirs and dot files (a .asl_chk_print_* temp a killed check left beside its source is not a source), build outputs (out) and fixtures")
fn ! aslFilesUnder! root: String rel: String -> (Result (List String) String)
  (match (dirList (str root "/" rel))
    ((err e) (err (str rel ": " e)))
    ((ok names) (filesUnder! root rel (listSort names) (list))))

fn ! reportSymbol! root: String symbol: String -> Int64
  (match (findBySymbol! root symbol)
    ((err e) (do (println (str "(:doc :symbol \"" symbol "\" :status :error :message \"" e "\")")) 1))
    ((ok found) (match found
      ((none) (do (println (str "(:doc :symbol \"" symbol "\" :found false)")) 0))
      ((some row) (do (println (str "(:doc :symbol \"" symbol "\" :found true :text \"" (escRow (renderText row.text)) "\")")) 0)))))

fn rowLine! r: DocRow -> String
  (str "(:row :symbol \"" r.symbol "\" :text \"" (escRow (renderText r.text)) "\")")

fn ! reportFile! root: String file: String -> Int64
  (match (findByFile! root file)
    ((err e) (do (println (str "(:doc :file \"" file "\" :status :error :message \"" e "\")")) 1))
    ((ok rows) (do (println (str "(:doc :file \"" file "\" :found " (stringFromInt64 (listLength rows)) " :rows [" (stringJoin (map rowLine! rows) " ") "])")) 0)))

fn ! main args: (List String) -> (Result Int64 String)
  (if (= (optionOr (listHead args) "") "--check") (ok (reportFindings! "."))
  (let [(fileMode (listContains? args "--file"))
        (rest (filter (fn [(a String)] -> Bool (!= a "--file")) args))
        (key (optionOr (listHead rest) ""))]
    (if (stringEmpty? key)
      (do (println "(:doc :status :error :message \"usage: docLedger.asl [--file] SYMBOL|FILE\")") (ok 64))
      (ok (if fileMode (reportFile! "." key) (reportSymbol! "." key))))))

; (:m :ref DOC-THIN :do "rule docs (asl/grammar/rules.asn): a (:doc) row is never required and may only light up what the name and types do not say; a finding is kind refused (the row breaks the rule, why names which part) or stale (the row names a symbol or file that is gone), with the ledger the row lives in")
(schema RowFinding
  (:f kind String)
  (:f sym String)
  (:f why String)
  (:f ledger String)
  (:f text String :default ""))

(schema SrcFacts
  (:f exists Bool)
  (:f parsed Bool)
  (:f tops (List ast/TopForm))
  (:f exports (List String))
  (:f metas (Map String String))
  (:f test Bool))

(schema Header
  (:f name String)
  (:f exports (List String))
  (:f imports (List (Pair String String))))

; (:m :ref DOC-THIN :do "adopted cap: p90 of the text length of 19815 rows measured 2026-11-21 was 197 chars")
fn rowCap -> Int64
  200

fn alnumByte? b: Int64 -> Bool
  (or (and (>= b 97) (<= b 122)) (or (and (>= b 65) (<= b 90)) (and (>= b 48) (<= b 57))))

fn upperByte? b: Int64 -> Bool
  (and (>= b 65) (<= b 90))

fn sliceOr s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn wordsLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (< start 0) acc (cons (stringLower (sliceOr s start n)) acc)))
    (let [(b (bytesGet bs i))]
      (cond
        ((not (alnumByte? b)) (wordsLoop s bs n (+ i 1) -1 (if (< start 0) acc (cons (stringLower (sliceOr s start i)) acc))))
        ((< start 0) (wordsLoop s bs n (+ i 1) i acc))
        ((and (upperByte? b) (not (upperByte? (bytesGet bs (- i 1))))) (wordsLoop s bs n (+ i 1) i (cons (stringLower (sliceOr s start i)) acc)))
        (else (wordsLoop s bs n (+ i 1) start acc)))))

; (:m :ref DOC-THIN :do "the words of a text or a name: split at every byte that is not an ASCII letter or digit and before an upper-case letter that follows a lower-case one, lower-cased")
fn camelWords s: String -> (List String)
  (let [(bs (stringToBytes s))] (wordsLoop s bs (bytesLength bs) 0 -1 (list)))

fn stopWords -> (List String)
  (list "a" "an" "the" "of" "to" "in" "on" "for" "by" "with" "from" "at" "as" "into" "and" "or" "is" "are" "was" "be" "been" "it" "its" "this" "that" "these" "those" "which" "what" "when" "whether" "if" "then" "so" "each" "every" "all" "any" "some" "one" "per" "via" "return" "returns" "returned" "get" "gets" "give" "gives" "given" "value" "values" "function" "fn" "helper" "true" "false" "has" "have" "do" "does" "can" "may" "will" "also" "only" "just" "same" "own" "s" "e" "g" "i")

fn abbreviations -> (List (Pair String String))
  (list (pair "identifier" "id") (pair "identifiers" "id") (pair "ids" "id") (pair "number" "num") (pair "numbers" "num") (pair "string" "str") (pair "strings" "str") (pair "length" "len") (pair "message" "msg") (pair "messages" "msg") (pair "configuration" "config") (pair "cfg" "config") (pair "directory" "dir") (pair "directories" "dir") (pair "milliseconds" "ms") (pair "millisecond" "ms") (pair "seconds" "sec") (pair "second" "sec") (pair "secs" "sec") (pair "arguments" "arg") (pair "argument" "arg") (pair "args" "arg") (pair "parameters" "param") (pair "parameter" "param") (pair "params" "param") (pair "index" "idx") (pair "indices" "idx") (pair "position" "pos") (pair "positions" "pos") (pair "information" "info") (pair "specification" "spec") (pair "expression" "expr") (pair "expressions" "expr") (pair "temporary" "tmp") (pair "temp" "tmp") (pair "buffer" "buf") (pair "buffers" "buf") (pair "character" "char") (pair "characters" "char") (pair "chars" "char"))

fn canon w: String -> String
  (match (listFind (fn [(p (Pair String String))] -> Bool (= (pairFirst p) w)) (abbreviations))
    ((some p) (pairSecond p))
    ((none) (if (and (> (stringLength w) 3) (and (stringEndsWith? w "s") (not (stringEndsWith? w "ss")))) (sliceOr w 0 (- (stringLength w) 1)) w)))

fn contentWords text: String -> (List String)
  (map canon (filter (fn [(w String)] -> Bool (not (listContains? (stopWords) w))) (camelWords text)))

fn symPath sym: String -> String
  (sliceOr sym 0 (optionOr (stringIndexOf sym "#") 0))

fn symName sym: String -> String
  (sliceOr sym (+ (optionOr (stringIndexOf sym "#") (stringLength sym)) 1) (stringLength sym))

; (:m :ref DOC-THIN :do "name echo: every content word of the text is a word of the symbol's name or of its file path, after stop words, a light plural strip and a fixed abbreviation map (id and identifier are one word); an empty text is an echo too")
fn nameEcho? sym: String text: String -> Bool
  (let [(own (map canon (listAppend (camelWords (symName sym)) (camelWords (stringReplace (symPath sym) ".asl" "")))))]
    (listAll? (fn [(w String)] -> Bool (listContains? own w)) (contentWords text)))

fn paraphraseStarts -> (List String)
  (list "returns " "return " "takes " "gets " "get " "given " "true when " "true if " "true for " "computes " "builds " "creates ")

fn reasonMarkers -> (List String)
  (list " because " " so that " " since " " why " " to avoid " " otherwise " " instead " " used by " " called by " " caller" " unless " " never " " keeps " " prevents " " prevent " " avoids " " avoid ")

fn spaced text: String -> String
  (str " " (fold (fn [(t String) (c String)] -> String (stringReplace t c " ")) (stringLower text) (list "," ";" ":" "." "(" ")" "\"")) " ")

; (:m :ref DOC-THIN :do "the openings that restate a type: an X from its ..., the X of ..., and a lone word with a colon (name: ...)")
fn shapeLead? low: String -> Bool
  (let [(w (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (stringSplit low " ")))
        (w0 (optionOr (listGet w 0) "")) (w2 (optionOr (listGet w 2) "")) (w3 (optionOr (listGet w 3) ""))]
    (or (and (or (= w0 "a") (= w0 "an")) (and (= w2 "from") (= w3 "its")))
        (or (and (= w0 "the") (= w2 "of"))
            (and (stringEndsWith? w0 ":") (and (> (stringLength w0) 1) (not (stringContains? (sliceOr w0 0 (- (stringLength w0) 1)) ":")))))))

; (:m :ref DOC-THIN :do "signature paraphrase: the text opens with returns, takes, gets, given, true when, if or for, computes, builds or creates, or with a shapeLead?, and carries no reason or scenario marker, so it says what the type already says")
fn paraphrase? text: String -> Bool
  (let [(low (stringLower (stringTrim text))) (sp (spaced text))]
    (and (or (listAny? (fn [(p String)] -> Bool (stringStartsWith? low p)) (paraphraseStarts)) (shapeLead? low))
         (not (listAny? (fn [(m String)] -> Bool (stringContains? sp m)) (reasonMarkers)))))

; (:m :ref DOC-THIN :do "a row repeats the (:m) above its symbol when at least 60 percent of its content words occur in that (:m) text")
fn metaEcho? meta: String text: String -> Bool
  (let [(mw (contentWords meta)) (dw (contentWords text)) (hit (listLength (filter (fn [(w String)] -> Bool (listContains? mw w)) dw)))]
    (and (not (stringEmpty? (stringTrim meta))) (and (not (listEmpty? dw)) (>= (* 10 hit) (* 6 (listLength dw))))))

fn sentLoop bs: Bytes n: Int64 i: Int64 k: Int64 -> Int64
  (if (>= (+ i 2) n) k
    (let [(b (bytesGet bs i)) (c (bytesGet bs (+ i 2)))]
      (sentLoop bs n (+ i 1) (if (and (or (= b 46) (or (= b 33) (= b 63))) (and (= (bytesGet bs (+ i 1)) 32) (upperByte? c))) (+ k 1) k))))

; (:m :ref DOC-THIN :do "sentences: one plus every . ! or ? followed by a space and an upper-case letter, e.g. and i.e. not counted")
fn sentenceCount text: String -> Int64
  (let [(bs (stringToBytes (stringReplace (stringReplace text "e.g. " "eg ") "i.e. " "ie ")))]
    (sentLoop bs (bytesLength bs) 0 1))

; (:m :ref DOC-THIN :do "a text that opens with the symbol's own name and then its arguments, a colon or a parenthesis restates the call, whatever follows")
fn nameLead? sym: String text: String -> Bool
  (let [(nm (stringLower (stringReplace (stringReplace (symName sym) "!" "") "?" ""))) (low (stringLower (stringTrim text)))]
    (and (> (stringLength nm) 2) (listAny? (fn [(c String)] -> Bool (stringStartsWith? low (str nm c))) (list " " ":" "("))))

fn textReasons sym: String text: String meta: String -> (List String)
  (let [(t (renderText text)) (echo (nameEcho? sym t))]
    (filter (fn [(r String)] -> Bool (not (stringEmpty? r)))
            (list (if echo "nameEcho" "")
                  (if (and (not echo) (or (paraphrase? t) (nameLead? sym t))) "paraphrase" "")
                  (if (metaEcho? meta t) "metaEcho" "")
                  (if (> (sentenceCount t) 1) "sentences" "")
                  (if (> (stringLength t) (rowCap)) "overCap" ""))))

; (:m :ref DOC-THIN :do "a test directory is a path segment tests, test, fixtures or corpus; a file name ending in Test.asl is not a sign, asl/tools/nativeTest.asl is the runner itself")
fn testDir? p: String -> Bool
  (listAny? (fn [(x String)] -> Bool (or (= x "tests") (or (= x "test") (or (= x "fixtures") (= x "corpus"))))) (stringSplit p "/"))

fn suiteExport? x: String -> Bool
  (or (= x "runTests") (or (= x "suiteWallS") (stringStartsWith? x "test")))

; (:m :ref DOC-THIN :do "a test file lives in a test directory or exports nothing but its suite (runTests, test functions, suiteWallS); a module that also exports a library, as the runner nativeTest does beside its own runTests, is a source")
fn testSource? path: String text: String -> Bool
  (or (testDir? path) (let [(xs (headerOf text).exports)] (and (listContains? xs "runTests") (listAll? suiteExport? xs))))

; (:m :ref DOC-THIN :do "what kind of symbol may not carry a row whatever its text: anything in a test file, a record field, a line anchor, a name the module does not export, main and runTests; a module row of a source file may")
fn kindReason test: Bool name: String exports: (List String) -> String
  (cond
    (test "testFile")
    ((stringEmpty? name) "")
    ((isLineSymbol? name) "lineAnchor")
    ((stringContains? name ".") "field")
    ((or (= name "main") (= name "runTests")) "plumbing")
    ((not (listContains? exports name)) "internal")
    (else ""))

fn doTextOf line: String -> String
  (match (stringIndexOf line ":do \"")
    ((none) "")
    ((some at) (let [(rest (sliceOr line (+ at 5) (stringLength line)))
                     (bs (stringToBytes rest))]
                 (sliceOr rest 0 (quoteEnd bs (bytesLength bs) 0)))))

fn quoteEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (bytesGet bs i) 92) (quoteEnd bs n (+ i 2)))
    ((= (bytesGet bs i) 34) i)
    (else (quoteEnd bs n (+ i 1))))

fn defName line: String -> String
  (let [(w (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (stringSplit (stringReplace line "(" " ") " ")))
        (h (optionOr (listGet w 0) ""))
        (second (optionOr (listGet w 1) ""))]
    (cond
      ((and (= h "fn") (= second "!")) (optionOr (listGet w 2) ""))
      ((or (= h "fn") (or (= h "schema") (= h "enum"))) second)
      (else "")))

; (:m :ref DOC-THIN :do "the (:m :do) texts of the comment lines directly above each fn, schema and enum, by name, and the module's own (:m) lines above its header under the empty name")
fn metaOf text: String -> (Map String String)
  (let [(r (fold (fn [(acc (Pair (Map String String) String)) (l String)] -> (Pair (Map String String) String)
                   (cond
                     ((stringStartsWith? l "; (:m ") (pair (pairFirst acc) (str (pairSecond acc) " " (doTextOf l))))
                     ((stringStartsWith? l "(module ") (pair (if (stringEmpty? (pairSecond acc)) (pairFirst acc) (mapSet (pairFirst acc) "" (pairSecond acc))) ""))
                     (else (let [(nm (defName l))]
                             (pair (if (or (stringEmpty? nm) (stringEmpty? (pairSecond acc))) (pairFirst acc) (mapSet (pairFirst acc) nm (pairSecond acc))) "")))))
                 (pair (mapEmpty) "") (stringLines text)))]
    (pairFirst r))

fn noFacts -> SrcFacts
  (SrcFacts :exists false :parsed false :tops (list) :exports (list) :metas (mapEmpty) :test false)

fn ! factsOf! root: String path: String -> SrcFacts
  (match (fileReadString (str root "/" path))
    ((err _) (with (noFacts) :test (testDir? path)))
    ((ok text) (match (ast/parse text)
                 ((err _) (with (noFacts) :exists true :test (testSource? path text)))
                 ((ok tops) (SrcFacts :exists true :parsed true :tops tops :exports (exportsOf text) :metas (metaOf text) :test (testSource? path text))))))

fn finding kind: String lr: (Pair String DocRow) why: String -> RowFinding
  (RowFinding :kind kind :sym (pairSecond lr).symbol :why why :ledger (pairFirst lr) :text (pairSecond lr).text)

fn rowLocal facts: (Map String SrcFacts) lr: (Pair String DocRow) -> (List RowFinding)
  (let [(sym (pairSecond lr).symbol) (path (symPath sym)) (name (symName sym))
        (f (mapGetOr facts path (noFacts)))
        (kind (kindReason f.test name f.exports))]
    (cond
      ((< (hashIdx sym) 0) (list (finding "refused" lr "noHash")))
      ((not f.exists) (list (finding "stale" lr "noFile")))
      ((isLineSymbol? name) (list (finding "refused" lr "lineAnchor")))
      ((not f.parsed) (list))
      ((not (nameResolves? f.tops name)) (list (finding "stale" lr "removed")))
      ((not (stringEmpty? kind)) (list (finding "refused" lr kind)))
      (else (map (fn [(r String)] -> RowFinding (finding "refused" lr r)) (textReasons sym (pairSecond lr).text (mapGetOr f.metas name ""))))))

fn uniqueStrings xs: (List String) -> (List String)
  (mapKeys (fold (fn [(m (Map String Bool)) (x String)] -> (Map String Bool) (mapSet m x true)) (mapEmpty) xs))

; (:m :ref DOC-THIN :do "the local findings of rows (ledger, row): judged by the row and its own source file only, each file parsed once, so a red is always caused by a change to that row or that file")
fn ! localFindings! root: String rows: (List (Pair String DocRow)) -> (List RowFinding)
  (let [(paths (uniqueStrings (map (fn [(lr (Pair String DocRow))] -> String (symPath (pairSecond lr).symbol)) rows)))
        (facts (fold (fn [(m (Map String SrcFacts)) (p String)] -> (Map String SrcFacts) (mapSet m p (factsOf! root p))) (mapEmpty) paths))]
    (listFlatMap (fn [(lr (Pair String DocRow))] -> (List RowFinding) (rowLocal facts lr)) rows))

fn ! dirAsn! root: String rel: String -> (List String)
  (map (fn [(n String)] -> String (str rel "/" n))
       (filter (fn [(n String)] -> Bool (and (stringEndsWith? n ".asn") (not (stringStartsWith? n ".")))) (listSort (resultOr (dirList (str root "/" rel)) (list)))))

; (:m :ref DOC-THIN :do "a doc ledger path: a ledgerPathFor home (asl/packages/P/doc.asn, asl/doc/AREA.asn, .asl/mem/docs/TOP.asn) or tests/agentEval/doc.asn; asl/doc/web.asn is not one, asl/web keeps its own rules, and the tree scan and the gate both ask this one predicate")
fn ledgerPath? p: String -> Bool
  (let [(s (stringSplit p "/")) (k (listLength s))]
    (and (stringEndsWith? p ".asn")
         (and (!= p "asl/doc/web.asn")
              (or (and (= k 4) (and (stringStartsWith? p "asl/packages/") (stringEndsWith? p "/doc.asn")))
                  (or (and (= k 3) (stringStartsWith? p "asl/doc/"))
                      (or (and (= k 4) (stringStartsWith? p ".asl/mem/docs/"))
                          (= p "tests/agentEval/doc.asn")))))))

; (:m :ref DOC-THIN :do "every doc ledger of the tree, each path one ledgerPath? accepts")
fn ! ledgerFiles! root: String -> (List String)
  (let [(pkgs (filter (fn [(p String)] -> Bool (fileExists? (str root "/" p)))
                      (map (fn [(p String)] -> String (str "asl/packages/" p "/doc.asn")) (listSort (resultOr (dirList (str root "/asl/packages")) (list))))))
        (extra (filter (fn [(p String)] -> Bool (fileExists? (str root "/" p))) (list "tests/agentEval/doc.asn")))]
    (filter (fn [(p String)] -> Bool (ledgerPath? p)) (listAppend pkgs (listAppend (dirAsn! root "asl/doc") (listAppend (dirAsn! root ".asl/mem/docs") extra)))))

fn ! treeRows! root: String -> (Result (List (Pair String DocRow)) String)
  (fold (fn [(acc (Result (List (Pair String DocRow)) String)) (l String)] -> (Result (List (Pair String DocRow)) String)
          (match acc
            ((err e) (err e))
            ((ok xs) (match (loadLedger! (str root "/" l))
                       ((err e) (err (str l ": " e)))
                       ((ok rows) (ok (listAppend xs (map (fn [(r DocRow)] -> (Pair String DocRow) (pair l r)) rows))))))))
        (ok (list)) (ledgerFiles! root))

; (:m :ref DOC-THIN :do "the whole tree's local findings, the invariant docLedgerTest holds; a ledger that does not load is one finding of kind load")
fn ! treeFindings! root: String -> (List RowFinding)
  (match (treeRows! root)
    ((err e) (list (RowFinding :kind "load" :sym e :why "load" :ledger "")))
    ((ok rows) (localFindings! root rows)))

fn bytePred? b: Int64 -> Bool
  (or (alnumByte? b) (or (= b 45) (or (= b 95) (or (= b 33) (= b 63)))))

fn nameEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (bytePred? (bytesGet bs i))) (nameEnd bs n (+ i 1)) i)

fn leadName s: String -> String
  (let [(bs (stringToBytes s))] (sliceOr s 0 (nameEnd bs (bytesLength bs) 0)))

fn lastByteName? s: String -> Bool
  (let [(bs (stringToBytes s)) (n (bytesLength bs))] (and (> n 0) (bytePred? (bytesGet bs (- n 1)))))

fn refsLoop parts: (List String) prev: String acc: (List String) -> (List String)
  (match (listHead parts)
    ((none) acc)
    ((some p) (let [(nm (leadName p))]
                (refsLoop (listDrop parts 1) p (if (and (not (lastByteName? prev)) (not (stringEmpty? nm))) (cons nm acc) acc)))))

; (:m :ref DOC-THIN :do "the names a text reaches through alias/NAME, alias not glued to a longer name before it")
fn refsVia text: String alias: String -> (List String)
  (let [(parts (stringSplit text (str alias "/")))]
    (refsLoop (listDrop parts 1) (optionOr (listHead parts) "") (list)))

fn formEnd bs: Bytes n: Int64 i: Int64 depth: Int64 st: Int64 -> Int64
  (if (>= i n) i
    (let [(b (bytesGet bs i))]
      (cond
        ((= st 3) (formEnd bs n (+ i 1) depth (if (= b 10) 0 3)))
        ((= st 2) (formEnd bs n (+ i 1) depth 1))
        ((= st 1) (cond ((= b 92) (formEnd bs n (+ i 1) depth 2)) ((= b 34) (formEnd bs n (+ i 1) depth 0)) (else (formEnd bs n (+ i 1) depth 1))))
        ((= b 34) (formEnd bs n (+ i 1) depth 1))
        ((= b 59) (formEnd bs n (+ i 1) depth 3))
        ((or (= b 40) (= b 91)) (formEnd bs n (+ i 1) (+ depth 1) 0))
        ((or (= b 41) (= b 93)) (if (= depth 1) (+ i 1) (formEnd bs n (+ i 1) (- depth 1) 0)))
        (else (formEnd bs n (+ i 1) depth 0)))))

fn atomOf s: rd/SExpr -> String
  (match s ((rd/sexprAtom v) v) (_ ""))

fn itemsOf s: rd/SExpr -> (List rd/SExpr)
  (match s ((rd/sexprAtom _) (list)) ((rd/sexprList xs) xs) ((rd/sexprVect xs) xs))

fn lastSeg p: String -> String
  (optionOr (listLast (stringSplit p "/")) p)

fn importOf s: rd/SExpr -> (List (Pair String String))
  (match s
    ((rd/sexprAtom v) (list (pair (lastSeg v) v)))
    (_ (let [(xs (itemsOf s)) (heads (map atomOf (itemsOf s))) (m (optionOr (listHead heads) ""))
             (ai (optionOr (listIndexOf heads ":a") (optionOr (listIndexOf heads ":as") -1)))]
         (if (stringEmpty? m) (list)
           (list (pair (if (< ai 0) (lastSeg m) (optionOr (listGet heads (+ ai 1)) (lastSeg m))) m))))))

fn headerWalk xs: (List rd/SExpr) h: Header -> Header
  (match (listHead xs)
    ((none) h)
    ((some k)
      (let [(rest (listDrop xs 1)) (v (optionOr (listHead rest) (rd/sexprAtom ""))) (key (atomOf k))]
        (cond
          ((or (= key ":x") (= key ":export")) (headerWalk (listDrop rest 1) (with h :exports (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (map atomOf (itemsOf v))))))
          ((or (= key ":i") (= key ":import")) (headerWalk (listDrop rest 1) (with h :imports (listFlatMap importOf (itemsOf v)))))
          (else (headerWalk rest h))))))

fn emptyHeader -> Header
  (Header :name "" :exports (list) :imports (list))

; (:m :ref DOC-THIN :do "name, exports and (alias, module) imports of a file's module form, read from that form alone, so a scan of every file costs a header each")
fn headerOf text: String -> Header
  (match (stringIndexOf text "(module")
    ((none) (emptyHeader))
    ((some at) (let [(tail (sliceOr text at (stringLength text)))
                     (bs (stringToBytes tail))
                     (form (sliceOr tail 0 (formEnd bs (bytesLength bs) 0 0 0)))]
                 (match (meta/parseForms form)
                   ((err _) (emptyHeader))
                   ((ok fs) (match (listHead fs)
                              ((none) (emptyHeader))
                              ((some f) (let [(xs (itemsOf f))] (headerWalk (listDrop xs 2) (with (emptyHeader) :name (atomOf (optionOr (listGet xs 1) (rd/sexprAtom "")))))))))))))

; (:m :ref DOC-THIN :do "the unit a path belongs to: asl/packages/P, asl/AREA, or its top directory; a use from another unit makes an export public")
fn unitOf p: String -> String
  (let [(s (stringSplit p "/"))]
    (cond
      ((and (= (optionOr (listGet s 0) "") "asl") (= (optionOr (listGet s 1) "") "packages")) (str "pkg:" (optionOr (listGet s 2) "")))
      ((= (optionOr (listGet s 0) "") "asl") (str "asl:" (optionOr (listGet s 1) "")))
      (else (optionOr (listGet s 0) ""))))

fn ! scanFiles! root: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (testDir? p)))
          (listFlatMap (fn [(top String)] -> (List String) (if (fileExists? (str root "/" top)) (resultOr (aslFilesUnder! root top) (list)) (list)))
                       (list "asl" "tools" "bench" "harness")))

fn markUses marks: (Map String Bool) tp: String exports: (List String) names: (List String) -> (Map String Bool)
  (fold (fn [(m (Map String Bool)) (nm String)] -> (Map String Bool)
          (if (listContains? exports nm) (mapSet (mapSet m (str tp "#" nm) true) (str tp "#") true) m))
        marks names)

; (:m :ref DOC-THIN :do "which of the symbols path#name (and module rows path#) another unit uses: a non-test file under asl, tools, bench or harness of another unit imports the module and names alias/NAME of one of its exports; only files whose text holds a target module name are parsed")
fn ! crossUsed! root: String syms: (List String) -> (Map String Bool)
  (let [(paths (uniqueStrings (map symPath syms)))
        (heads (map (fn [(p String)] -> (Pair String Header) (pair p (headerOf (resultOr (fileReadString (str root "/" p)) "")))) paths))
        (byName (fold (fn [(m (Map String (List (Pair String Header)))) (ph (Pair String Header))] -> (Map String (List (Pair String Header)))
                        (if (stringEmpty? (pairSecond ph).name) m (mapSet m (pairSecond ph).name (cons ph (mapGetOr m (pairSecond ph).name (list))))))
                      (mapEmpty) heads))
        (names (mapKeys byName))]
    (if (listEmpty? names) (mapEmpty)
      (fold (fn [(marks (Map String Bool)) (f String)] -> (Map String Bool)
              (let [(text (resultOr (fileReadString (str root "/" f)) ""))]
                (if (or (not (listAny? (fn [(nm String)] -> Bool (stringContains? text nm)) names)) (testSource? f text)) marks
                  (fold (fn [(m2 (Map String Bool)) (imp (Pair String String))] -> (Map String Bool)
                          (let [(targets (filter (fn [(ph (Pair String Header))] -> Bool (!= (unitOf (pairFirst ph)) (unitOf f))) (mapGetOr byName (pairSecond imp) (list))))]
                            (if (listEmpty? targets) m2
                              (let [(used (refsVia text (pairFirst imp)))]
                                (fold (fn [(m3 (Map String Bool)) (ph (Pair String Header))] -> (Map String Bool) (markUses m3 (pairFirst ph) (pairSecond ph).exports used)) m2 targets)))))
                        marks (headerOf text).imports))))
            (mapEmpty) (scanFiles! root))))

fn diffPathOf line: String -> String
  (if (stringStartsWith? line "+++ b/") (sliceOr line 6 (stringLength line)) "")

; (:m :ref DOC-THIN :do "the (:doc) rows a -U0 git diff adds, each with the ledger it is added to; a malformed added row is an error naming it")
fn addedRows diff: String -> (Result (List (Pair String DocRow)) String)
  (let [(r (fold (fn [(acc (Pair String (Result (List (Pair String DocRow)) String))) (l String)] -> (Pair String (Result (List (Pair String DocRow)) String))
                   (let [(file (pairFirst acc)) (res (pairSecond acc)) (p (diffPathOf l))]
                     (cond
                       ((not (stringEmpty? p)) (pair p res))
                       ((stringStartsWith? l "+(:doc ")
                         (match res
                           ((err e) acc)
                           ((ok xs) (match (parseLedgerText (sliceOr l 1 (stringLength l)))
                                      ((err e) (pair file (err (str file ": " e))))
                                      ((ok rows) (pair file (ok (listAppend xs (map (fn [(x DocRow)] -> (Pair String DocRow) (pair file x)) rows)))))))))
                       (else acc))))
                 (pair "" (ok (list))) (stringLines diff)))]
    (pairSecond r))

fn findingKey f: RowFinding -> String
  (str f.kind " " f.sym " " f.why " " f.text)

fn dedupe fs: (List RowFinding) -> (List RowFinding)
  (pairFirst (fold (fn [(acc (Pair (List RowFinding) (Map String Bool))) (f RowFinding)] -> (Pair (List RowFinding) (Map String Bool))
                     (if (mapHas? (pairSecond acc) (findingKey f)) acc (pair (listAppend (pairFirst acc) (list f)) (mapSet (pairSecond acc) (findingKey f) true))))
                   (pair (list) (mapEmpty)) fs))

fn ! touchedRows! root: String touched: (List String) -> (List (Pair String DocRow))
  (listFlatMap (fn [(p String)] -> (List (Pair String DocRow))
                 (map (fn [(r DocRow)] -> (Pair String DocRow) (pair (dx/ledgerPathFor p) r)) (resultOr (findByFile! root p) (list))))
               (filter (fn [(p String)] -> Bool (stringEndsWith? p ".asl")) touched))

; (:m :ref DOC-THIN :do "the findings a diff owes: the local findings of the rows it adds and of every row of a source file it touches (a removed symbol, a (:m) it now repeats), and for an added row that passes those, notPublic when no other unit uses the symbol; rows the diff did not add are never judged against other packages")
fn ! rowFindings! root: String added: (List (Pair String DocRow)) touched: (List String) -> (List RowFinding)
  (let [(local (dedupe (localFindings! root (listAppend added (touchedRows! root touched)))))
        (flagged (fold (fn [(m (Map String Bool)) (f RowFinding)] -> (Map String Bool) (mapSet m f.sym true)) (mapEmpty) local))
        (clean (filter (fn [(lr (Pair String DocRow))] -> Bool (not (mapHas? flagged (pairSecond lr).symbol))) added))
        (used (if (listEmpty? clean) (mapEmpty) (crossUsed! root (map (fn [(lr (Pair String DocRow))] -> String (pairSecond lr).symbol) clean))))]
    (listAppend local (map (fn [(lr (Pair String DocRow))] -> RowFinding (finding "refused" lr "notPublic"))
                           (filter (fn [(lr (Pair String DocRow))] -> Bool (not (mapHas? used (pairSecond lr).symbol))) clean))))

; (:m :ref DOC-RULE-AUTODROP :do "the added (:doc) rows of a -U0 diff read line by line: the rows that parse with their ledger, and the (ledger, line) pairs that do not, so one malformed added row never hides the others")
fn looseAdded diff: String -> (Pair (List (Pair String DocRow)) (List (Pair String String)))
  (let [(r (fold (fn [(acc (Pair String (Pair (List (Pair String DocRow)) (List (Pair String String))))) (l String)] -> (Pair String (Pair (List (Pair String DocRow)) (List (Pair String String))))
                   (let [(file (pairFirst acc)) (good (pairFirst (pairSecond acc))) (bad (pairSecond (pairSecond acc))) (p (diffPathOf l))]
                     (cond
                       ((not (stringEmpty? p)) (pair p (pairSecond acc)))
                       ((stringStartsWith? l "+(:doc ")
                         (let [(line (sliceOr l 1 (stringLength l)))]
                           (match (parseLedgerText line)
                             ((err _) (pair file (pair good (listAppend bad (list (pair file line))))))
                             ((ok rows) (pair file (pair (listAppend good (map (fn [(x DocRow)] -> (Pair String DocRow) (pair file x)) rows)) bad))))))
                       (else acc))))
                 (pair "" (pair (list) (list))) (stringLines diff)))]
    (pairSecond r))

fn rowKey sym: String text: String -> String
  (str sym "\t" text)

; (:m :ref DOC-RULE-AUTODROP :do "what rule C refuses of a diff, by the computation of rowFindings!: the refused and stale findings of the rows it adds and of the rows of the source files it touches, and the added lines that do not parse; nothing else is ever dropped")
fn ! autodropPlan! root: String diff: String touched: (List String) -> (Pair (List RowFinding) (List (Pair String String)))
  (let [(loose (looseAdded diff))]
    (pair (filter (fn [(f RowFinding)] -> Bool (or (= f.kind "refused") (= f.kind "stale"))) (rowFindings! root (pairFirst loose) touched))
          (pairSecond loose)))

; (:m :ref DOC-RULE-AUTODROP :do "a ledger text without the (:doc) rows named by a (symbol, text) key and without the exact lines in bad; every other line is kept as it is; returns the new text and one label per row removed (its symbol, or unparsed)")
fn dropFromText text: String keys: (List String) bad: (List String) -> (Pair String (List String))
  (let [(r (fold (fn [(acc (Pair (List String) (List String))) (l String)] -> (Pair (List String) (List String))
                   (if (not (stringStartsWith? l "(:doc ")) (pair (listAppend (pairFirst acc) (list l)) (pairSecond acc))
                     (if (listContains? bad l) (pair (pairFirst acc) (listAppend (pairSecond acc) (list "unparsed")))
                       (match (parseLedgerText l)
                         ((ok rows) (let [(hit (filter (fn [(x DocRow)] -> Bool (listContains? keys (rowKey x.symbol x.text))) rows))]
                                      (if (listEmpty? hit) (pair (listAppend (pairFirst acc) (list l)) (pairSecond acc))
                                        (pair (pairFirst acc) (listAppend (pairSecond acc) (map (fn [(x DocRow)] -> String x.symbol) hit))))))
                         ((err _) (pair (listAppend (pairFirst acc) (list l)) (pairSecond acc)))))))
                 (pair (list) (list)) (stringSplit text "\n")))]
    (pair (stringJoin (pairFirst r) "\n") (pairSecond r)))

fn dropRowsText text: String syms: (List String) -> String
  (pairFirst (dropFromText text syms (list)))

; (:m :ref DOC-RULE-AUTODROP :do "removes the rows of the findings (by symbol and text) and the unparsed added lines from their ledgers under root; returns the changed ledger paths and one label per row removed; a ledger that cannot be read or written is left as it is")
fn ! dropRows! root: String fs: (List RowFinding) bad: (List (Pair String String)) -> (Pair (List String) (List String))
  (let [(ledgers (uniqueStrings (listAppend (map (fn [(f RowFinding)] -> String f.ledger) fs) (map pairFirst bad))))]
    (fold (fn [(acc (Pair (List String) (List String))) (lp String)] -> (Pair (List String) (List String))
            (match (fileReadString (str root "/" lp))
              ((err _) acc)
              ((ok text) (let [(keys (map (fn [(f RowFinding)] -> String (rowKey f.sym f.text)) (filter (fn [(f RowFinding)] -> Bool (= f.ledger lp)) fs)))
                               (lines (map pairSecond (filter (fn [(b (Pair String String))] -> Bool (= (pairFirst b) lp)) bad)))
                               (dropped (dropFromText text keys lines))]
                           (if (or (listEmpty? (pairSecond dropped)) (not (ok? (fileWrite (str root "/" lp) (pairFirst dropped))))) acc
                             (pair (listAppend (pairFirst acc) (list lp)) (listAppend (pairSecond acc) (pairSecond dropped))))))))
          (pair (list) (list)) ledgers))

fn findingLine f: RowFinding -> String
  (str "(:" f.kind " :symbol \"" (escRow f.sym) "\" :why " f.why " :ledger \"" f.ledger "\")")

fn ! reportFindings! root: String -> Int64
  (let [(fs (treeFindings! root))]
    (do (map (fn [(f RowFinding)] -> Unit (println (findingLine f))) fs)
        (println (str "(:docCheck :findings " (stringFromInt64 (listLength fs)) ")"))
        (if (listEmpty? fs) 0 1)))
