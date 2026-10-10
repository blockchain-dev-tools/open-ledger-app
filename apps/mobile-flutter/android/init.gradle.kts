// Gradle init script - Chinese mirrors for GFW
// Applied globally to all projects and included builds
allprojects {
    repositories {
        all {
            when (this) {
                is MavenArtifactRepository -> {
                    val originalUrl = url.toString()
                    if (originalUrl.contains("repo1.maven.org") || originalUrl.contains("repo.maven.apache.org")) {
                        setUrl("https://maven.aliyun.com/repository/public")
                    } else if (originalUrl.contains("dl.google.com") || originalUrl.contains("android.googlesource.com")) {
                        setUrl("https://maven.aliyun.com/repository/google")
                    } else if (originalUrl.contains("plugins.gradle.org")) {
                        setUrl("https://maven.aliyun.com/repository/gradle-plugin")
                    }
                }
            }
        }
    }
}
