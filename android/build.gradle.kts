allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// 必须写在 evaluationDependsOn 之前：否则 :app 会先把 file_picker 配完，补丁赶不上。
// file_picker 在 AGP 9 上会跳过 Kotlin 插件，但本工程 android.builtInKotlin=false，
// 结果 FilePickerPlugin 不会被编译。
subprojects {
    val sub = project
    sub.pluginManager.withPlugin("com.android.library") {
        if (sub.name == "file_picker" &&
            !sub.pluginManager.hasPlugin("org.jetbrains.kotlin.android")
        ) {
            sub.pluginManager.apply("org.jetbrains.kotlin.android")
            sub.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
