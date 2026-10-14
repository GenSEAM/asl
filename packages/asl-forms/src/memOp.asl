(module asl-forms/memOp :x [memStep!] :i [(asl-forms/kernel :a k) (asl-forms/vfs :a v) (asl-syntax/asl/asn :a asn) (asl-syntax/asl/paren :a prn) (asl-syntax/core/tree :a tr)])

(schema MemRow (:f raw String) (:f id String) (:f start Int64) (:f end Int64))

fn memHead id: Int64 -> String
  (str "  (:step :id " (stringFromInt64 id) " :op \"mem\"")

fn q s: String -> String
  (str "\"" (k/escapeAsnVal s) "\"")

fn fail id: Int64 code: String message: String -> k/EditOutcome
  (k/EditOutcome :lines (list (str (memHead id) " :status \"rejected\" :error-code \"" code "\" :message " (q message) ")")) :errCount 1)

fn memOk id: Int64 body: String -> k/EditOutcome
  (k/EditOutcome :lines (list (str (memHead id) " :status \"ok\"" body ")")) :errCount 0)

fn idText v: asn/AsnValue -> String
  (mt v ((asn/asnStr _) (optionOr (asn/asnStringValue v) "")) ((asn/asnSym name) name) ((asn/asnKw name) name) (_ (asn/asnWrite v)))

fn rowId v: asn/AsnValue -> String
  (mt v
    ((asn/asnCase _ fields) (mt (listHead fields) ((some x) (idText x)) ((none) "")))
    ((asn/asnRec fields) (let [(id (filter (fn [(f asn/AsnField)] -> Bool (= f.key "id")) fields))]
      (mt (listHead id) ((some f) (idText f.val)) ((none) (mt (listHead fields) ((some f) (idText f.val)) ((none) ""))))))
    (_ ""))

fn rowParse text: String el: tr/TreeElement value: asn/AsnValue -> MemRow
  (mt el
    ((tr/elemToken tok) (MemRow :raw (asn/asnWrite value) :id (rowId value) :start tok.start :end tok.end))
    ((tr/elemNode node)
      (let [(raw (optionOr (stringSlice text node.start node.end) ""))]
        (MemRow :raw raw :id (rowId value) :start node.start :end node.end))))

fn rowsLoop text: String elements: (List tr/TreeElement) values: (List asn/AsnValue) acc: (List MemRow) -> (List MemRow)
  (mt (listHead elements)
    ((none) (listReverse acc))
    ((some el) (mt (listHead values)
      ((none) (listReverse acc))
      ((some value) (rowsLoop text (optionOr (listTail elements) (list)) (optionOr (listTail values) (list)) (cons (rowParse text el value) acc))))))

fn ledgerRows text: String -> (Result (List MemRow) String)
  (let [(root (prn/parseString text)) (values (asn/asnReadForms text))]
    (if (or (prn/hasErrors root) (err? values)) (err "invalid ASN ledger")
      (ok (rowsLoop text (prn/topLevelForms root) (resultOr values (list)) (list)))))

fn listFilesLoop! dir: String rel: String names: (List String) acc: (List String) -> (Result (List String) String)
  (mt (listHead names)
    ((none) (ok acc))
    ((some name)
      (let [(full (k/joinPath dir name)) (r (if (stringEmpty? rel) name (str rel "/" name)))
            (tail (optionOr (listTail names) (list)))]
        (if (and (k/isDir! full) (not (v/isLink? full)))
          (mt (listFiles! full r)
            ((err e) (err e))
            ((ok nested) (listFilesLoop! dir rel tail (listAppend acc nested))))
          (listFilesLoop! dir rel tail (if (and (stringEndsWith? name ".asn") (k/isFile! full)) (listAppend acc (list r)) acc))))))

fn listFiles! dir: String rel: String -> (Result (List String) String)
  (if (and (stringEmpty? rel) (not (k/isDir! dir)))
    (ok (list))
    (listFilesIn! dir rel))

fn listFilesIn! dir: String rel: String -> (Result (List String) String)
  (mt (dirList dir)
    ((err e) (err e))
    ((ok names) (listFilesLoop! dir rel names (list))))

fn safeRel? path: String -> Bool
  (and (not (stringEmpty? path)) (not (stringStartsWith? path "/")) (not (listContains? (stringSplit path "/") "..")) (not (stringStartsWith? path "~")))

fn ! noLinkParts? current: String parts: (List String) -> Bool
  (mt (listHead parts)
    ((none) true)
    ((some part)
      (let [(next (k/joinPath current part))]
        (and (not (v/isLink? next)) (noLinkParts? next (optionOr (listTail parts) (list)))))))

fn ! safeMemRel? root: String rel: String -> Bool
  (let [(aslDir (k/joinPath root ".asl")) (base (memPath root ""))]
    (and (not (v/isLink? aslDir)) (not (v/isLink? base))
         (or (stringEmpty? rel) (and (safeRel? rel) (noLinkParts? base (stringSplit rel "/"))))))

fn listDirRel dir: String -> (Option String)
  (cond
    ((or (stringEmpty? dir) (= dir ".asl/mem")) (some ""))
    ((stringStartsWith? dir ".asl/mem/")
      (let [(rel (optionOr (stringSlice dir 9 (stringLength dir)) ""))]
        (if (safeRel? rel) (some rel) (none))))
    ((safeRel? dir) (some dir))
    (else (none)))

fn memPath root: String rel: String -> String
  (k/joinPath (k/joinPath (k/joinPath root ".asl") "mem") rel)

fn readRows! path: String -> (Result (Pair String (List MemRow)) String)
  (mt (fileReadString path) ((err e) (err e)) ((ok text) (mt (ledgerRows text) ((err e) (err e)) ((ok rs) (ok (pair text rs))))))

fn fileRows! root: String rel: String -> (Result (Pair String (List MemRow)) String)
  (if (not (safeMemRel? root rel)) (err "memory path must be relative and confined to .asl/mem") (readRows! (memPath root rel)))

fn countFiles! root: String fs: (List String) -> (Result (List String) String)
  (mt (listHead fs)
    ((none) (ok (list)))
    ((some rel)
      (mt (fileRows! root rel)
        ((err e)
          (mt (countFiles! root (optionOr (listTail fs) (list)))
            ((err later) (err later))
            ((ok rest) (ok (cons (str "(:file " (q rel) " :error " (q e) ")") rest)))))
        ((ok pair)
          (mt (countFiles! root (optionOr (listTail fs) (list)))
            ((err e) (err e))
            ((ok rest) (ok (cons (str "(:ledger :file " (q rel) " :rows " (stringFromInt64 (listLength (pairSecond pair))) " )") rest))))))))

fn findRow rows: (List MemRow) id: String -> (Option MemRow)
  (mt (listHead rows) ((none) (none)) ((some r) (if (= r.id id) (some r) (findRow (optionOr (listTail rows) (list)) id))))

fn ! getOp id: Int64 root: String kw: (Map String String) -> k/EditOutcome
  (let [(rel (k/kwOr kw "file" "")) (key (k/kwOr kw "id" ""))]
    (if (or (not (safeRel? rel)) (stringEmpty? key)) (fail id ":ERR_INVALID_ARG" "get requires confined :file and :id")
      (mt (fileRows! root rel) ((err e) (fail id ":ERR_MEM_READ" e)) ((ok pair)
        (mt (findRow (pairSecond pair) key) ((none) (fail id ":ERR_NOT_FOUND" "memory row not found")) ((some row) (memOk id (str " :file " (q rel) " :row " (q row.raw)))))))))

fn queryRows rows: (List MemRow) text: String limit: Int64 acc: (List String) -> (List String)
  (if (or (<= limit 0) (listEmpty? rows)) (listReverse acc)
    (let [(r (optionOr (listHead rows) (MemRow :raw "" :id "" :start 0 :end 0))) (tail (optionOr (listTail rows) (list)))]
      (if (stringContains? r.raw text) (queryRows tail text (- limit 1) (cons r.raw acc)) (queryRows tail text limit acc))))

fn ! queryOp id: Int64 root: String kw: (Map String String) -> k/EditOutcome
  (let [(text (k/kwOr kw "text" "")) (rel (k/kwOr kw "file" "")) (lim (mt (stringToInt64 (k/kwOr kw "limit" "100")) ((some n) (max 0 n)) ((none) 100)))
        (files (if (stringEmpty? rel) (listFiles! (memPath root "") "") (ok (list rel))))]
    (if (and (not (stringEmpty? rel)) (not (safeRel? rel))) (fail id ":ERR_BOUNDARY_VIOLATION" "memory path must stay under .asl/mem")
      (mt files
        ((err e) (fail id ":ERR_MEM_READ" e))
        ((ok fs) (mt (queryFiles root fs text lim (list))
          ((err e) (fail id ":ERR_MEM_READ" e))
          ((ok matches) (memOk id (str " :count " (stringFromInt64 (listLength matches)) " :rows [" (stringJoin matches " ") "]"))))))))

fn ! queryFiles root: String files: (List String) text: String limit: Int64 acc: (List String) -> (Result (List String) String)
  (if (or (listEmpty? files) (>= (listLength acc) limit)) (ok acc)
    (let [(f (optionOr (listHead files) "")) (tail (optionOr (listTail files) (list)))]
      (mt (fileRows! root f)
        ((err e) (err e))
        ((ok p)
          (let [(found (queryRows (pairSecond p) text (- limit (listLength acc)) (list)))
                (tagged (map (fn [(r String)] -> String (str "(:row :file " (q f) " :value " (q r) ")")) found))]
            (queryFiles root tail text limit (listAppend acc tagged)))))))

fn replaceRows text: String rows: (List MemRow) id: String newRow: String -> String
  (let [(matching (findRow rows id))]
    (mt matching ((none) (str (if (stringEndsWith? text "\n") text (str text "\n")) newRow "\n"))
      ((some target)
        (str (optionOr (stringSlice text 0 target.start) "") newRow
             (optionOr (stringSlice text target.end (stringLength text)) "")))))

fn putOp! id: Int64 root: String kw: (Map String String) -> k/EditOutcome
  (let [(rel (k/kwOr kw "file" "")) (row (k/kwOr kw "row" "")) (parsed (asn/asnRead row))]
    (cond
      ((not (safeRel? rel)) (fail id ":ERR_BOUNDARY_VIOLATION" "memory path must be relative under .asl/mem"))
      ((stringEmpty? row) (fail id ":ERR_MISSING_ARG" "put requires :row"))
      ((err? parsed) (fail id ":ERR_INVALID_ROW" "put row is not valid ASN"))
      (else (let [(key (rowId (resultOr parsed (asn/asnNil))))]
        (if (stringEmpty? key) (fail id ":ERR_INVALID_ROW" "row must have an id")
          (let [(path (memPath root rel)) (current (fileRows! root rel))]
            (mt current ((err e) (fail id ":ERR_MEM_READ" e)) ((ok p)
              (mt (v/vfsContext! root) ((err e) (fail id ":ERR_STAGE_FAILED" e)) ((ok vs)
                (let [(next (replaceRows (pairFirst p) (pairSecond p) key row))]
                  (mt (v/stage! vs path next) ((err e) (fail id ":ERR_STAGE_FAILED" e)) ((ok _) (memOk id (str " :file " (q rel) " :rowId " (q key) " :staged true")))))))))))))))

fn memStep! root: String id: Int64 kw: (Map String String) args: (List String) held: (List String) -> k/EditOutcome
  (let [(op (k/kwOr kw "op" (optionOr (listHead args) ""))) (memDir (memPath root ""))]
    (cond
      ((= op "list")
        (mt (listDirRel (k/kwOr kw "dir" ""))
          ((none) (fail id ":ERR_BOUNDARY_VIOLATION" "ledger directory must stay under .asl/mem"))
          ((some relDir)
            (if (and (safeMemRel? root relDir) (not (v/isLink? memDir)))
              (let [(dir (memPath root relDir))
                    (files (listFiles! dir relDir))]
                (mt files
                  ((err e) (fail id ":ERR_MEM_READ" e))
                  ((ok fs)
                    (mt (countFiles! root fs)
                      ((err e) (fail id ":ERR_MEM_READ" e))
                      ((ok entries)
                        (memOk id (str " :count " (stringFromInt64 (listLength fs)) " :ledgers [" (stringJoin entries " ") "]")))))))
              (fail id ":ERR_BOUNDARY_VIOLATION" "ledger directory must stay under .asl/mem")))))
      ((= op "get") (getOp id root kw))
      ((= op "query") (queryOp id root kw))
      ((= op "put") (putOp! id root kw))
      (else (fail id ":ERR_INVALID_OP" "mem op must be list, get, query, or put"))))
