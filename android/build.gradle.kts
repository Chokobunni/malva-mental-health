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
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android")
            val compileSdkField = android::class.java.getDeclaredMethod("getCompileSdk")
            val currentSdk = compileSdkField.invoke(android) as? Int
            if (currentSdk != null && currentSdk < 36) {
                android::class.java.getDeclaredMethod("setCompileSdk", Int::class.javaPrimitiveType)
                    .invoke(android, 36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
