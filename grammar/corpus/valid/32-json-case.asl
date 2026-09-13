"§4.1's wire-naming controls, which are pinned now even though Core ships no"
"serializer, so that adding one later cannot silently change the format. Both"
"grammars rejected `:json-case` until this fixture existed: the specification"
"defined a form no parser accepted, and nothing was looking."
(module wire/naming
  :doc "Records whose serialized field names differ from their source names."
  :export [Account Ledger describe])

(defschema Account
  :jsonCase camel
  (:field holderName String "Name on the account")
  (:field openedAt   Int64  "Creation time, epoch seconds")
  (:field nickname    String "Display label" :default "unnamed"))

(defschema Ledger
  :jsonCase snake
  (:field account Account "The account this ledger belongs to")
  (:field balance Int64   "Minor units" :json "balance_minor"))

(df describe [(l Ledger)] -> String
  :doc "One line naming the holder and the balance."
  (str (.-holderName (.-account l)) ": " (string-from-int64 (.-balance l))))
