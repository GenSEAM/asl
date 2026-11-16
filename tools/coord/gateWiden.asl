(module asl-tools/coord/gateWiden
  :x [moduleNameOf importsOf importersOf suitesOf widenedGate]
  :i [])

; (:m :ref CONDUCTOR-GATE-WIDEN :do "pure half of the conductor's widened gate: the module name of a source text, the imports named in its :i vector, which files import an owned module, which test suites exercise one, and the widened gate command list; the impure callers (files, git, asl check) live in conductor.asl")

fn moduleNameOf text: String -> String
  (let [(parts (stringSplit text "(module "))]
    (if (< (listLength parts) 2) ""
      (let [(rest (stringTrim (optionOr (listGet parts 1) "")))
            (cut (fn [(s String) (d String)] -> String (optionOr (listHead (stringSplit s d)) s)))]
        (cut (cut (cut (cut rest " ") "\n") ")") "]"))))

; (:m :do "module names inside the :i [...] vector, alias forms (x/y :a z) included; empty when the text has no :i vector")

fn firstToken s: String -> String
  (let [(noClose (optionOr (listHead (stringSplit s ")")) s))]
    (optionOr (listHead (stringSplit (stringTrim noClose) " ")) ""))

fn importsOf text: String -> (List String)
  (let [(parts (stringSplit text ":i ["))
        (vec (optionOr (listHead (stringSplit (optionOr (listGet parts 1) "") "]")) ""))]
    (filter (fn [(t String)] -> Bool (not (stringEmpty? t)))
            (map firstToken (stringSplit vec "("))))

; (:m :do "the module names of the owned paths, looked up in the files list; a path is not itself a module name")

fn ownedMods owned: (List String) files: (List (Pair String String)) -> (List String)
  (map (fn [(p String)] -> String
         (fold (fn [(acc String) (f (Pair String String))] -> String
                 (if (= (pairFirst f) p) (moduleNameOf (pairSecond f)) acc))
               "" files))
       owned)

; (:m :do "paths whose imports name a module defined by an owned file, owned files themselves left out, in input order")

fn importersOf owned: (List String) files: (List (Pair String String)) -> (List String)
  (let [(mods (ownedMods owned files))
        (live (filter (fn [(m String)] -> Bool (not (stringEmpty? m))) mods))
        (hits (filter (fn [(f (Pair String String))] -> Bool
                        (and (not (listContains? owned (pairFirst f)))
                             (listAny? (fn [(m String)] -> Bool (listContains? (importsOf (pairSecond f)) m)) live)))
                      files))]
    (map pairFirst hits))

; (:m :do "the directory part of a path")

fn dirOf p: String -> String
  (stringJoin (listTake (stringSplit p "/") (- (listLength (stringSplit p "/")) 1)) "/")

; (:m :do "test files under an owned file's package tests/ that import an owned module")

fn suitesOf owned: (List String) files: (List (Pair String String)) -> (List String)
  (let [(mods (ownedMods owned files))
        (live (filter (fn [(m String)] -> Bool (not (stringEmpty? m))) mods))
        (dirs (map (fn [(p String)] -> String (dirOf p)) owned))
        (hits (filter (fn [(f (Pair String String))] -> Bool
                        (and (stringEndsWith? (pairFirst f) "Test.asl")
                             (and (listAny? (fn [(d String)] -> Bool (stringStartsWith? (pairFirst f) (str d "/tests/"))) dirs)
                                  (listAny? (fn [(m String)] -> Bool (listContains? (importsOf (pairSecond f)) m)) live))))
                      files))]
    (map pairFirst hits))

fn dedup xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String)
          (if (listContains? acc x) acc (listAppend acc (list x))))
        (list) xs)

; (:m :do "declared first, then './bin/asl test T' per suite, then './bin/asl check F' per importer, deduplicated and sorted")

fn widenedGate declared: (List String) owned: (List String) files: (List (Pair String String)) -> (List String)
  (let [(suites (map (fn [(t String)] -> String (str "./bin/asl test " t)) (suitesOf owned files)))
        (checks (map (fn [(f String)] -> String (str "./bin/asl check " f)) (importersOf owned files)))
        (all (listAppend declared (listAppend suites checks)))]
    (listSort (dedup all)))
