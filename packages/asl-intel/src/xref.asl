(module aslIntel/xref :x [RefTarget CrossReference stripRefPrefix cleanRefToken parseRefUri formatRefUri refTargetEq? refTargetToString extractDocstringRefs isSupportedLanguage?] :i [])

(schema RefTarget (:f kind Str) (:f id Str) (:f line I64))

(schema CrossReference (:f source Str) (:f target RefTarget) (:f raw Str) (:f context Str))

fn stripRefPrefix s: Str -> Str
  (let [(trimmed (stringTrim s))] (if (stringStartsWith? trimmed "ref:") (stringTrim (optionOr (stringSlice trimmed 4 (stringLength trimmed)) "")) trimmed))

fn cleanRefToken tok: Str -> Str
  (let [(t0 (stringTrim tok)) (t1 (if (stringStartsWith? t0 "(") (optionOr (stringSlice t0 1 (stringLength t0)) "") t0)) (t2 (if (stringStartsWith? t1 "\"") (optionOr (stringSlice t1 1 (stringLength t1)) "") t1)) (t3 (if (stringEndsWith? t2 ")") (optionOr (stringSlice t2 0 (- (stringLength t2) 1)) "") t2)) (t4 (if (stringEndsWith? t3 "\"") (optionOr (stringSlice t3 0 (- (stringLength t3) 1)) "") t3)) (t5 (if (stringEndsWith? t4 "]") (optionOr (stringSlice t4 0 (- (stringLength t4) 1)) "") t4)) (t6 (if (stringEndsWith? t5 ",") (optionOr (stringSlice t5 0 (- (stringLength t5) 1)) "") t5)) (t7 (if (stringEndsWith? t6 ";") (optionOr (stringSlice t6 0 (- (stringLength t6) 1)) "") t6))] (stringTrim t7))

fn parseRefUri uri: Str -> RefTarget
  (let [(clean (stripRefPrefix uri))] (cond ((stringStartsWith? clean "task:") (let [(id (stringTrim (optionOr (stringSlice clean 5 (stringLength clean)) "")))] (RefTarget :kind "task" :id id :line 0))) ((stringStartsWith? clean "adr:") (let [(id (stringTrim (optionOr (stringSlice clean 4 (stringLength clean)) "")))] (RefTarget :kind "adr" :id id :line 0))) ((stringStartsWith? clean "d:") (let [(id (stringTrim (optionOr (stringSlice clean 2 (stringLength clean)) "")))] (RefTarget :kind "adr" :id id :line 0))) ((stringStartsWith? clean "c:") (let [(id (stringTrim (optionOr (stringSlice clean 2 (stringLength clean)) "")))] (RefTarget :kind "c" :id id :line 0))) ((stringStartsWith? clean "sym:") (let [(id (stringTrim (optionOr (stringSlice clean 4 (stringLength clean)) "")))] (RefTarget :kind "sym" :id id :line 0))) ((stringStartsWith? clean "chunk:") (let [(id (stringTrim (optionOr (stringSlice clean 6 (stringLength clean)) "")))] (RefTarget :kind "chunk" :id id :line 0))) ((stringStartsWith? clean "file:") (let [(rest (stringTrim (optionOr (stringSlice clean 5 (stringLength clean)) "")))] (if (stringContains? rest ":L") (let [(parts (stringSplit rest ":L")) (path (optionOr (listGet parts 0) rest)) (lStr (optionOr (listGet parts 1) "0")) (lNum (optionOr (stringToInt64 lStr) 0))] (RefTarget :kind "file" :id path :line lNum)) (RefTarget :kind "file" :id rest :line 0)))) (else (if (stringContains? clean ":") (let [(parts (stringSplit clean ":")) (k (optionOr (listGet parts 0) "unknown")) (rest (optionOr (listGet parts 1) clean))] (RefTarget :kind k :id rest :line 0)) (RefTarget :kind "unknown" :id clean :line 0)))))

fn formatRefUri target: RefTarget -> Str
  (let [(k target.kind) (id target.id) (l target.line)] (cond ((= k "file") (if (> l 0) (str "file:" id ":L" (stringFromInt64 l)) (str "file:" id))) (else (str k ":" id))))

fn refTargetToString target: RefTarget -> Str
  (formatRefUri target)

fn refTargetEq? a: RefTarget b: RefTarget -> Bool
  (and (= a.kind b.kind) (and (= a.id b.id) (= a.line b.line)))

fn extractDocstringRefs source: Str docstring: Str -> (List CrossReference)
  (let [(s1 (stringReplace docstring "\n" " ")) (s2 (stringReplace s1 "\t" " ")) (tokens (stringSplit s2 " ")) (refTokens (filter (fn [(tok Str)] -> Bool (stringContains? tok "ref:")) tokens))] (map (fn [(rawTok Str)] -> CrossReference (let [(cleaned (cleanRefToken rawTok)) (target (parseRefUri cleaned))] (CrossReference :source source :target target :raw cleaned :context docstring))) refTokens))

fn isSupportedLanguage? ext: Str -> Bool
  (let [(clean (if (stringStartsWith? ext ".") (optionOr (stringSlice ext 1 (stringLength ext)) "") ext))] (or (= clean "asl") (or (= clean "asn") (or (= clean "ts") (or (= clean "tsx") (or (= clean "js") (or (= clean "jsx") (or (= clean "py") (or (= clean "go") (or (= clean "rs") (or (= clean "php") (or (= clean "md") (= clean "c")))))))))))))
