(module aslHarness/containerBench :x [ContainerConfig ContainerRunResult makeContainerConfig evaluateContainerRun formatContainerReceipt isLocalExecution?] :i [])

(schema ContainerConfig (:f target Str) (:f model Str) (:f timeoutSec I64) (:f airgap Bool) (:f platform Str))

(schema ContainerRunResult (:f config ContainerConfig) (:f taskId Str) (:f exitCode I64) (:f durationMs I64) (:f turns I64) (:f tokenSavings F64) (:f passed Bool))

fn makeContainerConfig target: Any model: Str timeoutSec: I64 airgap: Bool -> ContainerConfig
  (let [(s (str target)) (tStr (if (or (= s ":docker") (= s "docker")) "docker" "modal")) (plat (if (= tStr "docker") "arm64" "x86_64"))] (ContainerConfig :target tStr :model model :timeoutSec timeoutSec :airgap airgap :platform plat))

fn isLocalExecution? cfg: ContainerConfig -> Bool
  (= cfg.target "docker")

fn evaluateContainerRun cfg: ContainerConfig taskId: Str exitCode: I64 durationMs: I64 turns: I64 tokenSavings: F64 passed: Bool -> ContainerRunResult
  (let [(okRun (and (= exitCode 0) passed))] (ContainerRunResult :config cfg :taskId taskId :exitCode exitCode :durationMs durationMs :turns turns :tokenSavings tokenSavings :passed okRun))

fn formatContainerReceipt res: ContainerRunResult -> Str
  (let [(cfg res.config) (tgt cfg.target) (status (if res.passed ":verified" ":failed"))] (str "(:container-receipt :task-id \"" res.taskId "\" :target :" tgt " :platform \"" cfg.platform "\" :status " status " :exit-code " (stringFromInt64 res.exitCode) " :duration-ms " (stringFromInt64 res.durationMs) " :turns " (stringFromInt64 res.turns) " :token-savings-pct " (stringFromFloat64 res.tokenSavings) ")"))
