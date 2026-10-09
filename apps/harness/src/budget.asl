(module aslHarness/budget :x [BudgetLimits BudgetTracker makeBudget recordTurn isBudgetExceeded?] :i [])

(schema BudgetLimits (:f maxTokens I64) (:f maxTurns I64) (:f maxMs I64))

(schema BudgetTracker (:f usedTokens I64) (:f usedTurns I64) (:f elapsedMs I64) (:f limits BudgetLimits))

fn makeBudget tokens: I64 turns: I64 ms: I64 -> BudgetTracker
  (BudgetTracker :usedTokens 0 :usedTurns 0 :elapsedMs 0 :limits (BudgetLimits :maxTokens tokens :maxTurns turns :maxMs ms))

fn recordTurn bt: BudgetTracker tokens: I64 duration: I64 -> BudgetTracker
  (with bt :usedTokens (+ bt.usedTokens tokens) :usedTurns (+ bt.usedTurns 1) :elapsedMs (+ bt.elapsedMs duration))

fn isBudgetExceeded? bt: BudgetTracker -> Bool
  (let [(lim bt.limits)] (or (> bt.usedTokens lim.maxTokens) (or (> bt.usedTurns lim.maxTurns) (> bt.elapsedMs lim.maxMs))))
