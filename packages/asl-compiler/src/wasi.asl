(module asl-compiler/wasi :x [wasiFdStdin wasiFdStdout wasiFdStderr wasiFdPreopenStart wasiErrno wasiErrnoName wasiOpenFlags wasiFileType wasiFileTypeName wasiStandardImports encodeCiovec wasiFdWrite! wasiFdRead! wasiPathOpen! wasiFdClose! wasiPathFilestatGet! wasiFileRead! wasiFileWrite! wasiFileExists? wasiDirList! wasiFileStat! wasiCapabilityCheck makeCapabilityRefusalReceipt sandboxedWasiCapabilities nativeTierCapabilities wasiSysExec! WasiExecReceipt errPlatformEof errPlatformTimeout errPlatformDenied errPlatformBadHandle errPlatformNotFound errPlatformBusy platformErrorName aslMemAllocPage aslMemFreePage aslSyscallDispatch platformAdapter] :i [])

fn wasiFdStdin -> Int64
  0

fn wasiFdStdout -> Int64
  1

fn wasiFdStderr -> Int64
  2

fn wasiFdPreopenStart -> Int64
  3

fn wasiErrno name: Str -> Int64
  (cond ((= name "ESUCCESS") 0) ((= name "EBADF") 8) ((= name "EEXIST") 20) ((= name "EINVAL") 28) ((= name "ENOENT") 44) ((= name "ENOTDIR") 54) ((= name "EPERM") 63) ((= name "ENOTCAPABLE") 76) (else -1))

fn wasiErrnoName code: Int64 -> Str
  (cond ((= code 0) "ESUCCESS") ((= code 8) "EBADF") ((= code 20) "EEXIST") ((= code 28) "EINVAL") ((= code 44) "ENOENT") ((= code 54) "ENOTDIR") ((= code 63) "EPERM") ((= code 76) "ENOTCAPABLE") (else (str "ERRNO_" (stringFromInt64 code))))

fn wasiOpenFlags name: Str -> Int64
  (cond ((or (= name "O_CREAT") (= name "creat")) 1) ((or (= name "O_DIRECTORY") (= name "directory")) 2) ((or (= name "O_EXCL") (= name "excl")) 4) ((or (= name "O_TRUNC") (= name "trunc")) 8) (else 0))

fn wasiFileType name: Str -> Int64
  (cond ((or (= name "UNKNOWN") (= name "unknown")) 0) ((or (= name "BLOCK_DEVICE") (= name "block_device")) 1) ((or (= name "CHARACTER_DEVICE") (= name "character_device")) 2) ((or (= name "DIRECTORY") (= name "directory")) 3) ((or (= name "REGULAR_FILE") (= name "regular_file")) 4) ((or (= name "SOCKET_DGRAM") (= name "socket_dgram")) 5) ((or (= name "SOCKET_STREAM") (= name "socket_stream")) 6) ((or (= name "SYMBOLIC_LINK") (= name "symbolic_link")) 7) (else 0))

fn wasiFileTypeName code: Int64 -> Str
  (cond ((= code 3) "DIRECTORY") ((= code 4) "REGULAR_FILE") ((= code 7) "SYMBOLIC_LINK") (else "UNKNOWN"))

fn wasiStandardImports -> (List Str)
  (list "fd_write" "fd_read" "path_open" "fd_close" "proc_exit")

fn encodeCiovec ptr: Int64 len: Int64 -> (List Int64)
  (list (mod ptr 256) (mod (/ ptr 256) 256) (mod (/ ptr 65536) 256) (mod (/ ptr 16777216) 256) (mod len 256) (mod (/ len 256) 256) (mod (/ len 65536) 256) (mod (/ len 16777216) 256))

fn ! wasiFileExists? path: Str -> Bool
  (fileExists? path)

fn wasiDirList! path: Str -> (List Str)
  (mt (dirList path) ((ok entries) entries) ((err _) (list)))

fn wasiFileRead! path: Str -> (Result Str Str)
  (if (not (fileExists? path)) (err "ENOENT") (mt (fileRead path) ((ok text) (ok text)) ((err _) (err "EIO"))))

fn wasiFileWrite! path: Str content: Str -> (Result Unit Str)
  (mt (fileWrite path content) ((ok _) (ok ())) ((err _) (err "EIO")))

fn wasiFileStat! path: Str -> (Option (Map Str Int64))
  (if (not (fileExists? path)) (none) (mt (fileStat path) ((ok st) (let [(sz (optionOr (stringToInt64 (str st.size)) 0)) (isD st.isDir) (ft (if isD 3 4))] (some (mapSet (mapSet (mapEmpty) "size" sz) "filetype" ft)))) ((err _) (mt (fileRead path) ((ok text) (some (mapSet (mapSet (mapEmpty) "size" (stringLength text)) "filetype" 4))) ((err _) (some (mapSet (mapSet (mapEmpty) "size" 0) "filetype" 3)))))))

fn wasiReadFdLines! -> (List Str)
  (let [(path "tmp/.asl_wasi_fd_table")] (if (not (fileExists? path)) (list) (mt (fileRead path) ((ok content) (filter (fn [(line Str)] -> Bool (not (stringEmpty? line))) (stringSplit content "\n"))) ((err _) (list)))))

fn wasiWriteFdLines! lines: (List Str) -> Bool
  (let [(path "tmp/.asl_wasi_fd_table") (content (str (stringJoin lines "\n") "\n"))] (mt (fileWrite path content) ((ok _) true) ((err _) false)))

fn wasiParseFdEntry line: Str -> (Map Str Str)
  (let [(parts (stringSplit line "|"))] (if (< (listLength parts) 5) (mapEmpty) (mapSet (mapSet (mapSet (mapSet (mapSet (mapEmpty) "fd" (optionOr (listGet parts 0) "")) "path" (optionOr (listGet parts 1) "")) "oflags" (optionOr (listGet parts 2) "0")) "offset" (optionOr (listGet parts 3) "0")) "status" (optionOr (listGet parts 4) "closed"))))

fn wasiFormatFdEntry fd: Int64 path: Str oflags: Int64 offset: Int64 status: Str -> Str
  (str (stringFromInt64 fd) "|" path "|" (stringFromInt64 oflags) "|" (stringFromInt64 offset) "|" status)

fn wasiPathOpen! dirFd: Int64 path: Str oflags: Int64 -> (Result Int64 Str)
  (if (< dirFd 3) (err "EBADF") (let [(exists (fileExists? path)) (isCreat (= (mod oflags 2) 1))] (if (and (not exists) (not isCreat)) (err "ENOENT") (let [(createRes (if (not exists) (fileWrite path "") (ok ())))] (mt createRes ((ok _) (let [(lines (wasiReadFdLines!)) (maxFd (fold (fn [(acc Int64) (l Str)] -> Int64 (let [(entry (wasiParseFdEntry l)) (fdNum (optionOr (stringToInt64 (optionOr (mapGet entry "fd") "0")) 0))] (max acc fdNum))) 3 lines)) (nextFd (+ maxFd 1)) (newEntry (wasiFormatFdEntry nextFd path oflags 0 "open")) (newLines (listAppend lines (list newEntry)))] (wasiWriteFdLines! newLines) (ok nextFd))) ((err _) (err "EIO")))))))

fn wasiFdWrite! fd: Int64 content: Str -> (Result Int64 Str)
  (if (or (or (< fd 0) (= fd 0)) (= fd 3)) (err "EBADF") (if (or (= fd 1) (= fd 2)) (ok (stringLength content)) (let [(lines (wasiReadFdLines!)) (fdStr (stringFromInt64 fd)) (matches (filter (fn [(l Str)] -> Bool (let [(entry (wasiParseFdEntry l))] (= (optionOr (mapGet entry "fd") "") fdStr))) lines))] (if (listEmpty? matches) (err "EBADF") (let [(l (optionOr (listGet matches 0) "")) (entry (wasiParseFdEntry l)) (st (optionOr (mapGet entry "status") "")) (path (optionOr (mapGet entry "path") "")) (oflags (optionOr (stringToInt64 (optionOr (mapGet entry "oflags") "0")) 0)) (offset (optionOr (stringToInt64 (optionOr (mapGet entry "offset") "0")) 0))] (if (!= st "open") (err "EBADF") (let [(existing (mt (fileRead path) ((ok c) c) ((err _) ""))) (writeRes (fileWrite path (str existing content)))] (mt writeRes ((ok _) (let [(newOffset (+ offset (stringLength content))) (updatedLine (wasiFormatFdEntry fd path oflags newOffset "open")) (newLines (map (fn [(item Str)] -> Str (if (= item l) updatedLine item)) lines))] (wasiWriteFdLines! newLines) (ok (stringLength content)))) ((err _) (err "EIO"))))))))))

fn wasiFdRead! fd: Int64 maxLen: Int64 -> (Result Str Str)
  (if (or (or (or (< fd 0) (= fd 1)) (= fd 2)) (= fd 3)) (err "EBADF") (if (= fd 0) (ok "") (let [(lines (wasiReadFdLines!)) (fdStr (stringFromInt64 fd)) (matches (filter (fn [(l Str)] -> Bool (let [(entry (wasiParseFdEntry l))] (= (optionOr (mapGet entry "fd") "") fdStr))) lines))] (if (listEmpty? matches) (err "EBADF") (let [(l (optionOr (listGet matches 0) "")) (entry (wasiParseFdEntry l)) (st (optionOr (mapGet entry "status") "")) (path (optionOr (mapGet entry "path") "")) (oflags (optionOr (stringToInt64 (optionOr (mapGet entry "oflags") "0")) 0)) (offset (optionOr (stringToInt64 (optionOr (mapGet entry "offset") "0")) 0))] (if (!= st "open") (err "EBADF") (let [(readRes (fileRead path))] (mt readRes ((ok fullText) (let [(fullLen (stringLength fullText))] (if (>= offset fullLen) (ok "") (let [(available (- fullLen offset)) (take (min maxLen available)) (chunk (optionOr (stringSlice fullText offset (+ offset take)) "")) (newOffset (+ offset take)) (updatedLine (wasiFormatFdEntry fd path oflags newOffset "open")) (newLines (map (fn [(item Str)] -> Str (if (= item l) updatedLine item)) lines))] (wasiWriteFdLines! newLines) (ok chunk))))) ((err _) (err "EIO"))))))))))

fn wasiFdClose! fd: Int64 -> (Result Unit Str)
  (if (< fd 3) (err "EBADF") (let [(lines (wasiReadFdLines!)) (fdStr (stringFromInt64 fd)) (matches (filter (fn [(l Str)] -> Bool (let [(entry (wasiParseFdEntry l))] (= (optionOr (mapGet entry "fd") "") fdStr))) lines))] (if (listEmpty? matches) (err "EBADF") (let [(l (optionOr (listGet matches 0) "")) (entry (wasiParseFdEntry l)) (st (optionOr (mapGet entry "status") "")) (path (optionOr (mapGet entry "path") "")) (oflags (optionOr (stringToInt64 (optionOr (mapGet entry "oflags") "0")) 0)) (offset (optionOr (stringToInt64 (optionOr (mapGet entry "offset") "0")) 0))] (if (!= st "open") (err "EBADF") (let [(closedLine (wasiFormatFdEntry fd path oflags offset "closed")) (newLines (map (fn [(item Str)] -> Str (if (= item l) closedLine item)) lines))] (wasiWriteFdLines! newLines) (ok ())))))))

fn wasiPathFilestatGet! dirFd: Int64 path: Str -> (Result (Map Str Int64) Str)
  (if (< dirFd 3) (err "EBADF") (if (not (fileExists? path)) (err "ENOENT") (let [(st (wasiFileStat! path))] (mt st ((some m) (ok m)) ((none) (err "EIO"))))))

fn wasiCapabilityCheck capName: Str grants: (Map Str Bool) -> Bool
  (if (mapHas? grants capName) (optionOr (mapGet grants capName) false) false)

(schema WasiExecReceipt (:f status Str) (:f code Int64) (:f stdout Str) (:f stderr Str))

fn makeCapabilityRefusalReceipt capName: Str -> WasiExecReceipt
  (let [(name (if (stringEmpty? capName) "execCmd" capName))] (WasiExecReceipt :status "refused" :code 126 :stdout "" :stderr (str "ERR_CAPABILITY_DENIED: " name " not permitted in sandboxed WebAssembly substrate")))

fn sandboxedWasiCapabilities -> (Map Str Bool)
  (mapSet (mapSet (mapSet (mapSet (mapSet (mapSet (mapEmpty) "execCmd" false) "sys-exec" false) "fileRead" true) "fileWrite" true) "fileStat" true) "dirList" true)

fn nativeTierCapabilities -> (Map Str Bool)
  (mapSet (mapSet (mapSet (mapSet (mapSet (mapSet (mapEmpty) "execCmd" true) "sys-exec" true) "fileRead" true) "fileWrite" true) "fileStat" true) "dirList" true)

fn wasiSysExec! cmd: Str capabilities: (Map Str Bool) -> WasiExecReceipt
  (if (not (or (wasiCapabilityCheck "execCmd" capabilities) (wasiCapabilityCheck "sys-exec" capabilities))) (makeCapabilityRefusalReceipt "execCmd") (let [(res (processRun cmd))] (WasiExecReceipt :status "ok" :code res.exitCode :stdout res.stdout :stderr res.stderr)))

fn errPlatformEof -> Int64
  1

fn errPlatformTimeout -> Int64
  2

fn errPlatformDenied -> Int64
  3

fn errPlatformBadHandle -> Int64
  4

fn errPlatformNotFound -> Int64
  5

fn errPlatformBusy -> Int64
  6

fn platformErrorName code: Int64 -> Str
  (cond ((= code 1) "ERR_PLATFORM_EOF") ((= code 2) "ERR_PLATFORM_TIMEOUT") ((= code 3) "ERR_PLATFORM_DENIED") ((= code 4) "ERR_PLATFORM_BAD_HANDLE") ((= code 5) "ERR_PLATFORM_NOT_FOUND") ((= code 6) "ERR_PLATFORM_BUSY") (else "ERR_PLATFORM_UNKNOWN"))

fn aslMemAllocPage pageCount: Int64 -> Int64
  (if (<= pageCount 0) 0 (* pageCount 65536))

fn aslMemFreePage pagePtr: Int64 pageCount: Int64 -> Bool
  (and (> pagePtr 0) (> pageCount 0))

fn aslSyscallDispatch opCode: Str arg1: Int64 arg2: Int64 arg3: Int64 -> Int64
  (cond ((= opCode "fsRead") (if (< arg1 0) (- 0 (errPlatformBadHandle)) arg3)) ((= opCode "fsWrite") (if (< arg1 0) (- 0 (errPlatformBadHandle)) arg3)) ((= opCode "fsStat") (if (< arg1 0) (- 0 (errPlatformNotFound)) 0)) ((= opCode "fsWatch") (if (< arg1 0) (- 0 (errPlatformDenied)) 100)) ((= opCode "procSpawn") (if (<= arg1 0) (- 0 (errPlatformNotFound)) 200)) ((= opCode "procWait") (if (<= arg1 0) (- 0 (errPlatformBadHandle)) 0)) ((= opCode "procSignal") (if (<= arg1 0) (- 0 (errPlatformBadHandle)) 0)) ((= opCode "netSocket") (if (<= arg1 0) (- 0 (errPlatformDenied)) 300)) ((= opCode "timeMonotonic") 1789730000000) ((= opCode "memAllocPage") (aslMemAllocPage arg1)) ((= opCode "memFreePage") (if (aslMemFreePage arg1 arg2) 0 (- 0 (errPlatformBadHandle)))) (else (- 0 (errPlatformDenied))))

fn platformAdapter -> (List Str)
  (list "fsRead" "fsWrite" "fsStat" "fsWatch" "procSpawn" "procWait" "procSignal" "netSocket" "timeMonotonic" "memAllocPage" "memFreePage")
