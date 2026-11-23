(module asl-forms/tests/memOpTest
  :x [runTests]
  :i [(asl-forms/memOp :a m)
      (asl-forms/vfs :a v)
      (asl-forms/kernel :a k)])

fn kw1 key: String val: String -> (Map String String)
  (mapSet (mapEmpty) key val)

fn kw2 k1: String v1: String k2: String v2: String -> (Map String String)
  (mapSet (kw1 k1 v1) k2 v2)

fn kw3 k1: String v1: String k2: String v2: String k3: String v3: String -> (Map String String)
  (mapSet (kw2 k1 v1 k2 v2) k3 v3)

fn firstLine out: k/EditOutcome -> String
  (optionOr (listHead out.lines) "")

fn rowCount text: String -> Int64
  (- (listLength (stringSplit text "(:u")) 1)

fn ! runTests -> Bool
  (let [(root (str "/tmp/memOpTest" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
        (memDir (k/joinPath (k/joinPath root ".asl") "mem"))
        (path (k/joinPath memDir "ledger.asn"))
        (mk (dirCreate memDir))
        (wr (fileWrite path "(:u :id A :st open)\n(:u :id B :st open)\n"))
        (getOut (m/memStep! root 1 (kw3 "op" "get" "file" "ledger.asn" "id" "A") (list) (list)))
        (putOut (m/memStep! root 2 (kw3 "op" "put" "file" "ledger.asn" "row" "(:u :id A :st done)") (list) (list)))
        (staged (match (v/vfsContext! root)
                  ((ok ctx) (v/stagedContent! ctx path))
                  ((err _) (none))))
        (stagedText (optionOr staged ""))
        (dupWrite (fileWrite path "(:u :id A :st open)\n(:u :id A :st open)\n"))
        (dupOut (m/memStep! root 3 (kw3 "op" "put" "file" "ledger.asn" "row" "(:u :id A :st done)") (list) (list)))]
    (do
      (assert (and (ok? mk) (ok? wr)) "the ledger fixture is written under .asl/mem")
      (assert (and (= getOut.errCount 0)
                   (stringContains? (firstLine getOut) "A")
                   (stringContains? (firstLine getOut) "open")
                   (not (stringContains? (firstLine getOut) "ERR_NOT_FOUND")))
              "get finds the row whose :id keyword value is A")
      (assert (and (= putOut.errCount 0)
                   (stringContains? (firstLine putOut) ":staged true"))
              "put stages a replacement for the row with id A")
      (assert (and (stringContains? stagedText "(:u :id A :st done)")
                   (stringContains? stagedText "(:u :id B :st open)")
                   (= (rowCount stagedText) 2))
              "the staged ledger replaces row A in place and keeps two rows")
      (assert (and (ok? dupWrite) (= dupOut.errCount 1)
                   (stringContains? (firstLine dupOut) "ERR_DUPLICATE_ID"))
              "put refuses a ledger that already has two rows with the same id")
      true))
