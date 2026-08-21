; The Map section of the vocabulary, in use: a small feature-flag registry.

(module data/maps
  :doc "Read and update a keyed registry of feature flags."
  :export [enable disable known? enabled? count names values-of entries
           from-entries empty-registry])

(defun enable [(flags (Map String Bool)) (name String)] -> (Map String Bool)
  :doc "Turn a flag on, adding it when absent."
  (map-set flags name true))

(defun disable [(flags (Map String Bool)) (name String)] -> (Map String Bool)
  :doc "Remove a flag from the registry entirely."
  (map-remove flags name))

(defun known? [(flags (Map String Bool)) (name String)] -> Bool
  :doc "True when the registry mentions the flag at all."
  (map-has? flags name))

(defun enabled? [(flags (Map String Bool)) (name String)] -> Bool
  :doc "True only when the flag is present and on; an unknown flag is off."
  (option-or (map-get flags name) false))

(defun count [(flags (Map String Bool))] -> Int64
  :doc "Number of registered flags."
  (map-size flags))

(defun names [(flags (Map String Bool))] -> (List String)
  :doc "Registered flag names, sorted."
  (map-keys flags))

(defun values-of [(flags (Map String Bool))] -> (List Bool)
  :doc "Flag states, ordered by sorted name."
  (map-values flags))

(defun entries [(flags (Map String Bool))] -> (List (Pair String Bool))
  :doc "Name and state together, ordered by sorted name."
  (map-pairs flags))

(defun from-entries [(es (List (Pair String Bool)))] -> (Map String Bool)
  :doc "Build a registry from pairs; a later entry wins."
  (map-from-pairs es))

(defun empty-registry [] -> (Map String Bool)
  :doc "A registry with no flags."
  (map-empty))
