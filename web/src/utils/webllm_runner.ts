/**
 * In-Browser WebGPU Inference Runner for Eddie
 * Powered by @mlc-ai/web-llm & ASL Anti-Hallucination Harness.
 * 100% Client-side, zero cloud calls, weights cached in IndexedDB.
 */

import { antiHallucinationHarness, FsmRepairReport } from './anti_hallucination';

export interface InBrowserModelSpec {
  id: string;
  name: string;
  mlcModelId: string;
  approxSizeMb: number;
  vramMb: number;
  quantization: string;
  description: string;
}

export const IN_BROWSER_MODELS: InBrowserModelSpec[] = [
  {
    id: 'qwen-coder-0.5b-q4',
    name: 'Qwen 2.5 Coder 0.5B (q4f16_1)',
    mlcModelId: 'Qwen2.5-Coder-0.5B-Instruct-q4f16_1-MLC',
    approxSizeMb: 240,
    vramMb: 945,
    quantization: 'q4f16_1 (4-bit)',
    description: 'Fastest download (~240MB). Low VRAM footprint (945MB). Instant streaming (~55 t/s).'
  },
  {
    id: 'qwen-coder-0.5b-fp16',
    name: 'Qwen 2.5 Coder 0.5B (q0f16 Unquantized FP16)',
    mlcModelId: 'Qwen2.5-Coder-0.5B-Instruct-q0f16-MLC',
    approxSizeMb: 980,
    vramMb: 1624,
    quantization: 'q0f16 (Unquantized FP16)',
    description: 'Full unquantized FP16 weights (~980MB). 100% mathematical precision with zero quantization clipping.'
  },
  {
    id: 'qwen-coder-1.5b-q4',
    name: 'Qwen 2.5 Coder 1.5B (q4f16_1)',
    mlcModelId: 'Qwen2.5-Coder-1.5B-Instruct-q4f16_1-MLC',
    approxSizeMb: 850,
    vramMb: 1630,
    quantization: 'q4f16_1 (4-bit)',
    description: '1.5B parameters (~850MB download, 1.6GB VRAM). Strong reasoning for multi-step logic.'
  },
  {
    id: 'qwen-coder-3b-q4',
    name: 'Qwen 2.5 Coder 3B (q4f16_1)',
    mlcModelId: 'Qwen2.5-Coder-3B-Instruct-q4f16_1-MLC',
    approxSizeMb: 1700,
    vramMb: 2504,
    quantization: 'q4f16_1 (4-bit)',
    description: 'Flagship 3B coding model (~1.7GB download, ~2.5GB VRAM). Exceptional game engine loops and algorithmic depth.'
  }
];

export interface WebLlmProgress {
  progress: number; // 0.0 - 1.0
  text: string;
  isDownloading: boolean;
}

export interface StreamTelemetry {
  tokensGenerated: number;
  tokensPerSec: number;
  elapsedMs: number;
  repairReport: FsmRepairReport | null;
}

class WebLlmRunner {
  private engine: any = null;
  private currentModelId: string | null = null;
  private isInitializing: boolean = false;

  public get loading(): boolean {
    return this.isInitializing;
  }

  public async isWebGpuAvailable(): Promise<boolean> {
    if (typeof navigator === 'undefined' || !(navigator as any).gpu) {
      return false;
    }
    try {
      const adapter = await (navigator as any).gpu.requestAdapter();
      return !!adapter;
    } catch {
      return false;
    }
  }

  public async isModelInCache(modelSpec: InBrowserModelSpec): Promise<boolean> {
    try {
      const webllm = await import('@mlc-ai/web-llm');
      return await webllm.hasModelInCache(modelSpec.mlcModelId);
    } catch {
      return false;
    }
  }

  public async downloadModelOnly(
    modelSpec: InBrowserModelSpec,
    onProgress: (progress: WebLlmProgress) => void
  ): Promise<void> {
    await this.loadModel(modelSpec, onProgress);
  }

  public async loadModel(
    modelSpec: InBrowserModelSpec,
    onProgress: (progress: WebLlmProgress) => void
  ): Promise<void> {
    if (this.engine && this.currentModelId === modelSpec.mlcModelId) {
      onProgress({ progress: 1.0, text: 'Model ready from cache', isDownloading: false });
      return;
    }

    this.isInitializing = true;
    try {
      const webllm = await import('@mlc-ai/web-llm');
      
      this.engine = await webllm.CreateMLCEngine(modelSpec.mlcModelId, {
        initProgressCallback: (report) => {
          onProgress({
            progress: report.progress,
            text: report.text,
            isDownloading: report.progress < 1.0
          });
        }
      });

      this.currentModelId = modelSpec.mlcModelId;
      this.isInitializing = false;
      onProgress({ progress: 1.0, text: 'Model loaded in WebGPU VRAM', isDownloading: false });
    } catch (err: any) {
      this.isInitializing = false;
      throw new Error(`Failed to initialize in-browser WebGPU model: ${err?.message || err}`);
    }
  }

  public async generateStreaming(
    prompt: string,
    systemPrompt: string,
    onToken: (token: string, fullText: string, telemetry: StreamTelemetry) => void,
    onDone: (finalRepairedCode: string, telemetry: StreamTelemetry) => void,
    onError: (err: any) => void
  ): Promise<void> {
    if (!this.engine) {
      onError(new Error('In-browser engine is not loaded.'));
      return;
    }

    try {
      const startTime = performance.now();
      let accumulatedRaw = '';
      let tokenCount = 0;

      const chunks = await this.engine.chat.completions.create({
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: prompt }
        ],
        stream: true,
        temperature: 0.15,
        max_tokens: 3000
      });

      for await (const chunk of chunks) {
        const delta = chunk.choices[0]?.delta?.content || '';
        accumulatedRaw += delta;
        tokenCount++;

        const elapsed = Math.max(1, performance.now() - startTime);
        const tokPerSec = Math.round((tokenCount / (elapsed / 1000)) * 10) / 10;

        onToken(delta, accumulatedRaw, {
          tokensGenerated: tokenCount,
          tokensPerSec: tokPerSec,
          elapsedMs: elapsed,
          repairReport: null
        });
      }

      const totalElapsed = Math.max(1, performance.now() - startTime);
      const finalTokPerSec = Math.round((tokenCount / (totalElapsed / 1000)) * 10) / 10;

      // Pass through the ASL Anti-Hallucination FSM balancer
      const repairReport = antiHallucinationHarness.repairAndNormalize(accumulatedRaw);

      onDone(repairReport.cleanCode, {
        tokensGenerated: tokenCount,
        tokensPerSec: finalTokPerSec,
        elapsedMs: totalElapsed,
        repairReport
      });
    } catch (err) {
      onError(err);
    }
  }

  public unload(): void {
    if (this.engine) {
      this.engine = null;
      this.currentModelId = null;
    }
  }
}

export const webLlmRunner = new WebLlmRunner();
