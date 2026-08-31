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

export class WasiExit extends Error {
  readonly code: number;
  constructor(code: number) {
    super(`WASI proc_exit: ${code}`);
    this.name = 'WasiExit';
    this.code = code;
  }
}

// WASI Error Constants (errno)
const WASI_ESUCCESS = 0;
const WASI_EBADF = 8;
const WASI_EINVAL = 28;
const WASI_ENOENT = 44;
const WASI_ENOSYS = 52;
const WASI_ENOTSUP = 58;

export function createWasiImportObject(
  getMemory: () => WebAssembly.Memory,
  options: WasmRunOptions = {},
  state: { stdout: string[]; stderr: string[] } = { stdout: [], stderr: [] }
): Record<string, Function> {
  const textDecoder = new TextDecoder('utf-8');
  const textEncoder = new TextEncoder();

  const args = options.args || ['main'];
  const envEntries = Object.entries(options.env || {});

  return {
    proc_exit(rval: number): void {
      throw new WasiExit(rval);
    },

    fd_write(fd: number, iovs_ptr: number, iovs_len: number, nwritten_ptr: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EBADF;
      const buffer = memory.buffer;
      const view = new DataView(buffer);
      const uint8 = new Uint8Array(buffer);

      let totalWritten = 0;
      let outputChunk = '';

      for (let i = 0; i < iovs_len; i++) {
        const offset = iovs_ptr + i * 8;
        const ptr = view.getUint32(offset, true);
        const len = view.getUint32(offset + 4, true);

        if (len > 0) {
          const slice = uint8.subarray(ptr, ptr + len);
          outputChunk += textDecoder.decode(slice, { stream: true });
          totalWritten += len;
        }
      }

      view.setUint32(nwritten_ptr, totalWritten, true);

      if (fd === 1) {
        state.stdout.push(outputChunk);
        if (options.onStdout) options.onStdout(outputChunk);
      } else if (fd === 2) {
        state.stderr.push(outputChunk);
        if (options.onStderr) options.onStderr(outputChunk);
      }

      return WASI_ESUCCESS;
    },

    fd_read(fd: number, iovs_ptr: number, iovs_len: number, nread_ptr: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EBADF;
      const view = new DataView(memory.buffer);
      view.setUint32(nread_ptr, 0, true);
      return WASI_ESUCCESS; // EOF
    },

    fd_close(fd: number): number {
      return WASI_ESUCCESS;
    },

    fd_seek(fd: number, offset: bigint, whence: number, newoffset_ptr: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EBADF;
      const view = new DataView(memory.buffer);
      view.setBigInt64(newoffset_ptr, 0n, true);
      return WASI_ESUCCESS;
    },

    fd_fdstat_get(fd: number, stat_ptr: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EBADF;
      const view = new DataView(memory.buffer);
      view.setUint8(stat_ptr, fd === 1 || fd === 2 ? 2 : 0); // character device or unknown
      view.setUint16(stat_ptr + 2, 0, true); // flags
      view.setBigUint64(stat_ptr + 8, 0xffffffffffffffffn, true); // rights base
      view.setBigUint64(stat_ptr + 16, 0xffffffffffffffffn, true); // rights inheriting
      return WASI_ESUCCESS;
    },

    fd_fdstat_set_flags(fd: number, flags: number): number {
      return WASI_ESUCCESS;
    },

    fd_filestat_get(fd: number, buf_ptr: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EBADF;
      const view = new DataView(memory.buffer);
      // dev: u64, ino: u64, filetype: u8, nlink: u64, size: u64, atim: u64, mtim: u64, ctim: u64
      view.setBigUint64(buf_ptr, 0n, true);
      view.setBigUint64(buf_ptr + 8, 0n, true);
      view.setUint8(buf_ptr + 16, fd === 1 || fd === 2 ? 2 : 0);
      view.setBigUint64(buf_ptr + 24, 1n, true);
      view.setBigUint64(buf_ptr + 32, 0n, true);
      view.setBigUint64(buf_ptr + 40, 0n, true);
      view.setBigUint64(buf_ptr + 48, 0n, true);
      view.setBigUint64(buf_ptr + 56, 0n, true);
      return WASI_ESUCCESS;
    },

    fd_filestat_set_size(fd: number, size: bigint): number {
      return WASI_EBADF;
    },

    fd_filestat_set_times(fd: number, atim: bigint, mtim: bigint, fst_flags: number): number {
      return WASI_EBADF;
    },

    path_open(
      fd: number,
      dirflags: number,
      path_ptr: number,
      path_len: number,
      oflags: number,
      fs_rights_base: bigint,
      fs_rights_inheriting: bigint,
      fdflags: number,
      opened_fd_ptr: number
    ): number {
      return WASI_ENOENT;
    },

    path_filestat_get(
      fd: number,
      flags: number,
      path_ptr: number,
      path_len: number,
      buf_ptr: number
    ): number {
      return WASI_ENOENT;
    },

    path_create_directory(fd: number, path_ptr: number, path_len: number): number {
      return WASI_EBADF;
    },

    path_unlink_file(fd: number, path_ptr: number, path_len: number): number {
      return WASI_EBADF;
    },

    path_remove_directory(fd: number, path_ptr: number, path_len: number): number {
      return WASI_EBADF;
    },

    path_rename(
      fd: number,
      old_path_ptr: number,
      old_path_len: number,
      new_fd: number,
      new_path_ptr: number,
      new_path_len: number
    ): number {
      return WASI_EBADF;
    },

    poll_oneoff(in_ptr: number, out_ptr: number, nsubscriptions: number, nevents_ptr: number): number {
      return WASI_ENOSYS;
    },

    fd_prestat_get(fd: number, prestat_ptr: number): number {
      if (fd === 3) {
        const memory = getMemory();
        if (!memory) return WASI_EBADF;
        const view = new DataView(memory.buffer);
        view.setUint8(prestat_ptr, 0); // WASI_PREOPENTYPE_DIR = 0
        view.setUint32(prestat_ptr + 4, 1, true); // dir name len = 1 ("/")
        return WASI_ESUCCESS;
      }
      return WASI_EBADF;
    },

    fd_prestat_dir_name(fd: number, path_ptr: number, path_len: number): number {
      if (fd === 3 && path_len >= 1) {
        const memory = getMemory();
        if (!memory) return WASI_EBADF;
        const uint8 = new Uint8Array(memory.buffer);
        uint8[path_ptr] = 47; // '/'
        return WASI_ESUCCESS;
      }
      return WASI_EBADF;
    },

    args_sizes_get(argc_ptr: number, argv_buf_size_ptr: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EINVAL;
      const view = new DataView(memory.buffer);
      view.setUint32(argc_ptr, args.length, true);

      let bufSize = 0;
      for (const arg of args) {
        bufSize += textEncoder.encode(arg).length + 1; // including \0
      }
      view.setUint32(argv_buf_size_ptr, bufSize, true);
      return WASI_ESUCCESS;
    },

    args_get(argv_ptrs_ptr: number, argv_buf_ptr: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EINVAL;
      const view = new DataView(memory.buffer);
      const uint8 = new Uint8Array(memory.buffer);

      let currentBuf = argv_buf_ptr;
      for (let i = 0; i < args.length; i++) {
        view.setUint32(argv_ptrs_ptr + i * 4, currentBuf, true);
        const encoded = textEncoder.encode(args[i]);
        uint8.set(encoded, currentBuf);
        uint8[currentBuf + encoded.length] = 0; // null terminator
        currentBuf += encoded.length + 1;
      }
      return WASI_ESUCCESS;
    },

    environ_sizes_get(environ_count_ptr: number, environ_buf_size_ptr: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EINVAL;
      const view = new DataView(memory.buffer);
      view.setUint32(environ_count_ptr, envEntries.length, true);

      let bufSize = 0;
      for (const [k, v] of envEntries) {
        bufSize += textEncoder.encode(`${k}=${v}`).length + 1;
      }
      view.setUint32(environ_buf_size_ptr, bufSize, true);
      return WASI_ESUCCESS;
    },

    environ_get(environ_ptrs_ptr: number, environ_buf_ptr: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EINVAL;
      const view = new DataView(memory.buffer);
      const uint8 = new Uint8Array(memory.buffer);

      let currentBuf = environ_buf_ptr;
      for (let i = 0; i < envEntries.length; i++) {
        view.setUint32(environ_ptrs_ptr + i * 4, currentBuf, true);
        const str = `${envEntries[i][0]}=${envEntries[i][1]}`;
        const encoded = textEncoder.encode(str);
        uint8.set(encoded, currentBuf);
        uint8[currentBuf + encoded.length] = 0;
        currentBuf += encoded.length + 1;
      }
      return WASI_ESUCCESS;
    },

    clock_time_get(id: number, precision: bigint, time_ptr: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EINVAL;
      const view = new DataView(memory.buffer);
      const nowNs = BigInt(Date.now()) * 1_000_000n;
      view.setBigUint64(time_ptr, nowNs, true);
      return WASI_ESUCCESS;
    },

    random_get(buf_ptr: number, buf_len: number): number {
      const memory = getMemory();
      if (!memory) return WASI_EINVAL;
      const uint8 = new Uint8Array(memory.buffer);
      for (let i = 0; i < buf_len; i++) {
        uint8[buf_ptr + i] = Math.floor(Math.random() * 256);
      }
      return WASI_ESUCCESS;
    },

    sched_yield(): number {
      return WASI_ESUCCESS;
    },
  };
}

export async function createWasmInstance(
  wasmSource: BufferSource | WebAssembly.Module,
  options: WasmRunOptions = {}
): Promise<WasmInstanceHandle> {
  const state = { stdout: [] as string[], stderr: [] as string[] };
  let memoryRef: WebAssembly.Memory | null = null;

  const wasiImports = createWasiImportObject(() => memoryRef!, options, state);
  const importObject = { wasi_snapshot_preview1: wasiImports };

  let module: WebAssembly.Module;
  let instance: WebAssembly.Instance;

  if (wasmSource instanceof WebAssembly.Module) {
    module = wasmSource;
    instance = await WebAssembly.instantiate(module, importObject);
  } else {
    const compiled = await WebAssembly.instantiate(wasmSource, importObject);
    instance = compiled.instance;
    module = compiled.module;
  }

  memoryRef = (instance.exports.memory as WebAssembly.Memory) || null;

  return {
    instance,
    module,
    memory: memoryRef!,
    exports: instance.exports,
    getStdout: () => state.stdout.join(''),
    getStderr: () => state.stderr.join(''),
  };
}

export async function runWasm(
  wasmSource: BufferSource | WebAssembly.Module,
  options: WasmRunOptions = {}
): Promise<WasmRunResult> {
  const start = Date.now();
  const handle = await createWasmInstance(wasmSource, options);
  let exitCode = 0;

  try {
    const startFn = handle.exports._start || handle.exports.main;
    if (typeof startFn === 'function') {
      startFn();
    }
  } catch (err: any) {
    if (err instanceof WasiExit) {
      exitCode = err.code;
    } else {
      // Trap or runtime error
      const msg = err && err.message ? err.message : String(err);
      if (!handle.getStderr()) {
        (handle.exports as any).stderrOutput = msg;
      }
      exitCode = 134; // standard abort/trap exit code
    }
  }

  return {
    stdout: handle.getStdout(),
    stderr: handle.getStderr(),
    exitCode,
    durationMs: Date.now() - start,
  };
}
