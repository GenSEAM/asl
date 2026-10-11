(module ioDemo :x [main])

fn ! describe path: String -> String
  (match (fileRead path) ((ok text) text) ((err e) (if (= e (notFound)) "missing" "unreadable")))

fn ! copyAll paths: (List String) -> (List String)
  (map (fn [p] (describe p)) paths)

fn ! main args: (List String) -> (Result Unit IoError)
  (match (listHead args) ((some src) (ok (println (stringJoin (copyAll args) "\n")))) ((none) (ok (println "usage: io-demo SRC..."))))
