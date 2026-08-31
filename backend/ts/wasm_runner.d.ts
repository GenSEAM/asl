/**
 * WASI Preview1 pure in-memory WebAssembly host runner for AgentScript.
 * Zero native dependencies; compatible with both Browser and Node.js environments.
 */
export interface WasmRunOptions {
    args?: string[];
    env?: Record<string, string>;
    stdin?: string | Uint8Array;
    onStdout?: (chunk: string) => void;
    onStderr?: (chunk: string) => void;
}
export interface WasmRunResult {
    stdout: string;
    stderr: string;
    exitCode: number;
    durationMs: number;
}
export interface WasmInstanceHandle {
    instance: WebAssembly.Instance;
    module: WebAssembly.Module;
    memory: WebAssembly.Memory;
    exports: Record<string, any>;
    getStdout: () => string;
    getStderr: () => string;
}
export declare class WasiExit extends Error {
    readonly code: number;
    constructor(code: number);
}
export declare function createWasiImportObject(getMemory: () => WebAssembly.Memory, options?: WasmRunOptions, state?: {
    stdout: string[];
    stderr: string[];
}): Record<string, Function>;
export declare function createWasmInstance(wasmSource: BufferSource | WebAssembly.Module, options?: WasmRunOptions): Promise<WasmInstanceHandle>;
export declare function runWasm(wasmSource: BufferSource | WebAssembly.Module, options?: WasmRunOptions): Promise<WasmRunResult>;
