(module asl-coord/paths
  :x [trimPath entryFile pathsOverlap? pathWithin? pathUnderOwns? exemptPath? listOverlapPath overlapBetween]
  :i [])

fn trimPath path: String -> String
  (cond
    ((stringStartsWith? path "./") (trimPath (optionOr (stringSlice path 2 (stringLength path)) "")))
    ((and (> (stringLength path) 1) (stringEndsWith? path "/"))
      (trimPath (optionOr (stringSlice path 0 (- (stringLength path) 1)) "")))
    (else path))

; (:m :ref OWNS-SYMBOL-CLAIMS :do "an :owns entry may be path#symbol (asl-tools/coord/store decides same-file clashes by symbol); a path check here is by file, so the symbol part is cut before the compare and a writer owning f.asl#sym may edit f.asl while f.asl and f.asl#B overlap")
fn entryFile e: String -> String
  (optionOr (listHead (stringSplit e "#")) e)

fn pathsOverlap? left: String right: String -> Bool
  (let [(a (trimPath (entryFile left))) (b (trimPath (entryFile right)))]
    (or (= a b) (stringStartsWith? a (str b "/")) (stringStartsWith? b (str a "/"))))

fn pathWithin? path: String root: String -> Bool
  (let [(p (trimPath (entryFile path))) (r (trimPath (entryFile root)))]
    (or (= p r) (stringStartsWith? p (str r "/"))))

fn pathUnderOwns? path: String owns: (List String) -> Bool
  (listAny? (fn [(root String)] -> Bool (pathWithin? path root)) owns)

fn exemptPath? path: String -> Bool
  (let [(p (trimPath path))]
    (or (= p "scripts/audit/foreignBaseline.asn") (= p "scripts/audit/foreignAllowlist.asn")))

fn listOverlapPath items: (List String) path: String -> String
  (match (listHead items)
    ((none) "")
    ((some item)
      (if (and (not (exemptPath? path)) (and (not (exemptPath? item)) (pathsOverlap? path item)))
        item
        (listOverlapPath (optionOr (listTail items) (list)) path))))


fn overlapBetween left: (List String) right: (List String) -> String
  (match (listHead left)
    ((none) "")
    ((some path)
      (let [(hit (listOverlapPath right path))]
        (if (stringEmpty? hit) (overlapBetween (optionOr (listTail left) (list)) right) path))))
