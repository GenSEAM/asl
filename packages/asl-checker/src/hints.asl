(module asl-checker/hints
  :x [Hint hintTable unboundName diagKind hintFor headerExports exportersOf!]
  :i [(asl-checker/types :a ty) (asl-checker/resolve :a r)])

; (:m :do "STATICHINT 2026-10-28: one short ASN hint per checker diagnostic, chosen by a data table (code plus a message fragment); the two context hints, nearest known name and exporting module, are built by the caller from heal symbolCandidates and exportersOf! and passed in, so no name-matching logic is copied here")

(schema Hint (:f code String) (:f when String) (:f say String))

fn hintTable -> (List Hint)
  (list
    (Hint :code "ERR_TYPE_MISMATCH" :when "(Option " :say "listGet/listHead/mapGet return Option: unwrap with match (some v)/(none) or optionOr")
    (Hint :code "ERR_TYPE_MISMATCH" :when "(Result " :say "fileReadString and parse fns return Result: unwrap with match (ok v)/(err e) or resultOr")
    (Hint :code "ERR_ARITY" :when "" :say "pass exactly the declared parameter count; read the callee signature by symbol")
    (Hint :code "ERR_TYPE_ARITY" :when "" :say "a type takes its declared number of type arguments: (List T) (Option T) (Map K V)")
    (Hint :code "ERR_NOT_EXPORTED" :when "" :say "add the name to the :x list of the module that defines it"))

; (:m :do "the checker reports some codes only inside the message (rule-9 carries ERR_NOT_EXPORTED:, type-arity is a bare code): diagKind folds them to one code")
fn diagKind d: ty/Diagnostic -> String
  (cond
    ((stringStartsWith? d.message "ERR_NOT_EXPORTED") "ERR_NOT_EXPORTED")
    ((= d.code "type-arity") "ERR_TYPE_ARITY")
    (else d.code))

fn slice s: String i: Int64 j: Int64 -> String
  (optionOr (stringSlice s i j) "")

fn unboundName d: ty/Diagnostic -> (Option String)
  (cond
    ((stringStartsWith? d.message "unbound symbol: ") (some (optionOr (listHead (stringSplit (slice d.message 16 (stringLength d.message)) ";")) "")))
    ((stringEndsWith? d.message " is not defined") (some (slice d.message 0 (- (stringLength d.message) 15))))
    (else none))

fn tableHint d: ty/Diagnostic -> (Option String)
  (let [(kind (diagKind d))
        (hit (filter (fn [(h Hint)] -> Bool (and (= h.code kind) (stringContains? d.message h.when))) (hintTable)))]
    (match (listHead hit) ((some h) (some h.say)) ((none) none)))

fn aliasOf modName: String -> String
  (optionOr (listLast (stringSplit modName "/")) modName)

; (:m :do "hintFor: unbound symbol with an exporting module names the import, else with a nearest known name names that; every other code reads the table; at most one hint, none when nothing applies. owners are the modules whose :x lists the name, near the nearest-name candidates")
fn hintFor d: ty/Diagnostic near: (List String) owners: (List String) -> (Option String)
  (match (unboundName d)
    ((some name)
      (cond
        ((= (listLength owners) 1)
          (let [(m (optionOr (listHead owners) ""))]
            (some (str "exported by " m ": add (" m " :a " (aliasOf m) ") to :i and call " (aliasOf m) "/" name))))
        ((> (listLength owners) 1) (some (str name " is exported by " (stringJoin owners " ") ": import the one you mean with :a")))
        ((not (listEmpty? near)) (some (str "nearest known name: " (optionOr (listHead near) ""))))
        (else none)))
    ((none) (tableHint d)))

fn headerExports text: String -> (List String)
  (match (stringIndexOf text ":x [")
    ((none) (list))
    ((some i)
      (let [(rest (slice text (+ i 4) (stringLength text)))]
        (match (stringIndexOf rest "]")
          ((none) (list))
          ((some j) (filter (fn [(w String)] -> Bool (not (stringEmpty? w)))
                            (stringSplit (stringReplace (stringReplace (slice rest 0 j) "\n" " ") "\t" " ") " ")))))))

fn ! readModule! root: String path: String -> String
  (match (fileReadString path)
    ((ok s) s)
    ((err _) (resultOr (fileReadString (str root "/" path)) "")))

; (:m :do "name -> modules whose header :x lists it, over the package index of root (tests dirs skipped); one read per module, built only when a caller has unbound names to place")
fn ! exportersOf! root: String names: (List String) -> (Map String (List String))
  (if (listEmpty? names)
    (mapEmpty)
    (let [(ix (r/ensureIndex! root (r/emptyModIndex)))]
      (fold (fn [(acc (Map String (List String))) (m r/IdxMod)] -> (Map String (List String))
              (if (stringContains? m.path "/tests/")
                acc
                (let [(ex (headerExports (readModule! root m.path)))]
                  (fold (fn [(a (Map String (List String))) (n String)] -> (Map String (List String))
                          (if (listContains? ex n) (mapSet a n (listAppend (optionOr (mapGet a n) (list)) (list m.name))) a))
                        acc names))))
            (mapEmpty) ix.mods)))
