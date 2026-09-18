(module asl-compiler/salsa :d "Pure ASL Salsa-Style Demand-Driven Reactive Compiler with Red-Green Backdating and Generational Epoch Eviction" :x [QueryKey QueryEntry QueryProvider SalsaDatabase QueryResult makeQueryKey makeSalsaDatabase registerQuery demandQuery executeQuery invalidateQuery evictStaleEpochs redGreenCheck simulateEditCycles findQuery findProvider computeHashString] :i [])

(dfs QueryKey (:f symbol Str "Target symbol identifier, e.g. Module:name") (:f kind Str "Compilation query kind, e.g. parse, typecheck, ir, codegen"))

(dfs QueryEntry (:f symbol Str "Target symbol identifier") (:f kind Str "Compilation query kind") (:f inputEpoch Int "Global epoch at which inputs were verified") (:f verifiedEpoch Int "Global epoch at which query was verified up-to-date") (:f changedEpoch Int "Global epoch at which query output value actually changed") (:f valueHash Str "Content digest of the query output value") (:f value Str "Cached evaluation output string") (:f dependencies (List QueryKey) "Direct dependency query keys") (:f lastAccessedEpoch Int "Last epoch in which query was accessed or executed") (:f state Str "green for valid up-to-date, red for stale"))

(dfs QueryProvider (:f symbol Str "Target symbol identifier") (:f kind Str "Compilation query kind") (:f dependencies (List QueryKey) "Declared dependency query keys") (:f compute (fn [(SalsaDatabase) (QueryKey)] -> (Pair SalsaDatabase Str)) "Dynamic computation function"))

(dfs SalsaDatabase (:f currentEpoch Int "Monotonically incrementing global compiler epoch counter") (:f maxEpochRetention Int "Maximum retention window for generational epoch eviction") (:f totalRecomputations Int "Telemetry counter of queries actively recomputed") (:f totalCacheHits Int "Telemetry counter of queries served from cache") (:f queries (List QueryEntry) "Active query cache table") (:f providers (List QueryProvider) "Registered query providers for demand-driven resolution"))

(dfs QueryResult (:f status Str "ok or error status string") (:f value Str "Computed query output value string") (:f valueHash Str "Output content digest hash") (:f wasRecomputed Bool "True if compute function was executed, false if served via backdating/cache") (:f changedEpoch Int "Global epoch at which output value was last changed"))

fn makeQueryKey symbol: Str kind: Str -> QueryKey
  (QueryKey :symbol symbol :kind kind)

fn makeSalsaDatabase maxRetention: Int -> SalsaDatabase
  (SalsaDatabase :currentEpoch 1 :maxEpochRetention (if (> maxRetention 0) maxRetention 10) :totalRecomputations 0 :totalCacheHits 0 :queries (list) :providers (list))

fn computeHashString s: Str -> Str
  (let [(len (string-length s))] (if (<= len 128) (str "h" (string-from-int64 len) "_" s) (let [(prefix (option-or (string-slice s 0 32) "")) (midStart (/ (- len 32) 2)) (mid (option-or (string-slice s midStart (+ midStart 32)) "")) (suffix (option-or (string-slice s (- len 32) len) ""))] (str "h" (string-from-int64 len) "_" prefix "_" mid "_" suffix))))

fn queryKeyEquals? a: QueryKey b: QueryKey -> Bool
  (and (= (.-symbol a) (.-symbol b)) (= (.-kind a) (.-kind b)))

fn makeDummyEntry key: QueryKey -> QueryEntry
  (QueryEntry :symbol (.-symbol key) :kind (.-kind key) :inputEpoch 0 :verifiedEpoch 0 :changedEpoch 0 :valueHash "" :value "" :dependencies (list) :lastAccessedEpoch 0 :state "red")

fn makeDummyProvider key: QueryKey -> QueryProvider
  (QueryProvider :symbol (.-symbol key) :kind (.-kind key) :dependencies (list) :compute (fn [(d SalsaDatabase) (k QueryKey)] (pair d "")))

fn findQueryInList queries: (List QueryEntry) sym: Str kind: Str -> (Option QueryEntry)
  (if (= (list-length queries) 0) (none) (let [(head (option-or (list-head queries) (makeDummyEntry (QueryKey :symbol sym :kind kind)))) (tail (option-or (list-tail queries) (list)))] (if (and (= (.-symbol head) sym) (= (.-kind head) kind)) (some head) (findQueryInList tail sym kind))))

fn findQuery db: SalsaDatabase key: QueryKey -> (Option QueryEntry)
  (findQueryInList (.-queries db) (.-symbol key) (.-kind key))

fn findProviderInList provs: (List QueryProvider) sym: Str kind: Str -> (Option QueryProvider)
  (if (= (list-length provs) 0) (none) (let [(head (option-or (list-head provs) (makeDummyProvider (QueryKey :symbol sym :kind kind)))) (tail (option-or (list-tail provs) (list)))] (if (and (= (.-symbol head) sym) (= (.-kind head) kind)) (some head) (findProviderInList tail sym kind))))

fn findProvider db: SalsaDatabase key: QueryKey -> (Option QueryProvider)
  (findProviderInList (.-providers db) (.-symbol key) (.-kind key))

fn registerQuery db: SalsaDatabase key: QueryKey deps: (List QueryKey) compute: (fn [(SalsaDatabase) (QueryKey)] -> (Pair SalsaDatabase Str)) -> SalsaDatabase
  (let [(kSym (.-symbol key)) (kKind (.-kind key)) (prov (QueryProvider :symbol kSym :kind kKind :dependencies deps :compute compute)) (filtered (list-filter (fn [(p QueryProvider)] (not (and (= (.-symbol p) kSym) (= (.-kind p) kKind)))) (.-providers db))) (updated (list-append filtered (list prov)))] (SalsaDatabase :currentEpoch (.-currentEpoch db) :maxEpochRetention (.-maxEpochRetention db) :totalRecomputations (.-totalRecomputations db) :totalCacheHits (.-totalCacheHits db) :queries (.-queries db) :providers updated))

fn upsertQueryEntry db: SalsaDatabase newEntry: QueryEntry -> SalsaDatabase
  (let [(kSym (.-symbol newEntry)) (kKind (.-kind newEntry)) (filtered (list-filter (fn [(e QueryEntry)] (not (and (= (.-symbol e) kSym) (= (.-kind e) kKind)))) (.-queries db))) (updated (list-append filtered (list newEntry)))] (SalsaDatabase :currentEpoch (.-currentEpoch db) :maxEpochRetention (.-maxEpochRetention db) :totalRecomputations (.-totalRecomputations db) :totalCacheHits (.-totalCacheHits db) :queries updated :providers (.-providers db)))

fn anyDepChangedAfter? db: SalsaDatabase deps: (List QueryKey) epoch: Int -> Bool
  (list-any? (fn [(depKey QueryKey)] (mt (findQuery db depKey) ((none) true) ((some depEntry) (or (= (.-state depEntry) "red") (> (.-changedEpoch depEntry) epoch))))) deps)

fn redGreenCheck db: SalsaDatabase key: QueryKey -> (Pair Bool SalsaDatabase)
  (mt (findQuery db key) ((none) (pair false db)) ((some entry) (if (= (.-state entry) "red") (pair false db) (if (= (.-verifiedEpoch entry) (.-currentEpoch db)) (pair true db) (let [(deps (.-dependencies entry)) (depsChanged (anyDepChangedAfter? db deps (.-verifiedEpoch entry)))] (if depsChanged (let [(redEntry (QueryEntry :symbol (.-symbol entry) :kind (.-kind entry) :inputEpoch (.-inputEpoch entry) :verifiedEpoch (.-verifiedEpoch entry) :changedEpoch (.-changedEpoch entry) :valueHash (.-valueHash entry) :value (.-value entry) :dependencies (.-dependencies entry) :lastAccessedEpoch (.-currentEpoch db) :state "red")) (updatedDb (upsertQueryEntry db redEntry))] (pair false updatedDb)) (let [(greenEntry (QueryEntry :symbol (.-symbol entry) :kind (.-kind entry) :inputEpoch (.-inputEpoch entry) :verifiedEpoch (.-currentEpoch db) :changedEpoch (.-changedEpoch entry) :valueHash (.-valueHash entry) :value (.-value entry) :dependencies (.-dependencies entry) :lastAccessedEpoch (.-currentEpoch db) :state "green")) (updatedDb (upsertQueryEntry db greenEntry))] (pair true updatedDb))))))))

fn isKeyInList? keys: (List QueryKey) k: QueryKey -> Bool
  (list-any? (fn [(item QueryKey)] (queryKeyEquals? item k)) keys)

fn hasAnyDepInStale? deps: (List QueryKey) staleKeys: (List QueryKey) -> Bool
  (list-any? (fn [(d QueryKey)] (isKeyInList? staleKeys d)) deps)

fn findDirectDownstreamKeys queries: (List QueryEntry) staleKeys: (List QueryKey) -> (List QueryKey)
  (let [(newEntries (list-filter (fn [(e QueryEntry)] (let [(k (QueryKey :symbol (.-symbol e) :kind (.-kind e)))] (and (not (isKeyInList? staleKeys k)) (hasAnyDepInStale? (.-dependencies e) staleKeys)))) queries))] (list-map (fn [(e QueryEntry)] (QueryKey :symbol (.-symbol e) :kind (.-kind e))) newEntries))

fn computeTransitiveStaleKeys queries: (List QueryEntry) staleKeys: (List QueryKey) -> (List QueryKey)
  (let [(newKeys (findDirectDownstreamKeys queries staleKeys))] (if (= (list-length newKeys) 0) staleKeys (computeTransitiveStaleKeys queries (list-append staleKeys newKeys))))

fn invalidateQuery db: SalsaDatabase key: QueryKey -> SalsaDatabase
  (let [(nextEpoch (+ (.-currentEpoch db) 1)) (allStaleKeys (computeTransitiveStaleKeys (.-queries db) (list key))) (invalidatedQueries (list-map (fn [(e QueryEntry)] (let [(k (QueryKey :symbol (.-symbol e) :kind (.-kind e)))] (if (isKeyInList? allStaleKeys k) (QueryEntry :symbol (.-symbol e) :kind (.-kind e) :inputEpoch (.-inputEpoch e) :verifiedEpoch (.-verifiedEpoch e) :changedEpoch (.-changedEpoch e) :valueHash (.-valueHash e) :value (.-value e) :dependencies (.-dependencies e) :lastAccessedEpoch (.-lastAccessedEpoch e) :state "red") e))) (.-queries db)))] (SalsaDatabase :currentEpoch nextEpoch :maxEpochRetention (.-maxEpochRetention db) :totalRecomputations (.-totalRecomputations db) :totalCacheHits (.-totalCacheHits db) :queries invalidatedQueries :providers (.-providers db)))

fn evictStaleEpochs db: SalsaDatabase -> SalsaDatabase
  (let [(curEpoch (.-currentEpoch db)) (retention (.-maxEpochRetention db)) (minEpoch (if (> curEpoch retention) (- curEpoch retention) 0)) (retained (list-filter (fn [(e QueryEntry)] (>= (.-lastAccessedEpoch e) minEpoch)) (.-queries db)))] (SalsaDatabase :currentEpoch curEpoch :maxEpochRetention retention :totalRecomputations (.-totalRecomputations db) :totalCacheHits (.-totalCacheHits db) :queries retained :providers (.-providers db)))

fn demandDependenciesLoop db: SalsaDatabase deps: (List QueryKey) -> SalsaDatabase
  (if (= (list-length deps) 0) db (let [(headDep (option-or (list-head deps) (makeQueryKey "" ""))) (tailDeps (option-or (list-tail deps) (list))) (pairRes (demandQuery db headDep)) (nextDb (pair-first pairRes))] (demandDependenciesLoop nextDb tailDeps)))

fn demandQuery db: SalsaDatabase key: QueryKey -> (Pair SalsaDatabase QueryResult)
  (let [(provOpt (findProvider db key)) (entryOpt (findQuery db key)) (declaredDeps (mt provOpt ((some p) (.-dependencies p)) ((none) (mt entryOpt ((some e) (.-dependencies e)) ((none) (list)))))) (dbAfterDeps (demandDependenciesLoop db declaredDeps)) (rgRes (redGreenCheck dbAfterDeps key)) (isGreen (pair-first rgRes)) (dbAfterCheck (pair-second rgRes))] (if isGreen (let [(entry (option-or (findQuery dbAfterCheck key) (makeDummyEntry key))) (updatedEntry (QueryEntry :symbol (.-symbol entry) :kind (.-kind entry) :inputEpoch (.-inputEpoch entry) :verifiedEpoch (.-verifiedEpoch entry) :changedEpoch (.-changedEpoch entry) :valueHash (.-valueHash entry) :value (.-value entry) :dependencies (.-dependencies entry) :lastAccessedEpoch (.-currentEpoch dbAfterCheck) :state "green")) (updatedDb (upsertQueryEntry (SalsaDatabase :currentEpoch (.-currentEpoch dbAfterCheck) :maxEpochRetention (.-maxEpochRetention dbAfterCheck) :totalRecomputations (.-totalRecomputations dbAfterCheck) :totalCacheHits (+ (.-totalCacheHits dbAfterCheck) 1) :queries (.-queries dbAfterCheck) :providers (.-providers dbAfterCheck)) updatedEntry)) (qRes (QueryResult :status "ok" :value (.-value entry) :valueHash (.-valueHash entry) :wasRecomputed false :changedEpoch (.-changedEpoch entry)))] (pair updatedDb qRes)) (mt provOpt ((none) (mt entryOpt ((none) (pair dbAfterCheck (QueryResult :status "error" :value "" :valueHash "" :wasRecomputed false :changedEpoch 0))) ((some existingEntry) (pair dbAfterCheck (QueryResult :status "ok" :value (.-value existingEntry) :valueHash (.-valueHash existingEntry) :wasRecomputed false :changedEpoch (.-changedEpoch existingEntry)))))) ((some provider) (let [(computeFn (.-compute provider)) (computeRes (computeFn dbAfterCheck key)) (dbAfterComp (pair-first computeRes)) (newValue (pair-second computeRes)) (newHash (computeHashString newValue)) (currentEpoch (.-currentEpoch dbAfterComp)) (oldEntryOpt (findQuery dbAfterComp key))] (mt oldEntryOpt ((none) (let [(newEntry (QueryEntry :symbol (.-symbol key) :kind (.-kind key) :inputEpoch currentEpoch :verifiedEpoch currentEpoch :changedEpoch currentEpoch :valueHash newHash :value newValue :dependencies (.-dependencies provider) :lastAccessedEpoch currentEpoch :state "green")) (updatedDb (upsertQueryEntry (SalsaDatabase :currentEpoch currentEpoch :maxEpochRetention (.-maxEpochRetention dbAfterComp) :totalRecomputations (+ (.-totalRecomputations dbAfterComp) 1) :totalCacheHits (.-totalCacheHits dbAfterComp) :queries (.-queries dbAfterComp) :providers (.-providers dbAfterComp)) newEntry)) (qRes (QueryResult :status "ok" :value newValue :valueHash newHash :wasRecomputed true :changedEpoch currentEpoch))] (pair updatedDb qRes))) ((some oldEntry) (let [(outputUnchanged (= newHash (.-valueHash oldEntry))) (effectiveChangedEpoch (if outputUnchanged (.-changedEpoch oldEntry) currentEpoch)) (recomputedFlag (not outputUnchanged)) (newEntry (QueryEntry :symbol (.-symbol key) :kind (.-kind key) :inputEpoch currentEpoch :verifiedEpoch currentEpoch :changedEpoch effectiveChangedEpoch :valueHash newHash :value newValue :dependencies (.-dependencies provider) :lastAccessedEpoch currentEpoch :state "green")) (updatedDb (upsertQueryEntry (SalsaDatabase :currentEpoch currentEpoch :maxEpochRetention (.-maxEpochRetention dbAfterComp) :totalRecomputations (if recomputedFlag (+ (.-totalRecomputations dbAfterComp) 1) (.-totalRecomputations dbAfterComp)) :totalCacheHits (if outputUnchanged (+ (.-totalCacheHits dbAfterComp) 1) (.-totalCacheHits dbAfterComp)) :queries (.-queries dbAfterComp) :providers (.-providers dbAfterComp)) newEntry)) (qRes (QueryResult :status "ok" :value newValue :valueHash newHash :wasRecomputed recomputedFlag :changedEpoch effectiveChangedEpoch))] (pair updatedDb qRes)))))))))

fn executeQuery db: SalsaDatabase key: QueryKey computeFn: (fn [(QueryKey) -> Str]) deps: (List QueryKey) -> (Pair SalsaDatabase QueryResult)
  (let [(adaptedCompute (fn [(d SalsaDatabase) (k QueryKey)] (pair d (computeFn k)))) (dbWithProv (registerQuery db key deps adaptedCompute))] (demandQuery dbWithProv key))

fn cyclesLoop db: SalsaDatabase totalCycles: Int step: Int sym: Str -> SalsaDatabase
  (if (>= step totalCycles) db (let [(tempKey (makeQueryKey (str "TempSymbol_" (string-from-int64 step)) "parse")) (resPair (executeQuery db tempKey (fn [(k QueryKey)] (str "ast_" (.-symbol k))) (list))) (dbWithTemp (pair-first resPair)) (mutKey (makeQueryKey sym "typecheck")) (invDb (invalidateQuery dbWithTemp mutKey)) (evictedDb (evictStaleEpochs invDb))] (cyclesLoop evictedDb totalCycles (+ step 1) sym)))

fn simulateEditCycles db: SalsaDatabase cycles: Int mutatedSymbol: Str -> SalsaDatabase
  (cyclesLoop db cycles 0 mutatedSymbol)
