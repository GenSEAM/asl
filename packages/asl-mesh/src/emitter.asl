(module aslMesh/emitter
  :d "Automated gap ledger emitter and record persistence engine under D85 and D83."
  :x [emitGapLedger
      writeGapRecord
      gapLedger
      roadmapLink]
  :i [])

(df roadmapLink [phaseId taskId adrRef] -> Map
  :d "Links gap finding to roadmap phase and decision context"
  {:phase phaseId :task taskId :adr adrRef})

(df gapLedger [records] -> Map
  :d "Constructs structured gap ledger collection"
  {:ledgerId "gaps-master-ledger" :records records :total (count records)})

(df writeGapRecord [targetPath record] -> Str
  :d "Formats gap record as pure ASN representation"
  (str "(:gapRecord :id \"" (get record :defectId) "\" :path \"" (get record :path) "\" :line " (get record :lineNumber) ")"))

(df emitGapLedger [targetDir defectRecords roadmapBinding] -> Map
  :d "Emits formal ASN gap ledger to target directory"
  {:outputFile (str targetDir "/GapsMasterLedger.asn")
   :emittedRecords (count defectRecords)
   :roadmapLink roadmapBinding
   :status :emitted})
