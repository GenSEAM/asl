(module aslMem/worklist :x [WorklistEntry Worklist makeWorklistEntry worklistCreate worklistCursorNext worklistClaimBatch worklistMarkDone worklistMarkSkipped worklistFindEntry worklistIsComplete? worklistFormatAsn] :i [(asl-text/escape :a esc)])

(schema WorklistEntry (:f path Str) (:f intent Str) (:f status Str) (:f reason Str) (:f notes Str) (:f walkerId Str) (:f timestamp Int))

(schema Worklist (:f id Str) (:f cursor Int) (:f entries (List WorklistEntry)))

fn makeWorklistEntry path: Str intent: Str -> WorklistEntry
  (WorklistEntry :path path :intent intent :status "pending" :reason "" :notes "" :walkerId "" :timestamp 1789280000000)

fn worklistCreate id: Str entries: (List WorklistEntry) -> Worklist
  (Worklist :id id :cursor 0 :entries entries)

fn worklistCursorNext wl: Worklist batchSize: Int -> (Map Str Any)
  (let [(cur wl.cursor) (all wl.entries) (total (listLength all)) (rem (if (>= cur total) 0 (- total cur))) (takeCount (if (<= rem batchSize) rem batchSize)) (endPos (+ cur takeCount)) (batch (if (> takeCount 0) (optionOr (listSlice all cur endPos) (list)) (list))) (updatedWl (with wl :cursor endPos :entries all))] {:batch batch :cursor endPos :hasMore (< endPos total) :worklist updatedWl})

fn worklistClaimBatch wl: Worklist walkerId: Str batchSize: Int -> (Map Str Any)
  (let [(all wl.entries) (pending (filter (fn [(e WorklistEntry)] -> Bool (= e.status "pending")) all)) (pendLen (listLength pending)) (takeN (if (<= pendLen batchSize) pendLen batchSize)) (toClaim (if (> takeN 0) (optionOr (listSlice pending 0 takeN) (list)) (list))) (claimPaths (map (fn [(e WorklistEntry)] -> Str e.path) toClaim)) (updatedEntries (map (fn [(e WorklistEntry)] -> WorklistEntry (if (listContains? claimPaths e.path) (WorklistEntry :path e.path :intent e.intent :status "reading" :reason e.reason :notes e.notes :walkerId walkerId :timestamp 1789280000000) e)) all)) (claimedBatch (filter (fn [(e WorklistEntry)] -> Bool (and (= e.status "reading") (= e.walkerId walkerId))) updatedEntries))] {:claimed claimedBatch :count (listLength claimedBatch) :worklist (with wl :entries updatedEntries)})

fn worklistMarkDone wl: Worklist path: Str notes: Str -> Worklist
  (let [(updatedEntries (map (fn [(e WorklistEntry)] -> WorklistEntry (if (= e.path path) (WorklistEntry :path e.path :intent e.intent :status "done" :reason e.reason :notes notes :walkerId e.walkerId :timestamp 1789280000000) e)) wl.entries))] (with wl :entries updatedEntries))

fn worklistMarkSkipped wl: Worklist path: Str reason: Str -> (Result Worklist Str)
  (if (stringEmpty? (stringTrim reason)) (err "reason string is mandatory for skipped entries") (let [(updatedEntries (map (fn [(e WorklistEntry)] -> WorklistEntry (if (= e.path path) (WorklistEntry :path e.path :intent e.intent :status "skipped" :reason reason :notes e.notes :walkerId e.walkerId :timestamp 1789280000000) e)) wl.entries))] (ok (with wl :entries updatedEntries))))

fn worklistFindEntry wl: Worklist path: Str -> (Option WorklistEntry)
  (let [(matches (filter (fn [(e WorklistEntry)] -> Bool (= e.path path)) wl.entries))] (if (> (listLength matches) 0) (listGet matches 0) (none)))

fn worklistIsComplete? wl: Worklist -> Bool
  (let [(pending (filter (fn [(e WorklistEntry)] -> Bool (or (= e.status "pending") (= e.status "reading"))) wl.entries))] (= (listLength pending) 0))

fn formatEntryAsn e: WorklistEntry -> Str
  (str "    (:entry" " :path \"" (esc/escapeAsnStr e.path) "\"" " :intent \"" (esc/escapeAsnStr e.intent) "\"" " :status :" e.status " :reason \"" (esc/escapeAsnStr e.reason) "\"" " :notes \"" (esc/escapeAsnStr e.notes) "\"" " :walker-id \"" (esc/escapeAsnStr e.walkerId) "\"" " :timestamp " e.timestamp ")")

fn worklistFormatAsn wl: Worklist -> Str
  (let [(entryLines (map formatEntryAsn wl.entries)) (entriesBody (if (= (listLength entryLines) 0) "" (str "\n" (stringJoin entryLines "\n"))))] (str "(:worklist\n" "  :id \"" (esc/escapeAsnStr wl.id) "\"\n" "  :cursor " wl.cursor "\n" "  :entries [" entriesBody "]\n" ")"))
