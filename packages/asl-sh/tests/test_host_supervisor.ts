/**
 * Process Supervisor Host Bridge Acceptance Test Suite (@pcp:d-446d)
 *
 * Verifies:
 * 1. Safe process spawning with PYTHONUNBUFFERED=1 injection
 * 2. Exit code and error propagation
 * 3. Bounded in-memory ring buffer ceiling (head/tail retention, middle eviction)
 * 4. Channel separation (stdout vs stderr)
 * 5. Interactive prompt detection ([y/N], ? ) and stdin unblocking
 * 6. Silence watchdog (QuietStall) and resume
 * 7. Hard timeout deadline (SIGKILL)
 * 8. ASL stream reduction (ANSI strip, CR collapse, line dedup, diagnostic extraction)
 * 9. Inline adaptive digest (inline for fast small runs, summary for heavy runs)
 * 10. Forced routing with justified bypass validation
 */

import assert from "assert";
import {
  ProcessSupervisor,
  RingBuffer,
  BypassPolicyViolationError,
  reduceStream,
  cleanTerminalText,
} from "../bridge/index.js";

console.log("=========================================================");
console.log("   ASL Process Supervisor Host Bridge Verification Suite ");
console.log("=========================================================\n");

async function runTests() {
  // Test 1: Subprocess execution & PYTHONUNBUFFERED=1 injection
  console.log("▶ Test 1: Subprocess spawn with unbuffered environment injection...");
  {
    const sup = new ProcessSupervisor();
    const res = await sup.run("node", [
      "-e",
      "console.log('MAGIC_OUTPUT'); console.log('PYTHONUNBUFFERED=' + process.env.PYTHONUNBUFFERED);",
    ]);

    assert.strictEqual(res.exitCode, 0, "Exit code must be 0");
    assert.strictEqual(res.timedOut, false, "Must not time out");
    assert(res.stdout.includes("MAGIC_OUTPUT"), "Stdout must contain MAGIC_OUTPUT");
    assert(
      res.stdout.includes("PYTHONUNBUFFERED=1"),
      "Must inject PYTHONUNBUFFERED=1 into subprocess environment"
    );
    console.log("  ✓ Subprocess executed cleanly and environment was injected.");
  }

  // Test 2: Exit code propagation
  console.log("\n▶ Test 2: Non-zero exit code propagation...");
  {
    const sup = new ProcessSupervisor();
    const res = await sup.run("node", ["-e", "process.exit(42);"]);
    assert.strictEqual(res.exitCode, 42, "Exit code must be 42");
    assert.strictEqual(res.state, "Exited");
    console.log("  ✓ Non-zero exit code correctly captured.");
  }

  // Test 3: Bounded Ring Buffer & Head/Tail eviction
  console.log("\n▶ Test 3: Ephemeral Ring Buffer bounded ceiling & eviction marker...");
  {
    const sup = new ProcessSupervisor({
      headLimit: 10,
      tailLimit: 20,
      maxLines: 30,
    });

    // Generate 100 lines
    const script = "for(let i = 1; i <= 100; i++) console.log(`line ${i}`);";
    const res = await sup.run("node", ["-e", script]);

    assert.strictEqual(res.exitCode, 0);
    const buf = res.ringBuffer;
    assert.strictEqual(buf.totalLines, 100, "Total lines generated must be 100");
    assert.strictEqual(buf.evictedCount, 70, "Must evict 70 lines (100 - 10 head - 20 tail)");

    const lines = buf.getLines();
    assert.strictEqual(lines.length, 31, "Retained lines count must be 10 + 1 marker + 20 = 31");
    assert.strictEqual(lines[0], "line 1", "First line must be line 1");
    assert.strictEqual(lines[9], "line 10", "10th line must be line 10");
    assert(
      lines[10].includes("70 lines evicted from in-memory ring buffer"),
      "Middle must contain eviction marker with count 70"
    );
    assert.strictEqual(lines[11], "line 81", "11th line must resume at line 81");
    assert.strictEqual(lines[30], "line 100", "Final line must be line 100");
    console.log("  ✓ Ring buffer ceiling enforced: 10 head, 20 tail, 70 evicted with marker.");
  }

  // Test 4: Channel separation (stdout vs stderr)
  console.log("\n▶ Test 4: Channel separation (stdout vs stderr)...");
  {
    const sup = new ProcessSupervisor();
    const res = await sup.run("node", [
      "-e",
      "console.log('OUT_MSG'); console.error('ERR_MSG');",
    ]);

    assert(res.stdout.includes("OUT_MSG"), "stdout must contain OUT_MSG");
    assert(!res.stdout.includes("ERR_MSG"), "stdout must NOT contain ERR_MSG");
    assert(res.stderr.includes("ERR_MSG"), "stderr must contain ERR_MSG");
    assert(!res.stderr.includes("OUT_MSG"), "stderr must NOT contain OUT_MSG");
    console.log("  ✓ Separate channels correctly isolated.");
  }

  // Test 5: Interactive prompt detection ([y/N]) & sendInput
  console.log("\n▶ Test 5: Interactive prompt detection & stdin response...");
  {
    const sup = new ProcessSupervisor();
    let promptDetected = false;

    sup.on("prompt", (e) => {
      promptDetected = true;
      assert(e.promptText.includes("[y/N]"), "Prompt text must include [y/N]");
      // Send input in response
      sup.sendInput("yes\n");
    });

    const script = `
      process.stdout.write("Do you want to proceed? [y/N] ");
      process.stdin.setEncoding("utf-8");
      process.stdin.once("data", (data) => {
        if (data.trim() === "yes") {
          console.log("CONFIRMED_ACTION");
          process.exit(0);
        } else {
          process.exit(1);
        }
      });
    `;

    const res = await sup.run("node", ["-e", script]);
    assert.strictEqual(res.exitCode, 0, "Process must exit 0 after answering prompt");
    assert.strictEqual(promptDetected, true, "Prompt must be detected");
    assert(res.stdout.includes("CONFIRMED_ACTION"), "Stdout must include CONFIRMED_ACTION");
    console.log("  ✓ Interactive prompt detected and unblocked via sendInput().");
  }

  // Test 6: Silence watchdog (QuietStall) and resumption
  console.log("\n▶ Test 6: Silence watchdog transition to QuietStall and resumption...");
  {
    const sup = new ProcessSupervisor({
      silenceTimeoutMs: 150, // Short timeout for test
    });

    let stallDetected = false;
    let resumeDetected = false;

    sup.on("quiet-stall", (e) => {
      stallDetected = true;
      assert(e.silentMs >= 140, "silentMs must be >= 140ms");
    });

    sup.on("resume", () => {
      resumeDetected = true;
    });

    const script = `
      console.log("PHASE_1");
      setTimeout(() => {
        console.log("PHASE_2");
        process.exit(0);
      }, 300);
    `;

    const res = await sup.run("node", ["-e", script]);
    assert.strictEqual(res.exitCode, 0);
    assert.strictEqual(stallDetected, true, "QuietStall must be triggered during 300ms pause");
    assert.strictEqual(resumeDetected, true, "Resume event must fire when PHASE_2 emitted");
    assert(res.stdout.includes("PHASE_2"), "Output must contain PHASE_2");
    console.log("  ✓ Silence watchdog correctly transitioned to QuietStall and resumed on output.");
  }

  // Test 7: Hard timeout deadline enforcement
  console.log("\n▶ Test 7: Hard timeout deadline (SIGKILL)...");
  {
    const sup = new ProcessSupervisor({
      timeoutMs: 300,
    });

    const script = "setInterval(() => console.log('tick'), 100);";
    const res = await sup.run("node", ["-e", script]);

    assert.strictEqual(res.timedOut, true, "timedOut flag must be true");
    assert.strictEqual(res.state, "TimedOut", "Final state must be TimedOut");
    console.log("  ✓ Hanging subprocess terminated at hard timeout deadline.");
  }

  // Test 8: ASL Stream Reduction (ANSI, CR, Dedup, Diagnostics)
  console.log("\n▶ Test 8: Pure ASL stream reduction algorithms...");
  {
    // Raw terminal output with ANSI colors, carriage return download bar, and duplicate lines
    const raw = [
      "\x1b[32m[INFO]\x1b[0m Starting compilation...",
      "Downloading 10%\rDownloading 50%\rDownloading 100%",
      "Compiling module foo",
      "Compiling module foo",
      "Compiling module foo",
      "Compiling module foo",
      "src/lib.rs:14:5 - error TS2322: Type 'number' is not assignable to type 'string'.",
      "FAILED tests/test_core.py::test_eval - AssertionError: 4 != 5",
      "Finished build.",
    ].join("\n");

    const reduced = reduceStream(raw, { headLimit: 50, tailLimit: 50, dedupRepeats: true });

    // ANSI stripped
    assert(!reduced.text.includes("\x1b["), "ANSI escape codes must be stripped");
    assert(reduced.text.includes("[INFO] Starting compilation..."), "Clean text must be preserved");

    // CR collapsed
    assert(reduced.text.includes("Downloading 100%"), "Carriage return must collapse to final state");
    assert(!reduced.text.includes("Downloading 10%"), "Previous CR progress states must be overwritten");

    // Consecutive duplicates deduplicated
    assert(
      reduced.text.includes("... [repeated 3 more times] ..."),
      "Repeated lines must be collapsed with repeat marker"
    );

    // Diagnostics extracted
    assert.strictEqual(reduced.diagnostics.errors, 1, "Must extract 1 tsc error");
    assert.strictEqual(reduced.diagnostics.failures, 1, "Must extract 1 pytest failure");
    assert.strictEqual(reduced.diagnostics.diagnostics.length, 2);

    const tscDiag = reduced.diagnostics.diagnostics[0];
    assert.strictEqual(tscDiag.kind, "tsc");
    assert.strictEqual(tscDiag.file, "src/lib.rs");
    assert.strictEqual(tscDiag.line, 14);

    const pytestDiag = reduced.diagnostics.diagnostics[1];
    assert.strictEqual(pytestDiag.kind, "pytest");
    assert.strictEqual(pytestDiag.file, "tests/test_core.py");
    console.log("  ✓ ANSI stripped, CR collapsed, duplicates deduped, diagnostics structured.");
  }

  // Test 9: Inline Adaptive Digest (§1.5)
  console.log("\n▶ Test 9: Inline Adaptive Digest (inline vs summary)...");
  {
    // Fast short command (<2s, <40 lines) -> inline mode
    const supShort = new ProcessSupervisor();
    const resShort = await supShort.run("node", ["-e", "console.log('clean output');"]);
    assert.strictEqual(resShort.digest.mode, "inline", "Short fast run must return inline digest");
    assert(resShort.digest.text.includes("clean output"));

    // Long command (>40 lines) -> summary mode with navHandles
    const supLong = new ProcessSupervisor();
    const script = "for(let i=0; i<60; i++) console.log(`out line ${i}`);";
    const resLong = await supLong.run("node", ["-e", script]);
    assert.strictEqual(resLong.digest.mode, "summary", "Heavy run (>40 lines) must return summary digest");
    assert(resLong.digest.navHandles, "Summary digest must provide navHandles");
    assert(resLong.digest.navHandles.slice.includes("proc_slice"));
    assert(resLong.digest.navHandles.grep.includes("proc_grep"));
    assert(resLong.digest.navHandles.query.includes("proc_query"));
    console.log("  ✓ Adaptive digest appropriately selects inline vs summary mode.");
  }

  // Test 10: Forced routing with justified bypass (§1.6)
  console.log("\n▶ Test 10: Justified bypass policy validation...");
  {
    // Missing reason must throw
    assert.throws(
      () => {
        new ProcessSupervisor({ bypassReduction: true });
      },
      BypassPolicyViolationError,
      "Must throw BypassPolicyViolationError if bypass_reason is omitted"
    );

    // Short reason (<10 chars) must throw
    assert.throws(
      () => {
        new ProcessSupervisor({ bypassReduction: true, bypassReason: "short" });
      },
      BypassPolicyViolationError,
      "Must throw BypassPolicyViolationError if bypass_reason < 10 characters"
    );

    // Valid reason (>= 10 chars) succeeds
    const sup = new ProcessSupervisor({
      bypassReduction: true,
      bypassReason: "Raw binary payload inspection",
    });
    const res = await sup.run("node", ["-e", "console.log('raw data');"]);
    assert.strictEqual(res.exitCode, 0);
    assert(res.reduced.text.includes("raw data"));
    console.log("  ✓ Bypass policy correctly enforced (>=10 chars requirement).");
  }

  console.log("\n=========================================================");
  console.log("  ALL 10 HOST SUPERVISOR TESTS PASSED CLEANLY (100%)");
  console.log("=========================================================\n");
}

runTests().catch((err) => {
  console.error("\n✗ Test suite failed with error:", err);
  process.exit(1);
});
