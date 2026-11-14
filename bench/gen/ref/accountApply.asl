schema Account { balance: Int64 frozen: Bool }

enum Op (deposit amount: Int64) (withdraw amount: Int64) (freeze) (unfreeze)

fn accountApply acct: Account op: Op -> (Result Account String)
  (match op
    ((freeze) (ok (with acct :frozen true)))
    ((unfreeze) (ok (with acct :frozen false)))
    ((deposit amount)
      (if acct.frozen
        (err "account is frozen")
        (ok (with acct :balance (+ acct.balance amount)))))
    ((withdraw amount)
      (cond
        (acct.frozen (err "account is frozen"))
        ((> amount acct.balance) (err "insufficient funds"))
        (else (ok (with acct :balance (- acct.balance amount)))))))
