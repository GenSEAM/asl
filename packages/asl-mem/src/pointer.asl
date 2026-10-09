(module aslMem/pointer :x [BlobPointer PerceptualFact makeBlobPointer formatPointerToken extractScalarFact formatPerceptualFact formatPointerDescriptor shouldOffload?] :i [])

(schema BlobPointer (:f id Str) (:f kind Str) (:f bytes I64) (:f tokensSaved I64) (:f summary Str))

(schema PerceptualFact (:f key Str) (:f val Str) (:f confidence F64) (:f sourceId Str))

fn makeBlobPointer id: Str kind: Str rawContent: Str summary: Str -> BlobPointer
  (let [(len (stringLength rawContent))] (BlobPointer :id id :kind kind :bytes len :tokensSaved (/ len 4) :summary summary))

fn formatPointerToken ptr: BlobPointer -> Str
  (str "(:ptr :id \"" ptr.id "\" :kind \"" ptr.kind "\" :tokens-saved " (stringFromInt64 ptr.tokensSaved) " :summary \"" ptr.summary "\")")

fn extractScalarFact ptr: BlobPointer key: Str val: Str -> PerceptualFact
  (PerceptualFact :key key :val val :confidence 1.0 :sourceId ptr.id)

fn formatPerceptualFact fact: PerceptualFact -> Str
  (str "(:fact :key \"" fact.key "\" :val \"" fact.val "\" :confidence " (stringFromFloat64 fact.confidence) " :source-id \"" fact.sourceId "\")")

fn formatPointerDescriptor id: Str action: Str bytes: I64 tokensSaved: I64 summary: Str -> Str
  (str "(:ptr :id \"" id "\" :action \"" action "\" :bytes " (stringFromInt64 bytes) " :tokens-saved " (stringFromInt64 tokensSaved) " :summary \"" summary "\")")

fn shouldOffload? bytes: I64 -> Bool
  (> bytes 500)
