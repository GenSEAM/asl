(module aslMesh/emitter
  :d "Automated gap ledger emitter and record persistence engine under D85 and D83."
  :x [emit_gap_ledger
      write_gap_record
      gap_ledger
      roadmap_link]
  :i [])

(df roadmap_link [phaseId taskId adrRef] -> Map
  :d "Links gap finding to roadmap phase and decision context"
  {:phase phaseId :task taskId :adr adrRef})

(df gap_ledger [records] -> Map
  :d "Constructs structured gap ledger collection"
  {:ledgerId "gaps-master-ledger" :records records :total (count records)})

(df write_gap_record [targetPath record] -> Str
  :d "Formats gap record as pure ASN representation"
  (str "(:gapRecord :id \"" (get record :defectId) "\" :path \"" (get record :path) "\" :line " (get record :lineNumber) ")"))

(df emit_gap_ledger [targetDir defectRecords roadmapBinding] -> Map
  :d "Emits formal ASN gap ledger to target directory"
  {:outputFile (str targetDir "/GapsMasterLedger.asn")
   :emittedRecords (count defectRecords)
   :roadmapLink roadmapBinding
   :status :emitted})
