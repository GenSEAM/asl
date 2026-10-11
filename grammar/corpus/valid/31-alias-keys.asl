(module t/aliasKeys :x [P readBack probe])

(schema P (:f x Int "A field named for the :export alias.") (:f d Int "A field named for the :doc alias.") (:f a Int "A field named for the :as alias.") (:f i Int "A field named for the :import alias.") (:f f Int "A field named for the :field alias.") (:f c Int "A field named for the :case alias."))

fn readBack p: P -> Str
  (stringJoin (list (stringFromInt64 p.x) (stringFromInt64 p.d) (stringFromInt64 p.a) (stringFromInt64 p.i) (stringFromInt64 p.f) (stringFromInt64 p.c)) "|")

fn probe -> Str
  (readBack (P :x 1 :d 2 :a 3 :i 4 :f 5 :c 6))
