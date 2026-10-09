(module aslPack/targets/kotlin :x [KotlinTargetSpec KotlinAppSpec generateJniBinding generateGradleDependency generateKmpBuildGradle generateComposeActivity generateKmpStateFlow] :i [])

(schema KotlinTargetSpec (:f packageId Str) (:f className Str))

(schema KotlinAppSpec (:f packageId Str) (:f appName Str) (:f minSdk Int64) (:f targetSdk Int64))

fn generateJniBinding spec: KotlinTargetSpec -> Str
  (let [(pkg spec.packageId) (cls spec.className)] (str "package " pkg "\n\n" "class " cls " {\n" "    companion object {\n" "        init {\n" "            System.loadLibrary(\"asl_wamr_jni\")\n" "        }\n" "    }\n\n" "    external fun initEngine(): Int\n" "    external fun evalModule(moduleName: String, inputBytes: ByteArray): ByteArray\n" "    external fun freeEngine(): Unit\n" "}\n"))

fn generateGradleDependency spec: KotlinTargetSpec -> Str
  (str "// Android NDK / WAMR integration for " spec.packageId "\n" "android {\n" "    defaultConfig {\n" "        ndk {\n" "            abiFilters 'arm64-v8a', 'x86_64'\n" "        }\n" "    }\n" "}\n" "dependencies {\n" "    implementation(\"io.genseam:asl-wamr-runtime:0.1.0\")\n" "}\n")

fn generateKmpBuildGradle spec: KotlinAppSpec -> Str
  (let [(pkg spec.packageId)] (str "plugins {\n" "    kotlin(\"multiplatform\") version \"2.0.20\"\n" "    id(\"com.android.application\")\n" "    id(\"org.jetbrains.compose\") version \"1.6.11\"\n" "}\n\n" "kotlin {\n" "    androidTarget()\n" "    iosArm64()\n" "    iosSimulatorArm64()\n" "    wasmJs { browser() }\n\n" "    sourceSets {\n" "        val commonMain by getting {\n" "            dependencies {\n" "                implementation(compose.runtime)\n" "                implementation(compose.foundation)\n" "                implementation(compose.material3)\n" "                implementation(\"org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1\")\n" "            }\n" "        }\n" "        val androidMain by getting {\n" "            dependencies {\n" "                implementation(\"androidx.activity:activity-compose:1.9.1\")\n" "                implementation(\"io.genseam:asl-wamr-runtime:0.1.0\")\n" "            }\n" "        }\n" "    }\n" "}\n\n" "android {\n" "    namespace = \"" pkg "\"\n" "    compileSdk = 34\n" "    defaultConfig {\n" "        applicationId = \"" pkg "\"\n" "        minSdk = " (int-to-string spec.minSdk) "\n" "        targetSdk = " (int-to-string spec.targetSdk) "\n" "    }\n" "}\n"))

fn generateComposeActivity spec: KotlinAppSpec -> Str
  (let [(pkg spec.packageId) (act spec.appName)] (str "package " pkg "\n\n" "import android.os.Bundle\n" "import androidx.activity.ComponentActivity\n" "import androidx.activity.compose.setContent\n" "import androidx.compose.material3.MaterialTheme\n" "import androidx.compose.material3.Surface\n\n" "class " act " : ComponentActivity() {\n" "    override fun onCreate(savedInstanceState: Bundle?) {\n" "        super.onCreate(savedInstanceState)\n" "        setContent {\n" "            MaterialTheme {\n" "                Surface {\n" "                    AppContent()\n" "                }\n" "            }\n" "        }\n" "    }\n" "}\n"))

fn generateKmpStateFlow packageId: Str -> Str
  (str "package " packageId "\n\n" "import kotlinx.coroutines.flow.MutableStateFlow\n" "import kotlinx.coroutines.flow.StateFlow\n" "import kotlinx.coroutines.flow.asStateFlow\n\n" "class ASLStateStore {\n" "    private val _state = MutableStateFlow(\"{}\")\n" "    val state: StateFlow<String> = _state.asStateFlow()\n\n" "    private val agent = ASLAgent()\n\n" "    fun dispatch(moduleName: String, actionPayload: String) {\n" "        val inputBytes = actionPayload.encodeToByteArray()\n" "        val resultBytes = agent.evalModule(moduleName, inputBytes)\n" "        _state.value = resultBytes.decodeToString()\n" "    }\n" "}\n")

fn int-to-string n: Int64 -> Str
  (stringFromInt64 n)
