/**
 * In-memory WASI preview1 host shim and WebAssembly runner.
 *
 * Pure TypeScript/ESM module with zero native/Node-specific dependencies,
 * executing wasm32-wasip1 binaries seamlessly in both Browser and Node.js.
 */

export const WASI_ERRNO = {
  SUCCESS: 0,
  E2BIG: 1,
  EACCES: 2,
  EADDRINUSE: 3,
  EADDRNOTAVAIL: 4,
  EAFNOSUPPORT: 5,
  EAGAIN: 6,
  EALREADY: 7,
  EBADF: 8,
  EBADMSG: 9,
  EBUSY: 10,
  ECANCELED: 11,
  ECHILD: 12,
  ECONNABORTED: 13,
  ECONNREFUSED: 14,
  ECONNRESET: 15,
  EDEADLK: 16,
  EDESTADDRREQ: 17,
  EDOM: 18,
  EDQUOT: 19,
  EEXIST: 20,
  EFAULT: 21,
  EFBIG: 22,
  EHOSTUNREACH: 23,
  EIDRM: 24,
  EILSEQ: 25,
  EINPROGRESS: 26,
  EINTR: 27,
  EINVAL: 28,
  EIO: 29,
  EISDIR: 30,
  ELOOP: 31,
  EMFILE: 32,
  EMLINK: 33,
  EMSGSIZE: 34,
  EMULTIHOP: 35,
  ENAMETOOLONG: 36,
  ENETDOWN: 37,
  ENETRESET: 38,
  ENETUNREACH: 39,
  ENFILE: 40,
  ENOBUFS: 41,
  ENODEV: 42,
  ENOENT: 44,
  ENOEXEC: 45,
  ENOLCK: 46,
  ENOLINK: 47,
  ENOMEM: 48,
  ENOMSG: 49,
  ENOPROTOOPT: 50,
  ENOSPC: 51,
  ENOSYS: 52,
  ENOTCONN: 53,
  ENOTDIR: 54,
  ENOTEMPTY: 55,
  ENOTRECOVERABLE: 56,
  ENOTSOCK: 57,
  ENOTSUP: 58,
  ENOTTY: 59,
  ENXIO: 60,
  EOVERFLOW: 61,
  EOWNERDEAD: 62,
  EPERM: 63,
  EPIPE: 64,
  EPROTO: 65,
  EPROTONOSUPPORT: 66,
  EPROTOTYPE: 67,
  ERANGE: 68,
  EROFS: 69,
  ESPIPE: 70,
  ESRCH: 71,
  ESTALE: 72,
  ETIMEDOUT: 73,
  ETXTBSY: 74,
  EXDEV: 75,
  ENOTCAPABLE: 76,
} as const;

export class WasiExit extends Error {
  readonly exitCode: number;

  constructor(exitCode: number) {
    super(`WASI proc_exit called with code ${exitCode}`);
    this.name = "WasiExit";
    this.exitCode = exitCode;
  }
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

export async function createWasmInstance(
  wasmSource: BufferSource | WebAssembly.Module,
  options: WasmRunOptions = {}
): Promise<WasmInstance> {
  const args = options.args ?? ["main"];
  const env = options.env ?? {};
  let stdinBytes: Uint8Array;
  if (typeof options.stdin === "string") {
    stdinBytes = new TextEncoder().encode(options.stdin);
  } else if (options.stdin instanceof Uint8Array) {
    stdinBytes = options.stdin;
  } else {
    stdinBytes = new Uint8Array(0);
  }

  let stdinOffset = 0;
  const stdoutChunks: string[] = [];
  const stderrChunks: string[] = [];
  const textDecoder = new TextDecoder("utf-8");
  const textEncoder = new TextEncoder();

  let memoryInstance: WebAssembly.Memory | null = null;

  function getMemoryView(): { view: DataView; u8: Uint8Array } {
    if (!memoryInstance) {
      throw new Error("Wasm memory is not bound or initialized");
    }
    return {
      view: new DataView(memoryInstance.buffer),
      u8: new Uint8Array(memoryInstance.buffer),
    };
  }

  const wasiSnapshotPreview1 = {
    args_sizes_get(argc_ptr: number, argv_buf_size_ptr: number): number {
      const { view } = getMemoryView();
      const encodedArgs = args.map((a) => textEncoder.encode(a));
      const argc = encodedArgs.length;
      let argv_buf_size = 0;
      for (const ea of encodedArgs) {
        argv_buf_size += ea.byteLength + 1;
      }
      view.setUint32(argc_ptr, argc, true);
      view.setUint32(argv_buf_size_ptr, argv_buf_size, true);
      return WASI_ERRNO.SUCCESS;
    },

    args_get(argv_ptr: number, argv_buf_ptr: number): number {
      const { view, u8 } = getMemoryView();
      const encodedArgs = args.map((a) => textEncoder.encode(a));
      let currentBuf = argv_buf_ptr;
      let currentArgv = argv_ptr;
      for (const ea of encodedArgs) {
        view.setUint32(currentArgv, currentBuf, true);
        currentArgv += 4;
        u8.set(ea, currentBuf);
        u8[currentBuf + ea.byteLength] = 0;
        currentBuf += ea.byteLength + 1;
      }
      return WASI_ERRNO.SUCCESS;
    },

    environ_sizes_get(environc_ptr: number, environ_buf_size_ptr: number): number {
      const { view } = getMemoryView();
      const entries = Object.entries(env).map(([k, v]) => `${k}=${v}`);
      const encodedEntries = entries.map((e) => textEncoder.encode(e));
      const environc = encodedEntries.length;
      let environ_buf_size = 0;
      for (const ee of encodedEntries) {
        environ_buf_size += ee.byteLength + 1;
      }
      view.setUint32(environc_ptr, environc, true);
      view.setUint32(environ_buf_size_ptr, environ_buf_size, true);
      return WASI_ERRNO.SUCCESS;
    },

    environ_get(environ_ptr: number, environ_buf_ptr: number): number {
      const { view, u8 } = getMemoryView();
      const entries = Object.entries(env).map(([k, v]) => `${k}=${v}`);
      const encodedEntries = entries.map((e) => textEncoder.encode(e));
      let currentBuf = environ_buf_ptr;
      let currentEnviron = environ_ptr;
      for (const ee of encodedEntries) {
        view.setUint32(currentEnviron, currentBuf, true);
        currentEnviron += 4;
        u8.set(ee, currentBuf);
        u8[currentBuf + ee.byteLength] = 0;
        currentBuf += ee.byteLength + 1;
      }
      return WASI_ERRNO.SUCCESS;
    },

    fd_write(fd: number, iovs: number, iovs_len: number, nwritten: number): number {
      const { view, u8 } = getMemoryView();
      let totalWritten = 0;
      for (let i = 0; i < iovs_len; i++) {
        const iovOffset = iovs + i * 8;
        const ptr = view.getUint32(iovOffset, true);
        const len = view.getUint32(iovOffset + 4, true);
        if (len === 0) continue;
        const slice = u8.subarray(ptr, ptr + len);
        const chunk = textDecoder.decode(slice);
        if (fd === 1) {
          stdoutChunks.push(chunk);
          options.onStdout?.(chunk);
          totalWritten += len;
        } else if (fd === 2) {
          stderrChunks.push(chunk);
          options.onStderr?.(chunk);
          totalWritten += len;
        } else {
          return WASI_ERRNO.EBADF;
        }
      }
      view.setUint32(nwritten, totalWritten, true);
      return WASI_ERRNO.SUCCESS;
    },

    fd_read(fd: number, iovs: number, iovs_len: number, nread: number): number {
      const { view, u8 } = getMemoryView();
      if (fd !== 0) {
        return WASI_ERRNO.EBADF;
      }
      let totalRead = 0;
      for (let i = 0; i < iovs_len; i++) {
        const iovOffset = iovs + i * 8;
        const ptr = view.getUint32(iovOffset, true);
        const len = view.getUint32(iovOffset + 4, true);
        if (len === 0) continue;
        const available = stdinBytes.byteLength - stdinOffset;
        if (available <= 0) {
          break;
        }
        const toRead = Math.min(len, available);
        u8.set(stdinBytes.subarray(stdinOffset, stdinOffset + toRead), ptr);
        stdinOffset += toRead;
        totalRead += toRead;
      }
      view.setUint32(nread, totalRead, true);
      return WASI_ERRNO.SUCCESS;
    },

    fd_close(fd: number): number {
      if (fd === 0 || fd === 1 || fd === 2) {
        return WASI_ERRNO.SUCCESS;
      }
      return WASI_ERRNO.EBADF;
    },

    fd_fdstat_get(fd: number, stat_ptr: number): number {
      const { view, u8 } = getMemoryView();
      if (fd !== 0 && fd !== 1 && fd !== 2) {
        return WASI_ERRNO.EBADF;
      }
      for (let i = 0; i < 24; i++) {
        u8[stat_ptr + i] = 0;
      }
      // fs_filetype: character_device = 2
      view.setUint8(stat_ptr, 2);
      view.setUint16(stat_ptr + 2, 0, true);
      const rights = fd === 0 ? 0x0000000000000002n : 0x0000000000000040n;
      view.setBigUint64(stat_ptr + 8, rights, true);
      view.setBigUint64(stat_ptr + 16, 0n, true);
      return WASI_ERRNO.SUCCESS;
    },

    fd_fdstat_set_flags(fd: number, _flags: number): number {
      if (fd === 0 || fd === 1 || fd === 2) {
        return WASI_ERRNO.SUCCESS;
      }
      return WASI_ERRNO.EBADF;
    },

    fd_prestat_get(_fd: number, _prestat_ptr: number): number {
      return WASI_ERRNO.EBADF;
    },

    fd_prestat_dir_name(_fd: number, _path_ptr: number, _path_len: number): number {
      return WASI_ERRNO.EBADF;
    },

    fd_seek(fd: number, _offset: bigint, _whence: number, _newoffset_ptr: number): number {
      if (fd === 0 || fd === 1 || fd === 2) {
        return WASI_ERRNO.ESPIPE;
      }
      return WASI_ERRNO.EBADF;
    },

    clock_time_get(clock_id: number, _precision: bigint, time_ptr: number): number {
      const { view } = getMemoryView();
      let nowNs: bigint;
      if (clock_id === 0) {
        nowNs = BigInt(Date.now()) * 1_000_000n;
      } else {
        nowNs = BigInt(Math.floor(performance.now() * 1_000_000));
      }
      view.setBigUint64(time_ptr, nowNs, true);
      return WASI_ERRNO.SUCCESS;
    },

    clock_res_get(_clock_id: number, res_ptr: number): number {
      const { view } = getMemoryView();
      view.setBigUint64(res_ptr, 1000n, true);
      return WASI_ERRNO.SUCCESS;
    },

    random_get(buf_ptr: number, buf_len: number): number {
      const { u8 } = getMemoryView();
      if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") {
        let remaining = buf_len;
        let offset = buf_ptr;
        while (remaining > 0) {
          const chunk = Math.min(remaining, 65536);
          crypto.getRandomValues(u8.subarray(offset, offset + chunk));
          offset += chunk;
          remaining -= chunk;
        }
      } else {
        for (let i = 0; i < buf_len; i++) {
          u8[buf_ptr + i] = Math.floor(Math.random() * 256);
        }
      }
      return WASI_ERRNO.SUCCESS;
    },

    proc_exit(rval: number): void {
      throw new WasiExit(rval);
    },

    sched_yield(): number {
      return WASI_ERRNO.SUCCESS;
    },

    poll_oneoff(_in_ptr: number, _out_ptr: number, _nsubscriptions: number, _nevents_ptr: number): number {
      return WASI_ERRNO.ENOSYS;
    },

    path_open(): number { return WASI_ERRNO.ENOENT; },
    fd_filestat_get(): number { return WASI_ERRNO.EBADF; },
    path_filestat_get(): number { return WASI_ERRNO.ENOENT; },
    fd_sync(): number { return WASI_ERRNO.SUCCESS; },
    fd_advise(): number { return WASI_ERRNO.SUCCESS; },
    fd_allocate(): number { return WASI_ERRNO.EBADF; },
    fd_datasync(): number { return WASI_ERRNO.SUCCESS; },
    fd_pread(): number { return WASI_ERRNO.ESPIPE; },
    fd_pwrite(): number { return WASI_ERRNO.ESPIPE; },
    fd_readdir(): number { return WASI_ERRNO.EBADF; },
    fd_renumber(): number { return WASI_ERRNO.EBADF; },
    fd_tell(): number { return WASI_ERRNO.ESPIPE; },
    path_create_directory(): number { return WASI_ERRNO.ENOTCAPABLE; },
    path_link(): number { return WASI_ERRNO.ENOTCAPABLE; },
    path_readlink(): number { return WASI_ERRNO.ENOTCAPABLE; },
    path_remove_directory(): number { return WASI_ERRNO.ENOTCAPABLE; },
    path_rename(): number { return WASI_ERRNO.ENOTCAPABLE; },
    path_symlink(): number { return WASI_ERRNO.ENOTCAPABLE; },
    path_unlink_file(): number { return WASI_ERRNO.ENOTCAPABLE; },
    proc_raise(): number { return WASI_ERRNO.ENOSYS; },
    sock_accept(): number { return WASI_ERRNO.ENOSYS; },
    sock_recv(): number { return WASI_ERRNO.ENOSYS; },
    sock_send(): number { return WASI_ERRNO.ENOSYS; },
    sock_shutdown(): number { return WASI_ERRNO.ENOSYS; },
  };

  let module: WebAssembly.Module;
  if (wasmSource instanceof WebAssembly.Module) {
    module = wasmSource;
  } else {
    module = await WebAssembly.compile(wasmSource);
  }

  const importObject = {
    wasi_snapshot_preview1: wasiSnapshotPreview1,
  };

  const instance = await WebAssembly.instantiate(module, importObject);

  if (instance.exports.memory instanceof WebAssembly.Memory) {
    memoryInstance = instance.exports.memory;
  }

  const start = (): number => {
    const startFn = instance.exports._start as (() => void) | undefined;
    if (typeof startFn !== "function") {
      throw new Error("Wasm module does not export _start function");
    }
    try {
      startFn();
      return 0;
    } catch (err: unknown) {
      if (err instanceof WasiExit) {
        return err.exitCode;
      }
      throw err;
    }
  };

  return {
    instance,
    module,
    memory: memoryInstance,
    start,
    getStdout: () => stdoutChunks.join(""),
    getStderr: () => stderrChunks.join(""),
  };
}

export async function runWasm(
  wasmSource: BufferSource | WebAssembly.Module,
  options: WasmRunOptions = {}
): Promise<WasmRunResult> {
  const startTime = performance.now();
  let wasmInstance: WasmInstance | null = null;
  let exitCode = 0;
  let trapError: string | null = null;

  try {
    wasmInstance = await createWasmInstance(wasmSource, options);
    exitCode = wasmInstance.start();
  } catch (err: unknown) {
    if (err instanceof WasiExit) {
      exitCode = err.exitCode;
    } else {
      exitCode = 134; // standard trap code
      trapError = err instanceof Error ? err.message : String(err);
    }
  }

  const durationMs = performance.now() - startTime;
  const stdout = wasmInstance ? wasmInstance.getStdout() : "";
  let stderr = wasmInstance ? wasmInstance.getStderr() : "";
  if (trapError && !stderr.includes(trapError)) {
    stderr = stderr ? `${stderr}\n${trapError}` : trapError;
  }

  return {
    stdout,
    stderr,
    exitCode,
    durationMs,
  };
}
