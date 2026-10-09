(module aslHarness/deps :x [LockfileKind PinnedDependency PackageSpec detectLockfileKind lockfileKindToEcosystem extractNpmVersion extractPnpmVersion extractCargoVersion extractPoetryVersion extractPipVersion parsePinnedVersion checkAntiCheatingPolicy resolveTypeSkeleton isGhostApi? depsResolveFromLockfile depsResolve formatPackageSpec] :i [])

(enum LockfileKind (:c lockfileNpm [] "package.json or package-lock.json (NPM package manager)") (:c lockfilePnpm [] "pnpm-lock.yaml (pnpm package manager)") (:c lockfileCargo [] "Cargo.lock (Rust Crates package manager)") (:c lockfilePoetry [] "poetry.lock (Python Poetry package manager)") (:c lockfilePip [] "requirements.txt (Python Pip package manager)") (:c lockfileUnknown [] "Unsupported or unrecognized lockfile format"))

(schema PinnedDependency (:f name Str) (:f version Str) (:f lockfileKind LockfileKind) (:f direct Bool))

(schema PackageSpec (:f packageName Str) (:f version Str) (:f symbol Str) (:f signature Str) (:f isDeprecated Bool) (:f replacement Str))

(schema NpmScanState (:f inTargetBlock Bool) (:f found (Option Str)))

(schema TomlScanState (:f inTargetPkg Bool) (:f found (Option Str)))

(schema PnpmScanState (:f inTargetBlock Bool) (:f found (Option Str)))

(schema PipScanState (:f found (Option Str)))

fn detectLockfileKind filename: Str -> LockfileKind
  (cond ((or (stringEndsWith? filename "pnpm-lock.yaml") (stringContains? filename "pnpm-lock.yaml")) (lockfilePnpm)) ((or (stringEndsWith? filename "package-lock.json") (stringContains? filename "package-lock.json")) (lockfileNpm)) ((or (stringEndsWith? filename "package.json") (stringContains? filename "package.json")) (lockfileNpm)) ((or (stringEndsWith? filename "Cargo.lock") (stringContains? filename "Cargo.lock")) (lockfileCargo)) ((or (stringEndsWith? filename "poetry.lock") (stringContains? filename "poetry.lock")) (lockfilePoetry)) ((or (stringEndsWith? filename "requirements.txt") (stringContains? filename "requirements.txt")) (lockfilePip)) (else (lockfileUnknown)))

fn lockfileKindToEcosystem kind: LockfileKind -> Str
  (mt kind ((lockfileNpm) "npm") ((lockfilePnpm) "pnpm") ((lockfileCargo) "cargo") ((lockfilePoetry) "poetry") ((lockfilePip) "pip") ((lockfileUnknown) "unknown"))

fn stripQuotes s: Str -> Str
  (stringReplace (stringReplace s "\"" "") "'" "")

fn cleanVersion raw: Str -> Str
  (let [(s0 (stringTrim (stripQuotes raw))) (s1 (if (stringStartsWith? s0 "==") (optionOr (stringSlice s0 2 (stringLength s0)) "") s0)) (s2 (if (stringStartsWith? s1 ">=") (optionOr (stringSlice s1 2 (stringLength s1)) "") s1)) (s3 (if (stringStartsWith? s2 "<=") (optionOr (stringSlice s2 2 (stringLength s2)) "") s2)) (s4 (if (stringStartsWith? s3 "~=") (optionOr (stringSlice s3 2 (stringLength s3)) "") s3)) (s5 (if (stringStartsWith? s4 "^") (optionOr (stringSlice s4 1 (stringLength s4)) "") s4)) (s6 (if (stringStartsWith? s5 "~") (optionOr (stringSlice s5 1 (stringLength s5)) "") s5)) (s7 (if (stringStartsWith? s6 ">") (optionOr (stringSlice s6 1 (stringLength s6)) "") s6)) (s8 (if (stringStartsWith? s7 "<") (optionOr (stringSlice s7 1 (stringLength s7)) "") s7)) (s9 (if (stringStartsWith? s8 "=") (optionOr (stringSlice s8 1 (stringLength s8)) "") s8)) (s10 (if (stringStartsWith? s9 "v") (optionOr (stringSlice s9 1 (stringLength s9)) "") s9)) (s11 (stringTrim s10)) (s12 (if (stringEndsWith? s11 ",") (optionOr (stringSlice s11 0 (- (stringLength s11) 1)) "") s11)) (s13 (if (stringEndsWith? s12 ";") (optionOr (stringSlice s12 0 (- (stringLength s12) 1)) "") s12))] (stringTrim s13))

fn parseMajorVersion version: Str -> I64
  (let [(clean (cleanVersion version)) (parts (stringSplit clean ".")) (head (optionOr (listHead parts) "0"))] (optionOr (stringToInt64 head) 0))

fn scanNpmLine acc: NpmScanState line: Str pkgName: Str -> NpmScanState
  (mt acc.found ((some _) acc) ((none) (let [(trimmed (stringTrim line)) (pkgKey (str "\"" pkgName "\"")) (nmKey (str "\"node_modules/" pkgName "\""))] (if (or (stringContains? trimmed pkgKey) (stringContains? trimmed nmKey)) (if (stringContains? trimmed ":") (let [(afterColon (optionOr (listHead (optionOr (listTail (stringSplit trimmed ":")) (list))) ""))] (if (stringContains? afterColon "\"") (let [(valClean (cleanVersion afterColon))] (if (not (stringEmpty? valClean)) (NpmScanState :inTargetBlock false :found (some valClean)) (NpmScanState :inTargetBlock true :found (none)))) (NpmScanState :inTargetBlock true :found (none)))) (NpmScanState :inTargetBlock true :found (none))) (if acc.inTargetBlock (if (stringContains? trimmed "\"version\":") (let [(afterVer (optionOr (listHead (optionOr (listTail (stringSplit trimmed "\"version\":")) (list))) "")) (valClean (cleanVersion afterVer))] (if (not (stringEmpty? valClean)) (NpmScanState :inTargetBlock false :found (some valClean)) acc)) (if (and (stringContains? trimmed "}") (not (stringContains? trimmed "{"))) (NpmScanState :inTargetBlock false :found (none)) acc)) acc)))))

fn extractNpmVersion content: Str pkgName: Str -> (Option Str)
  (let [(lines (stringSplit content "\n")) (init (NpmScanState :inTargetBlock false :found (none))) (finalSt (fold (fn [(st NpmScanState) (l Str)] -> NpmScanState (scanNpmLine st l pkgName)) init lines))] finalSt.found)

fn extractVersionAfterAt line: Str pkgName: Str -> (Option Str)
  (let [(needle (str pkgName "@")) (idx (stringIndexOf line needle))] (mt idx ((none) (none)) ((some i) (let [(prefixStr (optionOr (stringSlice line 0 i) "")) (validPrefix (if (= i 0) true (let [(prevChar (optionOr (stringSlice line (- i 1) i) ""))] (and (or (= prevChar "/") (or (= prevChar "'") (or (= prevChar "\"") (= prevChar " ")))) (not (stringContains? prefixStr "@"))))))] (if validPrefix (let [(afterStart (+ i (stringLength needle))) (tail (optionOr (stringSlice line afterStart (stringLength line)) "")) (c1 (optionOr (listHead (stringSplit tail ":")) tail)) (c2 (optionOr (listHead (stringSplit c1 "(")) c1)) (c3 (optionOr (listHead (stringSplit c2 "'")) c2)) (c4 (optionOr (listHead (stringSplit c3 "\"")) c3)) (c5 (optionOr (listHead (stringSplit c4 " ")) c4)) (ver (cleanVersion c5))] (if (not (stringEmpty? ver)) (some ver) (none))) (none))))))

fn scanPnpmLine acc: PnpmScanState line: Str pkgName: Str -> PnpmScanState
  (mt acc.found ((some _) acc) ((none) (let [(trimmed (stringTrim line)) (atOpt (extractVersionAfterAt trimmed pkgName))] (mt atOpt ((some v) (PnpmScanState :inTargetBlock false :found (some v))) ((none) (if (or (= trimmed (str pkgName ":")) (or (= trimmed (str "'" pkgName "':")) (= trimmed (str "\"" pkgName "\":")))) (PnpmScanState :inTargetBlock true :found (none)) (if acc.inTargetBlock (if (stringStartsWith? trimmed "version:") (let [(afterCol (optionOr (listHead (optionOr (listTail (stringSplit trimmed ":")) (list))) "")) (ver (cleanVersion afterCol))] (if (not (stringEmpty? ver)) (PnpmScanState :inTargetBlock false :found (some ver)) acc)) (if (and (not (stringStartsWith? line " ")) (not (stringStartsWith? line "\t"))) (PnpmScanState :inTargetBlock false :found (none)) acc)) acc)))))))

fn extractPnpmVersion content: Str pkgName: Str -> (Option Str)
  (let [(lines (stringSplit content "\n")) (init (PnpmScanState :inTargetBlock false :found (none))) (finalSt (fold (fn [(st PnpmScanState) (l Str)] -> PnpmScanState (scanPnpmLine st l pkgName)) init lines))] finalSt.found)

fn scanTomlLine acc: TomlScanState line: Str pkgName: Str -> TomlScanState
  (mt acc.found ((some _) acc) ((none) (let [(trimmed (stringTrim line))] (if (or (stringStartsWith? trimmed "[[") (and (stringStartsWith? trimmed "[") (not (stringStartsWith? trimmed "[[package")))) (TomlScanState :inTargetPkg false :found (none)) (if (or (stringContains? trimmed (str "name = \"" pkgName "\"")) (stringContains? trimmed (str "name = '" pkgName "'"))) (TomlScanState :inTargetPkg true :found (none)) (if acc.inTargetPkg (if (stringStartsWith? trimmed "version =") (let [(afterEq (optionOr (listHead (optionOr (listTail (stringSplit trimmed "=")) (list))) "")) (ver (cleanVersion afterEq))] (if (not (stringEmpty? ver)) (TomlScanState :inTargetPkg false :found (some ver)) acc)) acc) acc))))))

fn extractCargoVersion content: Str pkgName: Str -> (Option Str)
  (let [(lines (stringSplit content "\n")) (init (TomlScanState :inTargetPkg false :found (none))) (finalSt (fold (fn [(st TomlScanState) (l Str)] -> TomlScanState (scanTomlLine st l pkgName)) init lines))] finalSt.found)

fn extractPoetryVersion content: Str pkgName: Str -> (Option Str)
  (extractCargoVersion content pkgName)

fn isPipDelim c: Str -> Bool
  (or (= c "=") (or (= c ">") (or (= c "<") (or (= c "~") (or (= c "!") (or (= c " ") (or (= c "\t") (= c "@"))))))))

fn scanPipLine acc: PipScanState line: Str pkgName: Str -> PipScanState
  (mt acc.found ((some _) acc) ((none) (let [(cIdx (stringIndexOf line "#")) (noComment (mt cIdx ((none) line) ((some idx) (optionOr (stringSlice line 0 idx) "")))) (mIdx (stringIndexOf noComment ";")) (noMarker (mt mIdx ((none) noComment) ((some idx2) (optionOr (stringSlice noComment 0 idx2) "")))) (trimmed (stringTrim noMarker))] (if (stringStartsWith? trimmed pkgName) (let [(pkgLen (stringLength pkgName)) (tail (optionOr (stringSlice trimmed pkgLen (stringLength trimmed)) ""))] (if (stringEmpty? tail) acc (let [(firstChar (optionOr (stringSlice tail 0 1) ""))] (if (isPipDelim firstChar) (let [(ver (cleanVersion tail))] (if (not (stringEmpty? ver)) (PipScanState :found (some ver)) acc)) acc)))) acc))))

fn extractPipVersion content: Str pkgName: Str -> (Option Str)
  (let [(lines (stringSplit content "\n")) (init (PipScanState :found (none))) (finalSt (fold (fn [(st PipScanState) (l Str)] -> PipScanState (scanPipLine st l pkgName)) init lines))] finalSt.found)

fn parsePinnedVersion kind: LockfileKind content: Str pkgName: Str -> (Option Str)
  (mt kind ((lockfileNpm) (extractNpmVersion content pkgName)) ((lockfilePnpm) (extractPnpmVersion content pkgName)) ((lockfileCargo) (extractCargoVersion content pkgName)) ((lockfilePoetry) (extractPoetryVersion content pkgName)) ((lockfilePip) (extractPipVersion content pkgName)) ((lockfileUnknown) (none)))

fn checkAntiCheatingPolicy networkRequested: Bool -> Bool
  (if networkRequested false true)

fn normalizeSymbol sym: Str -> Str
  (let [(s1 (if (stringStartsWith? sym ".") (optionOr (stringSlice sym 1 (stringLength sym)) "") sym)) (s2 (if (stringEndsWith? s1 "()") (optionOr (stringSlice s1 0 (- (stringLength s1) 2)) "") s1))] (stringTrim s2))

fn resolveTypeSkeleton package: Str version: Str symbol: Str -> PackageSpec
  (let [(major (parseMajorVersion version)) (cleanSym (normalizeSymbol symbol))] (cond ((or (= package "pydantic") (= package "pydantic-core")) (if (>= major 2) (cond ((= cleanSym "dict") (PackageSpec :packageName package :version version :symbol symbol :signature "(self, *, mode: str = 'python', include = None, exclude = None, by_alias: bool = False, exclude_unset: bool = False, exclude_defaults: bool = False, exclude_none: bool = False, round_trip: bool = False, warnings: bool = True) -> dict[str, Any]" :isDeprecated true :replacement "model_dump()")) ((= cleanSym "model_dump") (PackageSpec :packageName package :version version :symbol symbol :signature "(self, *, mode: str = 'python', include = None, exclude = None, by_alias: bool = False, exclude_unset: bool = False, exclude_defaults: bool = False, exclude_none: bool = False, round_trip: bool = False, warnings: bool = True) -> dict[str, Any]" :isDeprecated false :replacement "")) ((= cleanSym "model_dump_json") (PackageSpec :packageName package :version version :symbol symbol :signature "(self, *, indent: int | None = None, include = None, exclude = None, by_alias: bool = False, exclude_unset: bool = False, exclude_defaults: bool = False, exclude_none: bool = False, round_trip: bool = False, warnings: bool = True) -> str" :isDeprecated false :replacement "")) ((= cleanSym "parse_obj") (PackageSpec :packageName package :version version :symbol symbol :signature "(cls, obj: Any, *, strict: bool | None = None, from_attributes: bool | None = None, context: dict[str, Any] | None = None) -> Self" :isDeprecated true :replacement "model_validate()")) (else (PackageSpec :packageName package :version version :symbol symbol :signature "unknown" :isDeprecated false :replacement ""))) (cond ((= cleanSym "dict") (PackageSpec :packageName package :version version :symbol symbol :signature "(self, *, include = None, exclude = None, by_alias: bool = False, skip_defaults: bool = None, exclude_unset: bool = False, exclude_defaults: bool = False, exclude_none: bool = False) -> dict[str, Any]" :isDeprecated false :replacement "")) ((= cleanSym "model_dump") (PackageSpec :packageName package :version version :symbol symbol :signature "unknown" :isDeprecated true :replacement "dict()")) (else (PackageSpec :packageName package :version version :symbol symbol :signature "unknown" :isDeprecated false :replacement ""))))) ((or (= package "react") (= package "react-dom")) (if (>= major 19) (cond ((= cleanSym "useFormState") (PackageSpec :packageName package :version version :symbol symbol :signature "<State, Payload>(action: (state: Awaited<State>, payload: Payload) => State | Promise<State>, initialState: Awaited<State>, permalink?: string) => [state: Awaited<State>, formAction: (payload: Payload) => void, isPending: boolean]" :isDeprecated true :replacement "useActionState")) ((= cleanSym "useActionState") (PackageSpec :packageName package :version version :symbol symbol :signature "<State, Payload>(action: (state: Awaited<State>, payload: Payload) => State | Promise<State>, initialState: Awaited<State>, permalink?: string) => [state: Awaited<State>, formAction: (payload: Payload) => void, isPending: boolean]" :isDeprecated false :replacement "")) (else (PackageSpec :packageName package :version version :symbol symbol :signature "unknown" :isDeprecated false :replacement ""))) (cond ((= cleanSym "useFormState") (PackageSpec :packageName package :version version :symbol symbol :signature "<State, Payload>(action: (state: Awaited<State>, payload: Payload) => State | Promise<State>, initialState: Awaited<State>, permalink?: string) => [state: Awaited<State>, formAction: (payload: Payload) => void]" :isDeprecated false :replacement "")) ((= cleanSym "useActionState") (PackageSpec :packageName package :version version :symbol symbol :signature "unknown" :isDeprecated true :replacement "useFormState")) (else (PackageSpec :packageName package :version version :symbol symbol :signature "unknown" :isDeprecated false :replacement ""))))) ((= package "zod") (cond ((= cleanSym "safeParse") (PackageSpec :packageName package :version version :symbol symbol :signature "(data: unknown) => SafeParseReturnType<Output, Output>" :isDeprecated false :replacement "")) ((= cleanSym "parse") (PackageSpec :packageName package :version version :symbol symbol :signature "(data: unknown) => Output" :isDeprecated false :replacement "")) (else (PackageSpec :packageName package :version version :symbol symbol :signature "unknown" :isDeprecated false :replacement "")))) ((= package "tokio") (cond ((= cleanSym "spawn") (PackageSpec :packageName package :version version :symbol symbol :signature "pub fn spawn<T>(future: T) -> JoinHandle<T::Output> where T: Future + Send + 'static, T::Output: Send + 'static" :isDeprecated false :replacement "")) (else (PackageSpec :packageName package :version version :symbol symbol :signature "unknown" :isDeprecated false :replacement "")))) (else (PackageSpec :packageName package :version version :symbol symbol :signature "unknown" :isDeprecated false :replacement ""))))

fn isGhostApi? spec: PackageSpec -> Bool
  spec.isDeprecated

fn depsResolveFromLockfile lockfileContent: Str kind: LockfileKind pkgName: Str symbol: Str -> PackageSpec
  (let [(optVer (parsePinnedVersion kind lockfileContent pkgName)) (ver (optionOr optVer "unknown"))] (resolveTypeSkeleton pkgName ver symbol))

fn depsResolve package: Str symbol: Str -> PackageSpec
  (let [(defaultVer (cond ((= package "pydantic") "2.6.1") ((= package "react") "19.0.0") ((= package "zod") "3.22.4") ((= package "tokio") "1.38.0") (else "1.0.0")))] (resolveTypeSkeleton package defaultVer symbol))

fn formatPackageSpec spec: PackageSpec -> Str
  (str "(:pkg-spec :package \"" spec.packageName "\" :version \"" spec.version "\" :symbol \"" spec.symbol "\" :sig \"" spec.signature "\" :is-deprecated " (if spec.isDeprecated "true" "false") " :replacement \"" spec.replacement "\")")
