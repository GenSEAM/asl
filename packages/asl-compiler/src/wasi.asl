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
      wasiSysExec
      WasiExecReceipt]
  :i [])

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
  (mt (dirList path)
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
      (mt (fileStat path)
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

(df wasiReadFdLines [] -> (List Str)
  :d "Reads existing FD table lines from ephemeral storage."
  (let [(path "tmp/.asl_wasi_fd_table")]
    (if (not (file-exists? path))
        (list)
        (mt (file-read path)
          ((ok content)
           (filter (fn [(line Str)] -> Bool (not (string-empty? line)))
                   (string-split content "\n")))
          ((err _) (list))))))

(df wasiWriteFdLines [(lines (List Str))] -> Bool
  :d "Writes FD table lines to ephemeral storage."
  (let [(path "tmp/.asl_wasi_fd_table")
        (content (str (string-join lines "\n") "\n"))]
    (mt (file-write path content)
      ((ok _) true)
      ((err _) false))))

(df wasiParseFdEntry [(line Str)] -> (Map Str Str)
  :d "Parses single pipe-delimited FD table entry."
  (let [(parts (string-split line "|"))]
    (if (< (list-length parts) 5)
        (map-empty)
        (map-set
          (map-set
            (map-set
              (map-set
                (map-set (map-empty) "fd" (option-or (list-get parts 0) ""))
                "path" (option-or (list-get parts 1) ""))
              "oflags" (option-or (list-get parts 2) "0"))
            "offset" (option-or (list-get parts 3) "0"))
          "status" (option-or (list-get parts 4) "closed")))))

(df wasiFormatFdEntry [(fd Int64) (path Str) (oflags Int64) (offset Int64) (status Str)] -> Str
  :d "Formats single pipe-delimited FD table entry."
  (str (string-from-int64 fd) "|" path "|" (string-from-int64 oflags) "|" (string-from-int64 offset) "|" status))

(df wasiPathOpen [(dirFd Int64) (path Str) (oflags Int64)] -> (Result Int64 Str)
  :d "Resolves and opens a path relative to directory descriptor."
  (if (< dirFd 3)
      (err "EBADF")
      (let [(exists (file-exists? path))
            (isCreat (= (mod oflags 2) 1))]
        (if (and (not exists) (not isCreat))
            (err "ENOENT")
            (let [(createRes (if (not exists) (file-write path "") (ok ())))]
              (mt createRes
                ((ok _)
                 (let [(lines (wasiReadFdLines))
                       (maxFd (fold (fn [(acc Int64) (l Str)] -> Int64
                                      (let [(entry (wasiParseFdEntry l))
                                            (fdNum (option-or (string-to-int64 (option-or (map-get entry "fd") "0")) 0))]
                                        (max acc fdNum)))
                                    3
                                    lines))
                       (nextFd (+ maxFd 1))
                       (newEntry (wasiFormatFdEntry nextFd path oflags 0 "open"))
                       (newLines (list-append lines (list newEntry)))]
                   (wasiWriteFdLines newLines)
                   (ok nextFd)))
                ((err _) (err "EIO"))))))))

(df wasiFdWrite [(fd Int64) (content Str)] -> (Result Int64 Str)
  :d "Writes string to file descriptor."
  (if (or (or (< fd 0) (= fd 0)) (= fd 3))
      (err "EBADF")
      (if (or (= fd 1) (= fd 2))
          (ok (string-length content))
          (let [(lines (wasiReadFdLines))
                (fdStr (string-from-int64 fd))
                (matches (filter (fn [(l Str)] -> Bool
                                   (let [(entry (wasiParseFdEntry l))]
                                     (= (option-or (map-get entry "fd") "") fdStr)))
                                 lines))]
            (if (list-empty? matches)
                (err "EBADF")
                (let [(l (option-or (list-get matches 0) ""))
                      (entry (wasiParseFdEntry l))
                      (st (option-or (map-get entry "status") ""))
                      (path (option-or (map-get entry "path") ""))
                      (oflags (option-or (string-to-int64 (option-or (map-get entry "oflags") "0")) 0))
                      (offset (option-or (string-to-int64 (option-or (map-get entry "offset") "0")) 0))]
                  (if (!= st "open")
                      (err "EBADF")
                      (let [(existing (mt (file-read path)
                                        ((ok c) c)
                                        ((err _) "")))
                            (writeRes (file-write path (str existing content)))]
                        (mt writeRes
                          ((ok _)
                           (let [(newOffset (+ offset (string-length content)))
                                 (updatedLine (wasiFormatFdEntry fd path oflags newOffset "open"))
                                 (newLines (map (fn [(item Str)] -> Str
                                                  (if (= item l) updatedLine item))
                                                lines))]
                             (wasiWriteFdLines newLines)
                             (ok (string-length content))))
                          ((err _) (err "EIO")))))))))))

(df wasiFdRead [(fd Int64) (maxLen Int64)] -> (Result Str Str)
  :d "Reads from file descriptor up to max length."
  (if (or (or (or (< fd 0) (= fd 1)) (= fd 2)) (= fd 3))
      (err "EBADF")
      (if (= fd 0)
          (ok "")
          (let [(lines (wasiReadFdLines))
                (fdStr (string-from-int64 fd))
                (matches (filter (fn [(l Str)] -> Bool
                                   (let [(entry (wasiParseFdEntry l))]
                                     (= (option-or (map-get entry "fd") "") fdStr)))
                                 lines))]
            (if (list-empty? matches)
                (err "EBADF")
                (let [(l (option-or (list-get matches 0) ""))
                      (entry (wasiParseFdEntry l))
                      (st (option-or (map-get entry "status") ""))
                      (path (option-or (map-get entry "path") ""))
                      (oflags (option-or (string-to-int64 (option-or (map-get entry "oflags") "0")) 0))
                      (offset (option-or (string-to-int64 (option-or (map-get entry "offset") "0")) 0))]
                  (if (!= st "open")
                      (err "EBADF")
                      (let [(readRes (file-read path))]
                        (mt readRes
                          ((ok fullText)
                           (let [(fullLen (string-length fullText))]
                             (if (>= offset fullLen)
                                 (ok "")
                                 (let [(available (- fullLen offset))
                                       (take (min maxLen available))
                                       (chunk (option-or (string-slice fullText offset (+ offset take)) ""))
                                       (newOffset (+ offset take))
                                       (updatedLine (wasiFormatFdEntry fd path oflags newOffset "open"))
                                       (newLines (map (fn [(item Str)] -> Str
                                                        (if (= item l) updatedLine item))
                                                      lines))]
                                   (wasiWriteFdLines newLines)
                                   (ok chunk)))))
                          ((err _) (err "EIO")))))))))))

(df wasiFdClose [(fd Int64)] -> (Result Unit Str)
  :d "Closes open file descriptor."
  (if (< fd 3)
      (err "EBADF")
      (let [(lines (wasiReadFdLines))
            (fdStr (string-from-int64 fd))
            (matches (filter (fn [(l Str)] -> Bool
                               (let [(entry (wasiParseFdEntry l))]
                                 (= (option-or (map-get entry "fd") "") fdStr)))
                             lines))]
        (if (list-empty? matches)
            (err "EBADF")
            (let [(l (option-or (list-get matches 0) ""))
                  (entry (wasiParseFdEntry l))
                  (st (option-or (map-get entry "status") ""))
                  (path (option-or (map-get entry "path") ""))
                  (oflags (option-or (string-to-int64 (option-or (map-get entry "oflags") "0")) 0))
                  (offset (option-or (string-to-int64 (option-or (map-get entry "offset") "0")) 0))]
              (if (!= st "open")
                  (err "EBADF")
                  (let [(closedLine (wasiFormatFdEntry fd path oflags offset "closed"))
                        (newLines (map (fn [(item Str)] -> Str
                                         (if (= item l) closedLine item))
                                       lines))]
                    (wasiWriteFdLines newLines)
                    (ok ()))))))))

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

(dfs WasiExecReceipt
  :d "Receipt of a WASI system command execution."
  (:f status Str)
  (:f code Int64)
  (:f stdout Str)
  (:f stderr Str))

(df makeCapabilityRefusalReceipt [(capName Str)] -> WasiExecReceipt
  :d "Constructs a typed capability denial receipt."
  (let [(name (if (string-empty? capName) "execCmd" capName))]
    (WasiExecReceipt
      :status "refused"
      :code 126
      :stdout ""
      :stderr (str "ERR_CAPABILITY_DENIED: " name " not permitted in sandboxed WebAssembly substrate"))))

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

(df wasiSysExec [(cmd Str) (capabilities (Map Str Bool))] -> WasiExecReceipt
  :d "Executes OS command if permitted by capabilities or returns explicit refusal receipt."
  (if (not (or (wasiCapabilityCheck "execCmd" capabilities) (wasiCapabilityCheck "sys-exec" capabilities)))
      (makeCapabilityRefusalReceipt "execCmd")
      (let [(res (sysExec cmd))]
        (WasiExecReceipt
          :status "ok"
          :code (.-exitCode res)
          :stdout (.-stdout res)
          :stderr (.-stderr res)))))
