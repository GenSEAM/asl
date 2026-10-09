(module asl-gates/docLedger
  :x [DocRow loadLedger! findBySymbol! findByFile! renderText unresolvedSymbols! checkLedger! main]
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
  (mt (listHead items)
    ((none) acc)
    ((some k)
      (let [(tail (optionOr (listTail items) (list)))]
        (mt (kwName k)
          ((none) (with acc :bad true))
          ((some key)
            (mt (listHead tail)
              ((none) (with acc :bad true))
              ((some v) (kvLoop (optionOr (listTail tail) (list)) (kvStep acc key v)))))))))

fn rowFromSym acc: KvAcc sym: String -> (Result DocRow String)
  (mt acc.text
    ((none) (err "doc ledger row is missing :text"))
    ((some txt) (ok (DocRow :symbol sym :text txt))))

fn rowFromAcc acc: KvAcc -> (Result DocRow String)
  (if acc.bad (err "doc ledger row has an unknown key or a non-string value")
    (mt acc.symbol
      ((none) (err "doc ledger row is missing :symbol"))
      ((some sym) (rowFromSym acc sym))))

fn rowFromForm f: rd/SExpr -> (Result DocRow String)
  (if (not (rd/isList? f)) (err "doc ledger row must be a list")
    (if (!= (rd/sexprHead f) ":doc") (err (str "doc ledger row must start with :doc, found " (rd/sexprHead f)))
      (rowFromAcc (kvLoop (optionOr (listTail (rd/sexprToList f)) (list)) (KvAcc :symbol (none) :text (none) :bad false)))))

fn rowsAppend row: DocRow restResult: (Result (List DocRow) String) -> (Result (List DocRow) String)
  (mt restResult
    ((err e) (err e))
    ((ok rest) (ok (cons row rest))))

fn rowsStep form: rd/SExpr rest: (List rd/SExpr) -> (Result (List DocRow) String)
  (mt (rowFromForm form)
    ((err e) (err e))
    ((ok row) (rowsAppend row (rowsFromForms rest))))

fn rowsFromForms forms: (List rd/SExpr) -> (Result (List DocRow) String)
  (mt (listHead forms)
    ((none) (ok (list)))
    ((some f) (rowsStep f (optionOr (listTail forms) (list)))))

fn parseLedgerText text: String -> (Result (List DocRow) String)
  (mt (meta/parseForms text)
    ((err e) (err e))
    ((ok forms) (rowsFromForms forms)))

fn loadLedgerFile! path: String -> (Result (List DocRow) String)
  (mt (fileReadString path)
    ((err e) (err e))
    ((ok text) (parseLedgerText text)))

fn loadLedger! path: String -> (Result (List DocRow) String)
  (if (not (fileExists? path)) (ok (list)) (loadLedgerFile! path))

fn findRowBySymbol rows: (List DocRow) symbol: String -> (Option DocRow)
  (mt (listHead rows)
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
        (mt (loadLedger! ledgerPath)
          ((err e) (err e))
          ((ok rows) (ok (findRowBySymbol rows symbol)))))))

fn findByFile! root: String file: String -> (Result (List DocRow) String)
  (let [(ledgerPath (str root "/" (dx/ledgerPathFor file))) (prefix (str file "#"))]
    (mt (loadLedger! ledgerPath)
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
    (mt t
      ((ast/topDefun n) (= n.name name))
      ((ast/topSchema n) (= n.name name))
      ((ast/topEnum n) (= n.name name))
      (_ false)))
    tops)

fn fieldExists? tops: (List ast/TopForm) schemaName: String fieldName: String -> Bool
  (listAny? (fn [(t ast/TopForm)] -> Bool
    (mt t
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
  (mt (ast/parse text)
    ((err _) false)
    ((ok tops) (nameResolves? tops name)))

fn ! resolveFileText! full: String name: String -> Bool
  (mt (fileReadString full)
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
  (mt (listHead rows)
    ((none) (list))
    ((some r)
      (let [(tail (optionOr (listTail rows) (list)))]
        (if (rowResolves! root r) (unresolvedSymbols! root tail) (cons r.symbol (unresolvedSymbols! root tail))))))

fn ! checkLedger! root: String ledgerPath: String -> (Result (List String) String)
  (mt (loadLedger! (str root "/" ledgerPath))
    ((err e) (err e))
    ((ok rows) (ok (unresolvedSymbols! root rows))))

fn ! reportSymbol! root: String symbol: String -> Int64
  (mt (findBySymbol! root symbol)
    ((err e) (do (println (str "(:doc :symbol \"" symbol "\" :status :error :message \"" e "\")")) 1))
    ((ok found) (mt found
      ((none) (do (println (str "(:doc :symbol \"" symbol "\" :found false)")) 0))
      ((some row) (do (println (str "(:doc :symbol \"" symbol "\" :found true :text \"" (escRow (renderText row.text)) "\")")) 0)))))

fn rowLine! r: DocRow -> String
  (str "(:row :symbol \"" r.symbol "\" :text \"" (escRow (renderText r.text)) "\")")

fn ! reportFile! root: String file: String -> Int64
  (mt (findByFile! root file)
    ((err e) (do (println (str "(:doc :file \"" file "\" :status :error :message \"" e "\")")) 1))
    ((ok rows) (do (println (str "(:doc :file \"" file "\" :found " (stringFromInt64 (listLength rows)) " :rows [" (stringJoin (map rowLine! rows) " ") "])")) 0)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(fileMode (listContains? args "--file"))
        (rest (filter (fn [(a String)] -> Bool (!= a "--file")) args))
        (key (optionOr (listHead rest) ""))]
    (if (stringEmpty? key)
      (do (println "(:doc :status :error :message \"usage: docLedger.asl [--file] SYMBOL|FILE\")") (ok 64))
      (ok (if fileMode (reportFile! "." key) (reportSymbol! "." key)))))
