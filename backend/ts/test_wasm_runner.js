import assert from "node:assert";
import { runWasm, createWasmInstance } from "./wasm_runner.js";
function encodeUleb128(n) {
    const res = [];
    do {
        let byte = n & 0x7f;
        n >>>= 7;
        if (n !== 0) {
            byte |= 0x80;
        }
        res.push(byte);
    } while (n !== 0);
    return res;
}
function encodeSleb128(n) {
    const res = [];
    let more = true;
    while (more) {
        let byte = n & 0x7f;
        n >>= 7;
        const signBit = (byte & 0x40) !== 0;
        if ((n === 0 && !signBit) || (n === -1 && signBit)) {
            more = false;
        }
        else {
            byte |= 0x80;
        }
        res.push(byte);
    }
    return res;
}
function encodeVec(items) {
    const count = encodeUleb128(items.length);
    const flattened = items.flat();
    return [...count, ...flattened];
}
function encodeSection(id, payload) {
    return [id, ...encodeUleb128(payload.length), ...payload];
}
function encodeString(str) {
    const bytes = new TextEncoder().encode(str);
    return [...encodeUleb128(bytes.length), ...Array.from(bytes)];
}
function buildTrapModule() {
    // Module with _start executing `unreachable`
    const magic = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
    const typeSec = encodeSection(1, encodeVec([[0x60, 0x00, 0x00]])); // () -> ()
    const funcSec = encodeSection(3, encodeVec([[0x00]])); // type 0
    const exportSec = encodeSection(7, encodeVec([[...encodeString("_start"), 0x00, 0x00]]));
    const codeBody = [0x00, 0x00, 0x0b]; // locals=0, unreachable, end
    const codeSec = encodeSection(10, encodeVec([[...encodeUleb128(codeBody.length), ...codeBody]]));
    return new Uint8Array([...magic, ...typeSec, ...funcSec, ...exportSec, ...codeSec]);
}
function buildProcExitModule(code) {
    const magic = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
    const types = [
        [0x60, 0x01, 0x7f, 0x00], // type 0: (i32) -> ()
        [0x60, 0x00, 0x00], // type 1: () -> ()
    ];
    const typeSec = encodeSection(1, encodeVec(types));
    const importSec = encodeSection(2, encodeVec([[...encodeString("wasi_snapshot_preview1"), ...encodeString("proc_exit"), 0x00, 0x00]]));
    const funcSec = encodeSection(3, encodeVec([[0x01]])); // func 1 has type 1
    const exportSec = encodeSection(7, encodeVec([[...encodeString("_start"), 0x00, 0x01]]));
    const codeBody = [0x00, 0x41, ...encodeSleb128(code), 0x10, 0x00, 0x0b]; // i32.const code, call 0, end
    const codeSec = encodeSection(10, encodeVec([[...encodeUleb128(codeBody.length), ...codeBody]]));
    return new Uint8Array([...magic, ...typeSec, ...importSec, ...funcSec, ...exportSec, ...codeSec]);
}
function buildStdoutModule(message, exitCode = 0) {
    const magic = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
    const types = [
        [0x60, 0x04, 0x7f, 0x7f, 0x7f, 0x7f, 0x01, 0x7f], // type 0: fd_write(i32, i32, i32, i32) -> i32
        [0x60, 0x01, 0x7f, 0x00], // type 1: proc_exit(i32) -> ()
        [0x60, 0x00, 0x00], // type 2: () -> ()
    ];
    const typeSec = encodeSection(1, encodeVec(types));
    const imports = [
        [...encodeString("wasi_snapshot_preview1"), ...encodeString("fd_write"), 0x00, 0x00],
        [...encodeString("wasi_snapshot_preview1"), ...encodeString("proc_exit"), 0x00, 0x01],
    ];
    const importSec = encodeSection(2, encodeVec(imports));
    const funcSec = encodeSection(3, encodeVec([[0x02]])); // func 2 has type 2
    const memSec = encodeSection(5, encodeVec([[0x00, 0x01]])); // min 1 page
    const exports = [
        [...encodeString("_start"), 0x00, 0x02],
        [...encodeString("memory"), 0x02, 0x00],
    ];
    const exportSec = encodeSection(7, encodeVec(exports));
    const msgBytes = new TextEncoder().encode(message);
    // Ciovec at offset 0: ptr=16, len=msgBytes.length
    const ciovec = [16, 0, 0, 0, msgBytes.length & 0xff, (msgBytes.length >> 8) & 0xff, 0, 0];
    const totalData = [...ciovec, 0, 0, 0, 0, 0, 0, 0, 0, ...Array.from(msgBytes)];
    const dataSeg = [0x00, 0x41, 0x00, 0x0b, ...encodeUleb128(totalData.length), ...totalData];
    const dataSec = encodeSection(11, encodeVec([dataSeg]));
    const codeBody = [
        0x00, // 0 locals
        0x41, 0x01, // i32.const 1 (stdout)
        0x41, 0x00, // i32.const 0 (iovs ptr)
        0x41, 0x01, // i32.const 1 (iovs_len)
        0x41, 0x08, // i32.const 8 (nwritten ptr)
        0x10, 0x00, // call fd_write
        0x1a, // drop
        0x41, ...encodeSleb128(exitCode), // i32.const exitCode
        0x10, 0x01, // call proc_exit
        0x0b, // end
    ];
    const codeSec = encodeSection(10, encodeVec([[...encodeUleb128(codeBody.length), ...codeBody]]));
    return new Uint8Array([...magic, ...typeSec, ...importSec, ...funcSec, ...memSec, ...exportSec, ...codeSec, ...dataSec]);
}
function buildMemoryGrowthModule(message) {
    const magic = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
    const types = [
        [0x60, 0x04, 0x7f, 0x7f, 0x7f, 0x7f, 0x01, 0x7f], // type 0: fd_write(i32, i32, i32, i32) -> i32
        [0x60, 0x01, 0x7f, 0x00], // type 1: proc_exit(i32) -> ()
        [0x60, 0x00, 0x00], // type 2: () -> ()
    ];
    const typeSec = encodeSection(1, encodeVec(types));
    const imports = [
        [...encodeString("wasi_snapshot_preview1"), ...encodeString("fd_write"), 0x00, 0x00],
        [...encodeString("wasi_snapshot_preview1"), ...encodeString("proc_exit"), 0x00, 0x01],
    ];
    const importSec = encodeSection(2, encodeVec(imports));
    const funcSec = encodeSection(3, encodeVec([[0x02]])); // func 2 has type 2
    const memSec = encodeSection(5, encodeVec([[0x00, 0x01]])); // min 1 page
    const exports = [
        [...encodeString("_start"), 0x00, 0x02],
        [...encodeString("memory"), 0x02, 0x00],
    ];
    const exportSec = encodeSection(7, encodeVec(exports));
    const msgBytes = new TextEncoder().encode(message);
    const codeOps = [
        0x00, // 0 locals
        // memory.grow(1)
        0x41, 0x01, // i32.const 1
        0x40, 0x00, // memory.grow 0
        0x1a, // drop
        // i32.store(65536, 65552)
        0x41, ...encodeSleb128(65536),
        0x41, ...encodeSleb128(65552),
        0x36, 0x02, 0x00, // i32.store align=2 offset=0
        // i32.store(65540, len)
        0x41, ...encodeSleb128(65540),
        0x41, ...encodeSleb128(msgBytes.length),
        0x36, 0x02, 0x00,
    ];
    // Write each byte into offset 65552 + i
    for (let i = 0; i < msgBytes.length; i++) {
        codeOps.push(0x41, ...encodeSleb128(65552 + i), 0x41, ...encodeSleb128(msgBytes[i]), 0x3a, 0x00, 0x00 // i32.store8 align=0 offset=0
        );
    }
    // fd_write(1, 65536, 1, 65544)
    codeOps.push(0x41, 0x01, // stdout
    0x41, ...encodeSleb128(65536), // iovs
    0x41, 0x01, // iovs_len
    0x41, ...encodeSleb128(65544), // nwritten
    0x10, 0x00, // call fd_write
    0x1a, // drop
    0x41, 0x00, // proc_exit(0)
    0x10, 0x01, 0x0b // end
    );
    const codeSec = encodeSection(10, encodeVec([[...encodeUleb128(codeOps.length), ...codeOps]]));
    return new Uint8Array([...magic, ...typeSec, ...importSec, ...funcSec, ...memSec, ...exportSec, ...codeSec]);
}
function buildArgvEchoModule() {
    const magic = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
    const types = [
        [0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f], // type 0: args_sizes_get(i32, i32) -> i32
        [0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f], // type 1: args_get(i32, i32) -> i32
        [0x60, 0x04, 0x7f, 0x7f, 0x7f, 0x7f, 0x01, 0x7f], // type 2: fd_write(i32, i32, i32, i32) -> i32
        [0x60, 0x01, 0x7f, 0x00], // type 3: proc_exit(i32) -> ()
        [0x60, 0x00, 0x00], // type 4: () -> ()
    ];
    const typeSec = encodeSection(1, encodeVec(types));
    const imports = [
        [...encodeString("wasi_snapshot_preview1"), ...encodeString("args_sizes_get"), 0x00, 0x00],
        [...encodeString("wasi_snapshot_preview1"), ...encodeString("args_get"), 0x00, 0x01],
        [...encodeString("wasi_snapshot_preview1"), ...encodeString("fd_write"), 0x00, 0x02],
        [...encodeString("wasi_snapshot_preview1"), ...encodeString("proc_exit"), 0x00, 0x03],
    ];
    const importSec = encodeSection(2, encodeVec(imports));
    const funcSec = encodeSection(3, encodeVec([[0x04]])); // func 4 has type 4
    const memSec = encodeSection(5, encodeVec([[0x00, 0x01]])); // min 1 page
    const exports = [
        [...encodeString("_start"), 0x00, 0x04],
        [...encodeString("memory"), 0x02, 0x00],
    ];
    const exportSec = encodeSection(7, encodeVec(exports));
    // Memory layout:
    // 0: argc (u32)
    // 4: argv_buf_size (u32)
    // 8: argv pointers array (e.g. 100 bytes)
    // 256: argv string buffer
    // 1024: ciovec struct (ptr, len)
    // 1032: nwritten
    const codeOps = [
        0x00, // 0 locals
        // args_sizes_get(0, 4)
        0x41, 0x00,
        0x41, 0x04,
        0x10, 0x00,
        0x1a,
        // args_get(8, 256)
        0x41, 0x08,
        0x41, ...encodeSleb128(256),
        0x10, 0x01,
        0x1a,
        // ciovec: ptr = i32.load(8), len = i32.load(4)
        0x41, ...encodeSleb128(1024),
        0x41, 0x08,
        0x28, 0x02, 0x00, // i32.load from 8 (argv[0] ptr)
        0x36, 0x02, 0x00, // i32.store at 1024
        0x41, ...encodeSleb128(1028),
        0x41, 0x04,
        0x28, 0x02, 0x00, // i32.load from 4 (total argv buf size)
        0x36, 0x02, 0x00, // i32.store at 1028
        // fd_write(1, 1024, 1, 1032)
        0x41, 0x01,
        0x41, ...encodeSleb128(1024),
        0x41, 0x01,
        0x41, ...encodeSleb128(1032),
        0x10, 0x02,
        0x1a,
        // proc_exit(0)
        0x41, 0x00,
        0x10, 0x03,
        0x0b,
    ];
    const codeSec = encodeSection(10, encodeVec([[...encodeUleb128(codeOps.length), ...codeOps]]));
    return new Uint8Array([...magic, ...typeSec, ...importSec, ...funcSec, ...memSec, ...exportSec, ...codeSec]);
}
async function runTests() {
    console.log("Starting WASI Runner Tests...");
    // Test 1: Pure / zero-output exit 0 test (C2)
    {
        console.log("Test 1: Zero-output exit 0");
        const wasm = buildProcExitModule(0);
        const result = await runWasm(wasm);
        assert.strictEqual(result.exitCode, 0);
        assert.strictEqual(result.stdout, "");
        assert.strictEqual(result.stderr, "");
        assert.strictEqual(typeof result.durationMs, "number");
        assert(result.durationMs >= 0);
    }
    // Test 2: Non-zero exit code capture (C3)
    {
        console.log("Test 2: Non-zero exit code 42");
        const wasm = buildProcExitModule(42);
        const result = await runWasm(wasm);
        assert.strictEqual(result.exitCode, 42);
        assert.strictEqual(result.stdout, "");
        assert.strictEqual(result.stderr, "");
    }
    // Test 3: Trap capture (C1)
    {
        console.log("Test 3: WebAssembly trap capture");
        const wasm = buildTrapModule();
        const result = await runWasm(wasm);
        assert.strictEqual(result.exitCode, 134);
        assert(result.stderr.length > 0, "stderr should contain trap description");
        assert(result.stderr.toLowerCase().includes("unreachable"), "stderr should note unreachable trap");
    }
    // Test 4: Stdout capture and streaming callbacks
    {
        console.log("Test 4: Stdout capture & streaming callbacks");
        const message = "Hello AgentScript Wasm!\n";
        const wasm = buildStdoutModule(message, 0);
        let streamed = "";
        const result = await runWasm(wasm, {
            onStdout: (chunk) => {
                streamed += chunk;
            },
        });
        assert.strictEqual(result.exitCode, 0);
        assert.strictEqual(result.stdout, message);
        assert.strictEqual(streamed, message);
        assert.strictEqual(result.stderr, "");
    }
    // Test 5: createWasmInstance export helper (D2)
    {
        console.log("Test 5: createWasmInstance helper");
        const message = "Instance direct run\n";
        const wasm = buildStdoutModule(message, 0);
        const inst = await createWasmInstance(wasm);
        assert.strictEqual(inst.getStdout(), "");
        const code = inst.start();
        assert.strictEqual(code, 0);
        assert.strictEqual(inst.getStdout(), message);
    }
    // Test 6: Memory growth detachment handling (D1)
    {
        console.log("Test 6: Memory growth does not detach or error");
        const message = "Growth across memory boundary!\n";
        const wasm = buildMemoryGrowthModule(message);
        const result = await runWasm(wasm);
        assert.strictEqual(result.exitCode, 0);
        assert.strictEqual(result.stdout, message);
    }
    // Test 7: CLI Argv passing (args_sizes_get / args_get)
    {
        console.log("Test 7: Argv passing via options.args");
        const wasm = buildArgvEchoModule();
        const result = await runWasm(wasm, {
            args: ["custom_arg"],
        });
        assert.strictEqual(result.exitCode, 0);
        assert(result.stdout.startsWith("custom_arg"));
    }
    console.log("All WASI runner unit tests passed successfully!");
}
runTests().catch((err) => {
    console.error("Test failed:", err);
    process.exit(1);
});
//# sourceMappingURL=test_wasm_runner.js.map