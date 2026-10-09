(module asl-codegen/c99Mangle :x [mangleCIdent isC99Keyword? mangleCTypeName mangleCModulePrefix pascalIdent capitalizeSeg sliceOr isDigitLeading?] :i [])

fn isC99Keyword? m: String -> Bool
  (listContains? (list "auto" "break" "case" "char" "const" "continue" "default" "do" "double" "else" "enum" "extern" "float" "for" "goto" "if" "inline" "int" "long" "register" "restrict" "return" "short" "signed" "sizeof" "static" "struct" "switch" "typedef" "union" "unsigned" "void" "volatile" "while" "_Bool" "_Complex" "_Imaginary" "main" "exit" "abort" "index" "stdin" "stdout" "stderr" "errno" "assert" "offsetof" "NULL" "EOF" "SEEK_SET" "SEEK_CUR" "SEEK_END" "BUFSIZ") m)

fn sliceOr s: String start: Int64 end: Int64 fallback: String -> String
  (optionOr (stringSlice s start end) fallback)

fn isDigitLeading? s: String -> Bool
  (if (<= (stringLength s) 0) false (let [(c (sliceOr s 0 1 ""))] (listContains? (list "0" "1" "2" "3" "4" "5" "6" "7" "8" "9") c)))

fn mangleCIdent s: String -> String
  (let [(sLen (stringLength s))] (if (<= sLen 0) "" (let [(isPred (and (> sLen 1) (stringEndsWith? s "?"))) (withoutPred (if isPred (sliceOr s 0 (- sLen 1) "") s)) (pLen (stringLength withoutPred)) (isMut (and (> pLen 1) (stringEndsWith? withoutPred "!"))) (withoutMut (if isMut (str (sliceOr withoutPred 0 (- pLen 1) "") "-mut") withoutPred)) (withIs (if isPred (if (or (stringStartsWith? withoutMut "is-") (stringStartsWith? withoutMut "is_")) (str "asl-" withoutMut) (str "asl-is-" withoutMut)) withoutMut)) (snaked (stringReplace (stringReplace withIs "-" "_") "/" "_")) (safeIdent (if (isC99Keyword? snaked) (str "asl_" snaked) (if (isDigitLeading? snaked) (str "asl_" snaked) snaked)))] safeIdent)))

fn capitalizeSeg seg: String -> String
  (let [(segLen (stringLength seg))] (if (<= segLen 0) "" (let [(head (stringUpper (sliceOr seg 0 1 ""))) (tail (stringLower (sliceOr seg 1 segLen "")))] (str head tail))))

fn pascalIdent s: String -> String
  (if (and (not (stringContains? s "-")) (not (stringContains? s "_"))) (if (and (> (stringLength s) 0) (= (stringUpper (sliceOr s 0 1 "")) (sliceOr s 0 1 ""))) s (capitalizeSeg s)) (let [(norm (stringReplace s "_" "-")) (segs (stringSplit norm "-")) (caps (map capitalizeSeg segs))] (stringJoin caps "")))

fn mangleCTypeName s: String -> String
  (let [(clean (if (stringStartsWith? s ":") (sliceOr s 1 (stringLength s) "") (stringReplace (stringReplace s "?" "") "!" "")))] (cond ((or (= clean "Int64") (= clean "I64") (= clean "Int")) "int64_t") ((or (= clean "Int32") (= clean "I32")) "int32_t") ((or (= clean "Float64") (= clean "F64") (= clean "Float") (= clean "Num")) "double") ((or (= clean "Float32") (= clean "F32")) "float") ((= clean "Bool") "bool") ((or (= clean "Unit") (= clean "void")) "void") ((or (= clean "String") (= clean "Str")) "asl_string_t") (else (let [(sLen (stringLength clean))] (if (<= sLen 0) "AslType" (let [(pascal (pascalIdent clean))] (if (stringStartsWith? pascal "Asl") pascal (str "Asl" pascal))))))))

fn mangleCModulePrefix modPath: String -> String
  (let [(p0 (if (stringStartsWith? modPath "asl/packages/") (sliceOr modPath 13 (stringLength modPath) "") (if (stringStartsWith? modPath "packages/") (sliceOr modPath 9 (stringLength modPath) "") (if (stringStartsWith? modPath "asl/") (sliceOr modPath 4 (stringLength modPath) "") modPath)))) (p1 (stringReplace (stringReplace p0 "/" "_") "-" "_")) (p2 (if (stringStartsWith? p1 "asl_") p1 (str "asl_" p1))) (p3 (if (stringEndsWith? p2 "_") p2 (str p2 "_")))] p3)
