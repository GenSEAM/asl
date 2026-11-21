(module aslAgent/gateLimit
  :x [gateLimitSec gateMarginSec innerBudgetSec]
  :i [])

; (:m :ref WALL-SLOW-GATES :do "the one place the Leon gate step limit lives; a gate that runs its own bounded work (docRowsGate) derives its inner budget from it, so the inner work can never be given the whole limit and lose the race to the kill")
fn gateLimitSec -> Int64
  300

; (:m :ref WALL-SLOW-GATES :do "seconds held back from the limit for process start, compile and the output of the verdict")
fn gateMarginSec -> Int64
  40

; (:m :ref WALL-SLOW-GATES :do "the budget a gate may spend on its own work under a limit: the limit less the margin, at least one second, so it is always strictly below the limit")
fn innerBudgetSec limit: Int64 -> Int64
  (if (> (- limit (gateMarginSec)) 0) (- limit (gateMarginSec)) 1)
