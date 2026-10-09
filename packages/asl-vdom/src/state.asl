(module aslVdom/state :x [StateStore Action StatePatch createStore getState getStateValue dispatchAction applyPatch applyPatches computeStateDiff subscribeStore unsubscribeStore hasSubscriber? isValidState? isUniqueList? uniqueSubscribers?])

(schema StateStore (:f state (Map String String)) (:f version Int64) (:f subscribers (List String)))

(schema Action (:f name String) (:f payload (Map String String)))

(schema StatePatch (:f path String) (:f op String) (:f value String))

fn isUniqueList? items: (List String) -> Bool
  (let [(seenMap (fold (fn [(acc (Map String Bool)) (s String)] -> (Map String Bool) (mapSet acc s true)) (mapEmpty) items))] (= (mapSize seenMap) (listLength items)))

fn uniqueSubscribers? subs: (List String) -> Bool
  (isUniqueList? subs)

fn isValidState? store: StateStore -> Bool
  (and (>= store.version 0) (uniqueSubscribers? store.subscribers))

fn createStore initialState: (Map String String) -> StateStore
  (StateStore :state initialState :version 0 :subscribers (list))

fn getState store: StateStore -> (Map String String)
  store.state

fn getStateValue store: StateStore key: String defaultVal: String -> String
  (mt (mapGet store.state key) ((some val) val) ((none) defaultVal))

fn dispatchAction store: StateStore action: Action reducer: (fn [(Map String String) Action] -> (Map String String)) -> StateStore
  (let [(nextState (reducer store.state action))] (with store :state nextState :version (+ store.version 1)))

fn applyPatch store: StateStore patch: StatePatch -> StateStore
  (let [(p patch.path) (op patch.op) (v patch.value)] (if (stringEmpty? p) store (let [(nextState (if (or (= op "remove") (= op "delete")) (mapRemove store.state p) (mapSet store.state p v)))] (with store :state nextState :version (+ store.version 1)))))

fn applyPatches store: StateStore patches: (List StatePatch) -> StateStore
  (fold (fn [(acc StateStore) (p StatePatch)] -> StateStore (applyPatch acc p)) store patches)

fn computeStateDiff oldState: (Map String String) newState: (Map String String) -> (List StatePatch)
  (let [(keysNew (mapKeys newState)) (keysOld (mapKeys oldState)) (updates (fold (fn [(acc (List StatePatch)) (k String)] -> (List StatePatch) (let [(newVal (mt (mapGet newState k) ((some nv) nv) ((none) "")))] (mt (mapGet oldState k) ((some oldV) (if (= oldV newVal) acc (cons (StatePatch :path k :op "set" :value newVal) acc))) ((none) (cons (StatePatch :path k :op "set" :value newVal) acc))))) (list) keysNew)) (removals (fold (fn [(acc (List StatePatch)) (k String)] -> (List StatePatch) (if (mapHas? newState k) acc (cons (StatePatch :path k :op "remove" :value "") acc))) (list) keysOld))] (listAppend updates removals))

fn subscribeStore store: StateStore subscriber: String -> StateStore
  (if (or (stringEmpty? subscriber) (listContains? store.subscribers subscriber)) store (with store :subscribers (listAppend store.subscribers (list subscriber))))

fn unsubscribeStore store: StateStore subscriber: String -> StateStore
  (with store :subscribers (filter (fn [(s String)] -> Bool (!= s subscriber)) store.subscribers))

fn hasSubscriber? store: StateStore subscriber: String -> Bool
  (listContains? store.subscribers subscriber)
