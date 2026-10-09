(module asl-compiler/elf :x [emitElf64 writeElfHeaders elfSections sysvAbi hostLinuxAdapter hostWindowsAdapter hostWasiAdapter normalizeWin32Path qpcToNanoseconds iocpRingInit iocpRingPush iocpRingPop translateIocpEvent] :i [])

fn sysvAbi -> Map
  (do {:intArgs ["rdi" "rsi" "rdx" "rcx" "r8" "r9"] :retReg "rax" :stackAlignment 16})

fn elfSections textSize: Any dataSize: Any -> List
  (list {:shName ".text" :shType 1 :shFlags 6 :shSize textSize} {:shName ".data" :shType 1 :shFlags 3 :shSize dataSize})

fn writeElfHeaders entryPoint: Any -> Map
  (do {:magic "ELF_MAGIC" :eiClass 2 :eiData 1 :eMachine "EM_X86_64" :eEntry entryPoint :eType 2 :eVersion 1})

fn emitElf64 irNodes: Any -> Map
  (let [(headers (writeElfHeaders 4194304)) (sections (elfSections 2048 512)) (abi (sysvAbi))] {:headers headers :sections sections :abi abi :status :emitted :target "linux-x86_64"})

fn hostLinuxAdapter -> Map
  (do {:os "linux" :format "ELF" :abi "sysv-elf" :clock "clock_monotonic" :eventLoop "epoll" :capabilities (list "fsRead" "fsWrite" "fsStat" "fsWatch" "procSpawn" "procWait" "procSignal" "netSocket" "timeMonotonic" "memAllocPage" "memFreePage")})

fn hostWindowsAdapter -> Map
  (do {:os "windows" :format "PE" :abi "win64" :clock "query_performance_counter" :eventLoop "iocp-ring" :ringCapacity 1024 :capabilities (list "fsRead" "fsWrite" "fsStat" "fsWatch" "procSpawn" "procWait" "procSignal" "netSocket" "timeMonotonic" "memAllocPage" "memFreePage")})

fn hostWasiAdapter -> Map
  (do {:os "wasi" :format "WASM" :abi "wasi-preview1" :clock "clock_time_get" :eventLoop "poll_oneoff" :capabilities (list "fsRead" "fsWrite" "fsStat" "timeMonotonic" "memAllocPage" "memFreePage")})

fn normalizeWin32Path p: Any -> Str
  (if (== (stringLength p) 0) "/" (let [(s1 (stringReplace p "\\" "/")) (len (stringLength s1))] (if (and (>= len 2) (== (optionOr (stringSlice s1 1 2) "") ":")) (let [(drive (stringLower (optionOr (stringSlice s1 0 1) ""))) (rest (optionOr (stringSlice s1 2 len) ""))] (let [(restWithSlash (if (stringStartsWith? rest "/") rest (str "/" rest)))] (str "/" drive restWithSlash))) s1)))

fn qpcToNanoseconds qpc: Any freq: Any -> Int64
  (if (or (<= freq 0) (<= qpc 0)) 0 (let [(quot (/ qpc freq)) (rem (mod qpc freq))] (+ (* quot 1000000000) (/ (* rem 1000000000) freq))))

fn iocpRingInit cap: Any -> Map
  (let [(boundedCap (if (<= cap 0) 1024 cap))] {:capacity boundedCap :events (list) :count 0 :overflowCount 0})

fn iocpRingPush ring: Any event: Any -> Map
  (let [(cnt ring.count) (cap ring.capacity) (ovf ring.overflowCount) (evts ring.events)] (if (>= cnt cap) {:capacity cap :events evts :count cnt :overflowCount (+ ovf 1) :error "errPlatformBusy"} {:capacity cap :events (listAppend evts (list event)) :count (+ cnt 1) :overflowCount ovf}))

fn iocpRingPop ring: Any -> Map
  (let [(cnt ring.count) (evts ring.events) (cap ring.capacity) (ovf ring.overflowCount)] (if (== cnt 0) {:capacity cap :events evts :count cnt :overflowCount ovf :error "errPlatformEof"} (let [(firstEvt (optionOr (listHead evts) {})) (restEvts (optionOr (listTail evts) (list)))] {:capacity cap :events restEvts :count (- cnt 1) :overflowCount ovf :event firstEvt})))

fn translateIocpEvent ring: Any event: Any -> Map
  (let [(pushRes (iocpRingPush ring event))] (if (!= (optionOr (mapGet pushRes :error) "") "") {:ok false :error (optionOr (mapGet pushRes :error) "") :ring pushRes} {:ok true :ring pushRes :event event}))
