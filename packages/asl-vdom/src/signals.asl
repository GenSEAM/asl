(module aslVdom/signals
  :x [Signal Computed Effect SignalBatch makeSignal signalGet signalSet signalSubscribe makeComputed computedGet computedInvalidate makeEffect runEffect makeSignalBatch queueSignalUpdate flushSignalBatch propagateSignalChange propagateEffects propagateSignalBatch]
  :i [])

(schema Signal
  (:f id String)
  (:f value String)
  (:f subscribers (List String)))

(schema Computed
  (:f id String)
  (:f cachedValue String)
  (:f dirty Bool)
  (:f dependencies (List String)))

(schema Effect
  (:f id String)
  (:f dependencies (List String))
  (:f runCount Int64))

fn makeSignal id: String initialValue: String -> Signal
  (Signal :id id :value initialValue :subscribers (list))

fn signalGet sig: Signal -> String
  sig.value

fn signalSet sig: Signal newValue: String -> Signal
  (with sig :value newValue)

fn signalSubscribe sig: Signal subscriberId: String -> Signal
  (if (or (stringEmpty? subscriberId) (listContains? sig.subscribers subscriberId))
    sig
    (with sig :subscribers (listAppend sig.subscribers (list subscriberId))))

fn makeComputed id: String initialValue: String dependencies: (List String) -> Computed
  (Computed :id id :cachedValue initialValue :dirty false :dependencies dependencies)

fn computedInvalidate comp: Computed -> Computed
  (with comp :dirty true)

fn computedGet comp: Computed recomputedVal: String -> (Pair Computed String)
  (if comp.dirty
    (let [(updated (with comp :cachedValue recomputedVal :dirty false))]
      (pair updated recomputedVal))
    (pair comp comp.cachedValue))

fn makeEffect id: String dependencies: (List String) -> Effect
  (Effect :id id :dependencies dependencies :runCount 0)

fn runEffect eff: Effect -> Effect
  (with eff :runCount (+ eff.runCount 1))

(schema SignalBatch
  (:f queuedSignalIds (List String))
  (:f isPending Bool))

fn makeSignalBatch -> SignalBatch
  (SignalBatch :queuedSignalIds (list) :isPending false)

fn queueSignalUpdate batch: SignalBatch signalId: String -> SignalBatch
  (if (or (stringEmpty? signalId) (listContains? batch.queuedSignalIds signalId))
    batch
    (SignalBatch
      :queuedSignalIds (listAppend batch.queuedSignalIds (list signalId))
      :isPending true))

fn flushSignalBatch batch: SignalBatch -> (Pair SignalBatch (List String))
  (pair (makeSignalBatch) batch.queuedSignalIds)

fn propagateSignalChange sigId: String computeds: (List Computed) -> (List Computed)
  (fold (fn [(acc (List Computed)) (c Computed)] -> (List Computed)
          (if (listContains? c.dependencies sigId)
            (listAppend acc (list (computedInvalidate c)))
            (listAppend acc (list c))))
        (list)
        computeds)

fn propagateEffects sigId: String effects: (List Effect) -> (List Effect)
  (fold (fn [(acc (List Effect)) (e Effect)] -> (List Effect)
          (if (listContains? e.dependencies sigId)
            (listAppend acc (list (runEffect e)))
            (listAppend acc (list e))))
        (list)
        effects)

fn propagateSignalBatch changedIds: (List String) computeds: (List Computed) effects: (List Effect) -> (Pair (List Computed) (List Effect))
  (fold (fn [(acc (pair (List Computed) (List Effect))) (sigId String)] -> (Pair (List Computed) (List Effect))
          (let [(curComps (pairFirst acc))
                (curEffs (pairSecond acc))
                (nextComps (propagateSignalChange sigId curComps))
                (nextEffs (propagateEffects sigId curEffs))]
            (pair nextComps nextEffs)))
        (pair computeds effects)
        changedIds)
