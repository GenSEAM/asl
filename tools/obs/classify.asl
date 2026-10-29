(module ws/asl/tools/obs/classify
  :x [FailClass parseTable classify normSig selfCheck unclassifiedId]
  :i [(ws/asl/tools/obs/sx :a sx)])

; (:m :ref OBSCORPUS :do "static classifier, no model: the class table is data (failClasses.asn), rows are tried in file order on the lower-cased outcome plus first error line, and a line no row matches is reported as unclassified, never forced into a class")
(schema FailClass
  (:f id String)
  (:f any (List String))
  (:f ex (List String)))

fn unclassifiedId -> String
  "unclassified"

fn rowToClass line: String -> FailClass
  (let [(f (sx/topFields line))]
    (FailClass :id (optionOr (sx/field f ":id") "")
               :any (map sx/unq (sx/listItems (optionOr (sx/fieldRaw f ":any") "()")))
               :ex (map sx/unq (sx/listItems (optionOr (sx/fieldRaw f ":ex") "()")))))

fn parseTable text: String -> (List FailClass)
  (map rowToClass (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:failClass ")) (stringLines text)))

fn hit? lower: String c: FailClass -> Bool
  (listAny? (fn [(p String)] -> Bool (stringContains? lower (stringLower p))) c.any)

fn classify table: (List FailClass) blob: String -> String
  (match (listFind (fn [(c FailClass)] -> Bool (hit? (stringLower blob) c)) table)
    ((some c) c.id)
    ((none) (unclassifiedId)))

fn digitChar? c: String -> Bool
  (let [(b (stringToBytes c))]
    (and (> (bytesLength b) 0) (and (>= (bytesGet b 0) 48) (<= (bytesGet b 0) 57))))

fn normSig text: String -> String
  (let [(res (fold (fn [(acc (Pair Bool (List String))) (c String)] -> (Pair Bool (List String))
                     (if (digitChar? c)
                       (if (pairFirst acc) acc (pair true (cons "N" (pairSecond acc))))
                       (pair false (cons c (pairSecond acc)))))
                   (pair false (list)) (stringChars text)))]
    (stringJoin (listReverse (pairSecond res)) ""))

fn selfCheck table: (List FailClass) -> (List String)
  (listFlatMap (fn [(c FailClass)] -> (List String)
             (filter (fn [(m String)] -> Bool (!= m ""))
                     (map (fn [(e String)] -> String
                            (if (= (classify table e) c.id) "" (str c.id ": " e " -> " (classify table e))))
                          c.ex)))
           table)
