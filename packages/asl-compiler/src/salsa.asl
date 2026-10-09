(module asl-compiler/salsa :x [QueryKey QueryEntry QueryProvider SalsaDatabase QueryResult makeQueryKey makeSalsaDatabase registerQuery demandQuery executeQuery invalidateQuery evictStaleEpochs redGreenCheck simulateEditCycles findQuery findProvider computeHashString makeDummyEntry] :i [])

(schema QueryKey (:f symbol Str) (:f kind Str))

(schema QueryEntry (:f symbol Str) (:f kind Str) (:f inputEpoch Int) (:f verifiedEpoch Int) (:f changedEpoch Int) (:f valueHash Str) (:f value Str) (:f dependencies (List QueryKey)) (:f lastAccessedEpoch Int) (:f state Str))

(schema QueryProvider (:f symbol Str) (:f kind Str) (:f dependencies (List QueryKey)) (:f compute (fn [(SalsaDatabase) (QueryKey)] -> (Pair SalsaDatabase Str))))

(schema SalsaDatabase (:f currentEpoch Int) (:f maxEpochRetention Int) (:f totalRecomputations Int) (:f totalCacheHits Int) (:f queries (List QueryEntry)) (:f providers (List QueryProvider)))

(schema QueryResult (:f status Str) (:f value Str) (:f valueHash Str) (:f wasRecomputed Bool) (:f changedEpoch Int))

fn makeQueryKey symbol: Str kind: Str -> QueryKey
  (QueryKey :symbol symbol :kind kind)

fn makeSalsaDatabase maxRetention: Int -> SalsaDatabase
  (SalsaDatabase :currentEpoch 1 :maxEpochRetention (if (> maxRetention 0) maxRetention 10) :totalRecomputations 0 :totalCacheHits 0 :queries (list) :providers (list))

fn computeHashString s: Str -> Str
  (let [(len (stringLength s))] (if (<= len 128) (str "h" (stringFromInt64 len) "_" s) (let [(prefix (optionOr (stringSlice s 0 32) "")) (midStart (/ (- len 32) 2)) (mid (optionOr (stringSlice s midStart (+ midStart 32)) "")) (suffix (optionOr (stringSlice s (- len 32) len) ""))] (str "h" (stringFromInt64 len) "_" prefix "_" mid "_" suffix))))

fn queryKeyEquals? a: QueryKey b: QueryKey -> Bool
  (and (= a.symbol b.symbol) (= a.kind b.kind))

fn makeDummyEntry key: QueryKey -> QueryEntry
  (QueryEntry :symbol key.symbol :kind key.kind :inputEpoch 0 :verifiedEpoch 0 :changedEpoch 0 :valueHash "" :value "" :dependencies (list) :lastAccessedEpoch 0 :state "red")

fn makeDummyProvider key: QueryKey -> QueryProvider
  (QueryProvider :symbol key.symbol :kind key.kind :dependencies (list) :compute (fn [(d SalsaDatabase) (k QueryKey)] (pair d "")))

fn findQueryInList queries: (List QueryEntry) sym: Str kind: Str -> (Option QueryEntry)
  (if (= (listLength queries) 0) (none) (let [(head (optionOr (listHead queries) (makeDummyEntry (QueryKey :symbol sym :kind kind)))) (tail (optionOr (listTail queries) (list)))] (if (and (= head.symbol sym) (= head.kind kind)) (some head) (findQueryInList tail sym kind))))

fn findQuery db: SalsaDatabase key: QueryKey -> (Option QueryEntry)
  (findQueryInList db.queries key.symbol key.kind)

fn findProviderInList provs: (List QueryProvider) sym: Str kind: Str -> (Option QueryProvider)
  (if (= (listLength provs) 0) (none) (let [(head (optionOr (listHead provs) (makeDummyProvider (QueryKey :symbol sym :kind kind)))) (tail (optionOr (listTail provs) (list)))] (if (and (= head.symbol sym) (= head.kind kind)) (some head) (findProviderInList tail sym kind))))

fn findProvider db: SalsaDatabase key: QueryKey -> (Option QueryProvider)
  (findProviderInList db.providers key.symbol key.kind)

fn registerQuery db: SalsaDatabase key: QueryKey deps: (List QueryKey) compute: (fn [(SalsaDatabase) (QueryKey)] -> (Pair SalsaDatabase Str)) -> SalsaDatabase
  (let [(kSym key.symbol) (kKind key.kind) (prov (QueryProvider :symbol kSym :kind kKind :dependencies deps :compute compute)) (filtered (filter (fn [(p QueryProvider)] (not (and (= p.symbol kSym) (= p.kind kKind)))) db.providers)) (updated (listAppend filtered (list prov)))] (with db :providers updated))

fn upsertQueryEntry db: SalsaDatabase newEntry: QueryEntry -> SalsaDatabase
  (let [(kSym newEntry.symbol) (kKind newEntry.kind) (filtered (filter (fn [(e QueryEntry)] (not (and (= e.symbol kSym) (= e.kind kKind)))) db.queries)) (updated (listAppend filtered (list newEntry)))] (with db :queries updated))

fn anyDepChangedAfter? db: SalsaDatabase deps: (List QueryKey) epoch: Int -> Bool
  (listAny? (fn [(depKey QueryKey)] (mt (findQuery db depKey) ((none) true) ((some depEntry) (or (= depEntry.state "red") (> depEntry.changedEpoch epoch))))) deps)

fn redGreenCheck db: SalsaDatabase key: QueryKey -> (Pair Bool SalsaDatabase)
  (mt (findQuery db key) ((none) (pair false db)) ((some entry) (if (= entry.state "red") (pair false db) (if (= entry.verifiedEpoch db.currentEpoch) (pair true db) (let [(deps entry.dependencies) (depsChanged (anyDepChangedAfter? db deps entry.verifiedEpoch))] (if depsChanged (let [(redEntry (QueryEntry :symbol entry.symbol :kind entry.kind :inputEpoch entry.inputEpoch :verifiedEpoch entry.verifiedEpoch :changedEpoch entry.changedEpoch :valueHash entry.valueHash :value entry.value :dependencies entry.dependencies :lastAccessedEpoch db.currentEpoch :state "red")) (updatedDb (upsertQueryEntry db redEntry))] (pair false updatedDb)) (let [(greenEntry (QueryEntry :symbol entry.symbol :kind entry.kind :inputEpoch entry.inputEpoch :verifiedEpoch db.currentEpoch :changedEpoch entry.changedEpoch :valueHash entry.valueHash :value entry.value :dependencies entry.dependencies :lastAccessedEpoch db.currentEpoch :state "green")) (updatedDb (upsertQueryEntry db greenEntry))] (pair true updatedDb))))))))

fn isKeyInList? keys: (List QueryKey) k: QueryKey -> Bool
  (listAny? (fn [(item QueryKey)] (queryKeyEquals? item k)) keys)

fn hasAnyDepInStale? deps: (List QueryKey) staleKeys: (List QueryKey) -> Bool
  (listAny? (fn [(d QueryKey)] (isKeyInList? staleKeys d)) deps)

fn findDirectDownstreamKeys queries: (List QueryEntry) staleKeys: (List QueryKey) -> (List QueryKey)
  (let [(newEntries (filter (fn [(e QueryEntry)] (let [(k (QueryKey :symbol e.symbol :kind e.kind))] (and (not (isKeyInList? staleKeys k)) (hasAnyDepInStale? e.dependencies staleKeys)))) queries))] (map (fn [(e QueryEntry)] (QueryKey :symbol e.symbol :kind e.kind)) newEntries))

fn computeTransitiveStaleKeys queries: (List QueryEntry) staleKeys: (List QueryKey) -> (List QueryKey)
  (let [(newKeys (findDirectDownstreamKeys queries staleKeys))] (if (= (listLength newKeys) 0) staleKeys (computeTransitiveStaleKeys queries (listAppend staleKeys newKeys))))

fn invalidateQuery db: SalsaDatabase key: QueryKey -> SalsaDatabase
  (let [(nextEpoch (+ db.currentEpoch 1)) (allStaleKeys (computeTransitiveStaleKeys db.queries (list key))) (invalidatedQueries (map (fn [(e QueryEntry)] (let [(k (QueryKey :symbol e.symbol :kind e.kind))] (if (isKeyInList? allStaleKeys k) (QueryEntry :symbol e.symbol :kind e.kind :inputEpoch e.inputEpoch :verifiedEpoch e.verifiedEpoch :changedEpoch e.changedEpoch :valueHash e.valueHash :value e.value :dependencies e.dependencies :lastAccessedEpoch e.lastAccessedEpoch :state "red") e))) db.queries))] (with db :currentEpoch nextEpoch :queries invalidatedQueries))

fn evictStaleEpochs db: SalsaDatabase -> SalsaDatabase
  (let [(curEpoch db.currentEpoch) (retention db.maxEpochRetention) (minEpoch (if (> curEpoch retention) (- curEpoch retention) 0)) (retained (filter (fn [(e QueryEntry)] (>= e.lastAccessedEpoch minEpoch)) db.queries))] (with db :currentEpoch curEpoch :maxEpochRetention retention :queries retained))

fn demandDependenciesLoop db: SalsaDatabase deps: (List QueryKey) -> SalsaDatabase
  (if (= (listLength deps) 0) db (let [(headDep (optionOr (listHead deps) (makeQueryKey "" ""))) (tailDeps (optionOr (listTail deps) (list))) (pairRes (demandQuery db headDep)) (nextDb (pairFirst pairRes))] (demandDependenciesLoop nextDb tailDeps)))

fn demandQuery db: SalsaDatabase key: QueryKey -> (Pair SalsaDatabase QueryResult)
  (let [(provOpt (findProvider db key)) (entryOpt (findQuery db key)) (declaredDeps (mt provOpt ((some p) p.dependencies) ((none) (mt entryOpt ((some e) e.dependencies) ((none) (list)))))) (dbAfterDeps (demandDependenciesLoop db declaredDeps)) (rgRes (redGreenCheck dbAfterDeps key)) (isGreen (pairFirst rgRes)) (dbAfterCheck (pairSecond rgRes))] (if isGreen (let [(entry (optionOr (findQuery dbAfterCheck key) (makeDummyEntry key))) (updatedEntry (QueryEntry :symbol entry.symbol :kind entry.kind :inputEpoch entry.inputEpoch :verifiedEpoch entry.verifiedEpoch :changedEpoch entry.changedEpoch :valueHash entry.valueHash :value entry.value :dependencies entry.dependencies :lastAccessedEpoch dbAfterCheck.currentEpoch :state "green")) (updatedDb (upsertQueryEntry (SalsaDatabase :currentEpoch dbAfterCheck.currentEpoch :maxEpochRetention dbAfterCheck.maxEpochRetention :totalRecomputations dbAfterCheck.totalRecomputations :totalCacheHits (+ dbAfterCheck.totalCacheHits 1) :queries dbAfterCheck.queries :providers dbAfterCheck.providers) updatedEntry)) (qRes (QueryResult :status "ok" :value entry.value :valueHash entry.valueHash :wasRecomputed false :changedEpoch entry.changedEpoch))] (pair updatedDb qRes)) (mt provOpt ((none) (mt entryOpt ((none) (pair dbAfterCheck (QueryResult :status "error" :value "" :valueHash "" :wasRecomputed false :changedEpoch 0))) ((some existingEntry) (pair dbAfterCheck (QueryResult :status "ok" :value existingEntry.value :valueHash existingEntry.valueHash :wasRecomputed false :changedEpoch existingEntry.changedEpoch))))) ((some provider) (let [(computeFn provider.compute) (computeRes (computeFn dbAfterCheck key)) (dbAfterComp (pairFirst computeRes)) (newValue (pairSecond computeRes)) (newHash (computeHashString newValue)) (currentEpoch dbAfterComp.currentEpoch) (oldEntryOpt (findQuery dbAfterComp key))] (mt oldEntryOpt ((none) (let [(newEntry (QueryEntry :symbol key.symbol :kind key.kind :inputEpoch currentEpoch :verifiedEpoch currentEpoch :changedEpoch currentEpoch :valueHash newHash :value newValue :dependencies provider.dependencies :lastAccessedEpoch currentEpoch :state "green")) (updatedDb (upsertQueryEntry (SalsaDatabase :currentEpoch currentEpoch :maxEpochRetention dbAfterComp.maxEpochRetention :totalRecomputations (+ dbAfterComp.totalRecomputations 1) :totalCacheHits dbAfterComp.totalCacheHits :queries dbAfterComp.queries :providers dbAfterComp.providers) newEntry)) (qRes (QueryResult :status "ok" :value newValue :valueHash newHash :wasRecomputed true :changedEpoch currentEpoch))] (pair updatedDb qRes))) ((some oldEntry) (let [(outputUnchanged (= newHash oldEntry.valueHash)) (effectiveChangedEpoch (if outputUnchanged oldEntry.changedEpoch currentEpoch)) (recomputedFlag (not outputUnchanged)) (newEntry (QueryEntry :symbol key.symbol :kind key.kind :inputEpoch currentEpoch :verifiedEpoch currentEpoch :changedEpoch effectiveChangedEpoch :valueHash newHash :value newValue :dependencies provider.dependencies :lastAccessedEpoch currentEpoch :state "green")) (updatedDb (upsertQueryEntry (SalsaDatabase :currentEpoch currentEpoch :maxEpochRetention dbAfterComp.maxEpochRetention :totalRecomputations (if recomputedFlag (+ dbAfterComp.totalRecomputations 1) dbAfterComp.totalRecomputations) :totalCacheHits (if outputUnchanged (+ dbAfterComp.totalCacheHits 1) dbAfterComp.totalCacheHits) :queries dbAfterComp.queries :providers dbAfterComp.providers) newEntry)) (qRes (QueryResult :status "ok" :value newValue :valueHash newHash :wasRecomputed recomputedFlag :changedEpoch effectiveChangedEpoch))] (pair updatedDb qRes)))))))))

fn executeQuery db: SalsaDatabase key: QueryKey computeFn: (fn [(QueryKey) -> Str]) deps: (List QueryKey) -> (Pair SalsaDatabase QueryResult)
  (let [(adaptedCompute (fn [(d SalsaDatabase) (k QueryKey)] (pair d (computeFn k)))) (dbWithProv (registerQuery db key deps adaptedCompute))] (demandQuery dbWithProv key))

fn cyclesLoop db: SalsaDatabase totalCycles: Int step: Int sym: Str -> SalsaDatabase
  (if (>= step totalCycles) db (let [(tempKey (makeQueryKey (str "TempSymbol_" (stringFromInt64 step)) "parse")) (resPair (executeQuery db tempKey (fn [(k QueryKey)] (str "ast_" k.symbol)) (list))) (dbWithTemp (pairFirst resPair)) (mutKey (makeQueryKey sym "typecheck")) (invDb (invalidateQuery dbWithTemp mutKey)) (evictedDb (evictStaleEpochs invDb))] (cyclesLoop evictedDb totalCycles (+ step 1) sym)))

fn simulateEditCycles db: SalsaDatabase cycles: Int mutatedSymbol: Str -> SalsaDatabase
  (cyclesLoop db cycles 0 mutatedSymbol)
