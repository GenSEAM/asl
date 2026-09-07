"A Nano alias is significant only in the position the projection names. `:x` is"
"`:export` in a module header and nothing at all in a constructor argument, so a"
"record whose field names are exactly the six option letters is an ordinary"
"record. This fixture is the pin: a transcoder, formatter or grammar that"
"rewrites `:x` by pattern-matching on the text rather than on the position turns"
"`(P :x 1)` into `(P :export 1)` and every field below stops resolving."

(module t/alias-keys
  :d "A record keyed by the six Nano option letters."
  :x [P read-back probe])

(dfs P
  (:f x Int "A field named for the :export alias.")
  (:f d Int "A field named for the :doc alias.")
  (:f a Int "A field named for the :as alias.")
  (:f i Int "A field named for the :import alias.")
  (:f f Int "A field named for the :field alias.")
  (:f c Int "A field named for the :case alias."))

(df read-back [(p P)] -> Str
  :d "Read every field back, in declaration order, so a key that resolved to the
      wrong field shows up as a transposition rather than as a type error."
  (string-join (list (string-from-int64 (.-x p))
                     (string-from-int64 (.-d p))
                     (string-from-int64 (.-a p))
                     (string-from-int64 (.-i p))
                     (string-from-int64 (.-f p))
                     (string-from-int64 (.-c p)))
               "|"))

(df probe [] -> Str
  :d "Construct the record with the six keyword arguments and read it back."
  (read-back (P :x 1 :d 2 :a 3 :i 4 :f 5 :c 6)))
