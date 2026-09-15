(module aslPack/targets/kotlin
  :d "Kotlin Multiplatform and Android JNI bridge generator."
  :x [KotlinTargetSpec
      KotlinAppSpec
      generateJniBinding
      generateGradleDependency
      generateKmpBuildGradle
      generateComposeActivity
      generateKmpStateFlow]
  :i [])

(dfs KotlinTargetSpec
  (:f packageId Str "Root package identifier e.g. io.genseam.asl")
  (:f className Str "Binding class name e.g. ASLAgent"))

(dfs KotlinAppSpec
  (:f packageId Str "Android application package identifier e.g. io.genseam.mobile")
  (:f appName Str "Application activity and branding name e.g. MainActivity")
  (:f minSdk Int64 "Minimum Android API level e.g. 26")
  (:f targetSdk Int64 "Target Android API level e.g. 34"))

(df generateJniBinding [(spec KotlinTargetSpec)] -> Str
  :d "Generates Kotlin external class definition delegating to native WAMR runtime."
  (let [(pkg (.-packageId spec))
        (cls (.-className spec))]
    (str "package " pkg "\n\n"
         "class " cls " {\n"
         "    companion object {\n"
         "        init {\n"
         "            System.loadLibrary(\"asl_wamr_jni\")\n"
         "        }\n"
         "    }\n\n"
         "    external fun initEngine(): Int\n"
         "    external fun evalModule(moduleName: String, inputBytes: ByteArray): ByteArray\n"
         "    external fun freeEngine(): Unit\n"
         "}\n")))

(df generateGradleDependency [(spec KotlinTargetSpec)] -> Str
  :d "Emits Android Gradle dependencies for native WAMR runtime embedding."
  (str "// Android NDK / WAMR integration for " (.-packageId spec) "\n"
       "android {\n"
       "    defaultConfig {\n"
       "        ndk {\n"
       "            abiFilters 'arm64-v8a', 'x86_64'\n"
       "        }\n"
       "    }\n"
       "}\n"
       "dependencies {\n"
       "    implementation(\"io.genseam:asl-wamr-runtime:0.1.0\")\n"
       "}\n"))

(df generateKmpBuildGradle [(spec KotlinAppSpec)] -> Str
  :d "Emits full Kotlin Multiplatform build.gradle.kts with Android, iOS, and Wasm targets."
  (let [(pkg (.-packageId spec))]
    (str "plugins {\n"
         "    kotlin(\"multiplatform\") version \"2.0.20\"\n"
         "    id(\"com.android.application\")\n"
         "    id(\"org.jetbrains.compose\") version \"1.6.11\"\n"
         "}\n\n"
         "kotlin {\n"
         "    androidTarget()\n"
         "    iosArm64()\n"
         "    iosSimulatorArm64()\n"
         "    wasmJs { browser() }\n\n"
         "    sourceSets {\n"
         "        val commonMain by getting {\n"
         "            dependencies {\n"
         "                implementation(compose.runtime)\n"
         "                implementation(compose.foundation)\n"
         "                implementation(compose.material3)\n"
         "                implementation(\"org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1\")\n"
         "            }\n"
         "        }\n"
         "        val androidMain by getting {\n"
         "            dependencies {\n"
         "                implementation(\"androidx.activity:activity-compose:1.9.1\")\n"
         "                implementation(\"io.genseam:asl-wamr-runtime:0.1.0\")\n"
         "            }\n"
         "        }\n"
         "    }\n"
         "}\n\n"
         "android {\n"
         "    namespace = \"" pkg "\"\n"
         "    compileSdk = 34\n"
         "    defaultConfig {\n"
         "        applicationId = \"" pkg "\"\n"
         "        minSdk = " (int-to-string (.-minSdk spec)) "\n"
         "        targetSdk = " (int-to-string (.-targetSdk spec)) "\n"
         "    }\n"
         "}\n")))

(df generateComposeActivity [(spec KotlinAppSpec)] -> Str
  :d "Emits idiomatic ComponentActivity using Jetpack Compose."
  (let [(pkg (.-packageId spec))
        (act (.-appName spec))]
    (str "package " pkg "\n\n"
         "import android.os.Bundle\n"
         "import androidx.activity.ComponentActivity\n"
         "import androidx.activity.compose.setContent\n"
         "import androidx.compose.material3.MaterialTheme\n"
         "import androidx.compose.material3.Surface\n\n"
         "class " act " : ComponentActivity() {\n"
         "    override fun onCreate(savedInstanceState: Bundle?) {\n"
         "        super.onCreate(savedInstanceState)\n"
         "        setContent {\n"
         "            MaterialTheme {\n"
         "                Surface {\n"
         "                    AppContent()\n"
         "                }\n"
         "            }\n"
         "        }\n"
         "    }\n"
         "}\n")))

(df generateKmpStateFlow [(packageId Str)] -> Str
  :d "Emits Kotlin StateFlow observable state store for multiplatform ASL dispatch."
  (str "package " packageId "\n\n"
       "import kotlinx.coroutines.flow.MutableStateFlow\n"
       "import kotlinx.coroutines.flow.StateFlow\n"
       "import kotlinx.coroutines.flow.asStateFlow\n\n"
       "class ASLStateStore {\n"
       "    private val _state = MutableStateFlow(\"{}\")\n"
       "    val state: StateFlow<String> = _state.asStateFlow()\n\n"
       "    private val agent = ASLAgent()\n\n"
       "    fun dispatch(moduleName: String, actionPayload: String) {\n"
       "        val inputBytes = actionPayload.encodeToByteArray()\n"
       "        val resultBytes = agent.evalModule(moduleName, inputBytes)\n"
       "        _state.value = resultBytes.decodeToString()\n"
       "    }\n"
       "}\n"))(df int-to-string [(n Int64)] -> Str
  :d "Converts integer to string representation."
  (string-from-int64 n))


