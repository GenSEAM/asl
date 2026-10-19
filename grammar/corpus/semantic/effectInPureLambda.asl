fn ! readEach paths: (List String) -> (List (Result String String))
  (map (fn [p] (fileReadString p)) paths)
