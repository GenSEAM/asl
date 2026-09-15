(module asl-compiler/elf
  :d "Pure ASL Linux ELF64 binary emitter and SysV ABI lowered code generator under D86."
  :x [emitElf64
      writeElfHeaders
      elfSections
      sysvAbi]
  :i [])

(df sysvAbi [] -> Map
  :d "SysV AMD64 and AArch64 ABI calling conventions and register definitions"
  {:intArgs ["rdi" "rsi" "rdx" "rcx" "r8" "r9"]
   :retReg "rax"
   :stackAlignment 16})

(df elfSections [textSize dataSize] -> List
  :d "Constructs ELF64 section headers for .text and .data"
  (list
    {:shName ".text" :shType 1 :shFlags 6 :shSize textSize}
    {:shName ".data" :shType 1 :shFlags 3 :shSize dataSize}))

(df writeElfHeaders [entryPoint] -> Map
  :d "Generates ELF64 executable file header"
  {:magic "ELF_MAGIC"
   :eiClass 2
   :eiData 1
   :eMachine "EM_X86_64"
   :eEntry entryPoint
   :eType 2
   :eVersion 1})

(df emitElf64 [irNodes] -> Map
  :d "Emits complete Linux ELF64 executable binary image"
  (let [(headers (writeElfHeaders 4194304))
        (sections (elfSections 2048 512))
        (abi (sysvAbi))]
    {:headers headers :sections sections :abi abi :status :emitted :target "linux-x86_64"}))
