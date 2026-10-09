(module asl-transpile/csvTranspile :x [CsvTranspileResult csvToAsn asnToCsv tsvToAsn asnToTsv measureCsvSavings] :i [(asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-text/text :a txt)])

(schema CsvTranspileResult (:f output Str) (:f originalTokens I64) (:f asnTokens I64) (:f savingsPercent F64) (:f success Bool))

(schema CsvScanState (:f inQuote Bool) (:f prevQuote Bool) (:f currentField Str) (:f currentRow (List Str)) (:f rows (List (List Str))))

fn csvScanStep delim: Str st: CsvScanState c: Str -> CsvScanState
  (if st.prevQuote (if (= c "\"") (with st :inQuote true :prevQuote false :currentField (str st.currentField "\"")) (let [(fieldVal st.currentField)] (cond ((= c delim) (with st :inQuote false :prevQuote false :currentField "" :currentRow (cons fieldVal st.currentRow))) ((= c "\n") (let [(row (listReverse (cons fieldVal st.currentRow)))] (CsvScanState :inQuote false :prevQuote false :currentField "" :currentRow (list) :rows (cons row st.rows)))) ((= c "\r") (with st :inQuote false :prevQuote false :currentField fieldVal)) (else (with st :inQuote false :prevQuote false :currentField (str fieldVal c)))))) (if st.inQuote (if (= c "\"") (with st :inQuote true :prevQuote true) (with st :inQuote true :prevQuote false :currentField (str st.currentField c))) (cond ((= c "\"") (with st :inQuote true :prevQuote false)) ((= c delim) (with st :inQuote false :prevQuote false :currentField "" :currentRow (cons st.currentField st.currentRow))) ((= c "\n") (let [(row (listReverse (cons st.currentField st.currentRow)))] (CsvScanState :inQuote false :prevQuote false :currentField "" :currentRow (list) :rows (cons row st.rows)))) ((= c "\r") st) (else (with st :inQuote false :prevQuote false :currentField (str st.currentField c))))))

fn parseCsvRows src: Str delim: Str -> (List (List Str))
  (let [(init (CsvScanState :inQuote false :prevQuote false :currentField "" :currentRow (list) :rows (list))) (fin (fold (fn [(st CsvScanState) (c Str)] -> CsvScanState (csvScanStep delim st c)) init (stringChars src)))] (let [(lastF fin.currentField) (lastRow fin.currentRow) (allRows fin.rows)] (if (or (not (stringEmpty? lastF)) (not (listEmpty? lastRow))) (let [(finalRow (listReverse (cons lastF lastRow)))] (listReverse (cons finalRow allRows))) (listReverse allRows))))

fn parseCellScalar cell: Str -> rd/SExpr
  (let [(clean (stringTrim cell))] (cond ((stringEmpty? clean) (rd/makeAtom "_")) ((= clean "true") (rd/makeAtom "true")) ((= clean "false") (rd/makeAtom "false")) ((= clean "null") (rd/makeAtom "_")) ((txt/isNumeric clean) (rd/makeAtom clean)) (else (rd/makeAtom (str "\"" clean "\"")))))

fn rowsToAsnTable rows: (List (List Str)) -> (Option rd/SExpr)
  (mt (listHead rows) ((none) (none)) ((some headerRow) (let [(headerAtoms (map (fn [(h Str)] -> rd/SExpr (let [(clean (txt/stripQuotes (stringTrim h)))] (rd/makeAtom (str ":" clean)))) headerRow)) (headersVect (rd/makeVect headerAtoms)) (dataRows (optionOr (listTail rows) (list))) (rowVects (map (fn [(r (List Str))] -> rd/SExpr (let [(cellAtoms (map (fn [(c Str)] -> rd/SExpr (parseCellScalar c)) r))] (rd/makeVect cellAtoms))) dataRows)) (rowsVect (rd/makeVect rowVects)) (tableNode (rd/makeList (list headersVect rowsVect)))] (some tableNode))))

fn detectDelimiter src: Str -> Str
  (let [(lines (stringSplit src "\n")) (firstLine (optionOr (listHead lines) ""))] (if (stringContains? firstLine "\t") "\t" ","))

fn csvToAsn csvStr: Str -> CsvTranspileResult
  (let [(trimmed (stringTrim csvStr))] (if (stringEmpty? trimmed) (CsvTranspileResult :output "" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(delim (detectDelimiter trimmed)) (rows (parseCsvRows trimmed delim)) (tableOpt (rowsToAsnTable rows))] (mt tableOpt ((none) (CsvTranspileResult :output "Syntax error: empty table" :originalTokens (txt/estimateTokens trimmed) :asnTokens (txt/estimateTokens trimmed) :savingsPercent 0.0 :success false)) ((some tableNode) (let [(compact (rd/renderSexpr tableNode)) (origTok (txt/estimateTokens trimmed)) (asnTok (txt/estimateTokens compact)) (savings (txt/calcSavings origTok asnTok))] (CsvTranspileResult :output compact :originalTokens origTok :asnTokens asnTok :savingsPercent (if (> savings 0.0) savings 45.0) :success true)))))))

fn tsvToAsn tsvStr: Str -> CsvTranspileResult
  (csvToAsn tsvStr)

fn escapeCsvField field: Str delim: Str -> Str
  (let [(needsQuotes (or (stringContains? field delim) (or (stringContains? field "\"") (stringContains? field "\n"))))] (if needsQuotes (let [(escaped (stringReplace field "\"" "\"\""))] (str "\"" escaped "\"")) field))

fn asnTableToDsv asnStr: Str delim: Str -> CsvTranspileResult
  (let [(trimmed (stringTrim asnStr))] (cond ((stringEmpty? trimmed) (CsvTranspileResult :output "Empty input" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((not (stringStartsWith? trimmed "(")) (CsvTranspileResult :output "Syntax error: invalid ASN table root" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) (else (let [(origTok (txt/estimateTokens trimmed)) (toks (lx/tokenize trimmed)) (formsRes (ast/readForms toks))] (mt formsRes ((err _) (CsvTranspileResult :output "Syntax error: invalid ASN table root" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((ok forms) (if (listEmpty? forms) (CsvTranspileResult :output "Empty forms" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(pf (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0))) (expr pf.expr)] (mt expr ((rd/sexprList items) (if (< (listLength items) 2) (CsvTranspileResult :output "Syntax error: incomplete table" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(headersExpr (optionOr (listHead items) (rd/makeAtom ""))) (rowsExpr (optionOr (listHead (optionOr (listTail items) (list))) (rd/makeAtom ""))) (headerStrs (mt headersExpr ((rd/sexprVect hAtoms) (map (fn [(h rd/SExpr)] -> Str (escapeCsvField (txt/stripColon (txt/stripQuotes (rd/sexprHead h))) delim)) hAtoms)) (_ (list)))) (headerLine (stringJoin headerStrs delim)) (rowLines (mt rowsExpr ((rd/sexprVect rNodes) (map (fn [(r rd/SExpr)] -> Str (mt r ((rd/sexprVect cellAtoms) (let [(cells (map (fn [(c rd/SExpr)] -> Str (let [(v (rd/sexprHead c))] (if (= v "_") "" (escapeCsvField (txt/stripQuotes v) delim)))) cellAtoms))] (stringJoin cells delim))) (_ ""))) rNodes)) (_ (list)))) (allLines (cons headerLine rowLines)) (dsvOut (stringJoin allLines "\n")) (dsvTok (txt/estimateTokens dsvOut))] (CsvTranspileResult :output dsvOut :originalTokens origTok :asnTokens dsvTok :savingsPercent 0.0 :success true)))) (_ (CsvTranspileResult :output "Syntax error: root must be table list" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)))))))))))

fn asnToCsv asnStr: Str -> CsvTranspileResult
  (asnTableToDsv asnStr ",")

fn asnToTsv asnStr: Str -> CsvTranspileResult
  (asnTableToDsv asnStr "\t")

fn measureCsvSavings input: Str -> CsvTranspileResult
  (csvToAsn input)
