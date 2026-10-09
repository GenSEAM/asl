(module asl-transpile/asnCheck :x [AsnDiag asnCheck diagCodes] :i [(asn :a a)])

(schema AsnDiag (:f code String) (:f detail String))

fn diagCodes ds: (List AsnDiag) -> String
  (stringJoin (map (fn [(d AsnDiag)] -> String d.code) ds) "|")

fn asnCheck v: a/AsnValue -> (List AsnDiag)
  (listReverse (chk v (list) (list)))

(schema DupState (:f seen (List String)) (:f dup (Option String)))

fn dupStep st: DupState k: String -> DupState
  (if (listContains? st.seen k) (with st :dup (mt st.dup ((some d) (some d)) ((none) (some k)))) (with st :seen (cons k st.seen)))

fn dupOf keys: (List String) -> (Option String)
  (fold dupStep (DupState :seen (list) :dup (none)) keys).dup

fn dupDiag keys: (List String) code: String acc: (List AsnDiag) -> (List AsnDiag)
  (mt (dupOf keys) ((some k) (cons (AsnDiag :code code :detail k) acc)) ((none) acc))

fn note code: String detail: String acc: (List AsnDiag) -> (List AsnDiag)
  (cons (AsnDiag :code code :detail detail) acc)

fn fieldKeys fs: (List a/AsnField) -> (List String)
  (map (fn [(f a/AsnField)] -> String f.key) fs)

fn entryKeys es: (List a/AsnEntry) -> (List String)
  (map (fn [(e a/AsnEntry)] -> String (a/asnWrite e.key)) es)

fn fieldLookup fs: (List a/AsnField) key: String -> (Option a/AsnValue)
  (mt (listHead (filter (fn [(f a/AsnField)] -> Bool (= f.key key)) fs)) ((some f) (some f.val)) ((none) (none)))

fn poolLength pools: (List Int64) -> Int64
  (mt (listHead pools) ((some n) n) ((none) -1))

fn mergeable? v: a/AsnValue -> Bool
  (mt v ((a/asnRec _) true) ((a/asnCtor _ _) true) ((a/asnMap _) true) (_ false))

fn dataKindOk? v: a/AsnValue -> Bool
  (mt v ((a/asnVec _) true) ((a/asnRows _ _) true) ((a/asnTable _ _) true) (_ false))

fn isEnvelope? keys: (List String) -> Bool
  (and (listContains? keys ":data") (not (listEmpty? (filter (fn [(k String)] -> Bool (and (not (= k ":data")) (not (= k ":pool")))) keys))))

fn chk v: a/AsnValue pools: (List Int64) acc: (List AsnDiag) -> (List AsnDiag)
  (mt v ((a/asnVec items) (chkList items pools acc)) ((a/asnMap es) (chkMap es pools acc)) ((a/asnRec fs) (chkRec fs pools acc)) ((a/asnCtor _ fs) (chkFields fs pools (dupDiag (fieldKeys fs) "record-duplicate-key" acc))) ((a/asnRows _ rows) (chkList rows pools acc)) ((a/asnTable cs rs) (chkTable cs rs pools acc)) ((a/asnCase _ args) (chkList args pools acc)) ((a/asnPair k val) (chk val pools (chk k pools acc))) (_ acc))

fn chkList items: (List a/AsnValue) pools: (List Int64) acc: (List AsnDiag) -> (List AsnDiag)
  (fold (fn [(a (List AsnDiag)) (x a/AsnValue)] -> (List AsnDiag) (chk x pools a)) acc items)

fn chkFields fs: (List a/AsnField) pools: (List Int64) acc: (List AsnDiag) -> (List AsnDiag)
  (fold (fn [(a (List AsnDiag)) (f a/AsnField)] -> (List AsnDiag) (chk f.val pools a)) acc fs)

fn chkMap es: (List a/AsnEntry) pools: (List Int64) acc: (List AsnDiag) -> (List AsnDiag)
  (fold (fn [(a (List AsnDiag)) (e a/AsnEntry)] -> (List AsnDiag) (chk e.val pools (chk e.key pools a))) (dupDiag (entryKeys es) "map-duplicate-key" acc) es)

fn chkTable cs: (List a/AsnValue) rs: (List a/AsnValue) pools: (List Int64) acc: (List AsnDiag) -> (List AsnDiag)
  (let [(width (listLength cs)) (a1 (dupDiag (map (fn [(c a/AsnValue)] -> String (a/asnWrite c)) cs) "table-duplicate-column" acc)) (a2 (fold (fn [(a (List AsnDiag)) (r a/AsnValue)] -> (List AsnDiag) (if (= (listLength (a/vecItems r)) width) a (note "table-ragged" (str "row of " (stringFromInt64 (listLength (a/vecItems r))) " against " (stringFromInt64 width) " columns") a))) a1 rs))] (chkList rs pools a2))

fn chkRec fs: (List a/AsnField) pools: (List Int64) acc: (List AsnDiag) -> (List AsnDiag)
  (let [(keys (fieldKeys fs)) (a1 (dupDiag keys "record-duplicate-key" acc)) (a2 (chkPool fs a1)) (a3 (chkRef fs keys pools a2)) (a4 (chkEnvelope fs keys a3))] (chkFields fs (pushPool fs pools) a4))

fn chkPool fs: (List a/AsnField) acc: (List AsnDiag) -> (List AsnDiag)
  (mt (fieldLookup fs ":pool") ((some v) (if (a/isVec? v) acc (note "pool-kind" (a/asnWrite v) acc))) ((none) acc))

fn pushPool fs: (List a/AsnField) pools: (List Int64) -> (List Int64)
  (mt (fieldLookup fs ":pool") ((some v) (if (a/isVec? v) (cons (listLength (a/vecItems v)) pools) pools)) ((none) pools))

fn chkRef fs: (List a/AsnField) keys: (List String) pools: (List Int64) acc: (List AsnDiag) -> (List AsnDiag)
  (if (listContains? keys ":ref") (if (= (listLength fs) 1) (mt (fieldLookup fs ":ref") ((some v) (chkRefIndex v pools acc)) ((none) acc)) (note "ref-shape" (stringJoin keys " ") acc)) acc)

fn chkRefIndex v: a/AsnValue pools: (List Int64) acc: (List AsnDiag) -> (List AsnDiag)
  (mt (a/asnIntValue v) ((none) (note "ref-shape" (a/asnWrite v) acc)) ((some n) (let [(size (poolLength pools))] (cond ((= size -1) (note "ref-no-pool" (a/asnWrite v) acc)) ((or (< n 0) (>= n size)) (note "ref-dangling" (str (a/asnWrite v) " against a pool of " (stringFromInt64 size)) acc)) (else acc)))))

fn chkEnvelope fs: (List a/AsnField) keys: (List String) acc: (List AsnDiag) -> (List AsnDiag)
  (if (isEnvelope? keys) (mt (fieldLookup fs ":data") ((some d) (if (dataKindOk? d) (chkElements d acc) (note "envelope-data-kind" (a/asnWrite d) acc))) ((none) acc)) acc)

fn chkElements d: a/AsnValue acc: (List AsnDiag) -> (List AsnDiag)
  (mt d ((a/asnVec items) (fold (fn [(a (List AsnDiag)) (x a/AsnValue)] -> (List AsnDiag) (if (mergeable? x) a (note "envelope-scalar-element" (a/asnWrite x) a))) acc items)) (_ acc))
