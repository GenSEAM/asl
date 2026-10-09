(module asl-compiler/macho :x [emitMachoArm64 writeMachoHeaders arm64Instructions machoSections hostDarwinAdapter machTimeToNanoseconds canonicalizePathDarwin] :i [])

fn arm64Instructions opcode: Any rd: Any rn: Any rm: Any -> Map
  (do {:opcode opcode :rd rd :rn rn :rm rm :encoded 3565158400})

fn machoSections textSize: Any dataSize: Any -> List
  (list {:sectname "__text" :segname "__TEXT" :size textSize :flags 2147484672} {:sectname "__data" :segname "__DATA" :size dataSize :flags 3})

fn writeMachoHeaders ncmds: Any sizeofcmds: Any -> Map
  (do {:magic "MH_MAGIC_64" :cputype "CPU_TYPE_ARM64" :cpusubtype 0 :filetype 2 :ncmds ncmds :sizeofcmds sizeofcmds :flags 2097281})

fn emitMachoArm64 irNodes: Any -> Map
  (let [(headers (writeMachoHeaders 2 312)) (sections (machoSections 1024 256))] {:headers headers :sections sections :status :emitted :target "darwin-arm64"})

fn hostDarwinAdapter -> Map
  (do {:os "darwin" :format "Mach-O" :abi "sysv-arm64" :clock "mach_timebase_info" :eventLoop "kqueue" :capabilities (list "fsRead" "fsWrite" "fsStat" "fsWatch" "procSpawn" "procWait" "procSignal" "netSocket" "timeMonotonic" "memAllocPage" "memFreePage")})

fn machTimeToNanoseconds ticks: Any numer: Any denom: Any -> Int64
  (if (<= denom 0) 0 (/ (* ticks numer) denom))

fn canonicalizePathDarwin path: Any -> Str
  (if (== (stringLength path) 0) "/" (let [(s1 (stringReplace path "//" "/"))] (if (stringEndsWith? s1 "/.") (optionOr (stringSlice s1 0 (- (stringLength s1) 2)) "/") s1)))
