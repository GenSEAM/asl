(module asl-web/webllm-runner
  :d "In-Browser WebGPU Inference Runner specification & model registry in pure AgentScript"
  :x [InBrowserModelSpec StreamTelemetry in-browser-models find-model-by-id default-webgpu-model]
  :i [(core/strings :a s)])

(dfs InBrowserModelSpec
  (:f id Str "Unique model identifier")
  (:f name Str "Human-readable display name")
  (:f mlc-id Str "MLC model repository identifier")
  (:f approx-size-mb I64 "Approximate download footprint in MB")
  (:f vram-mb I64 "Allocated WebGPU VRAM in MB")
  (:f quantization Str "Quantization scheme (e.g. q4f16_1)")
  (:f description Str "Architecture notes and performance characteristics")
  (:f supports-thinking Bool "Whether model supports explicit reasoning tags"))

(dfs StreamTelemetry
  (:f tokens-generated I64 "Total generated tokens count")
  (:f tokens-per-sec F64 "Generation speed in tokens per second")
  (:f elapsed-ms I64 "Total elapsed generation time in milliseconds")
  (:f reasoning-text Str "Extracted chain of thought or planning output"))

(df in-browser-models [] -> (List InBrowserModelSpec)
  :d "Returns available client-side WebGPU models"
  [
    (InBrowserModelSpec
      :id "qwen-coder-0.5b-q4"
      :name "Qwen 2.5 Coder 0.5B (q4f16_1)"
      :mlc-id "Qwen2.5-Coder-0.5B-Instruct-q4f16_1-MLC"
      :approx-size-mb 240
      :vram-mb 945
      :quantization "q4f16_1"
      :description "Fastest download (~240MB). Low VRAM footprint (945MB). Instant streaming (~28 t/s)."
      :supports-thinking false)
    (InBrowserModelSpec
      :id "qwen-coder-1.5b-q4"
      :name "Qwen 2.5 Coder 1.5B (q4f16_1)"
      :mlc-id "Qwen2.5-Coder-1.5B-Instruct-q4f16_1-MLC"
      :approx-size-mb 850
      :vram-mb 1630
      :quantization "q4f16_1"
      :description "1.5B parameters (~850MB download, 1.6GB VRAM). Fast responsive coding assistant."
      :supports-thinking false)
    (InBrowserModelSpec
      :id "qwen-coder-3b-q4"
      :name "Qwen 2.5 Coder 3B (q4f16_1)"
      :mlc-id "Qwen2.5-Coder-3B-Instruct-q4f16_1-MLC"
      :approx-size-mb 1700
      :vram-mb 2504
      :quantization "q4f16_1"
      :description "Flagship 3B coding model (~1.7GB download, ~2.5GB VRAM). Exceptional game engine loops and algorithmic depth."
      :supports-thinking false)
  ])

(df default-webgpu-model [] -> Str
  :d "Returns the default WebGPU model id"
  "qwen-coder-0.5b-q4")

(df find-model-by-id [(model-id Str)] -> Str
  :d "Finds model configuration by identifier"
  (if (= model-id "qwen-coder-1.5b-q4")
    "Qwen2.5-Coder-1.5B-Instruct-q4f16_1-MLC"
    (if (= model-id "qwen-coder-3b-q4")
      "Qwen2.5-Coder-3B-Instruct-q4f16_1-MLC"
      "Qwen2.5-Coder-0.5B-Instruct-q4f16_1-MLC")))
