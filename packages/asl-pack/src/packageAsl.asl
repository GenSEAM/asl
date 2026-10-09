(module aslPack/packageAsl
  :x [PackageDependency PackageDef isPublishablePackage validatePackageDef parsePackageAsl scanPackageTree]
  :i [])

(schema PackageDependency
  (:f name Str)
  (:f sourceType Str)
  (:f gitUrl Str)
  (:f tag Str)
  (:f checksum Str))

(schema PackageDef
  (:f name Str)
  (:f version Str)
  (:f public Bool)
  (:f entry Str)
  (:f doc Str)
  (:f modules (List Str))
  (:f dependencies (List PackageDependency)))

fn isPublishablePackage pDef: PackageDef -> Bool
  pDef.public

fn validateDependencyForPublic dep: PackageDependency -> Bool
  (if (= dep.sourceType "git")
    (and (not (stringEmpty? dep.gitUrl))
         (not (stringEmpty? dep.tag)))
    (if (= dep.sourceType "local")
      false
      true))

fn validatePackageDependencies deps: (List PackageDependency) isPublic: Bool -> Bool
  (if (not isPublic)
    true
    (fold
      (fn [(validSoFar Bool) (dep PackageDependency)] -> Bool
        (if (not validSoFar)
          false
          (validateDependencyForPublic dep)))
      true
      deps))

fn validatePackageDef pDef: PackageDef -> Bool
  (let [(nameValid (not (stringEmpty? pDef.name)))
        (verValid (not (stringEmpty? pDef.version)))
        (entryValid (not (stringEmpty? pDef.entry)))
        (depsValid (validatePackageDependencies pDef.dependencies pDef.public))]
    (and nameValid (and verValid (and entryValid depsValid))))

fn extractStringValue src: Str key: Str defaultVal: Str -> Str
  (if (stringContains? src key)
    (let [(parts (stringSplit src key))]
      (if (>= (listLength parts) 2)
        (let [(rest (optionOr (listGet parts 1) ""))]
          (let [(trimmed (stringTrim rest))]
            (if (stringStartsWith? trimmed "\"")
              (let [(afterQuote (optionOr (stringSlice trimmed 1 (stringLength trimmed)) ""))]
                (let [(quoteParts (stringSplit afterQuote "\""))]
                  (if (>= (listLength quoteParts) 1)
                    (optionOr (listHead quoteParts) defaultVal)
                    defaultVal)))
              defaultVal)))
        defaultVal))
    defaultVal)

fn extractBoolValue src: Str key: Str defaultVal: Bool -> Bool
  (if (stringContains? src key)
    (let [(parts (stringSplit src key))]
      (if (>= (listLength parts) 2)
        (let [(rest (optionOr (listGet parts 1) ""))]
          (let [(trimmed (stringTrim rest))]
            (if (stringStartsWith? trimmed "true")
              true
              (if (stringStartsWith? trimmed "false")
                false
                defaultVal))))
        defaultVal))
    defaultVal)

fn parsePackageAsl src: Str -> PackageDef
  (let [(pkgName (extractStringValue src ":package" ""))
        (ver (extractStringValue src ":version" "0.1.0"))
        (isPub (extractBoolValue src ":public" false))
        (entryPath (extractStringValue src ":entry" "src/main.asl"))
        (docText (extractStringValue src ":doc" ""))]
    (PackageDef
      :name pkgName
      :version ver
      :public isPub
      :entry entryPath
      :doc docText
      :modules (list)
      :dependencies (list)))

fn isValidPackagePath p: Str -> Bool
  (and (stringEndsWith? p "package.asl")
       (and (not (stringContains? p "scratch/"))
            (and (not (stringContains? p ".git/"))
                 (not (stringContains? p "dist/")))))

fn scanPackageTree paths: (List Str) -> (List Str)
  (fold
    (fn [(acc (List Str)) (p Str)] -> (List Str)
      (if (isValidPackagePath p)
        (listAppend acc (list p))
        acc))
    (list)
    paths)
