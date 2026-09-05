(module asl-contracts/tests/spec-test
  :d "Unit tests for pure functional smart contract specification, address checks, and transition invariants."
  :x [test-address-validation test-block-context test-transition-result test-balance-invariant run-tests]
  :i [(spec :a s)])

(df test-address-validation [] -> Bool
  :d "Verifies 0x-prefixed 42-character address validator."
  (let [(valid "0x1234567890123456789012345678901234567890")
        (invalid-prefix "123456789012345678901234567890123456789012")
        (invalid-len "0x1234")]
    (and (s/is-valid-address valid)
         (and (not (s/is-valid-address invalid-prefix))
              (not (s/is-valid-address invalid-len))))))

(df test-block-context [] -> Bool
  :d "Verifies execution block context construction."
  (let [(sender "0x0000000000000000000000000000000000000001")
        (ctx (s/make-block-context sender 1000000 1725573000 12500000))]
    (and (= (.-sender ctx) sender)
         (and (= (.-value ctx) 1000000)
              (and (= (.-timestamp ctx) 1725573000)
                   (= (.-height ctx) 12500000))))))

(df test-transition-result [] -> Bool
  :d "Verifies success and revert outcomes in contract transitions."
  (let [(event (s/ContractEvent :name "Transfer" :data "from=0x1,to=0x2,amount=50"))
        (succ (s/transition-success (list event)))
        (rev (s/transition-revert "Insufficient funds"))]
    (and (.-success succ)
         (and (= (list-length (.-events succ)) 1)
              (and (not (.-success rev))
                   (= (.-error-msg rev) "Insufficient funds"))))))

(df test-balance-invariant [] -> Bool
  :d "Verifies non-negative balance guard prevents underflow."
  (and (s/validate-non-negative-balance 0)
       (and (s/validate-non-negative-balance 500)
            (not (s/validate-non-negative-balance -1)))))

(df run-tests [] -> Bool
  :d "Executes full contract specification test suite."
  (and (test-address-validation)
       (and (test-block-context)
            (and (test-transition-result)
                 (test-balance-invariant)))))
