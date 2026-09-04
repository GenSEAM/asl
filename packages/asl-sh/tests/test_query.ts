/**
 * Stream Query, Grep & Structured Filter Acceptance Test Suite (@pcp:d-446d)
 *
 * Verifies:
 * 1. In-buffer text & regex pattern search (grepStream)
 * 2. Surrounding context window extraction (beforeContext, afterContext)
 * 3. Inverted match and max match limit (grepStream)
 * 4. Structured jq/yq path navigation (queryStructured) over JSON & embedded logs
 * 5. Array indexing, wildcard mapping, and deep recursive property queries
 * 6. Bounded pagination slicing (sliceStream)
 */

import assert from "assert";
import {
  RingBuffer,
  grepStream,
  queryStructured,
  sliceStream,
} from "../bridge/index.js";

console.log("=========================================================");
console.log("   ASL Stream Query, Grep & Filter Verification Suite    ");
console.log("=========================================================\n");

async function runTests() {
  // Test 1: Exact text grep with line numbers
  console.log("▶ Test 1: Exact text grep with line numbers...");
  {
    const lines = [
      "Starting application server...",
      "Connecting to database at localhost:5432",
      "Database connection established",
      "Listening on port 8080",
    ];

    const res = grepStream(lines, "database");
    assert.strictEqual(res.totalMatches, 1, "Should find 1 match (case sensitive)");
    assert.strictEqual(res.matches.length, 1);
    assert.strictEqual(res.matches[0].lineNumber, 2);
    assert.strictEqual(res.matches[0].lineIndex, 1);
    assert.strictEqual(res.matches[0].line, "Connecting to database at localhost:5432");
    console.log("  ✓ Exact text grep correctly identified line and position.");
  }

  // Test 2: RegExp grep with case insensitivity
  console.log("\n▶ Test 2: Case-insensitive RegExp pattern grep...");
  {
    const lines = [
      "[INFO] Server initialized",
      "[warn] Low memory warning: 85% used",
      "[WARN] High latency detected on worker-3",
      "[ERROR] Connection dropped",
    ];

    const res = grepStream(lines, /warn/i);
    assert.strictEqual(res.totalMatches, 2, "Should find 2 warnings case-insensitively");
    assert.strictEqual(res.matches[0].lineNumber, 2);
    assert.strictEqual(res.matches[1].lineNumber, 3);
    console.log("  ✓ Case-insensitive regex matching verified.");
  }

  // Test 3: Grep with context windows (beforeContext, afterContext)
  console.log("\n▶ Test 3: Grep with before/after context windows...");
  {
    const lines = [
      "line 1: header",
      "line 2: config",
      "line 3: TARGET MATCH",
      "line 4: detail 1",
      "line 5: detail 2",
      "line 6: footer",
    ];

    const res = grepStream(lines, "TARGET MATCH", {
      beforeContext: 2,
      afterContext: 2,
    });

    assert.strictEqual(res.matches.length, 1);
    const m = res.matches[0];
    assert.deepStrictEqual(m.contextBefore, ["line 1: header", "line 2: config"]);
    assert.deepStrictEqual(m.contextAfter, ["line 4: detail 1", "line 5: detail 2"]);
    console.log("  ✓ Context windows correctly captured before and after match.");
  }

  // Test 4: Inverted match (grep -v)
  console.log("\n▶ Test 4: Inverted matching (invertMatch: true)...");
  {
    const lines = [
      "DEBUG: trace 1",
      "INFO: started",
      "DEBUG: trace 2",
      "ERROR: failed",
    ];

    const res = grepStream(lines, "DEBUG", { invertMatch: true });
    assert.strictEqual(res.totalMatches, 2);
    assert.strictEqual(res.matches[0].line, "INFO: started");
    assert.strictEqual(res.matches[1].line, "ERROR: failed");
    console.log("  ✓ Inverted matching correctly filtered matching lines.");
  }

  // Test 5: Max matches limit and hasMore flag
  console.log("\n▶ Test 5: Max match ceiling and hasMore indicator...");
  {
    const lines = Array.from({ length: 50 }, (_, i) => `item error count: ${i}`);
    const res = grepStream(lines, "error", { maxMatches: 5 });

    assert.strictEqual(res.totalMatches, 50, "Total matches count must be 50");
    assert.strictEqual(res.matches.length, 5, "Only 5 matches returned due to maxMatches");
    assert.strictEqual(res.hasMore, true, "hasMore flag must be true");
    console.log("  ✓ Max match ceiling and pagination indicator working.");
  }

  // Test 6: Grep directly on RingBuffer instance
  console.log("\n▶ Test 6: Grep directly on RingBuffer instance...");
  {
    const buf = new RingBuffer();
    buf.append("Worker 1 ready\nWorker 2 busy\nWorker 3 ready\n");
    buf.flush();

    const res = grepStream(buf, "ready");
    assert.strictEqual(res.totalMatches, 2);
    assert.strictEqual(res.matches[0].line, "Worker 1 ready");
    assert.strictEqual(res.matches[1].line, "Worker 3 ready");
    console.log("  ✓ Grep executed directly on RingBuffer instance.");
  }

  // Test 7: Structured path query: simple dot access
  console.log("\n▶ Test 7: Structured path query: simple property access...");
  {
    const payload = JSON.stringify({
      service: "asl-auth",
      status: "healthy",
      uptime: 3600,
    });

    const service = queryStructured(payload, ".service");
    const status = queryStructured(payload, ".status");
    const uptime = queryStructured(payload, ".uptime");

    assert.strictEqual(service, "asl-auth");
    assert.strictEqual(status, "healthy");
    assert.strictEqual(uptime, 3600);
    console.log("  ✓ Simple properties queried successfully.");
  }

  // Test 8: Structured path query: nested property access
  console.log("\n▶ Test 8: Nested property access (.metadata.author.name)...");
  {
    const obj = {
      spec: "1.0.0",
      metadata: {
        cluster: {
          region: "us-east-1",
          nodes: 12,
        },
      },
    };

    const region = queryStructured(obj, ".metadata.cluster.region");
    const nodes = queryStructured(obj, ".metadata.cluster.nodes");
    assert.strictEqual(region, "us-east-1");
    assert.strictEqual(nodes, 12);
    console.log("  ✓ Nested object path traversal verified.");
  }

  // Test 9: Structured path query: array indexing
  console.log("\n▶ Test 9: Array indexing (.items[1])...");
  {
    const data = {
      items: ["alpha", "bravo", "charlie"],
    };

    const first = queryStructured(data, ".items[0]");
    const second = queryStructured(data, ".items[1]");
    const outOfBounds = queryStructured(data, ".items[99]");

    assert.strictEqual(first, "alpha");
    assert.strictEqual(second, "bravo");
    assert.strictEqual(outOfBounds, undefined);
    console.log("  ✓ Array element lookup by index verified.");
  }

  // Test 10: Structured path query: wildcard array extraction (.services[*].name)
  console.log("\n▶ Test 10: Wildcard array projection (.services[*].name)...");
  {
    const cluster = {
      services: [
        { id: "s1", name: "auth", port: 8001 },
        { id: "s2", name: "gateway", port: 8000 },
        { id: "s3", name: "billing", port: 8002 },
      ],
    };

    const names = queryStructured(cluster, ".services[*].name");
    const ports = queryStructured(cluster, ".services[*].port");

    assert.deepStrictEqual(names, ["auth", "gateway", "billing"]);
    assert.deepStrictEqual(ports, [8001, 8000, 8002]);
    console.log("  ✓ Wildcard array projection verified.");
  }

  // Test 11: Deep recursive property query (..key)
  console.log("\n▶ Test 11: Deep recursive property search (..id)...");
  {
    const tree = {
      id: "root",
      children: [
        { id: "node-1", data: { id: "leaf-1" } },
        { id: "node-2", data: { id: "leaf-2" } },
      ],
    };

    const allIds = queryStructured(tree, "..id") as string[];
    assert(Array.isArray(allIds));
    assert.strictEqual(allIds.length, 5);
    assert(allIds.includes("root"));
    assert(allIds.includes("node-1"));
    assert(allIds.includes("leaf-1"));
    assert(allIds.includes("node-2"));
    assert(allIds.includes("leaf-2"));
    console.log("  ✓ Recursive deep property search found all occurrences.");
  }

  // Test 12: Extracting embedded JSON from log lines
  console.log("\n▶ Test 12: Extracting structured JSON embedded in terminal log streams...");
  {
    const logText = `
2026-09-05T01:00:00.000Z [INFO] Initializing service
2026-09-05T01:00:01.000Z [INFO] Output:
{
  "build": {
    "version": "v2.4.0",
    "artifacts": ["main.wasm", "main.d.ts"]
  },
  "success": true
}
2026-09-05T01:00:02.000Z [INFO] Deployment completed
    `;

    const version = queryStructured(logText, ".build.version");
    const success = queryStructured(logText, ".success");
    const artifacts = queryStructured(logText, ".build.artifacts[0]");

    assert.strictEqual(version, "v2.4.0");
    assert.strictEqual(success, true);
    assert.strictEqual(artifacts, "main.wasm");
    console.log("  ✓ Embedded JSON block extracted and queried from log text.");
  }

  // Test 13: Bounded windowed pagination slicing (sliceStream)
  console.log("\n▶ Test 13: Bounded stream slicing and pagination (proc_slice)...");
  {
    const lines = Array.from({ length: 50 }, (_, i) => `log line ${i + 1}`);

    const slice1 = sliceStream(lines, 0, 10);
    assert.strictEqual(slice1.lines.length, 10);
    assert.strictEqual(slice1.startLine, 0);
    assert.strictEqual(slice1.endLine, 10);
    assert.strictEqual(slice1.lines[0], "log line 1");
    assert.strictEqual(slice1.lines[9], "log line 10");
    assert.strictEqual(slice1.hasMore, true);

    const slice2 = sliceStream(lines, 45, 10);
    assert.strictEqual(slice2.lines.length, 5);
    assert.strictEqual(slice2.startLine, 45);
    assert.strictEqual(slice2.endLine, 50);
    assert.strictEqual(slice2.lines[4], "log line 50");
    assert.strictEqual(slice2.hasMore, false);
    console.log("  ✓ Windowed slicing and boundary checks verified.");
  }

  console.log("\n=========================================================");
  console.log("  ALL 13 STREAM QUERY & FILTER TESTS PASSED CLEANLY (100%)");
  console.log("=========================================================\n");
}

runTests().catch((err) => {
  console.error("\n✗ Test suite failed with error:", err);
  process.exit(1);
});
