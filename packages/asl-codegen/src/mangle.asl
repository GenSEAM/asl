(module asl-codegen/mangle :x [mangleIdent pascalIdent rustModName shortModName capitalizeSeg isRustKeyword? sliceOr] :i [])

fn isRustKeyword? m: String -> Bool
  (listContains? (list "type" "match" "fn" "let" "loop" "move" "ref" "impl" "mod" "use" "const" "static" "crate" "super" "self" "struct" "enum" "trait" "where" "for" "while" "return" "break" "continue" "as" "in" "main") m)

fn sliceOr s: String start: Int64 end: Int64 fallback: String -> String
  (optionOr (stringSlice s start end) fallback)

fn mangleIdent s: String -> String
  (let [(sLen (stringLength s)) (base1 (if (and (> sLen 1) (stringEndsWith? s "?")) (str "is-" (sliceOr s 0 (- sLen 1) "")) s)) (len1 (stringLength base1)) (base2 (if (and (> len1 1) (stringEndsWith? base1 "!")) (str (sliceOr base1 0 (- len1 1) "") "-mut") base1)) (snaked (stringReplace base2 "-" "_"))] (if (isRustKeyword? snaked) (str snaked "_") snaked))

fn capitalizeSeg seg: String -> String
  (let [(segLen (stringLength seg))] (if (<= segLen 0) "" (let [(head (stringUpper (sliceOr seg 0 1 ""))) (tail (stringLower (sliceOr seg 1 segLen "")))] (str head tail))))

fn pascalIdent s: String -> String
  (if (and (not (stringContains? s "-")) (not (stringContains? s "_"))) (if (and (> (stringLength s) 0) (= (stringUpper (sliceOr s 0 1 "")) (sliceOr s 0 1 ""))) s (capitalizeSeg s)) (let [(norm (stringReplace s "_" "-")) (segs (stringSplit norm "-")) (caps (map capitalizeSeg segs))] (stringJoin caps "")))

fn rustModName modPath: String -> String
  (let [(segs (stringSplit modPath "/")) (mangled (map mangleIdent segs))] (stringJoin mangled "_"))

fn shortModName modPath: String -> String
  (if (stringContains? modPath "/") (let [(parts (stringSplit modPath "/")) (lastIdx (- (listLength parts) 1)) (lastPart (optionOr (listGet parts lastIdx) modPath))] (rustModName lastPart)) (rustModName modPath))
