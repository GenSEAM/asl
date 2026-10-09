(module aslMem/federatedMemory
  :x [PackageScopedMemory formatFederatedMemoryRecord filterMemoriesByPackage queryFederatedPackageMemory discoverPackageMemories]
  :i [])

(schema PackageScopedMemory
  (:f package Str)
  (:f category Str)
  (:f path Str)
  (:f entriesCount Int))

fn formatFederatedMemoryRecord rec: PackageScopedMemory content: Str -> Str
  (str "(:memoryRecord :package \"" rec.package "\" :category \"" rec.category "\" :scope :local :path \"" rec.path "\" :content \"" content "\")")

fn filterMemoriesByPackage memories: (List PackageScopedMemory) pkgName: Str -> (List PackageScopedMemory)
  (fold
    (fn [(acc (List PackageScopedMemory)) (m PackageScopedMemory)] -> (List PackageScopedMemory)
      (if (= m.package pkgName)
        (listAppend acc (list m))
        acc))
    (list)
    memories)

fn queryFederatedPackageMemory memories: (List PackageScopedMemory) pkgName: Str category: Str limit: Int -> (List PackageScopedMemory)
  (let [(filtered (fold
                    (fn [(acc (List PackageScopedMemory)) (m PackageScopedMemory)] -> (List PackageScopedMemory)
                      (if (and (= m.package pkgName) (= m.category category))
                        (listAppend acc (list m))
                        acc))
                    (list)
                    memories))]
    (if (<= limit 0)
      (list)
      (let [(total (listLength filtered))]
        (if (<= total limit)
          filtered
          (fold
            (fn [(acc (List PackageScopedMemory)) (m PackageScopedMemory)] -> (List PackageScopedMemory)
              (if (< (listLength acc) limit)
                (listAppend acc (list m))
                acc))
            (list)
            filtered)))))

fn isValidPackageMemoryPath p: Str -> Bool
  (and (stringEndsWith? p ".asn")
       (and (stringContains? p "/mem/")
            (and (not (stringContains? p "scratch/"))
                 (not (stringContains? p "/src/")))))

fn discoverPackageMemories paths: (List Str) -> (List Str)
  (fold
    (fn [(acc (List Str)) (p Str)] -> (List Str)
      (if (isValidPackageMemoryPath p)
        (listAppend acc (list p))
        acc))
    (list)
    paths)
