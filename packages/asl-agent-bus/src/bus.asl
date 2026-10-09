(module aslAgentBus/bus :x [AgentMessage BusEnvelope makeBusEnvelope makeSequencedBusEnvelope validateBusCasEpoch BusEvent formatSseEvent isBroadcast BusChannel TaskLifecycleState BusReceipt ConditionWake dispatchBusEvent queryBusEvents pullBusEvents makeConditionWake evalConditionWake makeLifecycleEvent formatLifecycleSse channelToStr lifecycleToStr isHighPriorityChannel? isHighPriorityMessage? filterBackpressureEvents BusPriority prioP0Control prioP1Audit prioP2Data prioP3Telemetry PriorityBusQueue makePriorityBusQueue pushPriorityEvent popPriorityEvent popPriorityEventTimed isExpiredMessage? filterExpiredMessages pruneExpiredQueue classifyMessagePriority priorityQueueLength InFlightMessage DlqStats popPriorityEventLeased busRecordInFlight busAckMessage busNackMessage busDlqStats busDlqDrain IpcMessageFrame packIpcFrame unpackIpcFrame computeIpcChecksum makeIpcMessageFrame verifyIpcFrame] :i [(asl-text/string :a s)])

(schema AgentMessage (:f sender Str) (:f target Str) (:f payload Str) (:f timestamp I64))

(schema BusEnvelope (:f id Str) (:f sender Str) (:f target Str) (:f payload Str) (:f timestamp I64) (:f correlationId Str) (:f epoch I64) (:f seq I64))

fn makeBusEnvelope id: Str sender: Str target: Str payload: Str ts: I64 corrId: Str -> BusEnvelope
  (BusEnvelope :id id :sender sender :target target :payload payload :timestamp ts :correlationId corrId :epoch 1 :seq 1)

fn makeSequencedBusEnvelope id: Str sender: Str target: Str payload: Str ts: I64 corrId: Str epoch: I64 seq: I64 -> BusEnvelope
  (BusEnvelope :id id :sender sender :target target :payload payload :timestamp ts :correlationId corrId :epoch epoch :seq seq)

fn validateBusCasEpoch env: BusEnvelope currentEpoch: I64 expectedMinSeq: I64 -> Bool
  (and (= env.epoch currentEpoch) (>= env.seq expectedMinSeq))

(enum BusEvent (:c direct [(msg AgentMessage)] "direct message") (:c broadcast [(msg AgentMessage)] "broadcast message") (:c ping [] "ping event"))

(enum BusChannel (:c lifecycle [] "Task lifecycle state transition events") (:c telemetry [] "High-signal auditory and visual telemetry metrics") (:c control [] "Supervisory control and handoff commands") (:c audit [] "Clean-context verification gate receipts"))

(enum TaskLifecycleState (:c queued [] "Task queued in pending buffer") (:c routing [] "Task routing to worker lanes") (:c executing [] "Task executing in worker lanes") (:c verifying [] "Task undergoing gate verification") (:c done [] "Task completed successfully") (:c failed [] "Task execution or verification failed"))

(schema BusReceipt (:f channel Str) (:f sender Str) (:f target Str) (:f delivered Bool) (:f timestamp I64))

(schema ConditionWake (:f conditionName Str) (:f predicateExpr Str) (:f targetAgent Str) (:f triggered Bool))

fn formatSseEvent eventName: Str data: Str -> Str
  (s/concat (s/concat (s/concat "event: " eventName) "\ndata: ") (s/concat data "\n\n"))

fn isBroadcast event: BusEvent -> Bool
  (mt event ((broadcast msg) true) (_ false))

fn channelToStr ch: BusChannel -> Str
  (mt ch ((lifecycle) "lifecycle") ((telemetry) "telemetry") ((control) "control") ((audit) "audit"))

fn lifecycleToStr state: TaskLifecycleState -> Str
  (mt state ((queued) "QUEUED") ((routing) "ROUTING") ((executing) "EXECUTING") ((verifying) "VERIFYING") ((done) "DONE") ((failed) "FAILED"))

fn makeLifecycleEvent taskId: Str state: TaskLifecycleState detail: Str -> AgentMessage
  (AgentMessage :sender "kernel" :target "bus" :payload (str "(:lifecycle :task \"" taskId "\" :state \"" (lifecycleToStr state) "\" :detail \"" detail "\")") :timestamp 1725800000)

fn dispatchBusEvent ch: BusChannel msg: AgentMessage -> BusReceipt
  (BusReceipt :channel (channelToStr ch) :sender msg.sender :target msg.target :delivered true :timestamp msg.timestamp)

fn queryBusEvents events: (List AgentMessage) channelFilter: Str targetPath: Str -> (List AgentMessage)
  (filter (fn [(msg AgentMessage)] -> Bool (and (or (= channelFilter "") (stringContains? msg.payload channelFilter)) (or (= targetPath "") (stringContains? msg.target targetPath) (and (= msg.target "bus") (stringContains? msg.payload targetPath))))) events)

fn pullBusEvents events: (List AgentMessage) topic: Str -> (List AgentMessage)
  (queryBusEvents events topic "")

fn makeConditionWake name: Str pred: Str agent: Str -> ConditionWake
  (ConditionWake :conditionName name :predicateExpr pred :targetAgent agent :triggered false)

fn evalConditionWake wake: ConditionWake msg: AgentMessage -> ConditionWake
  (if (stringContains? msg.payload wake.predicateExpr) (with wake :triggered true) wake)

fn formatLifecycleSse taskId: Str state: TaskLifecycleState detail: Str -> Str
  (let [(data (str "(:lifecycle :task \"" taskId "\" :state \"" (lifecycleToStr state) "\" :detail \"" detail "\")"))] (formatSseEvent "lifecycle" data))

fn isHighPriorityChannel? ch: BusChannel -> Bool
  (mt ch
    ((telemetry) false)
    (_ true))

fn isHighPriorityMessage? msg: AgentMessage -> Bool
  (not (stringContains? msg.payload ":sparkline"))

fn filterBackpressureEvents events: (List AgentMessage) shedTelemetry: Bool -> (List AgentMessage)
  (if (not shedTelemetry)
    events
    (filter (fn [(m AgentMessage)] (isHighPriorityMessage? m)) events))

(enum BusPriority
  (:c prioP0Control [] "Supervisory abort, cancel, circuit-breaker, witness")
  (:c prioP1Audit [] "Clean-context gate receipts, condition wakes, lease renewal")
  (:c prioP2Data [] "Standard task lifecycle payloads, AST slices, diffs")
  (:c prioP3Telemetry [] "Sparklines, metrics, heartbeat pings"))

(schema InFlightMessage (:f id Str) (:f message AgentMessage) (:f leasedAt I64) (:f retryCount Int64))

(schema DlqStats (:f totalCount Int64) (:f oldestTimestamp I64))

(schema PriorityBusQueue
  (:f p0Lanes (List AgentMessage))
  (:f p1Lanes (List AgentMessage))
  (:f p2Lanes (List AgentMessage))
  (:f p3Lanes (List AgentMessage))
  (:f inFlight (List InFlightMessage))
  (:f dlq (List AgentMessage))
  (:f retryCounts (Map Str I64))
  (:f starvationCount Int64))

fn makePriorityBusQueue -> PriorityBusQueue
  (PriorityBusQueue :p0Lanes (list) :p1Lanes (list) :p2Lanes (list) :p3Lanes (list) :inFlight (list) :dlq (list) :retryCounts (mapEmpty) :starvationCount 0)

fn classifyMessagePriority msg: AgentMessage -> BusPriority
  (let [(p msg.payload)]
    (if (or (stringContains? p ":abort") (or (stringContains? p ":cancel") (or (stringContains? p ":circuit-breaker") (stringContains? p ":witness"))))
      (prioP0Control)
      (if (or (stringContains? p ":audit") (or (stringContains? p ":receipt") (stringContains? p ":wake")))
        (prioP1Audit)
        (if (or (stringContains? p ":sparkline") (or (stringContains? p ":metric") (stringContains? p ":ping")))
          (prioP3Telemetry)
          (prioP2Data)))))

fn pushPriorityEvent q: PriorityBusQueue msg: AgentMessage -> PriorityBusQueue
  (let [(prio (classifyMessagePriority msg))
        (sc q.starvationCount)
        (infl q.inFlight)
        (dlq q.dlq)
        (rc q.retryCounts)]
    (mt prio
      ((prioP0Control) (with q :p0Lanes (listAppend q.p0Lanes (list msg)) :inFlight infl :dlq dlq :retryCounts rc :starvationCount sc))
      ((prioP1Audit) (with q :p1Lanes (listAppend q.p1Lanes (list msg)) :inFlight infl :dlq dlq :retryCounts rc :starvationCount sc))
      ((prioP2Data) (with q :p2Lanes (listAppend q.p2Lanes (list msg)) :inFlight infl :dlq dlq :retryCounts rc :starvationCount sc))
      ((prioP3Telemetry) (with q :p3Lanes (listAppend q.p3Lanes (list msg)) :inFlight infl :dlq dlq :retryCounts rc :starvationCount sc))))

fn isExpiredMessage? msg: AgentMessage now: I64 ttl: I64 -> Bool
  (and (> ttl 0) (> now (+ msg.timestamp ttl)))

fn filterExpiredMessages events: (List AgentMessage) now: I64 ttl: I64 -> (List AgentMessage)
  (filter (fn [(m AgentMessage)] (not (isExpiredMessage? m now ttl))) events)

fn pruneExpiredQueue q: PriorityBusQueue now: I64 ttl: I64 -> PriorityBusQueue
  (with q :p0Lanes (filterExpiredMessages q.p0Lanes now ttl) :p1Lanes (filterExpiredMessages q.p1Lanes now ttl) :p2Lanes (filterExpiredMessages q.p2Lanes now ttl) :p3Lanes (filterExpiredMessages q.p3Lanes now ttl))

fn popPriorityEvent q: PriorityBusQueue -> (Pair PriorityBusQueue (Option AgentMessage))
  (let [(infl q.inFlight)
        (dlq q.dlq)
        (rc q.retryCounts)]
    (if (and (>= q.starvationCount 3) (or (> (listLength q.p3Lanes) 0) (or (> (listLength q.p2Lanes) 0) (> (listLength q.p1Lanes) 0))))
      (if (and (> (listLength q.p0Lanes) 0) (> (listLength q.p1Lanes) 0))
        (let [(firstMsg (listGet q.p1Lanes 0))
              (restLanes (optionOr (listSlice q.p1Lanes 1 (listLength q.p1Lanes)) (list)))]
          (pair (with q :p1Lanes restLanes :inFlight infl :dlq dlq :retryCounts rc :starvationCount 0) firstMsg))
        (if (and (or (> (listLength q.p0Lanes) 0) (> (listLength q.p1Lanes) 0)) (> (listLength q.p2Lanes) 0))
          (let [(firstMsg (listGet q.p2Lanes 0))
                (restLanes (optionOr (listSlice q.p2Lanes 1 (listLength q.p2Lanes)) (list)))]
            (pair (with q :p2Lanes restLanes :inFlight infl :dlq dlq :retryCounts rc :starvationCount 0) firstMsg))
          (if (> (listLength q.p3Lanes) 0)
            (let [(firstMsg (listGet q.p3Lanes 0))
                  (restLanes (optionOr (listSlice q.p3Lanes 1 (listLength q.p3Lanes)) (list)))]
              (pair (with q :p3Lanes restLanes :inFlight infl :dlq dlq :retryCounts rc :starvationCount 0) firstMsg))
            (if (> (listLength q.p2Lanes) 0)
              (let [(firstMsg (listGet q.p2Lanes 0))
                    (restLanes (optionOr (listSlice q.p2Lanes 1 (listLength q.p2Lanes)) (list)))]
                (pair (with q :p2Lanes restLanes :inFlight infl :dlq dlq :retryCounts rc :starvationCount 0) firstMsg))
              (let [(firstMsg (listGet q.p1Lanes 0))
                    (restLanes (optionOr (listSlice q.p1Lanes 1 (listLength q.p1Lanes)) (list)))]
                (pair (with q :p1Lanes restLanes :inFlight infl :dlq dlq :retryCounts rc :starvationCount 0) firstMsg))))))
      (if (> (listLength q.p0Lanes) 0)
        (let [(firstMsg (listGet q.p0Lanes 0))
              (restLanes (optionOr (listSlice q.p0Lanes 1 (listLength q.p0Lanes)) (list)))]
          (pair (with q :p0Lanes restLanes :inFlight infl :dlq dlq :retryCounts rc :starvationCount (+ q.starvationCount 1)) firstMsg))
        (if (> (listLength q.p1Lanes) 0)
          (let [(firstMsg (listGet q.p1Lanes 0))
                (restLanes (optionOr (listSlice q.p1Lanes 1 (listLength q.p1Lanes)) (list)))]
            (pair (with q :p1Lanes restLanes :inFlight infl :dlq dlq :retryCounts rc :starvationCount (+ q.starvationCount 1)) firstMsg))
          (if (> (listLength q.p2Lanes) 0)
            (let [(firstMsg (listGet q.p2Lanes 0))
                  (restLanes (optionOr (listSlice q.p2Lanes 1 (listLength q.p2Lanes)) (list)))]
              (pair (with q :p2Lanes restLanes :inFlight infl :dlq dlq :retryCounts rc :starvationCount (+ q.starvationCount 1)) firstMsg))
            (if (> (listLength q.p3Lanes) 0)
              (let [(firstMsg (listGet q.p3Lanes 0))
                    (restLanes (optionOr (listSlice q.p3Lanes 1 (listLength q.p3Lanes)) (list)))]
                (pair (with q :p3Lanes restLanes :inFlight infl :dlq dlq :retryCounts rc :starvationCount 0) firstMsg))
              (pair q (none))))))))

fn popPriorityEventTimed q: PriorityBusQueue now: I64 ttl: I64 -> (Pair PriorityBusQueue (Option AgentMessage))
  (let [(pruned (pruneExpiredQueue q now ttl))]
    (popPriorityEvent pruned))

fn priorityQueueLength q: PriorityBusQueue -> Int64
  (+ (+ (listLength q.p0Lanes) (listLength q.p1Lanes)) (+ (listLength q.p2Lanes) (listLength q.p3Lanes)))

fn popPriorityEventLeased q: PriorityBusQueue msgId: Str now: I64 -> (Pair PriorityBusQueue (Option AgentMessage))
  (let [(poppedPair (popPriorityEvent q))
        (qPopped (pairFirst poppedPair))
        (optMsg (pairSecond poppedPair))]
    (mt optMsg
      ((some m)
        (let [(priorRetries (optionOr (mapGet qPopped.retryCounts msgId) 0))
              (inflight (InFlightMessage :id msgId :message m :leasedAt now :retryCount priorRetries))
              (qWithFlight (PriorityBusQueue
                             :p0Lanes qPopped.p0Lanes
                             :p1Lanes qPopped.p1Lanes
                             :p2Lanes qPopped.p2Lanes
                             :p3Lanes qPopped.p3Lanes
                             :inFlight (listAppend qPopped.inFlight (list inflight))
                             :dlq qPopped.dlq
                             :retryCounts qPopped.retryCounts
                             :starvationCount qPopped.starvationCount))]
          (pair qWithFlight (some m))))
      ((none)
        (pair q (none)))))

fn busRecordInFlight q: PriorityBusQueue msgId: Str msg: AgentMessage now: I64 retryCount: Int64 -> PriorityBusQueue
  (let [(inflight (InFlightMessage :id msgId :message msg :leasedAt now :retryCount retryCount))]
    (with q :inFlight (listAppend q.inFlight (list inflight))))

fn busAckMessage q: PriorityBusQueue msgId: Str -> PriorityBusQueue
  (let [(filtered (filter (fn [(f InFlightMessage)] (not (= f.id msgId))) q.inFlight))
        (nextRetries (mapSet q.retryCounts msgId 0))]
    (with q :inFlight filtered :retryCounts nextRetries))

fn busNackMessage q: PriorityBusQueue msgId: Str maxRetries: Int64 -> PriorityBusQueue
  (let [(targetMatch (filter (fn [(f InFlightMessage)] (= f.id msgId)) q.inFlight))
        (remainingInFlight (filter (fn [(f InFlightMessage)] (not (= f.id msgId))) q.inFlight))]
    (if (listEmpty? targetMatch)
      q
      (let [(inflight (optionOr (listHead targetMatch) (InFlightMessage :id "" :message (AgentMessage :sender "" :target "" :payload "" :timestamp 0) :leasedAt 0 :retryCount 0)))
            (nextRetries (+ inflight.retryCount 1))
            (origMsg inflight.message)]
        (if (>= nextRetries maxRetries)
          (let [(clearedRetries (mapSet q.retryCounts msgId 0))]
            (with q :inFlight remainingInFlight :dlq (listAppend q.dlq (list origMsg)) :retryCounts clearedRetries))
          (let [(updatedRetries (mapSet q.retryCounts msgId nextRetries))
                (qWithout (with q :inFlight remainingInFlight :retryCounts updatedRetries))]
            (pushPriorityEvent qWithout origMsg))))))

fn busDlqStats q: PriorityBusQueue -> DlqStats
  (let [(msgs q.dlq)
        (count (listLength msgs))]
    (if (= count 0)
      (DlqStats :totalCount 0 :oldestTimestamp 0)
      (let [(firstMsg (optionOr (listHead msgs) (AgentMessage :sender "" :target "" :payload "" :timestamp 0)))]
        (DlqStats :totalCount count :oldestTimestamp firstMsg.timestamp))))

fn busDlqDrain q: PriorityBusQueue -> (Pair PriorityBusQueue (List AgentMessage))
  (let [(drained q.dlq)
        (nextQ (with q :dlq (list)))]
    (pair nextQ drained))

(schema IpcMessageFrame
  (:f channel Str)
  (:f sender Str)
  (:f target Str)
  (:f payload Str)
  (:f timestamp I64)
  (:f checksum Int64))

fn computeIpcChecksum channel: Str sender: Str target: Str payload: Str timestamp: I64 -> Int64
  (let [(sig (str channel ":" sender ":" target ":" payload ":" (stringFromInt64 timestamp)))]
    (fnv1a64 sig))

fn makeIpcMessageFrame channel: Str sender: Str target: Str payload: Str timestamp: I64 -> IpcMessageFrame
  (let [(chk (computeIpcChecksum channel sender target payload timestamp))]
    (IpcMessageFrame
      :channel channel
      :sender sender
      :target target
      :payload payload
      :timestamp timestamp
      :checksum chk))

fn verifyIpcFrame frame: IpcMessageFrame -> Bool
  (let [(expected (computeIpcChecksum frame.channel frame.sender frame.target frame.payload frame.timestamp))]
    (= frame.checksum expected))

fn packIpcFrame frame: IpcMessageFrame -> Str
  (let [(chk (if (= frame.checksum 0)
               (computeIpcChecksum frame.channel frame.sender frame.target frame.payload frame.timestamp)
               frame.checksum))]
    (str frame.channel "\u001f"
         frame.sender "\u001f"
         frame.target "\u001f"
         frame.payload "\u001f"
         (stringFromInt64 frame.timestamp) "\u001f"
         (stringFromInt64 chk)))

fn unpackIpcFrame raw: Str -> (Option IpcMessageFrame)
  (let [(parts (stringSplit raw "\u001f"))]
    (if (!= (listLength parts) 6)
      (none)
      (let [(ch (optionOr (listGet parts 0) ""))
            (snd (optionOr (listGet parts 1) ""))
            (tgt (optionOr (listGet parts 2) ""))
            (pld (optionOr (listGet parts 3) ""))
            (optTs (stringToInt64 (optionOr (listGet parts 4) "")))
            (optCs (stringToInt64 (optionOr (listGet parts 5) "")))]
        (if (or (none? optTs) (none? optCs))
          (none)
          (let [(ts (optionOr optTs 0))
                (cs (optionOr optCs 0))
                (expectedCs (computeIpcChecksum ch snd tgt pld ts))]
            (if (!= cs expectedCs)
              (none)
              (some (IpcMessageFrame
                      :channel ch
                      :sender snd
                      :target tgt
                      :payload pld
                      :timestamp ts
                      :checksum cs))))))))


