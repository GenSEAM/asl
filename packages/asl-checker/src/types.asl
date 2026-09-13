(module asl-checker/types
  :d "Type AST, Diagnostics, and Builtin Vocabulary for the Self-Hosted Checker."
  :x [Type
      Diagnostic
      resolveTypeAlias
      unorderedType?
      intRangeBounds
      preludeUnionCases
      isNumericType?
      isIntegralType?
      builtinSig
      parseTypeStr
      showTypes
      showType])

(dfe Type
  (:c tyCon [(name String) (args (List Type)) (mod (Option String)) (shown (Option String))] "A nominal or constructed type")
  (:c tyVar [(id Int64) (kind String)] "A type variable metavariable: any, num, or int")
  (:c tyFun [(params (List Type)) (ret Type)] "A function type"))

(dfs Diagnostic
  (:f code String "Diagnostic rule code")
  (:f message String "Human diagnostic message")
  (:f line Int64 "1-based source line")
  (:f col Int64 "1-based source column")
  (:f path String "Source file path"))

(df resolveTypeAlias [(name String)] -> String
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

(df unorderedType? [(name String)] -> Bool
  :d "True when a type has no total order."
  (or (= name "Float64") (= name "IoError")))

(df intRangeBounds [(name String)] -> (Option (Pair Int64 Int64))
  :d "Integer literal range bounds for fixed-width types."
  (cond
    ((= name "Int32") (some (pair -2147483648 2147483647)))
    ((= name "Int64") (some (pair -9223372036854775808 9223372036854775807)))
    (:else (none))))

(df preludeUnionCases [(caseName String)] -> (Option String)
  :d "Maps constructor tags to their enclosing prelude union."
  (cond
    ((= caseName "already-exists") (some "IoError"))
    ((= caseName "interrupted") (some "IoError"))
    ((= caseName "invalid-path") (some "IoError"))
    ((= caseName "not-found") (some "IoError"))
    ((= caseName "other") (some "IoError"))
    ((= caseName "permission-denied") (some "IoError"))
    ((= caseName "some") (some "Option"))
    ((= caseName "none") (some "Option"))
    ((= caseName "ok") (some "Result"))
    ((= caseName "err") (some "Result"))
    ((= caseName "list") (some "List"))
    ((= caseName "cons") (some "List"))
    (:else (none))))

(df isNumericType? [(name String)] -> Bool
  :d "True for numeric primitive types."
  (or (= name "Int32") (or (= name "Int64") (= name "Float64"))))

(df isIntegralType? [(name String)] -> Bool
  :d "True for integer primitive types."
  (or (= name "Int32") (= name "Int64")))

(df sigFn [(params (List String)) (ret String)] -> (Option (Pair (List String) (Pair Bool String)))
  (some (pair params (pair false ret))))

(df sigVar [(params (List String)) (ret String)] -> (Option (Pair (List String) (Pair Bool String)))
  (some (pair params (pair true ret))))

(df numBinopSig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "N" "N") "N"))

(df cmpBinopSig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "T" "T") "Bool"))

(df ioerrorCtorSig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list) "IoError"))

(df ioResultUnitSig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "String") "(Result Unit IoError)"))

(df strPredSig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "String" "String") "Bool"))

(df listOptSig [] -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "(List T)") "(Option T)"))

(df builtinSig [(name String)] -> (Option (Pair (List String) (Pair Bool String)))
  :d "Lookup table for all 107 prelude builtin signatures."
  (cond
    ((or (= name "!=") (or (= name "=") (or (= name "<") (or (= name "<=") (or (= name ">") (= name ">=")))))) (cmpBinopSig))
    ((or (= name "*") (or (= name "+") (or (= name "-") (= name "/")))) (numBinopSig))
    ((or (= name "abs") (= name "neg")) (sigFn (list "N") "N"))
    ((or (= name "already-exists")
         (or (= name "interrupted")
             (or (= name "invalid-path")
                 (or (= name "not-found")
                     (or (= name "other") (= name "permission-denied"))))))
     (ioerrorCtorSig))
    ((= name "and") (sigFn (list "Bool" "Bool") "Bool"))
    ((or (= name "checked-div") (= name "checked-mod")) (sigFn (list "N" "N") "(Option N)"))
    ((or (= name "eprintln") (or (= name "print") (= name "println"))) (ioResultUnitSig))
    ((= name "dirList") (sigFn (list "String") "(Result (List String) IoError)"))
    ((= name "err") (sigFn (list "E") "(Result T E)"))
    ((= name "execCmd") (sigFn (list "String") "ProcessOutput"))
    ((or (= name "file-append") (= name "file-write")) (sigFn (list "String" "String") "(Result Unit IoError)"))
    ((= name "file-exists?") (sigFn (list "String") "(Result Bool IoError)"))
    ((= name "file-read") (sigFn (list "String") "(Result String IoError)"))
    ((= name "fileStat") (sigFn (list "String") "(Result FileStat IoError)"))
    ((= name "pathCanonicalize") (sigFn (list "String") "(Result String IoError)"))
    ((= name "filter") (sigFn (list "(fn [T] -> Bool)" "(List T)") "(List T)"))
    ((= name "float64-to-int64") (sigFn (list "Float64") "(Option Int64)"))
    ((= name "fold") (sigFn (list "(fn [B A] -> B)" "B" "(List A)") "B"))
    ((= name "int32-to-int64") (sigFn (list "Int32") "Int64"))
    ((= name "int64-to-float64") (sigFn (list "Int64") "Float64"))
    ((= name "int64-to-int32") (sigFn (list "Int64") "(Option Int32)"))
    ((or (= name "is-err?") (= name "is-ok?")) (sigFn (list "(Result T E)") "Bool"))
    ((or (= name "is-none?") (= name "is-some?")) (sigFn (list "(Option T)") "Bool"))
    ((= name "list") (sigVar (list "T") "(List T)"))
    ((= name "list-append") (sigFn (list "(List T)" "(List T)") "(List T)"))
    ((= name "list-cons") (sigFn (list "T" "(List T)") "(List T)"))
    ((= name "list-contains?") (sigFn (list "(List T)" "T") "Bool"))
    ((= name "list-empty?") (sigFn (list "(List T)") "Bool"))
    ((= name "list-get") (sigFn (list "(List T)" "Int64") "(Option T)"))
    ((or (= name "list-head") (or (= name "list-max") (= name "list-min"))) (listOptSig))
    ((= name "list-index-of") (sigFn (list "(List T)" "T") "(Option Int64)"))
    ((= name "list-length") (sigFn (list "(List T)") "Int64"))
    ((or (= name "list-reverse") (= name "list-sort")) (sigFn (list "(List T)") "(List T)"))
    ((= name "list-slice") (sigFn (list "(List T)" "Int64" "Int64") "(Option (List T))"))
    ((= name "list-sort-by") (sigFn (list "(fn [T] -> K)" "(List T)") "(List T)"))
    ((= name "list-sum") (sigFn (list "(List N)") "N"))
    ((= name "list-tail") (sigFn (list "(List T)") "(Option (List T))"))
    ((= name "map") (sigFn (list "(fn [A] -> B)" "(List A)") "(List B)"))
    ((= name "map-empty") (sigFn (list) "(Map K V)"))
    ((= name "map-from-pairs") (sigFn (list "(List (Pair K V))") "(Map K V)"))
    ((= name "map-get") (sigFn (list "(Map K V)" "K") "(Option V)"))
    ((= name "map-has?") (sigFn (list "(Map K V)" "K") "Bool"))
    ((= name "map-keys") (sigFn (list "(Map K V)") "(List K)"))
    ((= name "map-pairs") (sigFn (list "(Map K V)") "(List (Pair K V))"))
    ((= name "map-remove") (sigFn (list "(Map K V)" "K") "(Map K V)"))
    ((= name "map-set") (sigFn (list "(Map K V)" "K" "V") "(Map K V)"))
    ((= name "map-size") (sigFn (list "(Map K V)") "Int64"))
    ((= name "map-values") (sigFn (list "(Map K V)") "(List V)"))
    ((or (= name "max") (or (= name "min") (= name "mod"))) (numBinopSig))
    ((= name "none") (sigFn (list) "(Option T)"))
    ((= name "not") (sigFn (list "Bool") "Bool"))
    ((= name "ok") (sigFn (list "T") "(Result T E)"))
    ((= name "option-map") (sigFn (list "(fn [A] -> B)" "(Option A)") "(Option B)"))
    ((= name "option-or") (sigFn (list "(Option T)" "T") "T"))
    ((= name "option-to-result") (sigFn (list "(Option T)" "E") "(Result T E)"))
    ((= name "or") (sigFn (list "Bool" "Bool") "Bool"))
    ((= name "pair") (sigFn (list "A" "B") "(Pair A B)"))
    ((= name "range") (sigFn (list "Int64" "Int64") "(List Int64)"))
    ((= name "read-all") (sigFn (list) "(Result String IoError)"))
    ((= name "read-line") (sigFn (list) "(Result (Option String) IoError)"))
    ((= name "result-map") (sigFn (list "(fn [A] -> B)" "(Result A E)") "(Result B E)"))
    ((= name "result-map-err") (sigFn (list "(fn [E] -> F)" "(Result T E)") "(Result T F)"))
    ((= name "result-or") (sigFn (list "(Result T E)" "T") "T"))
    ((= name "result-to-option") (sigFn (list "(Result T E)") "(Option T)"))
    ((= name "some") (sigFn (list "T") "(Option T)"))
    ((= name "str") (sigVar (list "String") "String"))
    ((= name "string-chars") (sigFn (list "String") "(List String)"))
    ((or (= name "string-contains?") (or (= name "string-ends-with?") (= name "string-starts-with?"))) (strPredSig))
    ((= name "string-empty?") (sigFn (list "String") "Bool"))
    ((= name "string-from-float64") (sigFn (list "Float64") "String"))
    ((= name "string-from-int64") (sigFn (list "Int64") "String"))
    ((= name "string-index-of") (sigFn (list "String" "String") "(Option Int64)"))
    ((= name "string-join") (sigFn (list "(List String)" "String") "String"))
    ((= name "string-length") (sigFn (list "String") "Int64"))
    ((or (= name "string-lower")
         (or (= name "string-reverse")
             (or (= name "string-trim") (= name "string-upper"))))
     (sigFn (list "String") "String"))
    ((= name "string-replace") (sigFn (list "String" "String" "String") "String"))
    ((= name "string-slice") (sigFn (list "String" "Int64" "Int64") "(Option String)"))
    ((= name "string-split") (sigFn (list "String" "String") "(List String)"))
    ((= name "string-to-float64") (sigFn (list "String") "(Option Float64)"))
    ((= name "string-to-int64") (sigFn (list "String") "(Option Int64)"))
    ((= name "zip") (sigFn (list "(List A)" "(List B)") "(List (Pair A B))"))
    (:else (none))))

(df showTypes [(ts (List Type))] -> (List String)
  :d "Formats a list of types to a list of strings."
  (map (fn [(t Type)] -> String (showType t)) ts))

(df stripFirstChar [(s String)] -> String
  :d "Strips first character of string."
  (mt (string-slice s 1 (string-length s))
    ((some sub) sub)
    ((none) s)))

(df showType [(t Type)] -> String
  :d "Formats a Type AST node back into readable canonical AgentScript syntax."
  (mt t
    ((tyVar id kind)
     (cond
       ((= kind "num") "a number")
       ((= kind "int") "an integer")
       (:else "_")))
    ((tyFun params ret)
     (str "(fn [" (string-join (showTypes params) " ") "] -> " (showType ret) ")"))
    ((tyCon name args mod shown)
     (let [(head (mt shown
                   ((some s) s)
                   ((none) (if (string-starts-with? name "#")
                             (stripFirstChar name)
                             name))))]
       (if (list-empty? args)
         head
         (str "(" head " " (string-join (showTypes args) " ") ")"))))))

(dfs TypeTokState
  (:f toks (List String) "Token accumulator, reversed")
  (:f cur String "Current atom accumulator"))

(df flushCur [(toks (List String)) (cur String)] -> (List String)
  (if (string-empty? cur)
    toks
    (list-cons cur toks)))

(df tokenizeTypeStep [(st TypeTokState) (c String)] -> TypeTokState
  (cond
    ((or (= c "(") (or (= c ")") (or (= c "[") (= c "]"))))
     (let [(toks1 (flushCur (.-toks st) (.-cur st)))]
       (TypeTokState :toks (list-cons c toks1) :cur "")))
    ((or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))
     (TypeTokState :toks (flushCur (.-toks st) (.-cur st)) :cur ""))
    (:else
     (TypeTokState :toks (.-toks st) :cur (str (.-cur st) c)))))

(df tokenizeTypeStr [(s String)] -> (List String)
  (let [(st (fold tokenizeTypeStep
                  (TypeTokState :toks (list) :cur "")
                  (string-chars s)))]
    (list-reverse (flushCur (.-toks st) (.-cur st)))))

(df getTypevarId [(name String) (typevars (List String))] -> Int64
  (mt (list-index-of typevars name)
    ((some i) (+ i 1))
    ((none) 1)))

(df makeQualPair [(member String) (alias (Option String)) (head String)] -> (Pair String (Pair (Option String) (Option String)))
  (let [(optH (some head))]
    (pair (resolveTypeAlias member) (pair alias optH))))

(df parseConName [(head String)] -> (Pair String (Pair (Option String) (Option String)))
  (if (not (string-contains? head "/"))
    (pair (resolveTypeAlias head) (pair (none) (none)))
    (let [(parts (string-split head "/"))
          (alias (mt (list-get parts 0) ((some s) (some s)) ((none) (none))))
          (member (mt (list-get parts 1) ((some s) s) ((none) head)))]
      (makeQualPair member alias head))))

(df safeToksTail [(toks (List String))] -> (List String)
  (if (list-empty? toks)
    (list)
    (mt (list-slice toks 1 (list-length toks))
      ((some s) s)
      ((none) (list)))))

(df skipDelim [(toks (List String)) (delim String)] -> (List String)
  (mt (list-head toks)
    ((some h) (if (= h delim) (safeToksTail toks) toks))
    ((none) toks)))

(df parseTypeToks [(toks (List String)) (typevars (List String))] -> (Pair Type (List String))
  (mt (list-head toks)
    ((none) (pair (tyCon "Unit" (list) (none) (none)) (list)))
    ((some head)
     (let [(rest (safeToksTail toks))]
       (if (= head "(")
         (mt (list-head rest)
           ((none) (pair (tyCon "Unit" (list) (none) (none)) (list)))
           ((some headSym)
            (let [(rest2 (safeToksTail rest))]
              (if (= headSym "fn")
                (let [(curToks (skipDelim rest2 "["))
                      (pRes (parseFnParams curToks typevars (list)))
                      (params (.-first pRes))
                      (afterParams (.-second pRes))
                      (cur2 (skipDelim afterParams "->"))
                      (retRes (parseTypeToks cur2 typevars))
                      (ret (.-first retRes))
                      (afterRet (.-second retRes))
                      (finalRem (skipDelim afterRet ")"))]
                  (pair (tyFun params ret) finalRem))
                (let [(argsRes (parseTypeArgs rest2 typevars (list)))
                      (args (.-first argsRes))
                      (afterArgs (.-second argsRes))
                      (conInfo (parseConName headSym))
                      (cName (.-first conInfo))
                      (cMod (.-first (.-second conInfo)))
                      (cShown (.-second (.-second conInfo)))]
                  (pair (tyCon cName args cMod cShown) afterArgs))))))
         (if (list-contains? typevars head)
           (let [(varId (getTypevarId head typevars))
                 (kind (if (= head "N") "num" (if (or (= head "A") (or (= head "B") (or (= head "T") (= head "E")))) "any" "any")))]
             (pair (tyVar varId kind) rest))
           (let [(conInfo (parseConName head))
                 (cName (.-first conInfo))
                 (cMod (.-first (.-second conInfo)))
                 (cShown (.-second (.-second conInfo)))]
             (pair (tyCon cName (list) cMod cShown) rest))))))))

(df parseDelimitedTypes [(toks (List String)) (typevars (List String)) (closing String) (acc (List Type))] -> (Pair (List Type) (List String))
  (mt (list-head toks)
    ((none) (pair (list-reverse acc) (list)))
    ((some t)
     (if (= t closing)
       (let [(revAcc (list-reverse acc))
             (remToks (safeToksTail toks))]
         (pair revAcc remToks))
       (let [(res (parseTypeToks toks typevars))]
         (parseDelimitedTypes (.-second res) typevars closing (list-cons (.-first res) acc)))))))

(df parseTypeArgs [(toks (List String)) (typevars (List String)) (acc (List Type))] -> (Pair (List Type) (List String))
  (parseDelimitedTypes toks typevars ")" acc))

(df parseFnParams [(toks (List String)) (typevars (List String)) (acc (List Type))] -> (Pair (List Type) (List String))
  (parseDelimitedTypes toks typevars "]" acc))

(df parseTypeStr [(s String) (typevars (List String))] -> Type
  :d "Parses canonical type strings into Type trees."
  (let [(toks (tokenizeTypeStr s))]
    (.-first (parseTypeToks toks typevars))))
