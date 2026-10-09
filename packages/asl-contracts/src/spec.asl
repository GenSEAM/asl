(module aslContracts/spec :x [BlockContext ContractEvent TransitionResult isValidAddress makeBlockContext transitionSuccess transitionRevert validateNonNegativeBalance] :i [])

(schema BlockContext (:f sender Str) (:f value I64) (:f timestamp I64) (:f height I64))

(schema ContractEvent (:f name Str) (:f data Str))

(schema TransitionResult (:f success Bool) (:f events (List ContractEvent)) (:f errorMsg Str))

fn isHexChar c: Str -> Bool
  (let [(l (stringLower c))] (or (= l "0") (or (= l "1") (or (= l "2") (or (= l "3") (or (= l "4") (or (= l "5") (or (= l "6") (or (= l "7") (or (= l "8") (or (= l "9") (or (= l "a") (or (= l "b") (or (= l "c") (or (= l "d") (or (= l "e") (= l "f")))))))))))))))))

fn isValidAddress addr: Str -> Bool
  (and (stringStartsWith? addr "0x") (and (= (stringLength addr) 42) (let [(body (optionOr (stringSlice addr 2 42) "")) (chars (stringChars body))] (fold (fn [(acc Bool) (c Str)] -> Bool (and acc (isHexChar c))) true chars))))

fn makeBlockContext sender: Str value: I64 timestamp: I64 height: I64 -> BlockContext
  (do (assert (isValidAddress sender) "Invalid sender address") (assert (>= value 0) "Value cannot be negative") (assert (>= timestamp 0) "Timestamp cannot be negative") (assert (>= height 0) "Block height cannot be negative") (BlockContext :sender sender :value value :timestamp timestamp :height height))

fn transitionSuccess events: (List ContractEvent) -> TransitionResult
  (TransitionResult :success true :events events :errorMsg "")

fn transitionRevert reason: Str -> TransitionResult
  (TransitionResult :success false :events (list) :errorMsg reason)

fn validateNonNegativeBalance amount: I64 -> Bool
  (>= amount 0)
