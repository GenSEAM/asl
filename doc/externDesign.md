# Extern design: binding native libraries from ASL

Date 2026-11-13, base `b2e73a0d8`. Companion ledger: `.asl/mem/audits/fable-20261113/glue.asn`
(glue map of the 69 packages, backlog rows EXTERN-01 to EXTERN-09). Earlier design:
`.asl/mem/work/SH/ffiDesign-20261026.asn`.

## 1. Where things stand

Foreign calls already exist on main. `asl/ROADMAP.md` ("no `extern` in the language"),
`asl/README.md:27` and the 2026-11-13 audits (V-12, S-09) describe the state before 2026-10-26.

| Part | State on `b2e73a0d8` | Where |
|---|---|---|
| Declaration `fn ! name ... (foreign "lib" "symbol" "sig")` | works | `asl-checker/src/foreign.asl` |
| Kinds `i32 u32 i64 u64 f64 bool cstr str str32 bytes bytes32 void` | works | `asl-target-llvm/src/ffiRoute.asl` |
| `Handle` with finaliser: `handle`, `handle:F`, `close:F` | works | `ffiRoute.asl`, `ffiRt.asl` |
| Error conventions `!neg`, `!null` (errno text) | works | `ffiRoute.asl` |
| `:linkLibraries ["z"]` from every imported package's manifest | works | `asl-cli/src/build.asl` |
| Non-native targets and the host VM | refuse (`ERR_FOREIGN_TARGET`) | `ffiRoute.asl#rejectForeign` |
| Out pointers, out buffers, status codes, constants | missing | this design, EXTERN-02 and 04 |
| Variadic calls, callbacks, structs by value | missing | EXTERN-08 and 09 |
| Native dependency rows, installer check, signature check against headers | missing | EXTERN-03 |
| User documentation of the form | missing | EXTERN-01 |

Checked in this unit: `./bin/asl check` accepts declarations of `sqlite3_libversion`,
`sqlite3_libversion_number` and zlib `crc32` (exit 0) and rejects `out:handle:sqlite3_close` with
`ERR_FOREIGN_SIG`. Not checked: a native build of those declarations (the build did not finish in
110 s); the suite counts in the FFI commit messages.

## 2. Alternatives and the choice

| | A. Raw C ABI with checked wrappers emitted as LLVM IR | B. Hand-written or generated C shims | C. Process or IPC bridge |
|---|---|---|---|
| Foreign source in the tree | none | a `.c` file per library | none |
| Covers | scalars, strings, bytes, opaque handles, out pointers, out buffers; later variadics and callbacks | everything, including macros and structs | anything with a CLI |
| Cost per call | a copy of each String or Bytes argument | the same | a process spawn |
| Safety | wrapper range-checks and frees on every path; the prototype is trusted | the shim is unchecked C | process isolation |
| Works for a cheap model | 3 lines per function | must write C | must parse CLI output |
| Status | implemented (FFI1, FFI2) | forbidden by D157 and `audit foreign` | implemented (D155, `asl-proc`) |

**Chosen: A, with C as the fallback.** A is already built and gated, adds no foreign file, and
keeps D154 (no address is an ASL value) because pointers exist only inside the generated wrapper
or inside a `Handle`. B is rejected: a shim is foreign source, it moves the unchecked part into C
where no ASL gate reads it, and the wrapper A emits is the same shim written in IR by the
compiler. C stays for tools that have no stable C ABI or whose API needs what A lacks (ffmpeg,
duckdb, a browser, curl until EXTERN-08).

The `(extern name :from (:c ...) :sig [...] -> T)` form of ROADMAP item 4 is not adopted: it
would be a second surface for the same thing. Later origins reuse the library string:
`"npm:lodash"`, `"wasm:env"`.

## 3. Surface

```asl
fn ! NAME param: Type ... -> Ret
  (foreign "LIB" "C_SYMBOL" "ckind ... -> cret [!convention]")
```

Rules the checker enforces today (`foreignDiags`): the call is the whole body of a top-level fn
(`ERR_FOREIGN_PLACE`); three string literals; the fn is marked `!` (`ERR_FOREIGN_EFFECT`); no
type variables; the number and ASL type of each parameter match the kinds, and `Ret` is the
result kind's ASL type `T` or `(Result T String)` (`ERR_FOREIGN_SIG`).

### Type map

| Kind | ASL type | C side | State |
|---|---|---|---|
| `i32` `u32` | `Int64` | `int32_t` `uint32_t`, range-checked in, widened out | works |
| `i64` `u64` | `Int64` | 64-bit; `u64` above 2^63-1 is `ERR_RANGE` | works |
| `f64` | `Float64` | `double` | works |
| `bool` | `Bool` | C `int` 0 or 1 in, non-zero is true out | works |
| `cstr` | `String` | NUL-terminated copy in (embedded NUL is `ERR_FOREIGN_NUL`); borrowed and copied out | works |
| `str` `str32` | `String` | pointer and `size_t` or `uint32_t` length | works |
| `bytes` `bytes32` | `Bytes` | pointer to a copy and length | works |
| `void` | `Unit` | result only | works |
| `handle` `handle:F` `close:F` | `Handle` | opaque pointer; `F` is the C finaliser | works |
| `out:handle` `out:handle:F` | no parameter; becomes the result | `T **`: the wrapper passes the address of a zeroed slot and reads it back | EXTERN-02 |
| `lit:N` | no parameter | the constant `N` as a pointer-width integer (`lit:0` is `NULL`, `lit:-1` is `SQLITE_TRANSIENT`) | EXTERN-02 |
| `bytesBy:F` `strBy:F` (result) | `Bytes` `String` | returned pointer; length is `F` called with the same arguments | EXTERN-02 |
| `cap` | `Int64` capacity | pointer to a fresh buffer and `size_t` capacity; the result is the filled prefix as `Bytes` | EXTERN-04 |
| `outBytes:N` | no parameter | pointer to `N` zeroed bytes, returned as `Bytes` | EXTERN-04 |
| `capRef` | `Int64` capacity | buffer pointer and pointer to an in-out length | EXTERN-04 |
| `f32` `i8` `u8` `i16` `u16` | `Float64` `Int64` | need `SsaTy` rows and `signext`/`zeroext` | later |
| `...` | marks the variadic tail | emitted as a variadic call type, so arm64 Darwin passes the tail on the stack | EXTERN-08 |
| `cb:NAME` | no parameter | address of a C-convention trampoline to a top-level, non-capturing `fn !` with scalar parameters | EXTERN-08 |

Structs: by pointer only. An opaque struct is a `Handle`. A small plain struct the caller
allocates crosses as `outBytes:N` and is decoded in ASL; its layout is per ABI and the binding's
test asserts `N` against `sizeof` through `asl native verify`. Structs by value are not planned
before EXTERN-09 shows a need.

With an `out:handle` argument the declared return is `(Result Handle String)` and the C result is
the status, so `!nonzero` or `!neg` is required:

```asl
fn ! openDb path: String -> (Result Handle String)
  (foreign "sqlite3" "sqlite3_open" "cstr out:handle:sqlite3_close -> i32 !nonzero")
```

## 4. Ownership and memory

Runtime facts this rests on (`asl-target-llvm/src`): a value is `%Val = { i64 tag, i64 payload }`
(`rtAbi.asl`); heap objects are reference-counted with Perceus-style reuse (`rc.asl`), with a
traced collector mode beside it; strings reach C only through `valToCStr(val, repr)`, which
returns a `malloc` copy, and come back through `mkStr(ptr, len)`, which copies again
(`rtValue.asl`). `valToCStr` takes a representation argument, so a zero-copy borrow of a String is
not promised.

1. Nothing crosses by reference. Every String and Bytes argument is copied into a `malloc`
   buffer that lives for the call and is freed on every path.
2. A `cstr`, `strBy` or `bytesBy` result is borrowed from C and copied before the wrapper
   returns. The wrapper never frees what C returned.
3. Memory C owns is a `Handle`: the collector's Handle object (type 7, C pointer at offset 16,
   finaliser at 24, value tag 15). `handle:F` runs `F` once when the count reaches zero or at
   sweep; `close:F` runs through the call and clears both words, so `F` never runs twice and a
   later use is `ERR_FOREIGN_CLOSED`. An argument `handle:F` accepts only a Handle made with `F`.
4. A plain `handle` result is borrowed: never freed, valid only while its owner lives. The
   binding documents the owner.
5. Out slots and out buffers are wrapper-local `malloc` memory, copied into a fresh ASL value and
   freed before return.
6. No address is an ASL value (D154). Off-heap memory holds no counted reference.
7. A Handle is not sent into `parMap` workers; a library is called from one thread unless its
   binding states otherwise. (Rule to gate in EXTERN-02; not enforced today.)

## 5. Errors

| Declared return | Marshalling failure (range, NUL, NULL, no memory) | C failure convention |
|---|---|---|
| plain `T` | trap with the code, naming fn and argument | trap `ERR_FOREIGN_ERRNO` or `ERR_FOREIGN_STATUS` |
| `(Result T String)` | `(err "ERR_RANGE: ...")` | `(err "...")` |

Conventions after the result kind: `!neg` (negative `i32`/`i64`, text from `strerror(errno)`),
`!null` (NULL `cstr` or handle, errno text), `!nonzero` (EXTERN-02: `"ERR_FOREIGN_STATUS: who:
code"`; the binding maps the code to the library's message, for sqlite `sqlite3_errmsg`). The
error type is always `String`, with the code as the prefix up to the first colon.

## 6. Effects and checking

A foreign fn is `!`; callers inherit the effect through the module summary, so a `:pure` package
cannot reach C. The checker is pure and reads no header: the signature is trusted at check time.
`asl native verify` (EXTERN-03) closes that gap at gate time. From each declaration and the
manifest's `:header` it writes a C file outside the tree and runs `clang -fsyntax-only`:

```c
#include <sqlite3.h>
_Static_assert(sizeof(sqlite3_open((const char*)0, (void*)0)) == 4, "openDb");
```

Probe result (2026-11-13, macOS arm64): four correct declarations pass; a wrong arity, a wrong
return width, a pointer for an `int` and a pointer for a `double` each fail with exit 1. It does
not catch every integer width of a parameter.

## 7. Lowering, emission, linking

Already implemented: `asl-ir` lowers the body to one `opBuiltin foreign` over constant strings;
`ffiRoute.routeForeign` rebuilds each stub as a wrapper (unbox, range-check, copy, call, free,
widen, box or wrap in Result) and adds a native `SsaExtern`, emitted as `declare` and called with
the C calling convention; a clash of two signatures for one symbol is `ERR_FOREIGN_EXTERN`. New
kinds are new cases in `marshal`, `unmarshal`, `cParamTypes` and `checkConvention`.

Link line today: `clang FLAGS INPUTS libaslrt.a -l<each :linkLibraries> -lm -o OUT`
(`asl-cli/src/nativeBuild.asl#linkObjs!`).

| Triple | Default mode | Detail |
|---|---|---|
| macOS arm64 | dynamic, system | `-lNAME` against the SDK (`sqlite3`, `z`, `curl`, `xml2`, `iconv`, `bz2` are there; the probe binary linked `/usr/lib/libsqlite3.dylib`). Others: `:link static` or a Homebrew path from the native row. Frameworks: `:link framework`. |
| Linux x64, arm64 | dynamic, system | `-l:SONAME` (for example `-l:libsqlite3.so.0`), so linking needs the runtime library, not the `-dev` package. Not verified in this unit. |
| any | static, opt-in | an archive under `~/.asl/native/TRIPLE/lib`, digest-pinned in the native row; gives a single self-contained binary where the platform allows it |
| wasm32, js, host VM | none | `ERR_CAPABILITY_ABSENT` naming `foreignCall` |

No `dlopen` (D151): a library is resolved at link time.

## 8. Manifest

```asn
(:package asl-sqlite :version "0.1.0" :entry "src/sqlite.asl"
  :native [(:lib "sqlite3" :link system :header "sqlite3.h" :soname "libsqlite3.so.0"
            :probe "sqlite3_libversion" :min "3.35.0"
            :pkg (:brew "sqlite" :apt "libsqlite3-0" :dnf "sqlite-libs"))])
```

`:linkLibraries ["sqlite3"]` stays as the short form of `(:lib "sqlite3" :link system)`. Every
library name a foreign declaration uses must appear in a row of its own package (cross-check in
EXTERN-03; today a missing one is a clang undefined-symbol error). Each binding package also has
a row in `asl/grammar/capabilities.asn` with status, probe and fallback.

## 9. Hermetic tests

- A binding suite has two layers. Route level: lower and route the declarations, assert the
  extern shapes; no link, runs anywhere. Native level: one fixture binary per package, built and
  run through `tools/ffi/bindingFixture.asl` (EXTERN-01), which goes through
  `asl/tools/fleet/run.asl` with a timeout and a descendant limit (spawnSafety). The fixture is a
  separate program, never the running executable or the host.
- No network and no shared state: sqlite uses `:memory:` or a scratch directory; a client library
  is tested against a loopback `asl-net` server only.
- A missing library is reported as absent by the doctor probe and the suite fails with
  `ERR_CAPABILITY_ABSENT`; it is never skipped as passed.
- Cost: a native build of a nine-line program did not finish in 110 s here, so a package has one
  fixture binary holding all its assertions, and the gate goes red on a mutant of the binding.

## 10. Installer

`scripts/install.sh` installs no native library and makes no network call for them. It ends with
`asl native doctor`, which links a one-line probe per `:native` row of the installed packages and
prints, per row, present or absent with the exact command for this platform (`brew install
sqlite`, `apt-get install libsqlite3-0`). A program that needs an absent library fails at build
with `ERR_CAPABILITY_ABSENT` and the same line. `asl native fetch` (static archives into
`~/.asl/native/TRIPLE`, digest-pinned) is an outward step and runs only on an explicit request.
The core toolchain itself needs no library beyond libc and libm.

## 11. D157

D157 as written does not forbid a foreign declaration: a binding is an `.asl` file, FFI1 and FFI2
were merged under it, and D151 `:noDlopen` names C ABI FFI as the way to reuse C libraries. What
it and the ASL-first floor did was make reimplementation the default. Ruling R-1 option a, as a
decision refining D157:

- **Narrow** `:scope`: add a third allowed foreign artefact, "a prebuilt third-party native
  library linked through a foreign declaration, named in a package manifest `:native` row and a
  capabilities row with status, probe and fallback; never vendored as source".
- **Add** `:bindings`: "a library with a stable C ABI is bound, not reimplemented; a pure-ASL
  reimplementation needs a named host-VM or wasm consumer or a measured gain".
- **Stays**: zero Python and shell in the tree and under `~/.asl`; no hand-written C shim; the
  asl-host C floor does not grow; no `dlopen`; no address as an ASL value; the foreign-file
  ratchet (a binding adds no foreign file).

## 12. Binding template

What a cheap model needs: this section, the library's header, and the gate command.

```asl
(module asl-zlib/zlibSum
  :x [zlibVersion crc32 adler32 compressBound checksumText]
  :i [])

; (:m :ref EXTERN-TEMPLATE :do "zlib checksums; prototypes from zlib.h: const char *zlibVersion(void); uLong crc32(uLong, const Bytef *, uInt); uLong adler32(uLong, const Bytef *, uInt); uLong compressBound(uLong)")
fn ! zlibVersion -> String
  (foreign "z" "zlibVersion" "-> cstr")

fn ! crc32Raw seed: Int64 data: Bytes -> Int64
  (foreign "z" "crc32" "u64 bytes32 -> u64")

fn ! adler32Raw seed: Int64 data: Bytes -> Int64
  (foreign "z" "adler32" "u64 bytes32 -> u64")

fn ! compressBound sourceLength: Int64 -> (Result Int64 String)
  (foreign "z" "compressBound" "u64 -> u64")

fn ! crc32 data: Bytes -> Int64
  (crc32Raw 0 data)

fn ! adler32 data: Bytes -> Int64
  (adler32Raw 1 data)

fn ! checksumText data: Bytes -> String
  (str "crc32=" (crc32 data) " adler32=" (adler32 data))
```

This file passes `./bin/asl check` on `b2e73a0d8`. Manifest:
`(:package asl-zlib :version "0.1.0" :entry "src/zlibSum.asl" :linkLibraries ["z"])`.

Checklist:

1. Copy each C prototype from the header into the `(:m ...)` comment, then write one foreign fn
   per prototype. `unsigned long`, `size_t` are `u64`; `int` is `i32`; `unsigned int` is `u32`;
   `const char *` is `cstr`; pointer plus length is `str`/`bytes` (`size_t`) or `str32`/`bytes32`
   (`unsigned int`); `T *` to an opaque object is `handle:F` with `F` its destroy function.
2. Every foreign fn is `fn !`. Raw declarations keep C's shape and are not exported; exported
   functions are ASL-shaped facades with camelCase names.
3. A function that can fail returns `(Result T String)` and carries `!neg`, `!null` or
   `!nonzero`. Never return a raw status code from an exported function.
4. Every object C allocates is a `Handle` with its finaliser; the function that destroys it takes
   `close:F`.
5. Not expressible (variadic, callback, struct by value, a kind marked later in section 3): stop
   and report the prototype. Do not write C, do not spawn a shell.
6. Add the library to the manifest and a row to `asl/grammar/capabilities.asn`.
7. Test: route-level asserts on the extern shapes, and one fixture through
   `bindingFixture.bindingRun!` whose expected output comes from the library's documentation or
   from known-answer vectors (for the example: `crc32` of `"123456789"` is 3421780262, `adler32`
   is 152961502), not from running the binding.
8. Before committing: the gate is red on a mutant (swap two kinds, change a seed), the fixture
   uses no network and a scratch directory, no output prints environment values.

Gate, in order:

```
./bin/asl check asl/packages/asl-NAME/src/FILE.asl
./bin/asl native verify asl/packages/asl-NAME          # after EXTERN-03
./bin/asl test asl/packages/asl-NAME/tests/bindingTest.asl
```

## 13. Slices

Rows are in `glue.asn` `(:slices ...)`.

| Row | What | Effort | Model |
|---|---|---|---|
| EXTERN-01 | fixture helper, libc and libsqlite3 acceptance fixture, `ERR_CAPABILITY_ABSENT`, docs made true | S | sonnet |
| EXTERN-02 | kinds `out:handle`, `lit:N`, `!nonzero`, `bytesBy:F`; package `asl-sqlite` executing `asl-sql` text | L | opus for the kinds, sonnet for the package |
| EXTERN-03 | `:native` rows, link modes per triple, `asl native doctor` and `verify`, installer | M | sonnet |
| EXTERN-04 and later | out buffers and zlib, png, duckdb process, crypto, variadics and callbacks, tree-sitter trial | M to L | see ledger |

Heavy (compiler wrapper generation, reference counts, finalisers): EXTERN-02 kinds, EXTERN-04
kinds, EXTERN-08, EXTERN-09. From the template, by a cheap model: every binding package once its
kinds exist.
