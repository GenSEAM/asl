(module asl-intel/model
  :x [OutlineItem ModuleOutline makeOutlineItem makeModuleOutline]
  :i [])

(schema OutlineItem
  (:f name String)
  (:f kind String)
  (:f signature String)
  (:f exported Bool))

(schema ModuleOutline
  (:f moduleName String)
  (:f file String)
  (:f items (List OutlineItem))
  (:f totalSymbols Int64))

fn makeOutlineItem name: String kind: String sig: String exported: Bool -> OutlineItem
  (OutlineItem :name name :kind kind :signature sig :exported exported)

fn makeModuleOutline modName: String file: String items: (List OutlineItem) -> ModuleOutline
  (ModuleOutline :moduleName modName :file file :items items :totalSymbols (listLength items))
