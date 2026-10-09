(module asl-runtime/pipeline
  :x [PipelineStage PipelineContext Pipeline PipelineResult initPipeline addStage stageCount isHealthy initContext initContextWithFlag executePipeline recordLatency getAverageLatencyNs computeThroughput]
  :i [])

(schema PipelineStage
  (:f name Str)
  (:f enabled Bool))

(schema PipelineContext
  (:f payload Str)
  (:f stepIndex Int64)
  (:f valid Bool))

(schema Pipeline
  (:f name Str)
  (:f stages (List PipelineStage))
  (:f stageCount Int64)
  (:f totalLatencyNs Int64)
  (:f totalItems Int64)
  (:f healthy Bool))

(schema PipelineResult
  (:f context PipelineContext)
  (:f success Bool)
  (:f hasError Bool))

fn initPipeline name: Str -> Pipeline
  (Pipeline
    :name name
    :stages (list)
    :stageCount 0
    :totalLatencyNs 0
    :totalItems 0
    :healthy true)

fn addStage p: Pipeline stageName: Str enabled: Bool -> Pipeline
  (let [(stg (PipelineStage :name stageName :enabled enabled))]
    (with p :stages (listAppend p.stages (list stg)) :stageCount (if enabled (+ p.stageCount 1) p.stageCount)))

fn stageCount p: Pipeline -> Int64
  p.stageCount

fn isHealthy p: Pipeline -> Bool
  p.healthy

fn initContext payload: Str stepIndex: Int64 -> PipelineContext
  (PipelineContext
    :payload payload
    :stepIndex stepIndex
    :valid true)

fn initContextWithFlag payload: Str stepIndex: Int64 valid: Bool -> PipelineContext
  (PipelineContext
    :payload payload
    :stepIndex stepIndex
    :valid valid)

fn executePipeline p: Pipeline ctx: PipelineContext -> PipelineResult
  (if (or (not ctx.valid) (not p.healthy))
    (PipelineResult
      :context ctx
      :success false
      :hasError true)
    (let [(newIndex (+ ctx.stepIndex p.stageCount))
          (updatedCtx (with ctx :stepIndex newIndex :valid true))]
      (PipelineResult
        :context updatedCtx
        :success true
        :hasError false)))

fn recordLatency p: Pipeline latencyNs: Int64 items: Int64 -> Pipeline
  (let [(safeItems (if (<= items 0) 1 items))]
    (with p :totalLatencyNs (+ p.totalLatencyNs latencyNs) :totalItems (+ p.totalItems safeItems)))

fn getAverageLatencyNs p: Pipeline -> Int64
  (if (<= p.totalItems 0)
    0
    (/ p.totalLatencyNs p.totalItems))

fn computeThroughput p: Pipeline windowNs: Int64 -> Float
  (if (<= windowNs 0)
    0.0
    (let [(itemF (int64ToFloat64 p.totalItems))
          (winSec (/ (int64ToFloat64 windowNs) 1000000000.0))]
      (if (<= winSec 0.0) 0.0 (/ itemF winSec))))
