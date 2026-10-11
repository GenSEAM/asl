(module wire/naming :x [Account Ledger describe])

(schema Account :jsonCase camel (:f holderName String "Name on the account") (:f openedAt Int64 "Creation time, epoch seconds") (:f nickname String "Display label" :default "unnamed"))

(schema Ledger :jsonCase snake (:f account Account "The account this ledger belongs to") (:f balance Int64 "Minor units" :json "balance_minor"))

fn describe l: Ledger -> String
  (str l.account.holderName ": " (stringFromInt64 l.balance))
