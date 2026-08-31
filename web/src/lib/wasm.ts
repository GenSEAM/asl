/**
 * Browser-native WebAssembly WASI runner for AgentScript Playground.
 * Wraps WebAssembly execution with standard WASI preview1 host stubs.
 */

export interface WasiRunResult {
  stdout: string;
  stderr: string;
  exitCode: number;
  durationMs: number;
}

export async function runWasmInBrowser(
  wasmBytes: Uint8Array | ArrayBuffer,
  args: string[] = ["program"],
  stdinText: string = ""
): Promise<WasiRunResult> {
  const t0 = performance.now();
  let stdout = "";
  let stderr = "";
  let exitCode = 0;

  const stdoutDecoder = new TextDecoder("utf-8");
  const stderrDecoder = new TextDecoder("utf-8");
  const stdinEncoder = new TextEncoder();
  const stdinBytes = stdinEncoder.encode(stdinText);
  let stdinOffset = 0;

  let memory: WebAssembly.Memory;

  const wasi_snapshot_preview1 = {
    fd_write: (fd: number, iovs_ptr: number, iovs_len: number, nwritten_ptr: number): number => {
      if (!memory) return 28; // EINVAL
      const view = new DataView(memory.buffer);
      const memBytes = new Uint8Array(memory.buffer);
      let totalWritten = 0;

      for (let i = 0; i < iovs_len; i++) {
        const ptr = view.getUint32(iovs_ptr + i * 8, true);
        const len = view.getUint32(iovs_ptr + i * 8 + 4, true);
        const chunk = memBytes.subarray(ptr, ptr + len);

        if (fd === 1) {
          stdout += stdoutDecoder.decode(chunk, { stream: true });
        } else if (fd === 2) {
          stderr += stderrDecoder.decode(chunk, { stream: true });
        }
        totalWritten += len;
      }
      view.setUint32(nwritten_ptr, totalWritten, true);
      return 0; // ESUCCESS
    },

    fd_read: (fd: number, iovs_ptr: number, iovs_len: number, nread_ptr: number): number => {
      if (!memory) return 28;
      const view = new DataView(memory.buffer);
      const memBytes = new Uint8Array(memory.buffer);
      let totalRead = 0;

      if (fd === 0) {
        for (let i = 0; i < iovs_len; i++) {
          const ptr = view.getUint32(iovs_ptr + i * 8, true);
          const len = view.getUint32(iovs_ptr + i * 8 + 4, true);
          const available = Math.min(len, stdinBytes.length - stdinOffset);
          if (available > 0) {
            memBytes.set(stdinBytes.subarray(stdinOffset, stdinOffset + available), ptr);
            stdinOffset += available;
            totalRead += available;
          }
        }
      }
      view.setUint32(nread_ptr, totalRead, true);
      return 0;
    },

    fd_seek: (_fd: number, _offset: bigint, _whence: number, newoffset_ptr: number): number => {
      if (memory) new DataView(memory.buffer).setBigInt64(newoffset_ptr, 0n, true);
      return 0;
    },

    fd_close: (_fd: number): number => 0,
    fd_fdstat_get: (_fd: number, stat_ptr: number): number => {
      if (memory) {
        const v = new DataView(memory.buffer);
        v.setUint8(stat_ptr, 2); // character device
        v.setUint16(stat_ptr + 2, 0, true);
        v.setBigUint64(stat_ptr + 8, 0n, true);
        v.setBigUint64(stat_ptr + 16, 0n, true);
      }
      return 0;
    },
    fd_fdstat_set_flags: (): number => 0,
    fd_prestat_get: (fd: number, buf_ptr: number): number => {
      if (fd === 3 && memory) {
        new DataView(memory.buffer).setUint32(buf_ptr, 0, true); // WASI_PREOPENTYPE_DIR
        new DataView(memory.buffer).setUint32(buf_ptr + 4, 1, true); // length of "/"
        return 0;
      }
      return 8; // EBADF
    },
    fd_prestat_dir_name: (fd: number, path_ptr: number, path_len: number): number => {
      if (fd === 3 && path_len >= 1 && memory) {
        new Uint8Array(memory.buffer)[path_ptr] = 47; // '/'
        return 0;
      }
      return 8;
    },
    environ_sizes_get: (count_ptr: number, size_ptr: number): number => {
      if (memory) {
        new DataView(memory.buffer).setUint32(count_ptr, 0, true);
        new DataView(memory.buffer).setUint32(size_ptr, 0, true);
      }
      return 0;
    },
    environ_get: (): number => 0,
    args_sizes_get: (count_ptr: number, size_ptr: number): number => {
      if (memory) {
        let totalBytes = 0;
        for (const a of args) totalBytes += new TextEncoder().encode(a).length + 1;
        new DataView(memory.buffer).setUint32(count_ptr, args.length, true);
        new DataView(memory.buffer).setUint32(size_ptr, totalBytes, true);
      }
      return 0;
    },
    args_get: (argv_ptr: number, argv_buf_ptr: number): number => {
      if (memory) {
        const view = new DataView(memory.buffer);
        const memBytes = new Uint8Array(memory.buffer);
        let curBuf = argv_buf_ptr;
        for (let i = 0; i < args.length; i++) {
          view.setUint32(argv_ptr + i * 4, curBuf, true);
          const encoded = new TextEncoder().encode(args[i]);
          memBytes.set(encoded, curBuf);
          memBytes[curBuf + encoded.length] = 0;
          curBuf += encoded.length + 1;
        }
      }
      return 0;
    },
    clock_time_get: (_id: number, _precision: bigint, time_ptr: number): number => {
      if (memory) {
        const nanos = BigInt(Math.floor(performance.now() * 1_000_000));
        new DataView(memory.buffer).setBigUint64(time_ptr, nanos, true);
      }
      return 0;
    },
    clock_res_get: (_id: number, res_ptr: number): number => {
      if (memory) new DataView(memory.buffer).setBigUint64(res_ptr, 1_000_000n, true);
      return 0;
    },
    random_get: (buf_ptr: number, buf_len: number): number => {
      if (memory) crypto.getRandomValues(new Uint8Array(memory.buffer, buf_ptr, buf_len));
      return 0;
    },
    proc_exit: (code: number): void => {
      exitCode = code;
      throw new Error(`__WASI_EXIT_${code}__`);
    },
    sched_yield: (): number => 0,
    path_open: (): number => 44, // ENOENT
  };

  try {
    const compiled: any = await WebAssembly.instantiate(wasmBytes, { wasi_snapshot_preview1 });
    const instance = compiled.instance || compiled;
    memory = (instance.exports.memory as WebAssembly.Memory);
    const startFn = instance.exports._start as Function;
    if (startFn) {
      try {
        startFn();
      } catch (err: any) {
        if (!err.message?.includes("__WASI_EXIT_")) {
          stderr += `\nRuntime Trap: ${err.message}`;
          exitCode = 134;
        }
      }
    }
  } catch (err: any) {
    stderr += `\nInstantiation error: ${err.message}`;
    exitCode = 1;
  }

  const durationMs = performance.now() - t0;
  return { stdout, stderr, exitCode, durationMs };
}
