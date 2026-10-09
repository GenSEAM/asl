(module aslIntel/extractor :x [SymbolKind symFn symType symRecord symEnum symMethod symClass symInterface symVariable SymbolDef SymbolRef FileSymbols kindToString stringToKind parseAslTokens extractAslSymbols extractGenericSymbols filterExported])

(enum SymbolKind (:c symFn [] "Function symbol") (:c symType [] "Type symbol") (:c symRecord [] "Record symbol") (:c symEnum [] "Enum symbol") (:c symMethod [] "Method symbol") (:c symClass [] "Class symbol") (:c symInterface [] "Interface symbol") (:c symVariable [] "Variable symbol"))

(schema StringView (:f source Str) (:f start I64) (:f length I64))

fn viewCreate source: Str -> StringView
  (StringView :source source :start 0 :length (stringLength source))

fn viewAdvance v: StringView amount: I64 -> StringView
  (let [(clampedAmount (if (> amount v.length) v.length (if (< amount 0) 0 amount)))] (with v :start (+ v.start clampedAmount) :length (- v.length clampedAmount)))

fn viewToString v: StringView -> Str
  (optionOr (stringSlice v.source v.start (+ v.start v.length)) "")

(schema SymbolDef (:f name Str) (:f kind SymbolKind) (:f file Str) (:f startLine I64) (:f endLine I64) (:f signature Str) (:f exported Bool) (:f doc Str))

(schema SymbolRef (:f name Str) (:f caller Str) (:f file Str) (:f line I64))

(schema FileSymbols (:f file Str) (:f language Str) (:f symbols (List SymbolDef)) (:f refs (List SymbolRef)))

(schema ScanState (:f modName Str) (:f exports (List Str)) (:f currentCaller Str) (:f lineNo I64) (:f symbols (List SymbolDef)) (:f refs (List SymbolRef)))

fn kindToString k: SymbolKind -> Str
  (mt k ((symFn) "fn") ((symType) "type") ((symRecord) "record") ((symEnum) "enum") ((symMethod) "method") ((symClass) "class") ((symInterface) "interface") ((symVariable) "var"))

fn stringToKind s: Str -> SymbolKind
  (cond ((= s "fn") (symFn)) ((= s "function") (symFn)) ((= s "defun") (symFn)) ((= s "type") (symType)) ((= s "record") (symRecord)) ((= s "enum") (symEnum)) ((= s "method") (symMethod)) ((= s "class") (symClass)) ((= s "interface") (symInterface)) (else (symVariable)))

fn parseAslTokens source: Str -> (List Str)
  (stringSplit source " ")

fn isInList? target: Str items: (List Str) -> Bool
  (fold (fn [(acc Bool) (it Str)] -> Bool (or acc (= it target))) false items)

fn stripParen s: Str -> Str
  (let [(s1 (if (stringStartsWith? s "(") (optionOr (stringSlice s 1 (stringLength s)) "") s)) (s2 (if (stringStartsWith? s1 "[") (optionOr (stringSlice s1 1 (stringLength s1)) "") s1)) (s3 (if (stringEndsWith? s2 ")") (optionOr (stringSlice s2 0 (- (stringLength s2) 1)) "") s2)) (s4 (if (stringEndsWith? s3 "]") (optionOr (stringSlice s3 0 (- (stringLength s3) 1)) "") s3))] s4)

fn extractExports source: Str -> (List Str)
  (if (stringContains? source ":x [") (let [(p1 (optionOr (listGet (stringSplit source ":x [") 1) "")) (p2 (optionOr (listHead (stringSplit p1 "]")) "")) (words (stringSplit p2 " ")) (nonEmpty (filter (fn [(w Str)] -> Bool (not (= (stringTrim w) ""))) words))] (map stripParen nonEmpty)) (list))

fn extractModulePath source: Str -> Str
  (if (stringContains? source "(module ") (let [(p1 (optionOr (listGet (stringSplit source "(module ") 1) "")) (tokens (stringSplit p1 " ")) (tok0 (stripParen (optionOr (listHead tokens) "")))] (optionOr (listHead (stringSplit tok0 "\n")) "")) "")

fn extractLineRefs toks: (List Str) caller: Str file: Str lineNo: I64 acc: (List SymbolRef) -> (List SymbolRef)
  (fold (fn [(rAcc (List SymbolRef)) (t Str)] -> (List SymbolRef) (let [(clean (stripParen t))] (if (and (stringContains? clean "/") (and (not (stringStartsWith? clean "\"")) (not (stringStartsWith? clean ":")))) (cons (SymbolRef :name clean :caller caller :file file :line lineNo) rAcc) rAcc))) acc toks)

fn scanLine st: ScanState rawLine: Str file: Str -> ScanState
  (let [(lNo (+ st.lineNo 1)) (trimmed (stringTrim rawLine))] (if (= trimmed "") (with st :lineNo lNo) (let [(rawToks (stringSplit trimmed " ")) (toks (filter (fn [(t Str)] -> Bool (not (= (stringTrim t) ""))) rawToks)) (headRaw (stripParen (optionOr (listHead toks) ""))) (restToks (optionOr (listTail toks) (list)))] (cond ((or (or (or (= headRaw "fn") (= headRaw "df")) (= headRaw "def")) (= headRaw "defn")) (let [(t1 (stripParen (optionOr (listHead restToks) ""))) (isBang (= t1 "!")) (name (if isBang (stripParen (optionOr (listGet restToks 1) "")) t1)) (mod st.modName) (fq (if (= mod "") name (str mod "/" name))) (exp (or isBang (isInList? name st.exports))) (newSym (SymbolDef :name fq :kind (symFn) :file file :startLine lNo :endLine lNo :signature "" :exported exp :doc "")) (newRefs (extractLineRefs restToks fq file lNo st.refs))] (with st :modName mod :currentCaller fq :lineNo lNo :symbols (cons newSym st.symbols) :refs newRefs))) ((or (or (= headRaw "schema") (= headRaw "dfs")) (= headRaw "defstruct")) (let [(name (stripParen (optionOr (listHead restToks) ""))) (mod st.modName) (fq (if (= mod "") name (str mod "/" name))) (exp (isInList? name st.exports)) (newSym (SymbolDef :name fq :kind (symRecord) :file file :startLine lNo :endLine lNo :signature "" :exported exp :doc "")) (newRefs (extractLineRefs restToks st.currentCaller file lNo st.refs))] (with st :modName mod :lineNo lNo :symbols (cons newSym st.symbols) :refs newRefs))) ((or (or (= headRaw "enum") (= headRaw "dfe")) (= headRaw "defenum")) (let [(name (stripParen (optionOr (listHead restToks) ""))) (mod st.modName) (fq (if (= mod "") name (str mod "/" name))) (exp (isInList? name st.exports)) (newSym (SymbolDef :name fq :kind (symEnum) :file file :startLine lNo :endLine lNo :signature "" :exported exp :doc "")) (newRefs (extractLineRefs restToks st.currentCaller file lNo st.refs))] (with st :modName mod :lineNo lNo :symbols (cons newSym st.symbols) :refs newRefs))) ((or (= headRaw "dfp") (= headRaw "defprotocol")) (let [(name (stripParen (optionOr (listHead restToks) ""))) (mod st.modName) (fq (if (= mod "") name (str mod "/" name))) (exp (isInList? name st.exports)) (newSym (SymbolDef :name fq :kind (symInterface) :file file :startLine lNo :endLine lNo :signature "" :exported exp :doc "")) (newRefs (extractLineRefs restToks st.currentCaller file lNo st.refs))] (with st :modName mod :lineNo lNo :symbols (cons newSym st.symbols) :refs newRefs))) (else (let [(newRefs (extractLineRefs toks st.currentCaller file lNo st.refs))] (with st :lineNo lNo :refs newRefs)))))))

fn extractAslSymbols file: Str source: Str -> FileSymbols
  (let [(modName (extractModulePath source)) (exports (extractExports source)) (lines (stringSplit source "\n")) (initSt (ScanState :modName modName :exports exports :currentCaller "" :lineNo 0 :symbols (list) :refs (list))) (finalSt (fold (fn [(st ScanState) (line Str)] -> ScanState (scanLine st line file)) initSt lines))] (FileSymbols :file file :language "asl" :symbols (listReverse finalSt.symbols) :refs (listReverse finalSt.refs)))

fn extractGenericSymbols file: Str lang: Str defs: (List SymbolDef) refs: (List SymbolRef) -> FileSymbols
  (FileSymbols :file file :language lang :symbols defs :refs refs)

fn filterExported fs: FileSymbols -> (List SymbolDef)
  (filter (fn [(s SymbolDef)] -> Bool s.exported) fs.symbols)
