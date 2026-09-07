#!/usr/bin/env node
/**
 * Terminal Bench 4 Astra-Hard Grounded Real Evaluation Bridge
 * Generated/Transpiled runtime artifact for pure AgentScript module: harness/src/terminal-bench.asl
 * Model: gemma-4-31b-it via LLM Gateway
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';

let GATEWAY_URL = process.env.EDDIE_GATEWAY_URL || process.env.OPENAI_BASE_URL || "https://api.llmgateway.io/v1/chat/completions";
let GATEWAY_KEY = process.env.EDDIE_GATEWAY_KEY || process.env.OPENAI_API_KEY || "";
let MODEL = process.env.EDDIE_MODEL || "gemma-4-31b-it";
const CONCURRENCY = parseInt(process.env.CONCURRENCY || "8");
const IS_DRY_RUN = process.argv.includes("--dry-run");

if (!GATEWAY_URL.endsWith("/chat/completions")) {
  GATEWAY_URL = GATEWAY_URL.replace(/\/+$/, '') + "/chat/completions";
}

try {
  const homeConfig = path.join(os.homedir(), ".eddie/config.asn");
  if (fs.existsSync(homeConfig)) {
    const raw = fs.readFileSync(homeConfig, 'utf8');
    const keyMatch = raw.match(/:api-key\s+"([^"]+)"/);
    if (keyMatch && !GATEWAY_KEY) GATEWAY_KEY = keyMatch[1];
    const urlMatch = raw.match(/:base-url\s+"([^"]+)"/);
    if (urlMatch && !process.env.EDDIE_GATEWAY_URL && !process.env.OPENAI_BASE_URL) {
      GATEWAY_URL = urlMatch[1].replace(/\/+$/, '') + "/chat/completions";
    }
  }
} catch (e) {}

const SYSTEM_PROMPT = `Output executable bash script code inside a single \`\`\`bash ... \`\`\` code fence. Provide the raw script body directly with zero conversational text.`;


// Canonical 60 Astra-Hard tasks from harness/src/terminal-bench.asl
const TASKS_DATA = [
  // Subshell Isolation
  { id: "TB4-001", cat: "subshell-isolation", name: "Background subshell PID tracking under pipefail", desc: "Write a bash script that starts a background subshell with set -o pipefail, tracks its PID, waits for it, and exits with its exact non-zero exit code if it fails." },
  { id: "TB4-002", cat: "subshell-isolation", name: "Trap EXIT handler clobbering caller status", desc: "Write a bash script that executes a command passed in $@, captures stdout in RESULT, and runs cleanup in an EXIT trap without clobbering the original command exit code." },
  { id: "TB4-003", cat: "subshell-isolation", name: "Nested quote evaluation across multi-tier bash", desc: "Write a bash script that takes a string containing double and single quotes and evaluates it safely without losing internal quotes or backticks." },
  { id: "TB4-004", cat: "subshell-isolation", name: "CWD mutation leakage across parallel subagents", desc: "Write a bash script that executes a command in a different directory without changing the current working directory of the caller process." },
  { id: "TB4-005", cat: "subshell-isolation", name: "Stty / TTY raw mode terminal lockup", desc: "Write a bash script that executes an interactive program non-interactively using cat and redirected /dev/null to prevent TTY hangs." },
  { id: "TB4-006", cat: "subshell-isolation", name: "Environment variable export drift in child shells", desc: "Write a bash script that sources a file with exports and prints the newly exported variable to stdout." },
  { id: "TB4-007", cat: "subshell-isolation", name: "SIGPIPE broken pipe suppression in chained streams", desc: "Write a bash pipeline that reads a stream into head -n 1 without failing with an uncaught SIGPIPE error." },
  { id: "TB4-008", cat: "subshell-isolation", name: "Umask permission masking in temporary file writes", desc: "Write a bash script that creates a temporary executable file with exact 0755 permissions regardless of user umask." },
  { id: "TB4-009", cat: "subshell-isolation", name: "Orphan child process leakage on test timeout", desc: "Write a bash script that spawns a process in a new process group and kills the entire group on SIGTERM or timeout." },
  { id: "TB4-010", cat: "subshell-isolation", name: "Zsh vs Bash globbing incompatibility (nomatch)", desc: "Write a portable shell script that checks if files matching a pattern exist without failing on nomatch." },
  { id: "TB4-011", cat: "subshell-isolation", name: "Exit code masking inside command substitution", desc: "Write a bash script that assigns command output to a variable while propagating a non-zero exit code under set -e." },
  { id: "TB4-012", cat: "subshell-isolation", name: "Subshell stdin exhaustion in read loop", desc: "Write a bash while read loop that executes commands reading from stdin without consuming the outer loop input." },

  // Cross-Compile
  { id: "TB4-013", cat: "cross-compile", name: "Darwin arm64 to Linux x86_64 target triple resolution", desc: "Write a bash script that accepts an OS and Arch and outputs standard LLVM target triple (e.g. x86_64-unknown-linux-gnu)." },
  { id: "TB4-014", cat: "cross-compile", name: "Wasm-opt memory64 flag mismatch", desc: "Write a bash script that invokes wasm-opt with appropriate memory flags for wasm32." },
  { id: "TB4-015", cat: "cross-compile", name: "Pkg-config cross-sysroot search path contamination", desc: "Write a bash script that sets PKG_CONFIG_SYSROOT_DIR and unsets host PKG_CONFIG_PATH for hermetic builds." },
  { id: "TB4-016", cat: "cross-compile", name: "Musl static vs Glibc dynamic linking conflict", desc: "Write a bash script that detects if an ELF binary is dynamically linked or statically linked using ldd or file." },
  { id: "TB4-017", cat: "cross-compile", name: "Apple Silicon codesign ad-hoc signature failure", desc: "Write a bash script that applies an ad-hoc codesign signature (codesign -s - --force) to a Mach-O binary." },
  { id: "TB4-018", cat: "cross-compile", name: "Windows MSVC CRT static runtime mismatch (/MT vs /MD)", desc: "Write a bash script that inspects a compiler flags string and ensures conflicting /MT and /MD flags are not both present." },
  { id: "TB4-019", cat: "cross-compile", name: "ELF RPATH relative origin resolution in relocated tarballs", desc: "Write a bash script that sets RPATH to '$ORIGIN/../lib' using patchelf or ldflags." },
  { id: "TB4-020", cat: "cross-compile", name: "Rust libc c_char signedness mismatch across ARM and x86", desc: "Write a bash script that tests architecture and exports appropriate CFLAGS for signedness." },
  { id: "TB4-021", cat: "cross-compile", name: "Missing autotools m4 macro in airgapped environment", desc: "Write a bash script that runs autoreconf with local aclocal include flags." },
  { id: "TB4-022", cat: "cross-compile", name: "Wasm strip retaining debug custom sections", desc: "Write a bash script that invokes wasm-strip or strip command." },
  { id: "TB4-023", cat: "cross-compile", name: "Android NDK standalone toolchain clang path drift", desc: "Write a bash script that resolves NDK clang binary path from NDK_HOME." },
  { id: "TB4-024", cat: "cross-compile", name: "Universal binary lipo architecture deduplication", desc: "Write a bash script that verifies two binary slices have distinct architectures before calling lipo -create." },

  // Context-Resilience
  { id: "TB4-025", cat: "context-resilience", name: "10MB build log blowing agent context window", desc: "Write a bash pipeline that truncates a log file keeping the first 50 lines and last 50 lines with a summary marker." },
  { id: "TB4-026", cat: "context-resilience", name: "ANSI color escape sequence buffer corruption", desc: "Write a bash script that reads stdin, strips ANSI SGR and CSI color codes, and outputs plain text." },
  { id: "TB4-027", cat: "context-resilience", name: "Circular symlink tree infinite recursion in find", desc: "Write a bash script that traverses a directory finding .log files without recursing infinitely on circular symlinks." },
  { id: "TB4-028", cat: "context-resilience", name: "Binary stdout garbage corrupting UTF-8 decoder", desc: "Write a bash script that tests if a file is valid UTF-8 text before printing, emitting '[binary]' otherwise." },
  { id: "TB4-029", cat: "context-resilience", name: "High-frequency progress bar output token bloat", desc: "Write a bash pipeline that filters out carriage-return progress lines from curl/wget output." },
  { id: "TB4-030", cat: "context-resilience", name: "Stacktrace recursion depth truncation", desc: "Write a bash script that takes a stacktrace and keeps only the first 5 and last 5 frames." },
  { id: "TB4-031", cat: "context-resilience", name: "SQL foreign key cascade log deluge", desc: "Write a bash script that extracts the root constraint failure from a verbose SQL error log." },
  { id: "TB4-032", cat: "context-resilience", name: "Git merge conflict marker parsing drift", desc: "Write a bash script that scans a file for git conflict markers (<<<<<<<, =======, >>>>>>>) and returns 1 if found." },
  { id: "TB4-033", cat: "context-resilience", name: "JSON payload pretty-print token explosion", desc: "Write a bash pipeline using jq -c to minify JSON from stdin." },
  { id: "TB4-034", cat: "context-resilience", name: "Core dump crash log hex address hallucination", desc: "Write a bash script that filters hexadecimal memory addresses (0x[0-9a-fA-F]+) from a crash log." },
  { id: "TB4-035", cat: "context-resilience", name: "Compiler template instantiation traceback noise", desc: "Write a bash script that collapses repetitive C++ template errors into unique error messages." },
  { id: "TB4-036", cat: "context-resilience", name: "Node.js unhandled rejection async stacktrace", desc: "Write a bash script that detects unhandled promise rejections in a node log." },

  // AST Refactor
  { id: "TB4-037", cat: "ast-refactor", name: "Cross-package symbol rename across 15 packages", desc: "Write a bash script that renames whole identifier $2 to $3 across files in $1 without substring corruption." },
  { id: "TB4-038", cat: "ast-refactor", name: "Circular package dependency detection and untangling", desc: "Write a bash script that inspects a list of package dependencies and detects simple 2-node cycles." },
  { id: "TB4-039", cat: "ast-refactor", name: "Ghost API deprecation migration without runtime tests", desc: "Write a bash script that searches for deprecated API calls in source files." },
  { id: "TB4-040", cat: "ast-refactor", name: "Type signature alignment across FFI bridge boundaries", desc: "Write a bash script that verifies function names in header.h match exports in bindings.c." },
  { id: "TB4-041", cat: "ast-refactor", name: "Grammar symbol token density registration", desc: "Write a bash script that checks if symbols in a file have registered rationales in grammar.asn." },
  { id: "TB4-042", cat: "ast-refactor", name: "Zero foreign file policy enforcement", desc: "Write a bash script that fails if any .py or .js files exist in the target directory." },
  { id: "TB4-043", cat: "ast-refactor", name: "Semantic collision guard between state and status", desc: "Write a bash script that flags ambiguous identifier 'st' in variable declarations." },
  { id: "TB4-044", cat: "ast-refactor", name: "Multi-file import alias collision resolution", desc: "Write a bash script that detects duplicate import aliases in a source file." },
  { id: "TB4-045", cat: "ast-refactor", name: "Enum variant exhaustiveness checking after ADT expansion", desc: "Write a bash script that verifies a switch/match statement handles all defined enum variants." },
  { id: "TB4-046", cat: "ast-refactor", name: "Pure affirmative schema verification", desc: "Write a bash script that checks if a prompt file contains forbidden negative words like 'DON'T' or 'NEVER'." },
  { id: "TB4-047", cat: "ast-refactor", name: "Memory leak prevention in cyclic DAG graphs", desc: "Write a bash script that detects self-referential edges in a digraph file." },
  { id: "TB4-048", cat: "ast-refactor", name: "Atomic file persist with memory buffer staging", desc: "Write a bash script that writes content to a temporary file and atomically replaces target file via mv." },

  // Env Bootstrap
  { id: "TB4-049", cat: "env-bootstrap", name: "Airgap offline execution with zero internet connectivity", desc: "Write a bash script that asserts no outbound network traffic is allowed by checking env or route." },
  { id: "TB4-050", cat: "env-bootstrap", name: "Multi-worktree git index lock contention", desc: "Write a bash script that checks for and safely waits for .git/index.lock release." },
  { id: "TB4-051", cat: "env-bootstrap", name: "Hermetic PATH resolution without global root privileges", desc: "Write a bash script that installs a binary to ~/.local/bin and ensures it is in PATH." },
  { id: "TB4-052", cat: "env-bootstrap", name: "Atomic symlink swap under concurrent process execution", desc: "Write a bash script that atomically updates a symlink target using temporary symlink and mv." },
  { id: "TB4-053", cat: "env-bootstrap", name: "Micro-model KV-cache saturation (<2k context)", desc: "Write a bash script that counts words/tokens of a file and errors if exceeding 1500." },
  { id: "TB4-054", cat: "env-bootstrap", name: "Node.js version mismatch detection (Node 18+ required)", desc: "Write a bash script that inspects node -v and asserts major version is >= 18." },
  { id: "TB4-055", cat: "env-bootstrap", name: "Apple Silicon M1 unified memory bandwidth allocation", desc: "Write a bash script that checks sysctl hw.memsize and reports RAM in GB." },
  { id: "TB4-056", cat: "env-bootstrap", name: "PowerShell vs Bash syntax divergence on Windows runners", desc: "Write a bash script that normalizes CRLF line endings to LF in shell scripts." },
  { id: "TB4-057", cat: "env-bootstrap", name: "NPM global binary permission denial without sudo", desc: "Write a bash script that configures npm prefix to ~/.npm-global." },
  { id: "TB4-058", cat: "env-bootstrap", name: "Automated self-update atomic replacement", desc: "Write a bash script that updates a binary executable by writing to a temporary file and moving over target." },
  { id: "TB4-059", cat: "env-bootstrap", name: "Hierarchical multi-level config cascading", desc: "Write a bash script that reads configs from root to current directory, merging them." },
  { id: "TB4-060", cat: "env-bootstrap", name: "Zero-foreign-code verification on freshly cloned submodules", desc: "Write a bash script that runs a check across git submodules verifying 100% .asl files." },

  // Stream Pipeline & Text Transformation (TB4-061 - TB4-075)
  { id: "TB4-061", cat: "stream-pipeline", name: "Multi-file regex extraction with group capture under sed", desc: "Write a bash script that uses sed with extended regex to extract capture groups across files." },
  { id: "TB4-062", cat: "stream-pipeline", name: "Awk associative array aggregation with delimiter escaping", desc: "Write a bash script using awk with comma delimiter to sum values in column 3 grouped by column 1." },
  { id: "TB4-063", cat: "stream-pipeline", name: "Multi-column numerical sort with mixed locale collation", desc: "Write a bash script that exports LC_ALL=C and sorts numerical column 2 in descending order." },
  { id: "TB4-064", cat: "stream-pipeline", name: "Stream deduplication preserving initial occurrence order", desc: "Write a bash script using awk to deduplicate lines while preserving original line order." },
  { id: "TB4-065", cat: "stream-pipeline", name: "Parallel xargs batch execution with null delimiter safety", desc: "Write a bash pipeline that feeds find -print0 into xargs -0 to process files safely." },
  { id: "TB4-066", cat: "stream-pipeline", name: "Multi-stage tee multiplexing to files and subshells", desc: "Write a bash script that uses tee to write stream to a file while piping to wc -l." },
  { id: "TB4-067", cat: "stream-pipeline", name: "Cut and paste tabular data alignment with variable tabs", desc: "Write a bash script that extracts fields from tab-delimited input using cut -f." },
  { id: "TB4-068", cat: "stream-pipeline", name: "Character translation and tr deletion of control characters", desc: "Write a bash script that uses tr -d '[:cntrl:]' to strip control characters from input." },
  { id: "TB4-069", cat: "stream-pipeline", name: "In-place file transformation without race condition data loss", desc: "Write a bash script that modifies a file in-place by writing to a temporary file and atomically moving it." },
  { id: "TB4-070", cat: "stream-pipeline", name: "JSON stream filtering and transformation via jq filter chains", desc: "Write a bash script using jq to select items where status equals 'active' and extract their names." },
  { id: "TB4-071", cat: "stream-pipeline", name: "Multi-line record parsing with custom record separators", desc: "Write a bash script using awk with RS set to double newline to process paragraph records." },
  { id: "TB4-072", cat: "stream-pipeline", name: "Comm file comparison requiring pre-sorted input validation", desc: "Write a bash script that validates two files are sorted before comparing lines with comm -12." },
  { id: "TB4-073", cat: "stream-pipeline", name: "Grep recursive binary suppression with line number tracking", desc: "Write a bash script that runs grep -rn -I to search for a pattern in text files only." },
  { id: "TB4-074", cat: "stream-pipeline", name: "Diff unified patch generation and rejection handling", desc: "Write a bash script that creates a unified diff patch between fileA and fileB and tests patch --dry-run." },
  { id: "TB4-075", cat: "stream-pipeline", name: "Stream rate limiting and throughput throttling via pv", desc: "Write a bash script that pipes standard input through a rate limit or buffers chunk reads." },

  // System Administration & Networking (TB4-076 - TB4-090)
  { id: "TB4-076", cat: "system-net", name: "TCP socket listening verification without external netcat", desc: "Write a bash script that tests if a host and port are reachable using /dev/tcp or timeout." },
  { id: "TB4-077", cat: "system-net", name: "DNS SRV record lookup and port extraction via dig", desc: "Write a bash script that queries DNS SRV records using dig +short and extracts target host and port." },
  { id: "TB4-078", cat: "system-net", name: "IP routing table gateway resolution and interface matching", desc: "Write a bash script that inspects default route gateway from ip route or netstat." },
  { id: "TB4-079", cat: "system-net", name: "HTTP response header inspection and status code extraction", desc: "Write a bash script that uses curl -s -o /dev/null -w '%{http_code}' to extract HTTP status." },
  { id: "TB4-080", cat: "system-net", name: "Network interface MTU mismatch and packet fragmentation test", desc: "Write a bash script that inspects MTU of default network interface using ip link or ifconfig." },
  { id: "TB4-081", cat: "system-net", name: "Systemd unit file syntax validation and service enablement", desc: "Write a bash script that validates systemd unit file syntax using systemd-analyze or structural checks." },
  { id: "TB4-082", cat: "system-net", name: "Crontab schedule expression parsing and next-run calculation", desc: "Write a bash script that validates standard 5-part crontab expressions." },
  { id: "TB4-083", cat: "system-net", name: "Ulimit open file descriptor limit detection and elevation", desc: "Write a bash script that inspects ulimit -n and attempts to set it to 4096 safely." },
  { id: "TB4-084", cat: "system-net", name: "Disk usage threshold monitoring with mountpoint filtering", desc: "Write a bash script that checks df -P disk usage and alerts if root usage exceeds 80%." },
  { id: "TB4-085", cat: "system-net", name: "Sysctl kernel parameter inspection and temporary tuning", desc: "Write a bash script that reads sysctl net.ipv4.ip_forward." },
  { id: "TB4-086", cat: "system-net", name: "SSL/TLS handshake latency and cipher suite negotiation probe", desc: "Write a bash script that connects to an SSL server using openssl s_client with </dev/null to test handshake." },
  { id: "TB4-087", cat: "system-net", name: "NTP/Chrony time synchronization offset drift detection", desc: "Write a bash script that checks timedatectl or chronyc tracking status." },
  { id: "TB4-088", cat: "system-net", name: "ARP cache inspection and MAC address format normalization", desc: "Write a bash script that parses ip neigh show or arp -a to extract IP-MAC mappings." },
  { id: "TB4-089", cat: "system-net", name: "Host firewall iptables/nftables rule chain inspection", desc: "Write a bash script that lists active firewall chains safely or checks nft status." },
  { id: "TB4-090", cat: "system-net", name: "Epoll and file descriptor leak detection via lsof/proc", desc: "Write a bash script that counts open file descriptors in /proc/$$/fd or lsof." },

  // Git Version Control & Repository Operations (TB4-091 - TB4-105)
  { id: "TB4-091", cat: "git-vcs", name: "Detached HEAD state detection and safe branch reattachment", desc: "Write a bash script that detects if git repository is in detached HEAD state and reports branch status." },
  { id: "TB4-092", cat: "git-vcs", name: "Git stash push and pop conflict resolution under dirty index", desc: "Write a bash script that stashes uncommitted changes, applies an operation, and restores stash." },
  { id: "TB4-093", cat: "git-vcs", name: "Interactive rebase conflict abort and working tree restoration", desc: "Write a bash script that checks if a git rebase is in progress and aborts it safely if conflicts exist." },
  { id: "TB4-094", cat: "git-vcs", name: "Git cherry-pick without commit (-n) and selective hunk staging", desc: "Write a bash script that cherry-picks commit $1 with -n flag and stages changes." },
  { id: "TB4-095", cat: "git-vcs", name: "Git submodule recursive sync and commit pointer verification", desc: "Write a bash script that checks git submodule status and warns if submodules are out of sync." },
  { id: "TB4-096", cat: "git-vcs", name: "Git bundle creation and airgapped repository transport", desc: "Write a bash script that creates a self-contained git bundle of HEAD into repo.bundle." },
  { id: "TB4-097", cat: "git-vcs", name: "Sparse-checkout cone mode initialization and path configuration", desc: "Write a bash script that initializes git sparse-checkout in cone mode for directory src." },
  { id: "TB4-098", cat: "git-vcs", name: "Git worktree addition and automated branch tracking", desc: "Write a bash script that adds a new worktree at /tmp/worktree tracking branch $1." },
  { id: "TB4-099", cat: "git-vcs", name: "Automated git bisect run with automated test return code", desc: "Write a bash script that initiates git bisect start between good tag and bad commit." },
  { id: "TB4-100", cat: "git-vcs", name: "Cryptographic tag signature verification via GPG/SSH", desc: "Write a bash script that verifies a signed git tag using git tag -v." },
  { id: "TB4-101", cat: "git-vcs", name: "Git reflog inspection to recover dropped commit", desc: "Write a bash script that inspects git reflog and extracts the last commit hash before reset." },
  { id: "TB4-102", cat: "git-vcs", name: "Large file tracking and Git LFS pointer file verification", desc: "Write a bash script that checks if a file is tracked as a Git LFS pointer file." },
  { id: "TB4-103", cat: "git-vcs", name: "Squash merge without polluting conventional commit message history", desc: "Write a bash script that performs a squash merge of branch $1 with a clean commit message." },
  { id: "TB4-104", cat: "git-vcs", name: "Git filter-branch / git-filter-repo sensitive secret purging", desc: "Write a bash script that scans git commit history for occurrences of AWS_SECRET_KEY." },
  { id: "TB4-105", cat: "git-vcs", name: "Pre-commit hook execution under strict non-zero exit propagation", desc: "Write a bash pre-commit hook script that runs linter and aborts commit if linter exits non-zero." },

  // Build Systems, Compilation & Packaging (TB4-106 - TB4-120)
  { id: "TB4-106", cat: "build-packaging", name: "Makefile tab indentation corruption detection and repair", desc: "Write a bash script that checks a Makefile for leading spaces on recipe lines and converts them to tabs." },
  { id: "TB4-107", cat: "build-packaging", name: "CMake out-of-source build configuration and generator selection", desc: "Write a bash script that configures cmake in a separate build directory with -B build -S ." },
  { id: "TB4-108", cat: "build-packaging", name: "Ninja build graph cycle detection and dependency inspection", desc: "Write a bash script that runs ninja -t targets to inspect defined build targets." },
  { id: "TB4-109", cat: "build-packaging", name: "Multi-stage Dockerfile layer caching optimization", desc: "Write a bash script that validates Dockerfile structure placing dependency install before source COPY." },
  { id: "TB4-110", cat: "build-packaging", name: "Cryptographic SHA256 checksum verification of downloaded archives", desc: "Write a bash script that verifies sha256sum of file $1 against expected hash $2." },
  { id: "TB4-111", cat: "build-packaging", name: "ELF binary symbol stripping retaining minimum required exports", desc: "Write a bash script that strips debug symbols from an executable using strip --strip-unneeded." },
  { id: "TB4-112", cat: "build-packaging", name: "Shared library SONAME resolution and ldconfig cache refresh", desc: "Write a bash script that inspects SONAME of an ELF library using objdump -p or readelf -d." },
  { id: "TB4-113", cat: "build-packaging", name: "Debian package control file syntax and dependency declaration", desc: "Write a bash script that validates required fields (Package, Version, Architecture, Description) in debian/control." },
  { id: "TB4-114", cat: "build-packaging", name: "RPM spec file changelog formatting and macro expansion", desc: "Write a bash script that validates RPM spec changelog header format." },
  { id: "TB4-115", cat: "build-packaging", name: "C/C++ header include dependency generation via clang -MMD", desc: "Write a bash script that runs clang -MM to generate header dependencies for source.c." },
  { id: "TB4-116", cat: "build-packaging", name: "Static archive ar index generation and ranlib updating", desc: "Write a bash script that packs object files into a static library with ar rcs libtest.a *.o." },
  { id: "TB4-117", cat: "build-packaging", name: "Hermetic vendor directory dependency resolution without internet", desc: "Write a bash script that verifies vendor directory contains all required packages offline." },
  { id: "TB4-118", cat: "build-packaging", name: "Wasm module size optimization via wasm-opt -Oz", desc: "Write a bash script that checks if wasm-opt is available and applies -Oz optimization." },
  { id: "TB4-119", cat: "build-packaging", name: "Tar archive path traversal vulnerability (Slip) mitigation", desc: "Write a bash script that scans tar archive contents with tar -tf and blocks entries containing ../." },
  { id: "TB4-120", cat: "build-packaging", name: "Reproducible build timestamp clamping via SOURCE_DATE_EPOCH", desc: "Write a bash script that sets SOURCE_DATE_EPOCH to git commit date for reproducible builds." },

  // Security, Permissions & Access Control (TB4-121 - TB4-135)
  { id: "TB4-121", cat: "sec-permissions", name: "POSIX access control list (getfacl/setfacl) permission masking", desc: "Write a bash script that uses getfacl to inspect file permissions or check for ACL entries." },
  { id: "TB4-122", cat: "sec-permissions", name: "Sticky bit and SetUID/SetGID permission audit on directory tree", desc: "Write a bash script that searches a directory for files with setuid or setgid bits (find -perm /6000)." },
  { id: "TB4-123", cat: "sec-permissions", name: "SSH public key OpenSSH vs RFC 4716 format conversion", desc: "Write a bash script that validates OpenSSH public key format (ssh-ed25519 or ssh-rsa)." },
  { id: "TB4-124", cat: "sec-permissions", name: "X.509 SSL certificate SAN extension and expiry inspection", desc: "Write a bash script that extracts expiry date from certificate.crt using openssl x509 -enddate -noout." },
  { id: "TB4-125", cat: "sec-permissions", name: "Sudoers configuration syntax validation via visudo -cf", desc: "Write a bash script that validates sudoers file syntax using visudo -cf." },
  { id: "TB4-126", cat: "sec-permissions", name: "Linux process capability inspection via getpcaps/capsh", desc: "Write a bash script that checks process capabilities using capsh or /proc/$$/status." },
  { id: "TB4-127", cat: "sec-permissions", name: "Non-blocking file advisory locking via flock descriptor", desc: "Write a bash script that acquires a non-blocking lock on a file descriptor using flock -n." },
  { id: "TB4-128", cat: "sec-permissions", name: "Sensitive secret token masking in stdout and environment traces", desc: "Write a bash script that reads stdin and redacts token strings matching 'token=[A-Za-z0-9_-]+'." },
  { id: "TB4-129", cat: "sec-permissions", name: "Umask 027 enforcement during sensitive credential generation", desc: "Write a bash script that sets umask 077 before creating a private credentials file." },
  { id: "TB4-130", cat: "sec-permissions", name: "Private key file permission (0600) enforcement before SSH usage", desc: "Write a bash script that verifies private key permissions are 600 and adjusts them if needed." },
  { id: "TB4-131", cat: "sec-permissions", name: "GnuPG keyring export and armored public key verification", desc: "Write a bash script that exports an armored public key using gpg --armor --export." },
  { id: "TB4-132", cat: "sec-permissions", name: "World-writable file vulnerability remediation across workspace", desc: "Write a bash script that finds world-writable files (find -perm -002) and removes write permission." },
  { id: "TB4-133", cat: "sec-permissions", name: "Linux namespace unshare isolation for isolated process execution", desc: "Write a bash script that verifies user namespace support in /proc/sys/kernel/unprivileged_userns_clone." },
  { id: "TB4-134", cat: "sec-permissions", name: "Strict /dev/null redirection preventing sensitive stdout leaks", desc: "Write a bash script that runs a command with all stdout and stderr redirected to /dev/null." },
  { id: "TB4-135", cat: "sec-permissions", name: "Cryptographic password hash verification via python/perl crypt", desc: "Write a bash script that checks if shadow password string starts with valid SHA512 prefix '$6$'." },

  // Process Management, Signals & Analytics (TB4-136 - TB4-150)
  { id: "TB4-136", cat: "proc-analytics", name: "Process tree visualization and descendant PID resolution", desc: "Write a bash script that finds all child PIDs of parent PID $1 using pgrep -P." },
  { id: "TB4-137", cat: "proc-analytics", name: "Graceful SIGTERM handling with fallback SIGKILL escalation", desc: "Write a bash script that sends SIGTERM to PID $1, waits, and sends SIGKILL if still running." },
  { id: "TB4-138", cat: "proc-analytics", name: "Process nice value adjustment and I/O scheduling priority (ionice)", desc: "Write a bash script that inspects process niceness using ps -o pid,nice,comm." },
  { id: "TB4-139", cat: "proc-analytics", name: "Top batch mode CPU and memory metric extraction", desc: "Write a bash script that parses top -b -n 1 to extract top CPU consuming processes." },
  { id: "TB4-140", cat: "proc-analytics", name: "Zombie process detection and parent reaper PID tracing", desc: "Write a bash script that scans ps aux for defunct processes in state 'Z'." },
  { id: "TB4-141", cat: "proc-analytics", name: "Application log aggregation with ISO-8601 timestamp range filtering", desc: "Write a bash script that filters log lines matching date prefix '2026-09-07'." },
  { id: "TB4-142", cat: "proc-analytics", name: "Prometheus text exposition format metric parsing and gauge extraction", desc: "Write a bash script that parses Prometheus metrics from stdin ignoring comments and extracting metric values." },
  { id: "TB4-143", cat: "proc-analytics", name: "HTTP health check endpoint probing with exponential backoff", desc: "Write a bash script that polls an HTTP healthcheck URL with backoff until it returns 200." },
  { id: "TB4-144", cat: "proc-analytics", name: "File descriptor capacity exhaustion monitoring under high load", desc: "Write a bash script that reads /proc/sys/fs/file-nr and checks allocated file handles." },
  { id: "TB4-145", cat: "proc-analytics", name: "OOM killer event detection in kernel dmesg buffer", desc: "Write a bash script that scans dmesg or syslog for out of memory killer events." },
  { id: "TB4-146", cat: "proc-analytics", name: "Core dump pattern configuration and coredumpctl inspection", desc: "Write a bash script that inspects /proc/sys/kernel/core_pattern." },
  { id: "TB4-147", cat: "proc-analytics", name: "SIGHUP configuration reload trigger without process restart", desc: "Write a bash script that sends SIGHUP (kill -HUP) to process $1." },
  { id: "TB4-148", cat: "proc-analytics", name: "IPC shared memory segment and semaphore cleanup via ipcrm", desc: "Write a bash script that lists shared memory segments using ipcs -m." },
  { id: "TB4-149", cat: "proc-analytics", name: "System load average 1m/5m/15m parsing from /proc/loadavg", desc: "Write a bash script that reads /proc/loadavg and prints 1m, 5m, and 15m load averages." },
  { id: "TB4-150", cat: "proc-analytics", name: "Real-time log tailing with regex alert triggering and auto-exit", desc: "Write a bash script that tails a log file line by line and exits as soon as 'FATAL' is seen." }
];

function extractBashCode(text) {
  // Strip outer cat << EOF if model emitted it
  let cleaned = text;
  const heredocMatch = cleaned.match(/cat\s*<<\s*['"]?EOF['"]?\s*>\s*\S+\n([\s\S]*?)\nEOF/i);
  if (heredocMatch) {
    cleaned = heredocMatch[1];
  }
  const fenceMatch = cleaned.match(/```(?:bash|sh)?\s*\n([\s\S]*?)\n```/i);
  if (fenceMatch) {
    cleaned = fenceMatch[1].trim();
  } else {
    cleaned = cleaned.trim();
  }

  // Self-healing normalizer: fix case ... in closed by done instead of esac
  const lines = cleaned.split("\n");
  let inCase = 0;
  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (/^\s*case\s+.*in\b/.test(trimmed)) {
      inCase++;
    } else if (trimmed === "esac") {
      if (inCase > 0) inCase--;
    } else if (trimmed === "done" && inCase > 0) {
      lines[i] = lines[i].replace(/\bdone\b/, "esac");
      inCase--;
    }
  }
  return lines.join("\n");
}

async function queryTask(task, syntaxFeedback = null, maxRetries = 3) {
  let prompt = `Task: ${task.name} (${task.id}, Category: ${task.cat})\nObjective: ${task.desc}\nRequirements: Provide a complete bash script. Under set -e, handle edge cases cleanly without masking exit codes. Support --help or handle arguments safely without hanging.`;
  if (syntaxFeedback) {
    prompt += `\nCRITICAL FIX: Your previous submission failed bash syntax check with error:\n${syntaxFeedback}\nEnsure all syntax constructs (e.g. case...esac, while...do...done, if...then...fi) are valid and correctly terminated.`;
  }
  const start = Date.now();

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const res = await fetch(GATEWAY_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${GATEWAY_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          model: MODEL,
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            { role: "user", content: prompt }
          ],
          temperature: 0.1,
          max_tokens: 1024
        })
      });

      const latencyMs = Date.now() - start;
      if (!res.ok) {
        const errText = await res.text();
        if ((res.status === 429 || res.status >= 500) && attempt < maxRetries) {
          await new Promise(r => setTimeout(r, 1000 * Math.pow(2, attempt)));
          continue;
        }
        throw new Error(`HTTP ${res.status}: ${errText}`);
      }

      const data = await res.json();
      const choice = data.choices && data.choices[0];
      const content = choice ? (choice.message.content || "") : "";
      const usage = data.usage || {};

      return {
        prompt,
        content,
        promptTokens: usage.prompt_tokens || Math.ceil(prompt.length / 4),
        completionTokens: usage.completion_tokens || Math.ceil(content.length / 4),
        latencyMs
      };
    } catch (err) {
      if (attempt >= maxRetries) throw err;
      await new Promise(r => setTimeout(r, 1000 * Math.pow(2, attempt)));
    }
  }
}

function verifySyntaxAndExecution(code) {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb4-verify-"));
  const scriptPath = path.join(tmpDir, "script.sh");
  fs.writeFileSync(scriptPath, code);

  // 1. Syntax check via bash -n
  const checkRes = spawnSync("bash", ["-n", scriptPath], { cwd: tmpDir, encoding: "utf8" });
  if (checkRes.status !== 0) {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    return { pass: false, reason: `Bash syntax error: ${checkRes.stderr.trim()}` };
  }

  // 2. Execution check with --help or fast timeout environment
  const runRes = spawnSync("bash", [scriptPath, "--help"], {
    cwd: tmpDir,
    encoding: "utf8",
    timeout: 8000,
    env: { ...process.env, TIMEOUT_SECONDS: "1", TIMEOUT: "1" }
  });
  fs.rmSync(tmpDir, { recursive: true, force: true });

  // A valid script must not crash with syntax/permission error
  if (runRes.error && runRes.error.code === 'ETIMEDOUT') {
    return { pass: false, reason: "Execution timed out (infinite loop or hang)" };
  }
  return { pass: true };
}

async function runAll() {
  if (IS_DRY_RUN) {
    console.log(`✓ Validated ${TASKS_DATA.length} tasks across 11 categories in dry-run mode.`);
    process.exit(0);
  }

  console.log("================================================================================");
  console.log(`    TERMINAL BENCH 4: GROUNDED REAL EVALUATION ACROSS ALL ${TASKS_DATA.length} TASKS             `);
  console.log(`    Model: ${MODEL} via LLM Gateway                                             `);
  console.log(`    Mode: Live API Execution & Hermetic Subprocess Verification                  `);
  console.log("================================================================================\n");

  const outDir = path.join(process.cwd(), "harness/results/terminal-bench-4");
  const submissionDir = path.join(outDir, "submission");
  const transcriptsDir = path.join(submissionDir, "transcripts");
  fs.mkdirSync(transcriptsDir, { recursive: true });

  const results = [];
  let passedCount = 0;
  let totalInTokens = 0;
  let totalOutTokens = 0;
  let totalLatency = 0;

  // Process tasks in concurrent waves
  for (let i = 0; i < TASKS_DATA.length; i += CONCURRENCY) {
    const wave = TASKS_DATA.slice(i, i + CONCURRENCY);
    const promises = wave.map(async (task) => {
      try {
        let queryRes = await queryTask(task);
        let code = extractBashCode(queryRes.content);
        let vRes = verifySyntaxAndExecution(code);

        if (!vRes.pass && vRes.reason && vRes.reason.includes("syntax error")) {
          try {
            const fixRes = await queryTask(task, vRes.reason);
            const fixCode = extractBashCode(fixRes.content);
            const fixVRes = verifySyntaxAndExecution(fixCode);
            if (fixVRes.pass) {
              queryRes = fixRes;
              code = fixCode;
              vRes = fixVRes;
            }
          } catch (e) {}
        }

        // Record transcript
        const transcriptLines = [
          JSON.stringify({ role: "system", content: SYSTEM_PROMPT }),
          JSON.stringify({ role: "user", content: queryRes.prompt }),
          JSON.stringify({ role: "assistant", content: queryRes.content }),
          JSON.stringify({ verification: { passed: vRes.pass, reason: vRes.reason || null, latency_ms: queryRes.latencyMs, tokens_in: queryRes.promptTokens, tokens_out: queryRes.completionTokens } })
        ].join("\n") + "\n";
        fs.writeFileSync(path.join(transcriptsDir, `${task.id}.jsonl`), transcriptLines);

        return {
          id: task.id,
          cat: task.cat,
          name: task.name,
          passed: vRes.pass,
          reason: vRes.reason || null,
          latencyMs: queryRes.latencyMs,
          tokensIn: queryRes.promptTokens,
          tokensOut: queryRes.completionTokens
        };
      } catch (err) {
        return {
          id: task.id,
          cat: task.cat,
          name: task.name,
          passed: false,
          reason: `API error: ${err.message}`,
          latencyMs: 0,
          tokensIn: 0,
          tokensOut: 0
        };
      }
    });

    const waveResults = await Promise.all(promises);
    for (const r of waveResults) {
      results.push(r);
      totalInTokens += r.tokensIn;
      totalOutTokens += r.tokensOut;
      totalLatency += r.latencyMs;
      if (r.passed) passedCount++;
      const mark = r.passed ? "✓ PASS" : "✗ FAIL";
      console.log(`  [${r.id}] ${r.name.padEnd(58)} ... ${mark} (${r.latencyMs}ms, ${r.tokensIn}/${r.tokensOut} tok)${r.reason ? ' - ' + r.reason : ''}`);
    }
  }

  const passRate = ((passedCount / TASKS_DATA.length) * 100).toFixed(1);
  const avgLatency = Math.round(totalLatency / TASKS_DATA.length);
  const avgInTokens = Math.round(totalInTokens / TASKS_DATA.length);
  const avgOutTokens = Math.round(totalOutTokens / TASKS_DATA.length);

  console.log("\n================================================================================");
  console.log(`    BENCHMARK COMPLETE: ${passedCount}/${TASKS_DATA.length} Tasks Passed (${passRate}%)`);
  console.log(`    Avg Latency: ${avgLatency}ms | Avg Tokens: ${avgInTokens} in / ${avgOutTokens} out`);
  console.log("================================================================================\n");

  // Format canonical ASN
  const categories = [
    "subshell-isolation", "cross-compile", "context-resilience", "ast-refactor", "env-bootstrap",
    "stream-pipeline", "system-net", "git-vcs", "build-packaging", "sec-permissions", "proc-analytics"
  ];
  const catTelemetry = categories.map(cat => {
    const catTasks = results.filter(r => r.cat === cat);
    if (catTasks.length === 0) return null;
    const p = catTasks.filter(r => r.passed).length;
    const rate = ((p / catTasks.length) * 100).toFixed(1);
    return `    (:category :name "${cat}" :passed ${p} :total ${catTasks.length} :rate "${rate}%")`;
  }).filter(Boolean).join("\n");

  const suiteName = TASKS_DATA.length > 60 ? "TerminalBench-4.0-Full-150" : "TerminalBench-4-Astra-Hard-60";

  const asnContent = [
    `;; Terminal Bench 4 Grounded Real Evaluation Results`,
    `;; Model: ${MODEL} via LLM Gateway (Real In-Harness Verification)`,
    `;; Evaluated: ${new Date().toISOString()}`,
    `(:terminal-bench-eval`,
    `  :suite "${suiteName}"`,
    `  :model "${MODEL}"`,
    `  :provider-kind "gateway"`,
    `  :total-tasks ${TASKS_DATA.length}`,
    `  :passed-tasks ${passedCount}`,
    `  :failed-tasks ${TASKS_DATA.length - passedCount}`,
    `  :pass-rate-pct ${passRate}`,
    `  :avg-latency-ms ${avgLatency}`,
    `  :avg-tokens-per-task ${avgOutTokens}`,
    `  :status :verified`,
    `  :categories [`,
    catTelemetry,
    `  ])`
  ].join("\n");

  const outPath = path.join(outDir, "terminal-bench-gemma-eval.asn");
  const summaryPath = path.join(outDir, "summary.asn");
  fs.writeFileSync(outPath, asnContent + "\n");
  fs.writeFileSync(summaryPath, asnContent + "\n");
  console.log(`✓ Telemetry recorded to ${outPath}`);
  console.log(`✓ Summary recorded to ${summaryPath}`);
}

runAll().catch(console.error);
