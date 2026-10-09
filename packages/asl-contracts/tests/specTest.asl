(module aslContracts/tests/specTest :x [testAddressValidation testBlockContext testTransitionResult testBalanceInvariant runTests] :i [(spec :a s)])

fn testAddressValidation -> Bool
  (let [(valid "0x1234567890123456789012345678901234567890") (invalidPrefix "123456789012345678901234567890123456789012") (invalidLen "0x1234")] (assert (s/isValidAddress valid) "Valid 42-char address must pass") (assert (not (s/isValidAddress invalidPrefix)) "Address without 0x prefix must fail") (assert (not (s/isValidAddress invalidLen)) "Address with wrong length must fail") true)

fn testBlockContext -> Bool
  (let [(sender "0x0000000000000000000000000000000000000001") (ctx (s/makeBlockContext sender 1000000 1725573000 12500000))] (assert (= ctx.sender sender) "Sender must match") (assert (= ctx.value 1000000) "Value must match 1000000") (assert (= ctx.timestamp 1725573000) "Timestamp must match 1725573000") (assert (= ctx.height 12500000) "Block height must match 12500000") true)

fn testTransitionResult -> Bool
  (let [(event (s/ContractEvent :name "Transfer" :data "from=0x1,to=0x2,amount=50")) (succ (s/transitionSuccess (list event))) (rev (s/transitionRevert "Insufficient funds"))] (assert succ.success "Transition success must have success true") (assert (= (listLength succ.events) 1) "Transition success must have 1 event") (assert (not rev.success) "Transition revert must have success false") (assert (= rev.errorMsg "Insufficient funds") "Transition revert error must match") true)

fn testBalanceInvariant -> Bool
  (do (assert (s/validateNonNegativeBalance 0) "Zero balance must be valid") (assert (s/validateNonNegativeBalance 500) "Positive balance must be valid") (assert (not (s/validateNonNegativeBalance -1)) "Negative balance must be invalid") true)

fn runTests -> Bool
  (let [(t1 (testAddressValidation)) (t2 (testBlockContext)) (t3 (testTransitionResult)) (t4 (testBalanceInvariant))] (and t1 (and t2 (and t3 t4))))
