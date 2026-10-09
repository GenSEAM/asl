(module aslContracts/stage :x [PipelineStage StageStatus StageContract makeStageContract stageTransition stageSetOutput stageSetError isStageTerminal? isStageSuccessful? validateStageContract] :i [])

(enum PipelineStage (:c stageScript [] "Script generation and topic breakdown stage") (:c stageAudio [] "Voiceover synthesis and audio alignment stage") (:c stageVisuals [] "Asset sourcing, image generation and captioning stage") (:c stageRender [] "Video composition and rendering stage") (:c stagePublish [] "Distribution and publishing stage"))

(enum StageStatus (:c statusPending [] "Stage is queued awaiting preconditions") (:c statusRunning [] "Stage is currently executing") (:c statusCompleted [] "Stage completed successfully") (:c statusFailed [] "Stage execution failed with an error"))

(schema StageContract (:f id Str) (:f stage PipelineStage) (:f status StageStatus) (:f inputs (Map Str Str)) (:f outputs (Map Str Str)) (:f errorMsg Str))

fn makeStageContract id: Str stage: PipelineStage -> StageContract
  (StageContract :id id :stage stage :status (statusPending) :inputs (mapEmpty) :outputs (mapEmpty) :errorMsg "")

fn stageTransition contract: StageContract newStatus: StageStatus -> StageContract
  (do (assert (not (isStageTerminal? contract.status)) "Cannot transition from a terminal state") (assert (mt newStatus ((statusFailed) (> (stringLength contract.errorMsg) 0)) (_ true)) "Failed status requires non-empty errorMsg") (with contract :status newStatus :errorMsg (mt newStatus ((statusCompleted) "") (_ contract.errorMsg))))

fn stageSetOutput contract: StageContract key: Str val: Str -> StageContract
  (do (assert (not (isStageTerminal? contract.status)) "Cannot mutate terminal contract") (with contract :outputs (mapSet contract.outputs key val)))

fn stageSetError contract: StageContract err: Str -> StageContract
  (do (assert (not (isStageTerminal? contract.status)) "Cannot mutate terminal contract") (assert (> (stringLength err) 0) "Error string cannot be empty") (with contract :status (statusFailed) :errorMsg err))

fn isStageTerminal? status: StageStatus -> Bool
  (mt status ((statusCompleted) true) ((statusFailed) true) ((statusPending) false) ((statusRunning) false))

fn isStageSuccessful? contract: StageContract -> Bool
  (mt contract.status ((statusCompleted) (stringEmpty? contract.errorMsg)) ((statusPending) false) ((statusRunning) false) ((statusFailed) false))

fn validateStageContract contract: StageContract -> Bool
  (and (not (stringEmpty? contract.id)) (mt contract.status ((statusFailed) (not (stringEmpty? contract.errorMsg))) ((statusCompleted) (stringEmpty? contract.errorMsg)) ((statusPending) true) ((statusRunning) true)))
