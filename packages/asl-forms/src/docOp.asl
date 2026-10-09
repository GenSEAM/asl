(module asl-forms/docOp
  :x [docStep!]
  :i [(asl-forms/kernel :a k) (asl-gates/docLedger :a dl)])

fn docHead id: Int64 -> String
  (str "  (:step :id " (stringFromInt64 id) " :op \"doc\"")

fn q s: String -> String
  (str "\"" (k/escapeAsnVal s) "\"")

fn fail id: Int64 code: String message: String -> k/EditOutcome
  (k/EditOutcome :lines (list (str (docHead id) " :status \"rejected\" :error-code \"" code "\" :message " (q message) ")")) :errCount 1)

fn docOk id: Int64 body: String -> k/EditOutcome
  (k/EditOutcome :lines (list (str (docHead id) " :status \"ok\"" body ")")) :errCount 0)

fn rowLine r: dl/DocRow -> String
  (str "(:row :symbol " (q r.symbol) " :text " (q (dl/renderText r.text)) ")")

fn ! symbolOp! id: Int64 root: String symbol: String -> k/EditOutcome
  (mt (dl/findBySymbol! root symbol)
    ((err e) (fail id ":ERR_DOC_READ" e))
    ((ok found) (symbolResult id symbol found)))

fn symbolResult id: Int64 symbol: String found: (Option dl/DocRow) -> k/EditOutcome
  (mt found
    ((none) (docOk id (str " :symbol " (q symbol) " :found false")))
    ((some row) (docOk id (str " :symbol " (q symbol) " :found true :text " (q (dl/renderText row.text))))))

fn ! fileOp! id: Int64 root: String file: String -> k/EditOutcome
  (mt (dl/findByFile! root file)
    ((err e) (fail id ":ERR_DOC_READ" e))
    ((ok rows) (docOk id (str " :file " (q file) " :found " (stringFromInt64 (listLength rows)) " :rows [" (stringJoin (map rowLine rows) " ") "]"))))

fn ! docStep! root: String id: Int64 kw: (Map String String) -> k/EditOutcome
  (let [(symbol (k/kwOr kw "symbol" "")) (file (k/kwOr kw "file" ""))]
    (cond
      ((not (stringEmpty? symbol)) (symbolOp! id root symbol))
      ((not (stringEmpty? file)) (fileOp! id root file))
      (else (fail id ":ERR_MISSING_ARG" "doc requires :symbol or :file"))))
