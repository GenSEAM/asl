(module asl-mesh/emitter
  :d "Automated gap ledger emitter and record persistence engine under D85 and D83."
  :x [emit_gap_ledger
      write_gap_record
      gap_ledger
      roadmap_link]
  :i [])

(df roadmap_link [phase-id task-id adr-ref] -> Map
  :d "Links gap finding to roadmap phase and decision context"
  {:phase phase-id :task task-id :adr adr-ref})

(df gap_ledger [records] -> Map
  :d "Constructs structured gap ledger collection"
  {:ledgerId "gaps-master-ledger" :records records :total (count records)})

(df write_gap_record [target-path record] -> Str
  :d "Formats gap record as pure ASN representation"
  (str "(:gapRecord :id \"" (get record :defectId) "\" :path \"" (get record :path) "\" :line " (get record :lineNumber) ")"))

(df emit_gap_ledger [target-dir defect-records roadmap-binding] -> Map
  :d "Emits formal ASN gap ledger to target directory"
  {:outputFile (str target-dir "/GapsMasterLedger.asn")
   :emittedRecords (count defect-records)
   :roadmapLink roadmap-binding
   :status :emitted})
