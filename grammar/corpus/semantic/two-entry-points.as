; §9 rule 15: at most one defentry per program. Two parse perfectly well —
; "how many of this declaration exist" is a count, and no grammar counts.

(module bad/two-entries
  :doc "Two entry points, so which one starts the program is undefined."
  :export [])

(defentry [(argv (List String))] -> (Result Unit String)
  :doc "One entry point."
  :effects [console]
  (println "first"))

(defentry [(argv (List String))] -> (Result Unit String)
  :doc "A second entry point in the same program."
  :effects [console]
  (println "second"))
