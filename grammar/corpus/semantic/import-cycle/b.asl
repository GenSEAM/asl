"expect: rule-11"
"The other half; see a.agentscript."
(module b
  :doc "Imports a, which imports b."
  :export [fromB]
  :import [(a :as a)])

(df fromB [] -> Int64
  :doc "Exists so the module has a surface."
  2)
