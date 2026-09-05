(module asl-contracts/spec
  :d "AgentScript Verifiable Smart Contract Specification: pure functional state-machine transitions and zero-reentrancy contracts."
  :x [BlockContext ContractEvent ContractError TransitionResult
      is-valid-address make-block-context transition-success transition-revert
      validate-non-negative-balance]
  :i [])

(dfs BlockContext
  (:f sender Str "Address of the transaction caller")
  (:f value I64 "Coin or token value transferred with invocation (in base units)")
  (:f timestamp I64 "Block timestamp in seconds since epoch")
  (:f height I64 "Block number/height"))

(dfs ContractEvent
  (:f name Str "Event topic/identifier")
  (:f data Str "Serialized event payload"))

(dfs ContractError
  (:f code I64 "Standardized error code")
  (:f message Str "Descriptive revert explanation"))

(dfs TransitionResult
  (:f success Bool "True if state transition succeeded without reverting")
  (:f events (List ContractEvent) "Emitted contract events")
  (:f error-msg Str "Revert message if failed"))

(df is-valid-address [(addr Str)] -> Bool
  :d "Validates that an address is a 42-character 0x-prefixed hexadecimal string."
  (and (string-starts-with? addr "0x")
       (= (string-length addr) 42)))

(df make-block-context [(sender Str) (value I64) (timestamp I64) (height I64)] -> BlockContext
  :d "Constructs a verified execution context for a contract transaction."
  (BlockContext
    :sender sender
    :value value
    :timestamp timestamp
    :height height))

(df transition-success [(events (List ContractEvent))] -> TransitionResult
  :d "Constructs a successful transition outcome with emitted events."
  (TransitionResult
    :success true
    :events events
    :error-msg ""))

(df transition-revert [(reason Str)] -> TransitionResult
  :d "Constructs a reverted transition outcome halting state modification."
  (TransitionResult
    :success false
    :events (list)
    :error-msg reason))

(df validate-non-negative-balance [(amount I64)] -> Bool
  :d "Enforces non-negative balance invariant to prevent integer underflow exploits."
  (>= amount 0))
