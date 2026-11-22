(module asl-vault/unit
  :x [Passage ProvUnit hexHash? emitUnit parseUnit validateUnit bodyHash sealUnit splitPassages sha256Hex]
  :i [(asl-store/wire :a w) (asl-vault/codec :a cd)])

(schema Passage (:f id String) (:f text String))

; (:m :ref VS-VAULT :do "the provenance of one body of text: where it came from, when it was observed and fetched, its licence, when it must be reviewed, how sure the source is in basis points, which unit it replaces, the sha256 that seals it, and an ext list a product extends without a schema change; times are epoch milliseconds")
(schema ProvUnit
  (:f kind String)
  (:f source String)
  (:f title String)
  (:f observedAt Int64)
  (:f retrievedAt Int64)
  (:f licence String)
  (:f reviewBy Int64)
  (:f confidenceBp Int64)
  (:f replaces String)
  (:f contentHash String)
  (:f ext (List (Pair String String)))
  (:f passages (List Passage)))

fn hexChar? c: String -> Bool
  (or (and (>= (charCode c) 48) (<= (charCode c) 57)) (and (>= (charCode c) 97) (<= (charCode c) 102)))

fn hexHash? h: String -> Bool
  (and (= (stringLength h) 64) (listAll? hexChar? (stringChars h)))

fn sha256Hex s: String -> String
  (bytesSha256 (stringToBytes s))

fn passageSx p: Passage -> w/Sx
  (w/sxList (list (cd/atomSx ":passage") (cd/atomSx ":id") (cd/strSx p.id) (cd/atomSx ":text") (cd/strSx p.text)))

; (:m :ref VS-VAULT :do "one canonical single-line form per unit; equal units have equal bytes")
fn emitUnit u: ProvUnit -> String
  (w/sxShow (w/sxList (list (cd/atomSx ":unit") (cd/atomSx ":v") (cd/intSx 1)
    (cd/atomSx ":kind") (cd/strSx u.kind) (cd/atomSx ":source") (cd/strSx u.source) (cd/atomSx ":title") (cd/strSx u.title)
    (cd/atomSx ":observedAt") (cd/intSx u.observedAt) (cd/atomSx ":retrievedAt") (cd/intSx u.retrievedAt)
    (cd/atomSx ":licence") (cd/strSx u.licence) (cd/atomSx ":reviewBy") (cd/intSx u.reviewBy)
    (cd/atomSx ":confidenceBp") (cd/intSx u.confidenceBp) (cd/atomSx ":replaces") (cd/strSx u.replaces)
    (cd/atomSx ":contentHash") (cd/strSx u.contentHash) (cd/atomSx ":ext") (cd/pairList u.ext)
    (cd/atomSx ":passages") (w/sxList (map passageSx u.passages)))))

; (:m :ref VS-VAULT :do "the hash covers the canonical text with contentHash blanked, so a unit's name, its field and its bytes bind each other")
fn bodyHash u: ProvUnit -> String
  (sha256Hex (emitUnit (with u :contentHash "")))

fn sealUnit u: ProvUnit -> ProvUnit
  (with u :contentHash (bodyHash u))

fn passageOf x: w/Sx -> (Result Passage String)
  (cd/andThen (cd/formItems ":passage" x) (fn [(items (List w/Sx))] -> (Result Passage String)
    (let [(m (cd/fieldMap items))]
      (cd/andThen (cd/checkShape m (list (pair ":id" "s") (pair ":text" "s")))
        (fn [(_ Bool)] -> (Result Passage String) (ok (Passage :id (cd/fs m ":id") :text (cd/fs m ":text"))))))))

fn unitShape -> (List (Pair String String))
  (list (pair ":v" "i") (pair ":kind" "s") (pair ":source" "s") (pair ":title" "s") (pair ":observedAt" "i") (pair ":retrievedAt" "i")
        (pair ":licence" "s") (pair ":reviewBy" "i") (pair ":confidenceBp" "i") (pair ":replaces" "s") (pair ":contentHash" "s")
        (pair ":ext" "l") (pair ":passages" "l"))

fn unitOfMap m: (Map String w/Sx) -> (Result ProvUnit String)
  (cd/andThen (cd/mapResult passageOf (cd/fl m ":passages"))
    (fn [(ps (List Passage))] -> (Result ProvUnit String)
      (ok (ProvUnit :kind (cd/fs m ":kind") :source (cd/fs m ":source") :title (cd/fs m ":title")
                    :observedAt (cd/fi m ":observedAt") :retrievedAt (cd/fi m ":retrievedAt") :licence (cd/fs m ":licence")
                    :reviewBy (cd/fi m ":reviewBy") :confidenceBp (cd/fi m ":confidenceBp") :replaces (cd/fs m ":replaces")
                    :contentHash (cd/fs m ":contentHash") :ext (cd/fpairs m ":ext") :passages ps))))

fn unitOfItems items: (List w/Sx) -> (Result ProvUnit String)
  (let [(m (cd/fieldMap items))]
    (cd/andThen (cd/checkShape m (unitShape))
      (fn [(_ Bool)] -> (Result ProvUnit String)
        (if (= (cd/fi m ":v") 1) (unitOfMap m) (err "unsupported unit version")))))

; (:m :ref VS-VAULT :do "the inverse of emitUnit; trailing forms, a missing field or a wrong version is an error, never a default")
fn parseUnit text: String -> (Result ProvUnit String)
  (cd/andThen (w/sxRead text) (fn [(forms (List w/Sx))] -> (Result ProvUnit String)
    (if (!= (listLength forms) 1)
      (err "a unit row is exactly one form")
      (cd/andThen (cd/formItems ":unit" (w/headOr forms)) unitOfItems))))

; (:m :ref VS-VAULT :do "a unit is valid when its fields are well formed and ordered: observed before retrieved, review after retrieved, confidence in 0..10000, hashes sha256 hex or empty, ext keys and passage ids unique and non-empty, at least one passage")
fn validateUnit u: ProvUnit -> (Result ProvUnit String)
  (match (cd/firstFailure
    (list (cd/check (cd/validId? u.kind) "kind must be 1 to 120 of letters, digits, - and _")
          (cd/check (not (stringEmpty? (stringTrim u.source))) "source must not be empty")
          (cd/check (not (stringEmpty? (stringTrim u.title))) "title must not be empty")
          (cd/check (> u.observedAt 0) "observedAt must be positive epoch ms")
          (cd/check (> u.retrievedAt 0) "retrievedAt must be positive epoch ms")
          (cd/check (<= u.observedAt u.retrievedAt) "observedAt must not be after retrievedAt")
          (cd/check (> u.reviewBy u.retrievedAt) "reviewBy must be after retrievedAt")
          (cd/check (not (stringEmpty? (stringTrim u.licence))) "licence must not be empty")
          (cd/check (and (>= u.confidenceBp 0) (<= u.confidenceBp 10000)) "confidenceBp must lie in 0..10000")
          (cd/check (or (stringEmpty? u.replaces) (hexHash? u.replaces)) "replaces must be empty or a sha256 hex")
          (cd/check (or (stringEmpty? u.contentHash) (hexHash? u.contentHash)) "contentHash must be empty or a sha256 hex")
          (cd/check (listAll? (fn [(e (Pair String String))] -> Bool (not (stringEmpty? (pairFirst e)))) u.ext) "ext keys must not be empty")
          (cd/check (cd/uniqueStrings? (map (fn [(e (Pair String String))] -> String (pairFirst e)) u.ext)) "ext keys must be unique")
          (cd/check (not (listEmpty? u.passages)) "a unit needs at least one passage")
          (cd/check (listAll? (fn [(p Passage)] -> Bool (and (not (stringEmpty? p.id)) (not (stringEmpty? p.text)))) u.passages) "passage id and text must not be empty")
          (cd/check (cd/uniqueStrings? (map (fn [(p Passage)] -> String p.id) u.passages)) "passage ids must be unique")))
    ((some why) (err (str "ERR_VAULT_UNIT: " why)))
    ((none) (ok u)))

fn splitChunkChars chars: (List String) maxLen: Int64 acc: (List String) -> (List String)
  (if (listEmpty? chars)
    (listReverse acc)
    (splitChunkChars (listDrop chars maxLen) maxLen (cons (stringTrim (stringJoin (listTake chars maxLen) "")) acc)))

fn joinCur cur: (List String) acc: (List String) -> (List String)
  (if (listEmpty? cur) acc (cons (stringJoin (listReverse cur) "\n") acc))

fn normalizeBlocks lines: (List String) cur: (List String) acc: (List String) -> (List String)
  (match (listHead lines)
    ((none) (listReverse (joinCur cur acc)))
    ((some line)
      (let [(rest (optionOr (listTail lines) (list))) (trimmed (stringTrim line))]
        (cond
          ((stringEmpty? trimmed) (normalizeBlocks rest (list) (joinCur cur acc)))
          ((stringStartsWith? trimmed "#") (normalizeBlocks rest (list trimmed) (joinCur cur acc)))
          (else (normalizeBlocks rest (cons trimmed cur) acc))))))

fn explodeLong blocks: (List String) maxLen: Int64 -> (List String)
  (listFlatMap (fn [(b String)] -> (List String)
    (let [(t (stringTrim b))]
      (cond
        ((stringEmpty? t) (list))
        ((<= (stringLength t) maxLen) (list t))
        (else (filter (fn [(c String)] -> Bool (not (stringEmpty? c))) (splitChunkChars (stringChars t) maxLen (list)))))))
    blocks)

fn buildPassages texts: (List String) idx: Int64 acc: (List Passage) -> (List Passage)
  (match (listHead texts)
    ((none) (listReverse acc))
    ((some t) (buildPassages (optionOr (listTail texts) (list)) (+ idx 1) (cons (Passage :id (str "p" (stringFromInt64 idx)) :text t) acc))))

; (:m :ref VS-VAULT :do "a body splits at blank lines and # headings into passages p1, p2, ...; a block longer than 1200 characters is cut into chunks of 1200")
fn splitPassages text: String -> (List Passage)
  (buildPassages (explodeLong (normalizeBlocks (stringSplit (stringReplace text "\r\n" "\n") "\n") (list) (list)) 1200) 1 (list))
