(module aslHarness/normalizer :x [NormalizerReport normalizeIdentifier canonicalizeKeyword canonicalizeType normalizeAslFragment repairHallucinations] :i [(asl-parser/balance :a bal)])

(schema NormalizerReport (:f originalCode Str) (:f normalizedCode Str) (:f repairsCount I64) (:f isClean Bool))

fn normalizeIdentifier name: Str -> Str
  (stringReplace (stringReplace name "_" "-") " " "-")

fn canonicalizeKeyword kw: Str -> Str
  (cond ((or (= kw "def") (= kw "defun")) "fn") ((or (= kw "defn") (= kw "df")) "fn") ((= kw "fn*") "fn") ((or (= kw "defrecord") (or (= kw "struct") (= kw "dfs"))) "schema") ((or (= kw "defenum") (or (= kw "enum") (= kw "dfe"))) "enum") ((= kw "match") "mt") ((= kw "cond*") "cond") (else kw))

fn canonicalizeType ty: Str -> Str
  (cond ((or (= ty "string") (= ty "str")) "Str") ((or (= ty "int") (or (= ty "int64") (= ty "i64"))) "I64") ((or (= ty "int32") (= ty "i32")) "I32") ((or (= ty "bool") (= ty "boolean")) "Bool") ((or (= ty "float") (or (= ty "float64") (= ty "f64"))) "F64") ((or (= ty "unit") (= ty "void")) "Unit") (else ty))

fn normalizeAslFragment src: Str -> Str
  (let [(s1 (stringReplace src (str "(" "defun ") "(fn ")) (s2 (stringReplace s1 "(def " "(fn ")) (s3 (stringReplace s2 "(defn " "(fn ")) (s3b (stringReplace s3 "(df " "(fn ")) (s3c (stringReplace s3b "(dfs " "(schema ")) (s3d (stringReplace s3c "(dfe " "(enum ")) (s4 (stringReplace s3d " String " " Str ")) (s5 (stringReplace s4 " Int64 " " I64 ")) (s6 (stringReplace s5 " Boolean " " Bool ")) (s7 (bal/balanceDelimiters s6))] s7)

fn repairHallucinations raw: Str -> NormalizerReport
  (let [(normalized (normalizeAslFragment raw)) (repaired (not (= raw normalized)))] (NormalizerReport :originalCode raw :normalizedCode normalized :repairsCount (if repaired 1 0) :isClean (not repaired)))
