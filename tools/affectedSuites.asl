(module asl-tools/affectedSuites
  :x [Item Mod parseModule splitItems itemNameOf wordIn? affectedSuitesIn affectedSuites! changedSymbolsOf changedItemNames formNamesFrom dispatchesForm? reasonText main]
  :i [(asl-tools/testImpact :a ti)])

schema Item
  (:f name String)
  (:f text String)

schema Mod
  (:f path String)
  (:f name String)
  (:f imports (List String))
  (:f items (List Item))
  (:f source String)

; (:m :ref PERF-AFFECTED-TESTS-SYMBOL :do "selection by changed symbol: a suite is picked when one of its items mentions a changed symbol, or a symbol whose item mentions it, through a chain of direct dependents; a suite that only imports the module is not picked. Name matching is word-bounded and limited to the defining module and its importers")
fn nameByte? b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57))
      (and (>= b 65) (<= b 90))
      (and (>= b 97) (<= b 122))
      (= b 95) (= b 33) (= b 63) (= b 45) (= b 46))

fn boundaryAt? s: String i: Int64 -> Bool
  (or (< i 0) (>= i (stringLength s))
      (not (nameByte? (optionOr (stringByteAt s i) 0))))

fn stringByteAt s: String i: Int64 -> (Option Int64)
  (match (stringSlice s i (+ i 1))
    ((none) none)
    ((some c) (listHead (bytesToInts (stringToBytes c)))))

fn bytesToInts bs: Bytes -> (List Int64)
  (if (= (bytesLength bs) 0) (list) (list (bytesGet bs 0)))

fn wordFrom? text: String name: String from: Int64 -> Bool
  (match (stringIndexOf (optionOr (stringSlice text from (stringLength text)) "") name)
    ((none) false)
    ((some k)
      (let [(at (+ from k))
            (end (+ at (stringLength name)))]
        (if (and (boundaryAt? text (- at 1)) (boundaryAt? text end))
          true
          (wordFrom? text name (+ at 1))))))

fn wordIn? text: String name: String -> Bool
  (and (stringContains? text name) (wordFrom? text name 0))

fn firstWords line: String -> (List String)
  (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim line) " "))

fn stripParen w: String -> String
  (if (stringStartsWith? w "(") (optionOr (stringSlice w 1 (stringLength w)) "") w)

fn itemNameOf line: String -> String
  (let [(ws (firstWords line))
        (w0 (stripParen (optionOr (listGet ws 0) "")))
        (w1 (stripParen (optionOr (listGet ws 1) "")))
        (w2 (stripParen (optionOr (listGet ws 2) "")))]
    (cond
      ((= w0 "module") "*")
      ((= w0 "fn") (if (= w1 "!") w2 w1))
      ((or (= w0 "schema") (= w0 "enum") (= w0 "const") (= w0 "type")) w1)
      (else "")))

fn startsItem? line: String -> Bool
  (and (not (stringEmpty? line))
       (not (stringStartsWith? line " "))
       (not (stringStartsWith? line ";"))
       (not (stringStartsWith? line ")"))
       (not (stringEmpty? (itemNameOf line))))

; (:m :ref PERF-AFFECTED-TESTS-SYMBOL :do "one pass over the lines: comment lines wait and join the next item, indented and blank lines extend the open item")
fn ! itemsLoop lines: (List String) cur: (List String) pend: (List String) name: String out: (List Item) -> (List Item)
  (match (listHead lines)
    ((none) (if (stringEmpty? name) out (cons (Item :name name :text (stringJoin (listReverse cur) "\n")) out)))
    ((some line)
      (let [(rest (optionOr (listTail lines) (list)))]
        (cond
          ((startsItem? line)
            (let [(out2 (if (stringEmpty? name) out (cons (Item :name name :text (stringJoin (listReverse cur) "\n")) out)))]
              (itemsLoop rest (cons line pend) (list) (itemNameOf line) out2)))
          ((stringStartsWith? line ";") (itemsLoop rest cur (cons line pend) name out))
          (else (itemsLoop rest (cons line cur) pend name out))))))

fn ! splitItems source: String -> (List Item)
  (listReverse (itemsLoop (stringLines source) (list) (list) "" (list)))

fn moduleNameOfHeader header: String -> String
  (let [(line (optionOr (listHead (filter (fn [(l String)] -> Bool (not (or (stringEmpty? (stringTrim l)) (stringStartsWith? (stringTrim l) ";")))) (stringLines header))) ""))
        (ws (firstWords line))]
    (if (and (>= (listLength ws) 2) (= (optionOr (listGet ws 0) "") "(module"))
      (optionOr (listGet ws 1) "")
      ""))

fn ! parseModule path: String source: String -> Mod
  (let [(header (ti/headerOf source))]
    (Mod :path path :name (moduleNameOfHeader header) :imports (ti/headerImports header) :items (splitItems source) :source source))

fn isTest? path: String -> Bool
  (stringEndsWith? path "Test.asl")

schema Hit
  (:f key String)
  (:f parent String)
  (:f path String)
  (:f item String)

fn keyOf modName: String sym: String -> String
  (str modName "#" sym)

; (:m :ref PERF-AFFECTED-TESTS-SYMBOL :do "an import is the module name or, in the path form, the file path without .asl, so a suite importing asl/packages/P/src/M is a dependent of the module named in M's header")
fn dependents mods: (List Mod) target: String -> (List Mod)
  (let [(pathForm (map (fn [(m Mod)] -> String (optionOr (stringSlice m.path 0 (- (stringLength m.path) 4)) m.path))
                       (filter (fn [(m Mod)] -> Bool (and (= m.name target) (stringEndsWith? m.path ".asl"))) mods)))]
    (filter (fn [(m Mod)] -> Bool
              (or (= m.name target)
                  (listContains? m.imports target)
                  (some? (listHead (filter (fn [(i String)] -> Bool (listContains? pathForm i)) m.imports)))))
            mods))

; (:m :ref PERF-AFFECTED-TESTS-SYMBOL :do "form edge: a bin/asl-driven suite has no import edge, so a module counts as the handler of form K when a line of it compares something with the literal \"K\" or \":K\"")
fn ! dispatchesForm? source: String form: String -> Bool
  (let [(plain (if (stringStartsWith? form ":") (optionOr (stringSlice form 1 (stringLength form)) form) form))]
    (and (or (stringContains? source (str "\"" plain "\"")) (stringContains? source (str "\":" plain "\"")))
         (some? (listHead (filter (fn [(l String)] -> Bool
                                    (and (stringContains? l "(= ")
                                         (or (stringContains? l (str " \"" plain "\")")) (stringContains? l (str " \":" plain "\")")))))
                                  (stringLines source))))))

fn ! formMentions? source: String form: String -> Bool
  (let [(plain (if (stringStartsWith? form ":") (optionOr (stringSlice form 1 (stringLength form)) form) form))]
    (or (stringContains? source (str "(:" plain " "))
        (stringContains? source (str "(:" plain ")"))
        (stringContains? source (str "bin/asl " plain " "))))

fn formNamesFrom tools: String -> (List String)
  (filter (fn [(w String)] -> Bool (not (stringEmpty? w)))
    (map (fn [(chunk String)] -> String (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit chunk " ")) "") ")")) ""))
         (optionOr (listTail (stringSplit tools "(:op :")) (list))))

fn symbolsOfChanged mods: (List Mod) changedFiles: (List String) changedSymbols: (List String) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (m Mod)] -> (List (Pair String String))
          (if (not (listContains? changedFiles m.path))
            acc
            (let [(given (filter (fn [(s String)] -> Bool (stringStartsWith? s (str m.path "#"))) changedSymbols))
                  (names (if (or (listEmpty? given) (listContains? given (str m.path "#*")))
                           (map (fn [(i Item)] -> String i.name) m.items)
                           (map (fn [(s String)] -> String (optionOr (stringSlice s (+ (stringLength m.path) 1) (stringLength s)) "")) given)))]
              (listAppend acc (map (fn [(n String)] -> (Pair String String) (pair m.name n)) names)))))
        (list) mods)

fn ! visit! mods: (List Mod) queue: (List (Pair String String)) seen: (Map String Hit) picked: (List Hit) forms: (List String) -> (Pair (Map String Hit) (List Hit))
  (match (listHead queue)
    ((none) (pair seen picked))
    ((some cur)
      (let [(rest (optionOr (listTail queue) (list)))
            (modName (pairFirst cur))
            (sym (pairSecond cur))
            (curKey (keyOf modName sym))
            (hits (fold (fn [(acc (List Hit)) (m Mod)] -> (List Hit)
                          (listAppend acc
                            (map (fn [(i Item)] -> Hit (Hit :key (keyOf m.name i.name) :parent curKey :path m.path :item i.name))
                                 (filter (fn [(i Item)] -> Bool (and (not (stringEmpty? i.name)) (and (!= i.name "*") (wordIn? i.text sym)))) m.items))))
                        (list) (dependents mods modName)))
            (fresh (filter (fn [(h Hit)] -> Bool (and (not (mapHas? seen h.key)) (not (= h.key curKey)))) hits))
            (seen2 (fold (fn [(s (Map String Hit)) (h Hit)] -> (Map String Hit) (mapSet s h.key h)) seen fresh))
            (testHits (filter (fn [(h Hit)] -> Bool (isTest? h.path)) fresh))
            (next (map (fn [(h Hit)] -> (Pair String String) (pair (optionOr (listHead (stringSplit h.key "#")) "") h.item))
                       (filter (fn [(h Hit)] -> Bool (not (isTest? h.path))) fresh)))]
        (visit! mods (listAppend rest next) seen2 (listAppend picked testHits) forms))))

; (:m :ref AFFSYM-CHAIN-CYCLE :do "the reason chain from a hit back to a changed symbol, following parents; two changed items that mention each other are each other's parent, so the walk stops at the first node it has already listed (and at guard hops), never repeating one")
fn ! chainOf seen: (Map String Hit) key: String guard: Int64 -> (List String)
  (chainWalk seen key guard (list))

fn chainWalk seen: (Map String Hit) key: String guard: Int64 acc: (List String) -> (List String)
  (cond
    ((listContains? acc key) (listReverse acc))
    ((<= guard 0) (listReverse (cons key acc)))
    (else
      (match (mapGet seen key)
        ((none) (listReverse (cons key acc)))
        ((some h) (chainWalk seen h.parent (- guard 1) (cons key acc))))))

fn reasonText chain: (List String) -> String
  (stringJoin chain " <- ")

; (:m :ref PERF-AFFECTED-TESTS-SYMBOL :do "pure core over an in-memory source set; returns (suite path, reason) pairs sorted by path. formNames are the op names whose handler files get a form edge to the suites that mention (:K")
fn ! affectedSuitesIn sources: (List (Pair String String)) changedFiles: (List String) changedSymbols: (List String) formNames: (List String) -> (List (Pair String String))
  (let [(asl (filter (fn [(p (Pair String String))] -> Bool (stringEndsWith? (pairFirst p) ".asl")) sources))
        (mods (map (fn [(p (Pair String String))] -> Mod (parseModule (pairFirst p) (pairSecond p))) asl))
        (start (symbolsOfChanged mods changedFiles changedSymbols))
        (walked (visit! mods start (mapEmpty) (list) formNames))
        (seen (pairFirst walked))
        (bySymbol (map (fn [(h Hit)] -> (Pair String String) (pair h.path (reasonText (chainOf seen h.key 40)))) (pairSecond walked)))
        (touched (listUnique (listAppend (map pairFirst start) (map (fn [(h Hit)] -> String (optionOr (listHead (stringSplit h.key "#")) "")) (mapValues seen)))))
        (handlerForms (filter (fn [(f String)] -> Bool
                                (some? (listHead (filter (fn [(m Mod)] -> Bool (and (listContains? touched m.name) (dispatchesForm? m.source f))) mods))))
                              formNames))
        (byForm (fold (fn [(acc (List (Pair String String))) (m Mod)] -> (List (Pair String String))
                        (if (not (isTest? m.path)) acc
                          (match (listHead (filter (fn [(f String)] -> Bool (formMentions? m.source f)) handlerForms))
                            ((none) acc)
                            ((some f) (listAppend acc (list (pair m.path (str "form:" f))))))))
                      (list) mods))
        (byFile (fold (fn [(acc (List (Pair String String))) (m Mod)] -> (List (Pair String String))
                        (if (and (isTest? m.path) (listContains? changedFiles m.path)) (listAppend acc (list (pair m.path "changed"))) acc))
                      (list) mods))
        (byFixture (fold (fn [(acc (List (Pair String String))) (m Mod)] -> (List (Pair String String))
                           (if (not (isTest? m.path)) acc
                             (match (listHead (filter (fn [(c String)] -> Bool (mentionsFixture? m.source c)) changedFiles))
                               ((none) acc)
                               ((some c) (listAppend acc (list (pair m.path (str "fixture:" c))))))))
                         (list) mods))]
    (dedupe (listSortBy (fn [(p (Pair String String))] -> String (pairFirst p)) (listAppend (listAppend (listAppend bySymbol byForm) byFile) byFixture))))

fn mentionsFixture? source: String changed: String -> Bool
  (and (not (stringEndsWith? changed ".asl")) (stringContains? source changed))

fn dedupe ps: (List (Pair String String)) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (p (Pair String String))] -> (List (Pair String String))
          (if (some? (listHead (filter (fn [(q (Pair String String))] -> Bool (= (pairFirst q) (pairFirst p))) acc))) acc (listAppend acc (list p))))
        (list) ps)

fn listUnique xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

fn changedItemNames old: String new: String -> (List String)
  (let [(oldItems (splitItems old))
        (newItems (splitItems new))
        (oldText (fold (fn [(m (Map String String)) (i Item)] -> (Map String String) (mapSet m i.name i.text)) (mapEmpty) oldItems))
        (newText (fold (fn [(m (Map String String)) (i Item)] -> (Map String String) (mapSet m i.name i.text)) (mapEmpty) newItems))
        (changedOrNew (filter (fn [(i Item)] -> Bool (and (not (stringEmpty? i.name)) (!= (optionOr (mapGet oldText i.name) "\u0000") i.text))) newItems))
        (removed (filter (fn [(i Item)] -> Bool (and (not (stringEmpty? i.name)) (not (mapHas? newText i.name)))) oldItems))]
    (listUnique (map (fn [(i Item)] -> String i.name) (listAppend changedOrNew removed))))

; (:m :ref PERF-AFFECTED-TESTS-SYMBOL :do "item names whose text differs between the base and the working copy, per file, as path#name rows; a module header change is path#*; a file with no base copy is path#*")
fn ! changedSymbolsOf base: String files: (List String) -> (List String)
  (fold (fn [(acc (List String)) (path String)]
          -> (List String)
          (if (not (stringEndsWith? path ".asl")) acc
            (let [(old (ti/runProc (list "git" "show" (str base ":" path))))
                  (new (resultOr (fileReadString path) ""))]
              (if (!= old.exitCode 0)
                (listAppend acc (list (str path "#*")))
                (listAppend acc (map (fn [(n String)] -> String (str path "#" n)) (changedItemNames old.stdout new)))))))
        (list) files)

fn ! loadSources! -> (Result (List (Pair String String)) String)
  (let [(out (ti/runProc (list "git" "ls-files" "--cached" "--others" "--exclude-standard" "*.asl")))]
    (if (!= out.exitCode 0)
      (err out.stderr)
      (ok (fold (fn [(acc (List (Pair String String))) (p String)] -> (List (Pair String String))
                  (match (fileReadString p) ((ok s) (cons (pair p s) acc)) ((err _) acc)))
                (list) (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines out.stdout))))))

fn ! affectedSuites! changedFiles: (List String) changedSymbols: (List String) -> (Result (List (Pair String String)) String)
  (match (loadSources!)
    ((err e) (err e))
    ((ok sources)
      (let [(forms (formNamesFrom (resultOr (fileReadString "asl/grammar/tools.asn") "")))]
        (ok (affectedSuitesIn sources changedFiles changedSymbols forms)))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(baseArg (optionOr (listHead (filter (fn [(a String)] -> Bool (stringStartsWith? a "--base=")) args)) "--base=HEAD"))
        (base (optionOr (stringSlice baseArg 7 (stringLength baseArg)) "HEAD"))
        (changedRes (match (ti/changedFromArgs args) ((some c) (ok c)) ((none) (ti/changedFromGit base))))]
    (match changedRes
      ((err e) (do (eprintln e) (ok 2)))
      ((ok changed)
        (match (affectedSuites! changed (changedSymbolsOf base changed))
          ((err e) (do (eprintln e) (ok 2)))
          ((ok picked)
            (do (println (str "(:affected :base \"" base "\" :changed " (stringFromInt64 (listLength changed)) " :selected "
                              (stringFromInt64 (listLength picked)) " :suites ("
                              (stringJoin (map (fn [(p (Pair String String))] -> String (str "(\"" (pairFirst p) "\" \"" (pairSecond p) "\")")) picked) " ") "))"))
                (ok 0)))))))
