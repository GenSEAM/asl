(module aslAgentCore/fiberPool
  :x [FiberPriority FiberState prioCritical prioInteractive prioBackground
      fiberPending fiberRunning fiberYielded fiberCompleted fiberFailed
      FiberFrame FiberRecord FiberPool fiberPoolCreate fiberSpawn fiberStep
      fiberYield fiberComplete fiberPostMessage fiberNextRunnable formatFiberPoolStatus]
  :i [])

(enum FiberPriority
  (:c prioCritical [] "Instant interactive actions: voice barge-in, fast-path cancel (<1ms)")
  (:c prioInteractive [] "Conversational turn dispatch and interactive CLI queries (<50ms)")
  (:c prioBackground [] "Deep codebase indexation, doc lookup, and research queries"))

(enum FiberState
  (:c fiberPending [] "Waiting in run queue for scheduler dispatch")
  (:c fiberRunning [] "Actively executing AST reduction or tool step")
  (:c fiberYielded [] "Cooperatively yielded on I/O or token stream chunk")
  (:c fiberCompleted [] "Execution finished successfully with terminal receipt")
  (:c fiberFailed [] "Fiber encountered unhandled error or trap"))

(schema FiberFrame
  (:f frameId Str)
  (:f instruction Str)
  (:f fuelRemaining I64)
  (:f output Str))

(schema FiberRecord
  (:f id Str)
  (:f priority FiberPriority)
  (:f state FiberState)
  (:f frame FiberFrame)
  (:f mailbox (List Str))
  (:f createdAt I64)
  (:f totalFuelConsumed I64))

(schema FiberPool
  (:f capacity I64)
  (:f activeFibers (Map Str FiberRecord))
  (:f criticalQueue (List Str))
  (:f interactiveQueue (List Str))
  (:f backgroundQueue (List Str))
  (:f totalCompleted I64))

fn fiberPoolCreate capacity: I64 -> FiberPool
  (FiberPool
    :capacity capacity
    :activeFibers (mapEmpty)
    :criticalQueue (list)
    :interactiveQueue (list)
    :backgroundQueue (list)
    :totalCompleted 0)

fn fiberSpawn pool: FiberPool prio: FiberPriority directive: Str nowMs: I64 -> (Pair FiberPool Str)
  (let [(fiberId (str "fiber-" (stringFromInt64 (+ (mapSize pool.activeFibers) (+ pool.totalCompleted 1)))))
        (frame (FiberFrame :frameId (str "frame-" fiberId) :instruction directive :fuelRemaining 100 :output ""))
        (record (FiberRecord :id fiberId :priority prio :state (fiberPending) :frame frame :mailbox (list) :createdAt nowMs :totalFuelConsumed 0))
        (updatedActive (mapSet pool.activeFibers fiberId record))
        (updatedCrit (mt prio ((prioCritical) (listAppend pool.criticalQueue (list fiberId))) (_ pool.criticalQueue)))
        (updatedInter (mt prio ((prioInteractive) (listAppend pool.interactiveQueue (list fiberId))) (_ pool.interactiveQueue)))
        (updatedBack (mt prio ((prioBackground) (listAppend pool.backgroundQueue (list fiberId))) (_ pool.backgroundQueue)))]
    (pair
      (with pool :activeFibers updatedActive :criticalQueue updatedCrit :interactiveQueue updatedInter :backgroundQueue updatedBack)
      fiberId))

fn fiberPostMessage pool: FiberPool fiberId: Str msg: Str -> FiberPool
  (mt (mapGet pool.activeFibers fiberId)
    ((some rec)
      (let [(updatedMailbox (listAppend rec.mailbox (list msg)))
            (updatedRec (FiberRecord
                          :id rec.id
                          :priority rec.priority
                          :state rec.state
                          :frame rec.frame
                          :mailbox updatedMailbox
                          :createdAt rec.createdAt
                          :totalFuelConsumed rec.totalFuelConsumed))
            (updatedActive (mapSet pool.activeFibers fiberId updatedRec))]
        (with pool :activeFibers updatedActive)))
    ((none) pool))

fn fiberStep pool: FiberPool fiberId: Str fuel: I64 stepOutput: Str -> FiberPool
  (mt (mapGet pool.activeFibers fiberId)
    ((some rec)
      (let [(oldFrame rec.frame)
            (newFrame (FiberFrame
                        :frameId oldFrame.frameId
                        :instruction oldFrame.instruction
                        :fuelRemaining (if (> oldFrame.fuelRemaining fuel) (- oldFrame.fuelRemaining fuel) 0)
                        :output stepOutput))
            (updatedRec (FiberRecord
                          :id rec.id
                          :priority rec.priority
                          :state (fiberRunning)
                          :frame newFrame
                          :mailbox rec.mailbox
                          :createdAt rec.createdAt
                          :totalFuelConsumed (+ rec.totalFuelConsumed fuel)))
            (updatedActive (mapSet pool.activeFibers fiberId updatedRec))]
        (with pool :activeFibers updatedActive)))
    ((none) pool))

fn fiberYield pool: FiberPool fiberId: Str -> FiberPool
  (mt (mapGet pool.activeFibers fiberId)
    ((some rec)
      (let [(updatedRec (FiberRecord
                          :id rec.id
                          :priority rec.priority
                          :state (fiberYielded)
                          :frame rec.frame
                          :mailbox rec.mailbox
                          :createdAt rec.createdAt
                          :totalFuelConsumed rec.totalFuelConsumed))
            (updatedActive (mapSet pool.activeFibers fiberId updatedRec))]
        (with pool :activeFibers updatedActive)))
    ((none) pool))

fn fiberComplete pool: FiberPool fiberId: Str finalOutput: Str -> FiberPool
  (mt (mapGet pool.activeFibers fiberId)
    ((some rec)
      (let [(oldFrame rec.frame)
            (newFrame (FiberFrame
                        :frameId oldFrame.frameId
                        :instruction oldFrame.instruction
                        :fuelRemaining 0
                        :output finalOutput))
            (updatedRec (FiberRecord
                          :id rec.id
                          :priority rec.priority
                          :state (fiberCompleted)
                          :frame newFrame
                          :mailbox rec.mailbox
                          :createdAt rec.createdAt
                          :totalFuelConsumed rec.totalFuelConsumed))
            (updatedActive (mapSet pool.activeFibers fiberId updatedRec))]
        (with pool :activeFibers updatedActive :totalCompleted (+ pool.totalCompleted 1))))
    ((none) pool))

fn fiberNextRunnable pool: FiberPool -> (Option Str)
  (if (not (listEmpty? pool.criticalQueue))
    (listHead pool.criticalQueue)
    (if (not (listEmpty? pool.interactiveQueue))
      (listHead pool.interactiveQueue)
      (if (not (listEmpty? pool.backgroundQueue))
        (listHead pool.backgroundQueue)
        (none))))

fn formatFiberPoolStatus pool: FiberPool -> Str
  (str "(:fiber-pool :capacity " (stringFromInt64 pool.capacity)
       " :active " (stringFromInt64 (mapSize pool.activeFibers))
       " :critical-queue " (stringFromInt64 (listLength pool.criticalQueue))
       " :interactive-queue " (stringFromInt64 (listLength pool.interactiveQueue))
       " :background-queue " (stringFromInt64 (listLength pool.backgroundQueue))
       " :completed " (stringFromInt64 pool.totalCompleted) ")")
