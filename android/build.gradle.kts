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
subprojects {
    project.evaluationDependsOn(":app")
}

// L'analyse « lint vital » des plugins manque de mémoire sur un PC de 8 Go (OutOfMemoryError,
// build de 11 min qui échoue à la fin). Elle ne sert qu'à signaler des problèmes de code
// des bibliothèques : on la désactive pour construire l'APK.
subprojects {
    tasks.matching { it.name.contains("lintVital", ignoreCase = true) }.configureEach {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
