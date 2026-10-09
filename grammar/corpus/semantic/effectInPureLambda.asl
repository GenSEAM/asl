"expect: rule-12"

"The enclosing fn is marked, but the lambda is not, and the lambda is where"

"the effect happens. A marker on the outside does not cover the inside."

fn ! readEach paths: (List String) -> (List (Result String IoError))
  (map (fn [p] (fileRead p)) paths)
