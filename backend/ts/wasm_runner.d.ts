/**
 * In-memory WASI preview1 host shim and WebAssembly runner.
 *
 * Pure TypeScript/ESM module with zero native/Node-specific dependencies,
 * executing wasm32-wasip1 binaries seamlessly in both Browser and Node.js.
 */
export declare const WASI_ERRNO: {
    readonly SUCCESS: 0;
    readonly E2BIG: 1;
    readonly EACCES: 2;
    readonly EADDRINUSE: 3;
    readonly EADDRNOTAVAIL: 4;
    readonly EAFNOSUPPORT: 5;
    readonly EAGAIN: 6;
    readonly EALREADY: 7;
    readonly EBADF: 8;
    readonly EBADMSG: 9;
    readonly EBUSY: 10;
    readonly ECANCELED: 11;
    readonly ECHILD: 12;
    readonly ECONNABORTED: 13;
    readonly ECONNREFUSED: 14;
    readonly ECONNRESET: 15;
    readonly EDEADLK: 16;
    readonly EDESTADDRREQ: 17;
    readonly EDOM: 18;
    readonly EDQUOT: 19;
    readonly EEXIST: 20;
    readonly EFAULT: 21;
    readonly EFBIG: 22;
    readonly EHOSTUNREACH: 23;
    readonly EIDRM: 24;
    readonly EILSEQ: 25;
    readonly EINPROGRESS: 26;
    readonly EINTR: 27;
    readonly EINVAL: 28;
    readonly EIO: 29;
    readonly EISDIR: 30;
    readonly ELOOP: 31;
    readonly EMFILE: 32;
    readonly EMLINK: 33;
    readonly EMSGSIZE: 34;
    readonly EMULTIHOP: 35;
    readonly ENAMETOOLONG: 36;
    readonly ENETDOWN: 37;
    readonly ENETRESET: 38;
    readonly ENETUNREACH: 39;
    readonly ENFILE: 40;
    readonly ENOBUFS: 41;
    readonly ENODEV: 42;
    readonly ENOENT: 44;
    readonly ENOEXEC: 45;
    readonly ENOLCK: 46;
    readonly ENOLINK: 47;
    readonly ENOMEM: 48;
    readonly ENOMSG: 49;
    readonly ENOPROTOOPT: 50;
    readonly ENOSPC: 51;
    readonly ENOSYS: 52;
    readonly ENOTCONN: 53;
    readonly ENOTDIR: 54;
    readonly ENOTEMPTY: 55;
    readonly ENOTRECOVERABLE: 56;
    readonly ENOTSOCK: 57;
    readonly ENOTSUP: 58;
    readonly ENOTTY: 59;
    readonly ENXIO: 60;
    readonly EOVERFLOW: 61;
    readonly EOWNERDEAD: 62;
    readonly EPERM: 63;
    readonly EPIPE: 64;
    readonly EPROTO: 65;
    readonly EPROTONOSUPPORT: 66;
    readonly EPROTOTYPE: 67;
    readonly ERANGE: 68;
    readonly EROFS: 69;
    readonly ESPIPE: 70;
    readonly ESRCH: 71;
    readonly ESTALE: 72;
    readonly ETIMEDOUT: 73;
    readonly ETXTBSY: 74;
    readonly EXDEV: 75;
    readonly ENOTCAPABLE: 76;
};
export declare class WasiExit extends Error {
    readonly exitCode: number;
    constructor(exitCode: number);
}
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
export interface WasmInstance {
    instance: WebAssembly.Instance;
    module: WebAssembly.Module;
    memory: WebAssembly.Memory | null;
    start: () => number;
    getStdout: () => string;
    getStderr: () => string;
}
export declare function createWasmInstance(wasmSource: BufferSource | WebAssembly.Module, options?: WasmRunOptions): Promise<WasmInstance>;
export declare function runWasm(wasmSource: BufferSource | WebAssembly.Module, options?: WasmRunOptions): Promise<WasmRunResult>;
//# sourceMappingURL=wasm_runner.d.ts.map