(module asl-tools/coord/tests/planImportSymbolOwnsTest
  :x [runTests]
  :i [(asl-tools/coord/planImport :a pi) (asl-tools/coord/store :a st)])

; (:m :ref PLANIMPORT-SYMBOL-OWNS :do "bare symbol :owns items parse to their path text; a refused row carries the store refusal text in :bad; a dry import validates owns paths like the store and reports invalid rows as :bad")

fn ! scratchStore name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/planImportSymbolOwnsTest-" (stringFromInt64 (procSelf)) "-" name)

fn badOf r: (Result pi/Report String) -> (List String)
  (match r ((ok rep) rep.bad) ((err _) (list "ERR")))

fn putOf r: (Result pi/Report String) -> (List String)
  (match r ((ok rep) rep.put) ((err _) (list "ERR")))

fn ! idsOf store: String -> (List String)
  (match (st/readUnits! store) ((ok us) (map (fn [(u st/Task)] -> String u.id) us)) ((err _) (list)))

fn testBareSymbolOwns -> Bool
  (let [(rows (pi/rowsOf "(:u :id BS1 :auto true :do \"bare owns\" :owns (a/b.asl c/d.asl) :gate \"true\")\n"))
        (owns (match (listHead rows) ((some r) r.owns) ((none) (list))))]
    (do (assert (= owns (list "a/b.asl" "c/d.asl")) (str "bare symbol owns yield the two paths: " (stringJoin owns ",")))
        true))

fn ! testBadRowCarriesReason -> Bool
  (let [(store (scratchStore "badReason"))
        (_ (dirCreate store))
        (r (pi/plan! "(:u :id BAD1 :auto true :do \"bad owns\" :owns (\"../outside.asl\") :gate \"true\")\n" store "dev" false))
        (bad (badOf r))
        (entry (optionOr (listHead bad) ""))
        (ids (idsOf store))
        (_ (pathRemove store))]
    (do (assert (ok? r) (str "import runs: " r))
        (assert (= (listLength bad) 1) (str "one bad row: " (stringJoin bad ",")))
        (assert (and (stringStartsWith? entry "BAD1:") (and (stringContains? entry "(:refused") (stringContains? entry ":why owns"))) (str "bad entry carries the refusal text: " entry))
        (assert (listEmpty? ids) (str "the invalid owns row is not stored: " (stringJoin ids ",")))
        true))

fn ! testDryFlagsInvalidOwns -> Bool
  (let [(store (scratchStore "dryBad"))
        (_ (dirCreate store))
        (r (pi/plan! "(:u :id DRY1 :auto true :do \"bad owns\" :owns (\"../outside.asl\") :gate \"true\")\n" store "dev" true))
        (bad (badOf r))
        (entry (optionOr (listHead bad) ""))
        (put (putOf r))
        (ids (idsOf store))
        (_ (pathRemove store))]
    (do (assert (ok? r) (str "dry import runs: " r))
        (assert (= (listLength bad) 1) (str "dry flags the invalid owns path: " (stringJoin bad ",")))
        (assert (and (stringStartsWith? entry "DRY1:") (stringContains? entry ":why owns")) (str "dry bad entry carries the reason: " entry))
        (assert (and (listEmpty? put) (listEmpty? ids)) "a dry import puts nothing")
        true))

fn ! runTests -> Bool
  (do (assert (testBareSymbolOwns) "bare symbol owns parse")
      (assert (testBadRowCarriesReason) "a bad row carries its refusal reason")
      (assert (testDryFlagsInvalidOwns) "a dry import flags an invalid owns path")
      true)
