# asl-modal

Runs a self-hosted coder model on Modal as a gateway provider. The default preset is Bonsai 2: `prism-ml/Ternary-Bonsai-2-27B-gguf`, a ternary Qwen3.8-27B.

- `presets/*.asn`: the one place every version is pinned. `bonsai2.asn` is the default (PrismML llama.cpp fork). `bonsai2Vllm.asn` uses the community vLLM port.
- `src/modal.asl`: the ASL driver. It:
  - parses and validates a preset, with typed errors;
  - renders the `modal` command lines and the gateway entry;
  - builds the `aslGateway/plugin` record (`modalPlugin!`): capabilities, an OpenAI-compatible row, and a lifecycle whose spending ops the contract gates;
  - speaks the endpoint contract (`modalChat!`).
- `app.py`: the Modal-side app (Modal Python SDK), the one foreign edge the principal accepted.
  - No `.py` is tracked: its source is ASL data (`modalAppLines` in `src/modal.asl`). `app`, `deploy` and `prepare` render it to `~/.asl/run/modal/<app>-<tier>/app.py`.
  - It reads the same preset file and serves an OpenAI-compatible `/v1/chat/completions`.
  - `python3 app.py --settings PRESET TIER` prints what it derives without importing modal. The test renders it to a temp dir, runs `ast.parse` and `py_compile` on it, and checks that `--settings` equals `modalAppSettings`.
- `tests/modalTest.asl`: the gate. Nothing in it runs `modal`.

## Pins (one file)

| Pin | Preset key | Value | Why |
|---|---|---|---|
| Modal client | `:modalVersion` | `1.6.1` | Latest on PyPI (uploaded 2026-10-03). Commands run `uvx --from modal==1.6.1 modal`, and `app.py` refuses any other client version. |
| Image base | `:baseImage` | `nvidia/cuda:12.8.1-devel-ubuntu24.04` | The fork must be compiled with nvcc, and CUDA 13.3 builds crash (KNOWN_ISSUES #222). |
| Python | `:python` | `3.12` | Required by the vLLM port. |
| Engine | `:engineRef` | `prism-b10743-adfffbe` (commit `adfffbe41b2c`) or bonsai2-vllm `62cd607b` | Fork: the release Bonsai-demo pins. Port: its HEAD on 2026-10-01. |
| pip packages | `:packages`, `:preparePackages` | `vllm==0.26.0 torch==2.11.0 transformers==5.17.0`, `huggingface_hub==2.1.1` | `name==version` only. vllm 0.26.0 itself requires `torch==2.11.0`. |
| Weights | `:revision` | `b072e1d3b35a…` | HF commit, last modified 2026-09-25. |
| Tokenizer (vLLM) | `:tokenizerRevision` | `Qwen/Qwen3.8-27B@1d4bf0f2` | The GGUF repo has no `config.json`. |

`apt` packages (`git`, `cmake`, `build-essential`) come from the pinned Ubuntu base without version pins.

## Container design: one image per engine, not one for all

A preset selects one engine, and `app.py` builds only that engine's image:

- **prismLlamaCpp**: `from_registry(cuda devel)`, then the fork is compiled for the preset's `:cudaArch`, building only `llama-server`.
  - The fork tracks upstream llama.cpp; tags are `prism-b<upstream build>`.
  - So this image serves Bonsai's PTQ1_0/PQ2_0 and any stock GGUF model. Another model is a new preset (repo, revision, file, sampling, ladder) on the same image.
- **vllmBonsai**: the pinned vllm/torch wheels, plus the port at its commit.

Why not one shared image:
- The two engines share nothing but CUDA.
- One image would carry torch, vLLM and flashinfer (several GB) plus a CUDA toolchain into every cold start.
- Each engine would rebuild whenever the other's pin moved.

With one image per engine, Modal caches each engine's layers, and the presets choose which one to build.

The rest of the design:
- **Weights** go in a Modal Volume (`:volume`), filled once by `prepare`. They are not baked into the image, so the image does not grow by 6-7 GB, and changing a weight file does not rebuild it.
- **The preset file** is mounted into the container at `/asl/preset.asn`, so the container reads the same pins.
- **Per-tier weight file.** The model card says PTQ1_0 is faster on Ada and smaller parts but slower on Ampere and later. On A100, PQ2_0 measures 73.9 tok/s against 54.7 for PTQ1_0, so the A10 and A100 tiers override `:weightFile` with PQ2_0.
- **Snapshots.** `enable_memory_snapshot` and `experimental_options={"enable_gpu_snapshot": True}` are set, with the engine started in `@modal.enter(snap=True)`. For vLLM, the engine sleeps (`/sleep?level=1`) before the snapshot and wakes (`/wake_up`) after restore, which is Modal's own vLLM snapshot pattern.

## Spend gate

`modal deploy`, `modal run` and `modal serve` start containers and cost money.
- The CLI only prints these commands.
- The plugin's lifecycle runs only through the contract (`aslGateway/plugin`), which gates the ops that spend:
  - **deploy**: `pluginDeploy!` checks `budget/actionDeploy` against the endpoint. Without a ledger, or on a deny, it returns `spendGate` and the Modal fn never runs. The Modal fn renders `app.py`, runs the pinned deploy and reports `cold`.
  - **start**: `pluginStart!` checks `actionScaleUp` with the request's work `:unit` and `:expectedCost`. `modalLifecycleRequest` fills the cost with `modalStartCost` = price x (coldStartMs + scaledownSec), in micro-USD, the unit `budget.asl` adopts. The fn probes `/health`: 200 is `warm`, anything else `warming`.
  - **stop** and **status** are not gated. Stop runs `modal app stop` and reports `down`.
  - **status** maps `modal app list --json` (keys `description`, `state`, `tasks` in modal 1.6.1 `cli/app.py`) to a state:

    | `modal app list` | State |
    |---|---|
    | no row | `down` |
    | `stopped` / `disabled` | `down` |
    | `stopping...` | `draining` |
    | `initializing...` | `warming` |
    | deployed, 0 tasks | `cold` |
    | deployed, tasks running | `warm` |
- Each fn refuses a request whose endpoint, `:gpu` tier, model or `:version` (`modal==<v> <engine>@<ref>`) is not this plugin's.
- No credential is read or printed. The endpoint key lives in the Modal Secret `:secret`; locally it is the environment variable `:keyEnv`.

Deploying the L4 tier is one line, run from the repo root after the principal's yes. The secret must exist first: `modal secret create asl-modal-key ASL_MODAL_API_KEY=...`. The `$(...)` part renders `app.py` and spends nothing.

```sh
A=$(asl/host/out/asl-host run asl/packages/asl-modal/src/modal.asl app asl/packages/asl-modal/presets/bonsai2.asn L4) && env ASL_MODAL_PRESET=asl/packages/asl-modal/presets/bonsai2.asn ASL_MODAL_TIER=L4 uvx --from modal==1.6.1 modal run "$A::prepare" && env ASL_MODAL_PRESET=asl/packages/asl-modal/presets/bonsai2.asn ASL_MODAL_TIER=L4 uvx --from modal==1.6.1 modal deploy "$A"
```

```sh
H=asl/host/out/asl-host; M=asl/packages/asl-modal/src/modal.asl; P=asl/packages/asl-modal/presets/bonsai2.asn
$H run $M app|prepare|deploy|stop|status|settings|capability $P L4   # app/prepare/deploy render app.py first
$H run $M gateway $P L4 WORKSPACE   # (:provider ...) (:model ...) for ~/.asl/gateway.asn
```

## Runbook (L4, from the repo root)

Only steps 4, 5 and 6 touch Modal. Steps 4 and 5 spend money and wait for the principal's yes. The shell variables are set once:

```sh
H=asl/host/out/asl-host; M=asl/packages/asl-modal/src/modal.asl; P=asl/packages/asl-modal/presets/bonsai2.asn
MODAL="uvx --from modal==1.6.1 modal"
```

1. **Secret** (free). Create the endpoint key once. The gateway sends the same value from `ASL_MODAL_API_KEY`:

   ```sh
   export ASL_MODAL_API_KEY=$(openssl rand -hex 32)
   $MODAL secret create asl-modal-key ASL_MODAL_API_KEY="$ASL_MODAL_API_KEY"
   ```

2. **Gateway config** (free, prints only). CAP is the daily budget for the endpoint, in micro-USD (1000000 = $1). The output is one `(:gatewayAdditions ...)` form. Merge each of these into `~/.asl/gateway.asn` by hand:
   - its `:providers` and `:models` rows;
   - its `:endpoints` row;
   - its `:budget` line and the `(:approval ...)` for the same endpoint and cap.

   The CLI never writes `~/.asl`.

   ```sh
   $H run $M config $P L4 WORKSPACE 2000000
   ```

3. **Render** (free). Each command renders `~/.asl/run/modal/asl-bonsai2-l4/app.py` and prints the exact Modal command for that step:

   ```sh
   $H run $M prepare $P L4
   $H run $M deploy $P L4
   ```

4. **Prepare and deploy** (spends money). Prepare downloads the weights into the Volume. Deploy creates the app, which scales to zero while idle:

   ```sh
   A=$($H run $M app $P L4)
   env ASL_MODAL_PRESET=$P ASL_MODAL_TIER=L4 $MODAL run "$A::prepare"
   env ASL_MODAL_PRESET=$P ASL_MODAL_TIER=L4 $MODAL deploy "$A"
   ```

5. **Smoke** (spends money). Start the gateway with the step 2 config, then run smoke against it:
   - It refuses without `--yes`.
   - It refuses without `--cap`, or when the worst case exceeds the cap. The L4 worst case is 320124 µ$ = price x (startupSec + 2 x 120 s chat + scaledownSec).
   - It needs `ASL_GATEWAY_KEY` when the gateway requires a key.

   What it measures:
   - **Cold start**: from status `cold` to the first 200 on `/health`.
   - **First token**: the time for one 1-token chat sent through the gateway.
   - **Throughput**: tokens per second from one 256-token chat.

   It prints `(:modalSmoke :endpoint E :wasCold B :coldStartMs N :firstTokenMs N :tokS X.Y :completionTokens N :costMicroUsd N :capMicroUsd C)`. When the endpoint was already warm, `:coldStartMs` is -1. `:costMicroUsd` is the GPU price over elapsed time plus the scaledown window.

   ```sh
   $H run $M smoke $P L4 WORKSPACE http://127.0.0.1:PORT/v1 --cap 400000 --yes
   ```

6. **Stop** (ends spend). After stopping, `status` prints `down`:

   ```sh
   $H run $M stop $P L4      # prints the command; run it:
   $MODAL app stop --yes asl-bonsai2-l4
   $H run $M status $P L4
   ```

## Cost (Modal pricing page https://modal.com/pricing, read 2026-10-08)

GPU prices per second:

| Tier | $/s | µ$/s in preset |
|---|---|---|
| T4 | 0.000164 | 164 |
| L4 | 0.000222 | 222 |
| A10 | 0.000306 | 306 |
| L40S | 0.000542 | 542 |
| A100 40GB | 0.000583 | 583 |
| A100 80GB | 0.000694 | 694 |
| RTX PRO 6000 | 0.000842 | 842 |

Other charges and credits:
- CPU: $0.0000131 per core per second.
- Memory: $0.00000222 per GiB per second.
- Egress: $0.04 per GiB.
- The Starter plan includes $30 a month of free credits.

Estimate for L4 (assumed, not measured: about 1 core and 8 GiB alongside the GPU):
- Rate: about $0.000253/s, which is about $0.91 per busy hour.
- Idle: $0, since `min_containers=0` and `scaledown_window=2`.
- One start: about 92 s, which is about $0.023. The 90 s is the adopted `:coldStartMs`, not a measurement.
- One 16384-token reasoning reply at batch 1 (32.1 tok/s): about 510 s, which is about $0.13.
- With 4 slots: the same 510 s is shared by up to 4 replies, but per-slot speed at batch 4 is not measured.

## Claims and sources (read 2026-10-08)

| Claim | Source | Status |
|---|---|---|
| PTQ1_0 5.95 GB, PQ2_0 7.21 GB, 262K context, Apache-2.0 | https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf (README at `b072e1d3`) | verified |
| tg128 tok/s PTQ1_0 / PQ2_0: 4090 91.1/81.2, L40S 81.8/74.4, A100 SXM 54.7/73.9, L4 32.1/29.8, H100 86.9/113.9 | same README, throughput table | verified |
| "Stock llama.cpp will not run these files"; the PrismML-Eng/llama.cpp fork is required | same README | verified |
| Thinking sampling temp 1.0, top_p 0.95, top_k 20, min_p 0.05; default effort `xhigh`; run with `-n 16384` | same README; KNOWN_ISSUES (`-n 16384` with `-c 65536`) | verified; preset `:maxTokens 16384` |
| CUDA source builds need `-DCMAKE_CUDA_ARCHITECTURES` (#182); CUDA 13.3 builds crash, use 12.8 (#222) | https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/blob/b072e1d3/KNOWN_ISSUES.md | verified |
| The server splits its cache across slots | KNOWN_ISSUES (Bonsai-demo #183) | verified; app passes `-c contextTokens*maxConcurrency -np maxConcurrency` |
| Bonsai-demo pins `prism-b10743-adfffbe`; newest fork release is `prism-b10754-2459f68` (2026-10-02), with Linux CUDA 12.4/12.8/13.3 binaries | https://github.com/PrismML-Eng/Bonsai-demo, https://github.com/PrismML-Eng/llama.cpp/releases | verified |
| vLLM port: Python 3.12, torch 2.11, vLLM 0.26, transformers 5.17; `requirements.txt` pins `vllm==0.26.0`; tested on RTX PRO 6000 96 GB | https://github.com/shtjww/bonsai2-vllm (commit `62cd607b`, 2026-10-01) | verified |
| Port at 16-way 759 tok/s against the fork's 293; at 32-way 890 against 355; batch 1 90.6 tok/s | same README | verified; one machine (RTX PRO 6000) |
| `--from-safetensors` cuts startup from about 7 min to about 2 min; `max_tokens >= 8192` | same README | verified (README); the 8192 floor in the validator |
| `serve_bonsai.py` fixes `--served-model-name bonsai2-27b` and `--max-num-seqs 256`, and `--ternary` loads `Ternary-Bonsai-2-27B-PTQ1_0.gguf` by name | `vllm_bonsai/serve_bonsai.py` at `62cd607b` | verified; enforced by the validator |
| vLLM 0.26.0 reads `VLLM_API_KEY` when `--api-key` is absent | `vllm/entrypoints/openai/api_server.py` at v0.26.0, line 306 | verified |
| SDK 1.6.1 `App.cls` takes gpu, scaledown_window (> 0), timeout, startup_timeout, min/max_containers, enable_memory_snapshot, experimental_options; `web_server(port, startup_timeout, label)`; `enter(snap=)`; `concurrent(max_inputs=)` | modal-1.6.1 wheel source; `app.py` imported under modal 1.6.1 (no deploy) | verified |
| GPU snapshots: `enable_memory_snapshot=True` plus `experimental_options={"enable_gpu_snapshot": True}`; alpha; no help when weight loading dominates | https://modal.com/docs/guide/memory-snapshot | verified |
| Modal snapshots a vLLM subprocess, put to sleep before the snapshot and woken after | https://modal.com/docs/examples/vllm_snapshot | verified (Modal's example, vLLM 0.13) |
| Web endpoints, `web_server` included, cap a request at 150 s, then answer 303 to a result URL | https://modal.com/docs/guide/webhook-timeouts | verified; the driver types it as `endpointRedirect` |

## Unverified (check on the first deploy)

- **GPU snapshot of llama-server.** It is a subprocess holding a CUDA context. Modal shows the pattern only for vLLM.
- **Sleep mode in the vLLM port.** Sleep and wake are untested with the port's custom `TernaryHadamardLinear` weights.
- **vLLM port coverage.** The port is unmeasured on any tier in its ladder (L40S, A100-80GB, RTX PRO 6000). The base-model tokenizer and config are an inference.
- **Cold start.** `:coldStartMs` is an adopted planning value (90 s for the fork, 150 s for the port). The first deploy measures it.
- **Fork kernels.** T4 (sm75) and A10 have no published throughput.
- **KV fit.** Whether `-c 32768 x np` fits in VRAM for every tier is not measured; the model is hybrid with about 75% linear attention.
- **Budget lines.** With no budget lines, `budget.gate` allows a paid deploy. The Modal plugin needs one line per endpoint (`asl-<app>-<tier>`) with an approval, otherwise deploy and start are not capped. Routed to GWWIRE/GWBUDGET.
- **Long replies against the 150 s limit.** A reply longer than 150 s returns 303. The gateway transport must follow it, and streaming behaviour under the limit is undocumented.
- **Secrets during snapshots.** It is not confirmed that the Modal Secret's environment is present during `snap=True` enter. The API key passed to the engine is then part of the snapshot.
