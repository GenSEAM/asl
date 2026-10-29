(module asl-tools/coord/gateGuard
  :x [moduleName importsModule? importers shrunk? shrinkSig maxImporters]
  :i [])

; (:m :ref CONDHARDEN :do "pure checks of the conductor's gate stage: which files import an owned module, and whether an owned file lost more than half its base lines; the impure callers (git, files, asl check) live in conductor.asl")

fn maxImporters -> Int64
  40

; (:m :do "the module name of a source text: the token after the first '(module ', empty when the text has none")
fn moduleName text: String -> String
  (let [(parts (stringSplit text "(module "))]
    (if (< (listLength parts) 2) ""
      (let [(rest (stringTrim (optionOr (listGet parts 1) "")))
            (cut (fn [(s String) (d String)] -> String (optionOr (listHead (stringSplit s d)) s)))]
        (cut (cut (cut (cut rest " ") "\n") ")") "]"))))

; (:m :do "boundary: the name must stand alone, so asl/fleet/run does not match asl/fleet/runner")
fn delimBefore? c: String -> Bool
  (or (= c "(") (or (= c "[") (or (= c " ") (= c "\n"))))

fn delimAfter? c: String -> Bool
  (or (= c " ") (or (= c ")") (or (= c "]") (or (= c "\n") (= c "")))))

fn lastChar s: String -> String
  (if (stringEmpty? s) "" (optionOr (stringSlice s (- (stringLength s) 1) (stringLength s)) ""))

fn firstChar s: String -> String
  (if (stringEmpty? s) "" (optionOr (stringSlice s 0 1) ""))

; (:m :do "true when text lists mod as a whole name inside an import position (after a paren, bracket or space, before a space, closer or newline); a module header alone never counts")
fn importsModule? text: String mod: String -> Bool
  (if (stringEmpty? mod) false
    (let [(parts (stringSplit text mod))
          (n (listLength parts))
          (hit (fn [(i Int64)] -> Bool
                 (let [(left (optionOr (listGet parts i) ""))
                       (right (optionOr (listGet parts (+ i 1)) ""))]
                   (and (delimBefore? (lastChar left)) (and (delimAfter? (firstChar right)) (not (stringEndsWith? left "(module ")))))))]
      (and (> n 1) (listAny? hit (range 0 (- n 1))))))

; (:m :do "paths of files whose text imports any owned module, owned files themselves left out, in input order, at most maxImporters")
fn importers files: (List (Pair String String)) mods: (List String) owned: (List String) -> (List String)
  (let [(live (filter (fn [(m String)] -> Bool (not (stringEmpty? m))) mods))
        (hits (filter (fn [(f (Pair String String))] -> Bool
                        (and (not (listContains? owned (pairFirst f)))
                             (listAny? (fn [(m String)] -> Bool (importsModule? (pairSecond f) m)) live)))
                      files))]
    (listTake (map pairFirst hits) (maxImporters)))

; (:m :do "more than half of the base lines gone")
fn shrunk? baseLines: Int64 nowLines: Int64 -> Bool
  (and (> baseLines 0) (> (* 2 (- baseLines nowLines)) baseLines))

; (:m :do "the refusal signature for one owned file, empty when it kept enough lines or the task text says rewrite")
fn shrinkSig path: String baseLines: Int64 nowLines: Int64 task: String -> String
  (if (and (shrunk? baseLines nowLines) (not (stringContains? (stringLower task) "rewrite")))
    (str "owned file " path " lost " (stringFromInt64 (- baseLines nowLines)) " of " (stringFromInt64 baseLines) " lines; the task text does not say rewrite")
    "")
