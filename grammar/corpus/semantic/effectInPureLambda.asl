fn ! readEach paths: (List String) -> (List (Result String IoError))
  (map (fn [p] (fileRead p)) paths)
