"I/O and the effect marker. `!` on a declaration says it touches the world; it"

"is inferred inside a body but written on the signature, because a caller reads"

"the signature and not the body. The host has no fileWrite, so the copy this"

"fixture once made is gone and it only echoes."

(module ioDemo :x [main])

fn ! describe path: String -> String
  (match (fileRead path) ((ok text) text) ((err e) (if (= e (notFound)) "missing" "unreadable")))

fn ! copyAll paths: (List String) -> (List String)
  (map (fn [p] (describe p)) paths)

fn ! main args: (List String) -> (Result Unit IoError)
  (match (listHead args) ((some src) (ok (println (stringJoin (copyAll args) "\n")))) ((none) (ok (println "usage: io-demo SRC..."))))
