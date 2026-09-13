(module asl-compiler/wasi
  :d "Pure AgentScript WASI Preview 1 ABI types, constants, and host import descriptors."
  :x [wasiFdStdin
      wasiFdStdout
      wasiFdStderr
      wasiFdPreopenStart
      wasiErrno
      wasiErrnoName
      wasiOpenFlags
      wasiFileType
      wasiFileTypeName
      wasiStandardImports
      wasiStandardImportEntries
      wasiStandardImportTypes
      encodeCiovec
      wasiFdWrite
      wasiFdRead
      wasiPathOpen
      wasiFdClose
      wasiPathFilestatGet
      wasiFileRead
      wasiFileWrite
      wasiFileExists?
      wasiDirList
      wasiFileStat
      wasiCapabilityCheck
      makeCapabilityRefusalReceipt
      sandboxedWasiCapabilities
      nativeTierCapabilities
      wasiSysExec]
  :i [(wasm :a w)])

(df wasiFdStdin [] -> Int64 0)

(df wasiFdStdout [] -> Int64 1)

(df wasiFdStderr [] -> Int64 2)

(df wasiFdPreopenStart [] -> Int64 3)

(df wasiErrno [(name Str)] -> Int64
  :d "Returns numeric errno code for standard WASI error names."
  (cond
    ((= name "ESUCCESS") 0)
    ((= name "EBADF") 8)
    ((= name "EEXIST") 20)
    ((= name "EINVAL") 28)
    ((= name "ENOENT") 44)
    ((= name "ENOTDIR") 54)
    ((= name "EPERM") 63)
    ((= name "ENOTCAPABLE") 76)
    (:else -1)))

(df wasiErrnoName [(code Int64)] -> Str
  :d "Returns standard errno name for WASI error code."
  (cond
    ((= code 0) "ESUCCESS")
    ((= code 8) "EBADF")
    ((= code 20) "EEXIST")
    ((= code 28) "EINVAL")
    ((= code 44) "ENOENT")
    ((= code 54) "ENOTDIR")
    ((= code 63) "EPERM")
    ((= code 76) "ENOTCAPABLE")
    (:else (str "ERRNO_" (string-from-int64 code)))))

(df wasiOpenFlags [(name Str)] -> Int64
  :d "Returns bitmask value for standard WASI open flags."
  (cond
    ((or (= name "O_CREAT") (= name "creat")) 1)
    ((or (= name "O_DIRECTORY") (= name "directory")) 2)
    ((or (= name "O_EXCL") (= name "excl")) 4)
    ((or (= name "O_TRUNC") (= name "trunc")) 8)
    (:else 0)))

(df wasiFileType [(name Str)] -> Int64
  :d "Returns numeric filetype constant for WASI file types."
  (cond
    ((or (= name "UNKNOWN") (= name "unknown")) 0)
    ((or (= name "BLOCK_DEVICE") (= name "block_device")) 1)
    ((or (= name "CHARACTER_DEVICE") (= name "character_device")) 2)
    ((or (= name "DIRECTORY") (= name "directory")) 3)
    ((or (= name "REGULAR_FILE") (= name "regular_file")) 4)
    ((or (= name "SOCKET_DGRAM") (= name "socket_dgram")) 5)
    ((or (= name "SOCKET_STREAM") (= name "socket_stream")) 6)
    ((or (= name "SYMBOLIC_LINK") (= name "symbolic_link")) 7)
    (:else 0)))

(df wasiFileTypeName [(code Int64)] -> Str
  :d "Returns string name for WASI filetype code."
  (cond
    ((= code 3) "DIRECTORY")
    ((= code 4) "REGULAR_FILE")
    ((= code 7) "SYMBOLIC_LINK")
    (:else "UNKNOWN")))

(df wasiStandardImports [] -> (List Str)
  :d "Returns list of standard WASI preview 1 import function names."
  (list "fd_write" "fd_read" "path_open" "fd_close" "proc_exit"))

(df wasiStandardImportEntries [] -> (List (List Int64))
  :d "Emits encoded WebAssembly import section entries for WASI Preview 1."
  (list
    (w/encodeImportEntry "wasi_snapshot_preview1" "fd_write" 0 0)
    (w/encodeImportEntry "wasi_snapshot_preview1" "fd_read" 0 0)
    (w/encodeImportEntry "wasi_snapshot_preview1" "path_open" 0 1)
    (w/encodeImportEntry "wasi_snapshot_preview1" "fd_close" 0 2)
    (w/encodeImportEntry "wasi_snapshot_preview1" "proc_exit" 0 3)))

(df wasiStandardImportTypes [] -> (List (List Int64))
  :d "Emits WebAssembly function type signatures for standard WASI preview 1 imports."
  (list
    (w/encodeFuncType (list 127 127 127 127) (list 127))
    (w/encodeFuncType (list 127 127 127 127 127 126 126 127 127) (list 127))
    (w/encodeFuncType (list 127) (list 127))
    (w/encodeFuncType (list 127) (list))))

(df encodeCiovec [(ptr Int64) (len Int64)] -> (List Int64)
  :d "Encodes a WASI ciovec struct (4-byte pointer, 4-byte length in little-endian)."
  (list
    (mod ptr 256)
    (mod (/ ptr 256) 256)
    (mod (/ ptr 65536) 256)
    (mod (/ ptr 16777216) 256)
    (mod len 256)
    (mod (/ len 256) 256)
    (mod (/ len 65536) 256)
    (mod (/ len 16777216) 256)))

(df wasiFileExists? [(path Str)] -> Bool
  :d "Checks whether a file or directory exists at path."
  (file-exists? path))

(df wasiDirList [(path Str)] -> (List Str)
  :d "Lists directory entries at path."
  (mt (dir-list path)
    ((ok entries) entries)
    ((err _) (list))))

(df wasiFileRead [(path Str)] -> (Result Str Str)
  :d "Reads full text content from file."
  (if (not (file-exists? path))
      (err "ENOENT")
      (mt (file-read path)
        ((ok text) (ok text))
        ((err _) (err "EIO")))))

(df wasiFileWrite [(path Str) (content Str)] -> (Result Unit Str)
  :d "Writes full text content to file."
  (mt (file-write path content)
    ((ok _) (ok ()))
    ((err _) (err "EIO"))))

(df wasiFileStat [(path Str)] -> (Option (Map Str Int64))
  :d "Returns file statistics map containing size and filetype."
  (if (not (file-exists? path))
      (none)
      (mt (file-stat path)
        ((ok st)
         (let [(sz (option-or (string-to-int64 (str (.-size st))) 0))
               (isD (.-isDir st))
               (ft (if isD 3 4))]
           (some (map-set (map-set (map-empty) "size" sz) "filetype" ft))))
        ((err _)
         (mt (file-read path)
           ((ok text)
            (some (map-set (map-set (map-empty) "size" (string-length text)) "filetype" 4)))
           ((err _)
            (some (map-set (map-set (map-empty) "size" 0) "filetype" 3))))))))

(df wasiPathOpen [(dirFd Int64) (path Str) (oflags Int64)] -> (Result Int64 Str)
  :d "Resolves and opens a path relative to directory descriptor."
  (if (< dirFd 3)
      (err "EBADF")
      (if (not (file-exists? path))
          (if (= (mod oflags 2) 1)
              (mt (file-write path "")
                ((ok _) (ok 4))
                ((err _) (err "EIO")))
              (err "ENOENT"))
          (ok 4))))

(df wasiFdWrite [(fd Int64) (content Str)] -> (Result Int64 Str)
  :d "Writes string to file descriptor."
  (if (or (< fd 0) (= fd 0))
      (err "EBADF")
      (if (or (= fd 1) (= fd 2))
          (ok (string-length content))
          (if (= fd 4)
              (ok (string-length content))
              (err "EBADF")))))

(df wasiFdRead [(fd Int64) (maxLen Int64)] -> (Result Str Str)
  :d "Reads from file descriptor up to max length."
  (if (< fd 0)
      (err "EBADF")
      (if (= fd 0)
          (ok "")
          (if (or (= fd 1) (= fd 2))
              (err "EBADF")
              (if (= fd 4)
                  (ok "")
                  (err "EBADF"))))))

(df wasiFdClose [(fd Int64)] -> (Result Unit Str)
  :d "Closes open file descriptor."
  (if (< fd 3)
      (err "EBADF")
      (if (= fd 4)
          (ok ())
          (err "EBADF"))))

(df wasiPathFilestatGet [(dirFd Int64) (path Str)] -> (Result (Map Str Int64) Str)
  :d "Retrieves file statistics relative to directory descriptor."
  (if (< dirFd 3)
      (err "EBADF")
      (if (not (file-exists? path))
          (err "ENOENT")
          (let [(st (wasiFileStat path))]
            (mt st
              ((some m) (ok m))
              ((none) (err "EIO")))))))

(df wasiCapabilityCheck [(capName Str) (grants (Map Str Bool))] -> Bool
  :d "Checks if a specific capability is granted."
  (if (map-has? grants capName)
      (option-or (map-get grants capName) false)
      false))

(df makeCapabilityRefusalReceipt [(capName Str)] -> (Map Str Any)
  :d "Constructs a typed capability denial receipt."
  (let [(name (if (string-empty? capName) "execCmd" capName))]
    {:status "refused"
     :code 126
     :stderr (str "ERR_CAPABILITY_DENIED: " name " not permitted in sandboxed WebAssembly substrate")
     :stdout ""}))

(df sandboxedWasiCapabilities [] -> (Map Str Bool)
  :d "Returns default capability map for sandboxed WebAssembly execution denying OS process spawning."
  (map-set
    (map-set
      (map-set
        (map-set
          (map-set
            (map-set (map-empty) "execCmd" false)
            "sys-exec" false)
          "fileRead" true)
        "fileWrite" true)
      "fileStat" true)
    "dirList" true))

(df nativeTierCapabilities [] -> (Map Str Bool)
  :d "Returns capability map granting native execution permissions."
  (map-set
    (map-set
      (map-set
        (map-set
          (map-set
            (map-set (map-empty) "execCmd" true)
            "sys-exec" true)
          "fileRead" true)
        "fileWrite" true)
      "fileStat" true)
    "dirList" true))

(df wasiSysExec [(cmd Str) (capabilities (Map Str Bool))] -> (Map Str Any)
  :d "Executes OS command if permitted by capabilities or returns explicit refusal receipt."
  (if (not (or (wasiCapabilityCheck "execCmd" capabilities) (wasiCapabilityCheck "sys-exec" capabilities)))
      (makeCapabilityRefusalReceipt "execCmd")
      (let [(res (sys-exec cmd))]
        {:status "ok"
         :code (.-exitCode res)
         :stdout (.-stdout res)
         :stderr (.-stderr res)})))
