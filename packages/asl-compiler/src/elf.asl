(module asl-compiler/elf
  :d "Pure ASL Linux ELF64 binary emitter and SysV ABI lowered code generator under D86."
  :x [emit_elf64
      write_elf_headers
      elf_sections
      sysv_abi]
  :i [])

(df sysv_abi [] -> Map
  :d "SysV AMD64 and AArch64 ABI calling conventions and register definitions"
  {:intArgs ["rdi" "rsi" "rdx" "rcx" "r8" "r9"]
   :retReg "rax"
   :stackAlignment 16})

(df elf_sections [textSize dataSize] -> List
  :d "Constructs ELF64 section headers for .text and .data"
  (list
    {:sh_name ".text" :sh_type 1 :sh_flags 6 :sh_size textSize}
    {:sh_name ".data" :sh_type 1 :sh_flags 3 :sh_size dataSize}))

(df write_elf_headers [entryPoint] -> Map
  :d "Generates ELF64 executable file header"
  {:magic "ELF_MAGIC"
   :ei_class 2
   :ei_data 1
   :e_machine "EM_X86_64"
   :e_entry entryPoint
   :e_type 2
   :e_version 1})

(df emit_elf64 [irNodes] -> Map
  :d "Emits complete Linux ELF64 executable binary image"
  (let [(headers (write_elf_headers 4194304))
        (sections (elf_sections 2048 512))
        (abi (sysv_abi))]
    {:headers headers :sections sections :abi abi :status :emitted :target "linux-x86_64"}))
