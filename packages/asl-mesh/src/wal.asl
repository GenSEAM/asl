(module asl-mesh/wal
  :x [WalRecord WalJournal walInit walAppendEntry! walReplayFromIndex walTruncateSuffix! computeWalChecksum walVerifyRecord formatWalRecord]
  :i [(asl-mesh/raft :a raft)])

(schema WalRecord
  (:f index Int64)
  (:f term Int64)
  (:f command String)
  (:f checksum Int64))

(schema WalJournal
  (:f logPath String)
  (:f records (List WalRecord))
  (:f lastAppendedIndex Int64))

fn computeWalChecksum term: Int64 index: Int64 command: String -> Int64
  (let [(sig (str (stringFromInt64 term) ":" (stringFromInt64 index) ":" command))]
    (fnv1a64 sig))

fn walVerifyRecord r: WalRecord -> Bool
  (= r.checksum (computeWalChecksum r.term r.index r.command))

fn formatWalRecord rec: WalRecord -> String
  (str "(:wal-rec :idx " (stringFromInt64 rec.index) " :term " (stringFromInt64 rec.term) " :cmd \"" rec.command "\" :chk " (stringFromInt64 rec.checksum) ")\n")

fn walInit logPath: String -> WalJournal
  (WalJournal :logPath logPath :records (list) :lastAppendedIndex 0)

fn walAppendEntry! journal: WalJournal term: Int64 command: String -> WalJournal
  (let [(nextIndex (+ journal.lastAppendedIndex 1))
        (chk (computeWalChecksum term nextIndex command))
        (rec (WalRecord :index nextIndex :term term :command command :checksum chk))
        (updatedRecords (listAppend journal.records (list rec)))]
    (do
      (if (and (not (stringEmpty? journal.logPath)) (!= journal.logPath ":memory:"))
        (let [(rendered (fold (fn [(acc String) (r WalRecord)] (str acc (formatWalRecord r))) "" updatedRecords))]
          (fileWrite journal.logPath rendered))
        (ok ()))
      (with journal :records updatedRecords :lastAppendedIndex nextIndex)))

fn walReplayFromIndex journal: WalJournal fromIndex: Int64 -> (List WalRecord)
  (filter (fn [(r WalRecord)] (and (>= r.index fromIndex) (walVerifyRecord r))) journal.records)

fn walTruncateSuffix! journal: WalJournal keepUpToIndex: Int64 -> WalJournal
  (let [(filtered (filter (fn [(r WalRecord)] (<= r.index keepUpToIndex)) journal.records))]
    (do
      (if (and (not (stringEmpty? journal.logPath)) (!= journal.logPath ":memory:"))
        (let [(rendered (fold (fn [(acc String) (r WalRecord)] (str acc (formatWalRecord r))) "" filtered))]
          (fileWrite journal.logPath rendered))
        (ok ()))
      (with journal :records filtered :lastAppendedIndex keepUpToIndex)))
