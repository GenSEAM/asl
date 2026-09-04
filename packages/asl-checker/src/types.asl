(module asl-checker/types
  :d "Type AST, Diagnostics, and Builtin Vocabulary for the Self-Hosted Checker."
  :x [Type
      Diagnostic
      resolve-type-alias
      unordered-type?
      int-range-bounds
      prelude-union-cases
      is-numeric-type?
      is-integral-type?
      builtin-sig
      parse-type-str
      show-types
      show-type])

(dfe Type
  (:c ty-con [(name String) (args (List Type)) (mod (Option String)) (shown (Option String))] "A nominal or constructed type")
  (:c ty-var [(id Int64) (kind String)] "A type variable metavariable: any, num, or int")
  (:c ty-fun [(params (List Type)) (ret Type)] "A function type"))

(dfs Diagnostic
  (:f code String "Diagnostic rule code")
  (:f message String "Human diagnostic message")
  (:f line Int64 "1-based source line")
  (:f col Int64 "1-based source column")
  (:f path String "Source file path"))

(df resolve-type-alias [(name String)] -> String
  :d "Resolves canonical type aliases to their Core types."
  (cond
    ((= name "Bool") "Bool")
    ((= name "F32") "Float64")
    ((= name "F64") "Float64")
    ((= name "Float") "Float64")
    ((= name "I32") "Int32")
    ((= name "I64") "Int64")
    ((= name "Int") "Int64")
    ((= name "Num") "Float64")
    ((= name "Str") "String")
    ((= name "Unit") "Unit")
    (:else name)))

(df unordered-type? [(name String)] -> Bool
  :d "True when a type has no total order."
  (or (= name "Float64") (= name "IoError")))

(df int-range-bounds [(name String)] -> (Option (Pair Int64 Int64))
  :d "Integer literal range bounds for fixed-width types."
  (cond
    ((= name "Int32") (some (pair -2147483648 2147483647)))
    ((= name "Int64") (some (pair -9223372036854775808 9223372036854775807)))
    (:else (none))))

(df prelude-union-cases [(case-name String)] -> (Option String)
  :d "Maps constructor tags to their enclosing prelude union."
  (cond
    ((= case-name "already-exists") (some "IoError"))
    ((= case-name "interrupted") (some "IoError"))
    ((= case-name "invalid-path") (some "IoError"))
    ((= case-name "not-found") (some "IoError"))
    ((= case-name "other") (some "IoError"))
    ((= case-name "permission-denied") (some "IoError"))
    ((= case-name "some") (some "Option"))
    ((= case-name "none") (some "Option"))
    ((= case-name "ok") (some "Result"))
    ((= case-name "err") (some "Result"))
    ((= case-name "list") (some "List"))
    ((= case-name "cons") (some "List"))
    (:else (none))))

(df is-numeric-type? [(name String)] -> Bool
  :d "True for numeric primitive types."
  (or (= name "Int32") (or (= name "Int64") (= name "Float64"))))

(df is-integral-type? [(name String)] -> Bool
  :d "True for integer primitive types."
  (or (= name "Int32") (= name "Int64")))

(df sig-fn [(params (List String)) (ret String)] -> (Option (Pair (List String) (Pair Bool String)))
  (some (pair params (pair false ret))))

(df sig-var [(params (List String)) (ret String)] -> (Option (Pair (List String) (Pair Bool String)))
  (some (pair params (pair true ret))))

(df num-binop-sig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sig-fn (list "N" "N") "N"))

(df cmp-binop-sig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sig-fn (list "T" "T") "Bool"))

(df ioerror-ctor-sig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sig-fn (list) "IoError"))

(df io-result-unit-sig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sig-fn (list "String") "(Result Unit IoError)"))

(df str-pred-sig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sig-fn (list "String" "String") "Bool"))

(df list-opt-sig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sig-fn (list "(List T)") "(Option T)"))

(df builtin-sig [(name String)] -> (Option (Pair (List String) (Pair Bool String)))
  :d "Lookup table for all 107 prelude builtin signatures."
  (cond
    ((or (= name "!=") (or (= name "=") (or (= name "<") (or (= name "<=") (or (= name ">") (= name ">=")))))) (cmp-binop-sig))
    ((or (= name "*") (or (= name "+") (or (= name "-") (= name "/")))) (num-binop-sig))
    ((or (= name "abs") (= name "neg")) (sig-fn (list "N") "N"))
    ((or (= name "already-exists")
         (or (= name "interrupted")
             (or (= name "invalid-path")
                 (or (= name "not-found")
                     (or (= name "other") (= name "permission-denied"))))))
     (ioerror-ctor-sig))
    ((= name "and") (sig-fn (list "Bool" "Bool") "Bool"))
    ((or (= name "checked-div") (= name "checked-mod")) (sig-fn (list "N" "N") "(Option N)"))
    ((or (= name "eprintln") (or (= name "print") (= name "println"))) (io-result-unit-sig))
    ((= name "err") (sig-fn (list "E") "(Result T E)"))
    ((or (= name "file-append") (= name "file-write")) (sig-fn (list "String" "String") "(Result Unit IoError)"))
    ((= name "file-exists?") (sig-fn (list "String") "(Result Bool IoError)"))
    ((= name "file-read") (sig-fn (list "String") "(Result String IoError)"))
    ((= name "filter") (sig-fn (list "(fn [T] -> Bool)" "(List T)") "(List T)"))
    ((= name "float64-to-int64") (sig-fn (list "Float64") "(Option Int64)"))
    ((= name "fold") (sig-fn (list "(fn [B A] -> B)" "B" "(List A)") "B"))
    ((= name "int32-to-int64") (sig-fn (list "Int32") "Int64"))
    ((= name "int64-to-float64") (sig-fn (list "Int64") "Float64"))
    ((= name "int64-to-int32") (sig-fn (list "Int64") "(Option Int32)"))
    ((or (= name "is-err?") (= name "is-ok?")) (sig-fn (list "(Result T E)") "Bool"))
    ((or (= name "is-none?") (= name "is-some?")) (sig-fn (list "(Option T)") "Bool"))
    ((= name "list") (sig-var (list "T") "(List T)"))
    ((= name "list-append") (sig-fn (list "(List T)" "(List T)") "(List T)"))
    ((= name "list-cons") (sig-fn (list "T" "(List T)") "(List T)"))
    ((= name "list-contains?") (sig-fn (list "(List T)" "T") "Bool"))
    ((= name "list-empty?") (sig-fn (list "(List T)") "Bool"))
    ((= name "list-get") (sig-fn (list "(List T)" "Int64") "(Option T)"))
    ((or (= name "list-head") (or (= name "list-max") (= name "list-min"))) (list-opt-sig))
    ((= name "list-index-of") (sig-fn (list "(List T)" "T") "(Option Int64)"))
    ((= name "list-length") (sig-fn (list "(List T)") "Int64"))
    ((or (= name "list-reverse") (= name "list-sort")) (sig-fn (list "(List T)") "(List T)"))
    ((= name "list-slice") (sig-fn (list "(List T)" "Int64" "Int64") "(Option (List T))"))
    ((= name "list-sort-by") (sig-fn (list "(fn [T] -> K)" "(List T)") "(List T)"))
    ((= name "list-sum") (sig-fn (list "(List N)") "N"))
    ((= name "list-tail") (sig-fn (list "(List T)") "(Option (List T))"))
    ((= name "map") (sig-fn (list "(fn [A] -> B)" "(List A)") "(List B)"))
    ((= name "map-empty") (sig-fn (list) "(Map K V)"))
    ((= name "map-from-pairs") (sig-fn (list "(List (Pair K V))") "(Map K V)"))
    ((= name "map-get") (sig-fn (list "(Map K V)" "K") "(Option V)"))
    ((= name "map-has?") (sig-fn (list "(Map K V)" "K") "Bool"))
    ((= name "map-keys") (sig-fn (list "(Map K V)") "(List K)"))
    ((= name "map-pairs") (sig-fn (list "(Map K V)") "(List (Pair K V))"))
    ((= name "map-remove") (sig-fn (list "(Map K V)" "K") "(Map K V)"))
    ((= name "map-set") (sig-fn (list "(Map K V)" "K" "V") "(Map K V)"))
    ((= name "map-size") (sig-fn (list "(Map K V)") "Int64"))
    ((= name "map-values") (sig-fn (list "(Map K V)") "(List V)"))
    ((or (= name "max") (or (= name "min") (= name "mod"))) (num-binop-sig))
    ((= name "none") (sig-fn (list) "(Option T)"))
    ((= name "not") (sig-fn (list "Bool") "Bool"))
    ((= name "ok") (sig-fn (list "T") "(Result T E)"))
    ((= name "option-map") (sig-fn (list "(fn [A] -> B)" "(Option A)") "(Option B)"))
    ((= name "option-or") (sig-fn (list "(Option T)" "T") "T"))
    ((= name "option-to-result") (sig-fn (list "(Option T)" "E") "(Result T E)"))
    ((= name "or") (sig-fn (list "Bool" "Bool") "Bool"))
    ((= name "pair") (sig-fn (list "A" "B") "(Pair A B)"))
    ((= name "range") (sig-fn (list "Int64" "Int64") "(List Int64)"))
    ((= name "read-all") (sig-fn (list) "(Result String IoError)"))
    ((= name "read-line") (sig-fn (list) "(Result (Option String) IoError)"))
    ((= name "result-map") (sig-fn (list "(fn [A] -> B)" "(Result A E)") "(Result B E)"))
    ((= name "result-map-err") (sig-fn (list "(fn [E] -> F)" "(Result T E)") "(Result T F)"))
    ((= name "result-or") (sig-fn (list "(Result T E)" "T") "T"))
    ((= name "result-to-option") (sig-fn (list "(Result T E)") "(Option T)"))
    ((= name "some") (sig-fn (list "T") "(Option T)"))
    ((= name "str") (sig-var (list "String") "String"))
    ((= name "string-chars") (sig-fn (list "String") "(List String)"))
    ((or (= name "string-contains?") (or (= name "string-ends-with?") (= name "string-starts-with?"))) (str-pred-sig))
    ((= name "string-empty?") (sig-fn (list "String") "Bool"))
    ((= name "string-from-float64") (sig-fn (list "Float64") "String"))
    ((= name "string-from-int64") (sig-fn (list "Int64") "String"))
    ((= name "string-index-of") (sig-fn (list "String" "String") "(Option Int64)"))
    ((= name "string-join") (sig-fn (list "(List String)" "String") "String"))
    ((= name "string-length") (sig-fn (list "String") "Int64"))
    ((or (= name "string-lower")
         (or (= name "string-reverse")
             (or (= name "string-trim") (= name "string-upper"))))
     (sig-fn (list "String") "String"))
    ((= name "string-replace") (sig-fn (list "String" "String" "String") "String"))
    ((= name "string-slice") (sig-fn (list "String" "Int64" "Int64") "(Option String)"))
    ((= name "string-split") (sig-fn (list "String" "String") "(List String)"))
    ((= name "string-to-float64") (sig-fn (list "String") "(Option Float64)"))
    ((= name "string-to-int64") (sig-fn (list "String") "(Option Int64)"))
    ((= name "zip") (sig-fn (list "(List A)" "(List B)") "(List (Pair A B))"))
    (:else (none))))

(df show-types [(ts (List Type))] -> (List String)
  :d "Formats a list of types to a list of strings."
  (map (fn [(t Type)] -> String (show-type t)) ts))

(df strip-first-char [(s String)] -> String
  :d "Strips first character of string."
  (mt (string-slice s 1 (string-length s))
    ((some sub) sub)
    ((none) s)))

(df show-type [(t Type)] -> String
  :d "Formats a Type AST node back into readable canonical AgentScript syntax."
  (mt t
    ((ty-var id kind)
     (cond
       ((= kind "num") "a number")
       ((= kind "int") "an integer")
       (:else "_")))
    ((ty-fun params ret)
     (str "(fn [" (string-join (show-types params) " ") "] -> " (show-type ret) ")"))
    ((ty-con name args mod shown)
     (let [(head (mt shown
                   ((some s) s)
                   ((none) (if (string-starts-with? name "#")
                             (strip-first-char name)
                             name))))]
       (if (list-empty? args)
         head
         (str "(" head " " (string-join (show-types args) " ") ")"))))))

(dfs TypeTokState
  (:f toks (List String) "Token accumulator, reversed")
  (:f cur String "Current atom accumulator"))

(df flush-cur [(toks (List String)) (cur String)] -> (List String)
  (if (string-empty? cur)
    toks
    (list-cons cur toks)))

(df tokenize-type-step [(st TypeTokState) (c String)] -> TypeTokState
  (cond
    ((or (= c "(") (or (= c ")") (or (= c "[") (= c "]"))))
     (let [(toks1 (flush-cur (.-toks st) (.-cur st)))]
       (TypeTokState :toks (list-cons c toks1) :cur "")))
    ((or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))
     (TypeTokState :toks (flush-cur (.-toks st) (.-cur st)) :cur ""))
    (:else
     (TypeTokState :toks (.-toks st) :cur (str (.-cur st) c)))))

(df tokenize-type-str [(s String)] -> (List String)
  (let [(st (fold tokenize-type-step
                  (TypeTokState :toks (list) :cur "")
                  (string-chars s)))]
    (list-reverse (flush-cur (.-toks st) (.-cur st)))))

(df get-typevar-id [(name String) (typevars (List String))] -> Int64
  (mt (list-index-of typevars name)
    ((some i) (+ i 1))
    ((none) 1)))

(df make-qual-pair [(member String) (alias (Option String)) (head String)] -> (Pair String (Pair (Option String) (Option String)))
  (let [(opt-h (some head))]
    (pair (resolve-type-alias member) (pair alias opt-h))))

(df parse-con-name [(head String)] -> (Pair String (Pair (Option String) (Option String)))
  (if (not (string-contains? head "/"))
    (pair (resolve-type-alias head) (pair (none) (none)))
    (let [(parts (string-split head "/"))
          (alias (mt (list-get parts 0) ((some s) (some s)) ((none) (none))))
          (member (mt (list-get parts 1) ((some s) s) ((none) head)))]
      (make-qual-pair member alias head))))

(df safe-toks-tail [(toks (List String))] -> (List String)
  (if (list-empty? toks)
    (list)
    (mt (list-slice toks 1 (list-length toks))
      ((some s) s)
      ((none) (list)))))

(df skip-delim [(toks (List String)) (delim String)] -> (List String)
  (mt (list-head toks)
    ((some h) (if (= h delim) (safe-toks-tail toks) toks))
    ((none) toks)))

(df parse-type-toks [(toks (List String)) (typevars (List String))] -> (Pair Type (List String))
  (mt (list-head toks)
    ((none) (pair (ty-con "Unit" (list) (none) (none)) (list)))
    ((some head)
     (let [(rest (safe-toks-tail toks))]
       (if (= head "(")
         (mt (list-head rest)
           ((none) (pair (ty-con "Unit" (list) (none) (none)) (list)))
           ((some head-sym)
            (let [(rest2 (safe-toks-tail rest))]
              (if (= head-sym "fn")
                (let [(cur-toks (skip-delim rest2 "["))
                      (p-res (parse-fn-params cur-toks typevars (list)))
                      (params (.-first p-res))
                      (after-params (.-second p-res))
                      (cur2 (skip-delim after-params "->"))
                      (ret-res (parse-type-toks cur2 typevars))
                      (ret (.-first ret-res))
                      (after-ret (.-second ret-res))
                      (final-rem (skip-delim after-ret ")"))]
                  (pair (ty-fun params ret) final-rem))
                (let [(args-res (parse-type-args rest2 typevars (list)))
                      (args (.-first args-res))
                      (after-args (.-second args-res))
                      (con-info (parse-con-name head-sym))
                      (c-name (.-first con-info))
                      (c-mod (.-first (.-second con-info)))
                      (c-shown (.-second (.-second con-info)))]
                  (pair (ty-con c-name args c-mod c-shown) after-args))))))
         (if (list-contains? typevars head)
           (let [(var-id (get-typevar-id head typevars))
                 (kind (if (= head "N") "num" (if (or (= head "A") (or (= head "B") (or (= head "T") (= head "E")))) "any" "any")))]
             (pair (ty-var var-id kind) rest))
           (let [(con-info (parse-con-name head))
                 (c-name (.-first con-info))
                 (c-mod (.-first (.-second con-info)))
                 (c-shown (.-second (.-second con-info)))]
             (pair (ty-con c-name (list) c-mod c-shown) rest))))))))

(df parse-delimited-types [(toks (List String)) (typevars (List String)) (closing String) (acc (List Type))] -> (Pair (List Type) (List String))
  (mt (list-head toks)
    ((none) (pair (list-reverse acc) (list)))
    ((some t)
     (if (= t closing)
       (let [(rev-acc (list-reverse acc))
             (rem-toks (safe-toks-tail toks))]
         (pair rev-acc rem-toks))
       (let [(res (parse-type-toks toks typevars))]
         (parse-delimited-types (.-second res) typevars closing (list-cons (.-first res) acc)))))))

(df parse-type-args [(toks (List String)) (typevars (List String)) (acc (List Type))] -> (Pair (List Type) (List String))
  (parse-delimited-types toks typevars ")" acc))

(df parse-fn-params [(toks (List String)) (typevars (List String)) (acc (List Type))] -> (Pair (List Type) (List String))
  (parse-delimited-types toks typevars "]" acc))

(df parse-type-str [(s String) (typevars (List String))] -> Type
  :d "Parses canonical type strings into Type trees."
  (let [(toks (tokenize-type-str s))]
    (.-first (parse-type-toks toks typevars))))
