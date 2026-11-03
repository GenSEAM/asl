(module asl-mesh/emitter :x [emitGapLedger writeGapRecord gapLedger roadmapLink] :i [])

; (:m :ref BASE-CHECK-DRIFT :do "field access needs a record type the checker can see: a gap record is a GapRecord, and the literal {:defectId .. :path .. :lineNumber ..} callers pass is one")
(schema GapRecord
  (:f defectId String)
  (:f path String)
  (:f lineNumber Int64))

fn roadmapLink phaseId: Any taskId: Any adrRef: Any -> Map
  (do {:phase phaseId :task taskId :adr adrRef})

fn gapLedger records: Any -> Map
  (do {:ledgerId "gaps-master-ledger" :records records :total (listLength records)})

fn writeGapRecord targetPath: Any record: GapRecord -> Str
  (str "(:gapRecord :id \"" record.defectId "\" :path \"" record.path "\" :line " record.lineNumber ")")

fn emitGapLedger targetDir: Any defectRecords: Any roadmapBinding: Any -> Map
  (do {:outputFile (str targetDir "/GapsMasterLedger.asn") :emittedRecords (listLength defectRecords) :roadmapLink roadmapBinding :status :emitted})
