(module hashSemantics
  :x [main]
  :i [(prelude/tests/hashMapTest :a semantics)])

; (:m :ref INTHASHMAP :do "the prelude HashMap semantics suite (aliases, collisions, growth, backward-shift removal, model replays) run as a native program, so the untraced build checks the native bodies with the same assertions")
fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str (semantics/runTests)))
      (ok 0))
