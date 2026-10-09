"A Nano alias is significant only in the position the projection names. `:x` is"

"`:export` in a module header and nothing at all in a constructor argument, so a"

"record whose field names are exactly the six option letters is an ordinary"

"record. This fixture is the pin: a transcoder, formatter or grammar that"

"rewrites `:x` by pattern-matching on the text rather than on the position turns"

"`(P :x 1)` into `(P :export 1)` and every field below stops resolving."

(module t/aliasKeys :x [P readBack probe])

(schema P (:f x Int "A field named for the :export alias.") (:f d Int "A field named for the :doc alias.") (:f a Int "A field named for the :as alias.") (:f i Int "A field named for the :import alias.") (:f f Int "A field named for the :field alias.") (:f c Int "A field named for the :case alias."))

fn readBack p: P -> Str
  (stringJoin (list (stringFromInt64 p.x) (stringFromInt64 p.d) (stringFromInt64 p.a) (stringFromInt64 p.i) (stringFromInt64 p.f) (stringFromInt64 p.c)) "|")

fn probe -> Str
  (readBack (P :x 1 :d 2 :a 3 :i 4 :f 5 :c 6))
