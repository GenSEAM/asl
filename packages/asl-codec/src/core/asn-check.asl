(module asl-codec/asnCheck
  :d "The schema-free half of ASN conformance. Normative source: docs/ASN_SPEC.md sections 11 and 14.

  Only the rules a decoder can decide from the text alone live here. Whether a
  record inside a row is a sparse override or an ordinary positional value is a
  question the field count answers, so every row-* rule, nil-at-required-field,
  unknown-schema and table-missing-column belong to schema-directed
  materialisation and are deliberately absent rather than guessed at."
  :x [AsnDiag asnCheck diagCodes]
  :i [(asn :a a)])

(dfs AsnDiag
  (:f code String "The rule code, one of the set docs/ASN_SPEC.md §11 names")
  (:f detail String "The offending text, so a report names what it found"))

(df diagCodes [(ds (List AsnDiag))] -> String
  :d "The codes of a diagnostic list, in report order, joined by `|`."
  (string-join (map (fn [(d AsnDiag)] -> String (.-code d)) ds) "|"))

(df asnCheck [(v a/AsnValue)] -> (List AsnDiag)
  :d "Every schema-free conformance failure in a document, in the order a reader
      would meet them: a form's own rules before the values it contains."
  (list-reverse (chk v (list) (list))))

(dfs DupState
  (:f seen (List String) "Keys already met")
  (:f dup (Option String) "The first repeated key"))

(df dupStep [(st DupState) (k String)] -> DupState
  :d "One fold step: remember a key, or record it as the first repeat."
  (if (list-contains? (.-seen st) k)
    (DupState :seen (.-seen st)
              :dup (mt (.-dup st) ((some d) (some d)) ((none) (some k))))
    (DupState :seen (list-cons k (.-seen st)) :dup (.-dup st))))

(df dupOf [(keys (List String))] -> (Option String)
  :d "The first key that appears twice, or none."
  (.-dup (fold dupStep (DupState :seen (list) :dup (none)) keys)))

(df dupDiag [(keys (List String)) (code String) (acc (List AsnDiag))] -> (List AsnDiag)
  :d "Report a repeated key under the given code."
  (mt (dupOf keys)
    ((some k) (list-cons (AsnDiag :code code :detail k) acc))
    ((none)   acc)))

(df note [(code String) (detail String) (acc (List AsnDiag))] -> (List AsnDiag)
  :d "Add one diagnostic."
  (list-cons (AsnDiag :code code :detail detail) acc))

(df fieldKeys [(fs (List a/AsnField))] -> (List String)
  :d "Every field key, in source order."
  (map (fn [(f a/AsnField)] -> String (.-key f)) fs))

(df entryKeys [(es (List a/AsnEntry))] -> (List String)
  :d "Every map key rendered to text, so keys of different kinds compare."
  (map (fn [(e a/AsnEntry)] -> String (a/asnWrite (.-key e))) es))

(df fieldLookup [(fs (List a/AsnField)) (key String)] -> (Option a/AsnValue)
  :d "The value of the named field, or none."
  (mt (list-head (filter (fn [(f a/AsnField)] -> Bool (= (.-key f) key)) fs))
    ((some f) (some (.-val f)))
    ((none)   (none))))

(df poolLength [(pools (List Int64))] -> Int64
  :d "The size of the innermost pool in scope, or -1 when there is none."
  (mt (list-head pools) ((some n) n) ((none) -1)))

(df mergeable? [(v a/AsnValue)] -> Bool
  :d "True for a value an envelope's shared field has somewhere to go."
  (mt v
    ((a/asnRec _)    true)
    ((a/asnCtor _ _) true)
    ((a/asnMap _)    true)
    (_                false)))

(df dataKindOk? [(v a/AsnValue)] -> Bool
  :d "True for the three shapes an envelope's `:data` may take."
  (mt v
    ((a/asnVec _)     true)
    ((a/asnRows _ _)  true)
    ((a/asnTable _ _) true)
    (_                 false)))

(df isEnvelope? [(keys (List String))] -> Bool
  :d "A record is an envelope when it carries `:data` beside a key that is not
      the pool. `:data` alone is an ordinary field called `data`."
  (and (list-contains? keys ":data")
       (not (list-empty?
              (filter (fn [(k String)] -> Bool
                        (and (not (= k ":data")) (not (= k ":pool"))))
                      keys)))))

(df chk [(v a/AsnValue) (pools (List Int64)) (acc (List AsnDiag))] -> (List AsnDiag)
  :d "Every failure in one value and everything below it."
  (mt v
    ((a/asnVec items)   (chkList items pools acc))
    ((a/asnMap es)      (chkMap es pools acc))
    ((a/asnRec fs)      (chkRec fs pools acc))
    ((a/asnCtor _ fs)   (chkFields fs pools
                                     (dupDiag (fieldKeys fs) "record-duplicate-key" acc)))
    ((a/asnRows _ rows) (chkList rows pools acc))
    ((a/asnTable cs rs) (chkTable cs rs pools acc))
    ((a/asnCase _ args) (chkList args pools acc))
    ((a/asnPair k val)  (chk val pools (chk k pools acc)))
    (_                   acc)))

(df chkList [(items (List a/AsnValue)) (pools (List Int64)) (acc (List AsnDiag))]
    -> (List AsnDiag)
  :d "Every failure in a list of values, left to right."
  (fold (fn [(a (List AsnDiag)) (x a/AsnValue)] -> (List AsnDiag) (chk x pools a))
        acc items))

(df chkFields [(fs (List a/AsnField)) (pools (List Int64)) (acc (List AsnDiag))]
    -> (List AsnDiag)
  :d "Every failure in a field list's values."
  (fold (fn [(a (List AsnDiag)) (f a/AsnField)] -> (List AsnDiag) (chk (.-val f) pools a))
        acc fs))

(df chkMap [(es (List a/AsnEntry)) (pools (List Int64)) (acc (List AsnDiag))]
    -> (List AsnDiag)
  :d "A map's duplicate keys, then every failure in its keys and values."
  (fold (fn [(a (List AsnDiag)) (e a/AsnEntry)] -> (List AsnDiag)
          (chk (.-val e) pools (chk (.-key e) pools a)))
        (dupDiag (entryKeys es) "map-duplicate-key" acc)
        es))

(df chkTable [(cs (List a/AsnValue)) (rs (List a/AsnValue)) (pools (List Int64))
                  (acc (List AsnDiag))] -> (List AsnDiag)
  :d "A table's header and shape, then every failure inside its cells."
  (let [(width (list-length cs))
        (a1 (dupDiag (map (fn [(c a/AsnValue)] -> String (a/asnWrite c)) cs)
                      "table-duplicate-column" acc))
        (a2 (fold (fn [(a (List AsnDiag)) (r a/AsnValue)] -> (List AsnDiag)
                    (if (= (list-length (a/vecItems r)) width)
                      a
                      (note "table-ragged"
                            (str "row of " (string-from-int64 (list-length (a/vecItems r)))
                                 " against " (string-from-int64 width) " columns")
                            a)))
                  a1 rs))]
    (chkList rs pools a2)))

(df chkRec [(fs (List a/AsnField)) (pools (List Int64)) (acc (List AsnDiag))]
    -> (List AsnDiag)
  :d "A record's own rules — duplicate keys, the pool it declares, the reference
      it may be, the envelope it may be — then its values under the pool it
      brings into scope. The pool is pushed BEFORE descending so that it governs
      its own elements, which is what lets pool entry 0 name pool entry 1."
  (let [(keys (fieldKeys fs))
        (a1 (dupDiag keys "record-duplicate-key" acc))
        (a2 (chkPool fs a1))
        (a3 (chkRef fs keys pools a2))
        (a4 (chkEnvelope fs keys a3))]
    (chkFields fs (pushPool fs pools) a4)))

(df chkPool [(fs (List a/AsnField)) (acc (List AsnDiag))] -> (List AsnDiag)
  :d "A declared pool must be a vector: it is indexed by integer, and a map has
      no index 0 for a reference to resolve against."
  (mt (fieldLookup fs ":pool")
    ((some v) (if (a/isVec? v) acc (note "pool-kind" (a/asnWrite v) acc)))
    ((none)   acc)))

(df pushPool [(fs (List a/AsnField)) (pools (List Int64))] -> (List Int64)
  :d "The pool stack a record's values are checked under. A nested pool shadows
      an outer one; a malformed pool brings nothing into scope."
  (mt (fieldLookup fs ":pool")
    ((some v) (if (a/isVec? v)
                (list-cons (list-length (a/vecItems v)) pools)
                pools))
    ((none) pools)))

(df chkRef [(fs (List a/AsnField)) (keys (List String)) (pools (List Int64))
                (acc (List AsnDiag))] -> (List AsnDiag)
  :d "`(:ref N)` is a single-key record over a non-negative integer that lands
      inside the innermost pool in scope. A miss is an error and never nil:
      substituting nil turns a transport fault into a data fault, somewhere it
      can no longer be traced back to the payload."
  (if (list-contains? keys ":ref")
    (if (= (list-length fs) 1)
      (mt (fieldLookup fs ":ref")
        ((some v) (chkRefIndex v pools acc))
        ((none)   acc))
      (note "ref-shape" (string-join keys " ") acc))
    acc))

(df chkRefIndex [(v a/AsnValue) (pools (List Int64)) (acc (List AsnDiag))]
    -> (List AsnDiag)
  :d "Resolve one reference index against the pool in scope."
  (mt (a/asnIntValue v)
    ((none) (note "ref-shape" (a/asnWrite v) acc))
    ((some n)
     (let [(size (poolLength pools))]
       (cond
         ((= size -1) (note "ref-no-pool" (a/asnWrite v) acc))
         ((or (< n 0) (>= n size))
          (note "ref-dangling"
                (str (a/asnWrite v) " against a pool of " (string-from-int64 size))
                acc))
         (:else acc))))))

(df chkEnvelope [(fs (List a/AsnField)) (keys (List String)) (acc (List AsnDiag))]
    -> (List AsnDiag)
  :d "An envelope merges its shared fields into the ELEMENTS of `:data`, so
      `:data` must have elements, and a vector's elements must have fields."
  (if (isEnvelope? keys)
    (mt (fieldLookup fs ":data")
      ((some d)
       (if (dataKindOk? d)
         (chkElements d acc)
         (note "envelope-data-kind" (a/asnWrite d) acc)))
      ((none) acc))
    acc))

(df chkElements [(d a/AsnValue) (acc (List AsnDiag))] -> (List AsnDiag)
  :d "Every element of an envelope's `:data` vector must be able to take the
      shared fields. Row groups and tables are bound by a schema, so their rows
      are left to schema-directed materialisation."
  (mt d
    ((a/asnVec items)
     (fold (fn [(a (List AsnDiag)) (x a/AsnValue)] -> (List AsnDiag)
             (if (mergeable? x) a (note "envelope-scalar-element" (a/asnWrite x) a)))
           acc items))
    (_ acc)))
