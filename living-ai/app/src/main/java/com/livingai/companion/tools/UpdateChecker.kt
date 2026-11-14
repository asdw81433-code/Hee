package com.livingai.companion.tools

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Looks for a newer Kivo on the project's GitHub releases page. Runs only when the user presses
 * "check for updates"; sends nothing but the request itself.
 */
object UpdateChecker {
    const val RELEASE_API = "https://api.github.com/repos/asdw81433-code/Hee/releases/tags/living-ai-latest"
    const val RELEASE_PAGE = "https://github.com/asdw81433-code/Hee/releases/tag/living-ai-latest"

    data class Result(val latest: String, val newer: Boolean, val downloadUrl: String?)

    suspend fun check(current: String): Result = withContext(Dispatchers.IO) {
        val conn = URL(RELEASE_API).openConnection() as HttpURLConnection
        conn.connectTimeout = 15_000; conn.readTimeout = 15_000
        conn.setRequestProperty("Accept", "application/vnd.github+json")
        conn.setRequestProperty("User-Agent", "Kivo-Android")
        try {
            if (conn.responseCode != 200) throw java.io.IOException("HTTP ${conn.responseCode}")
            val json = JSONObject(conn.inputStream.bufferedReader().readText())
            val assets = json.getJSONArray("assets")
            var version: String? = null
            var url: String? = null
            for (i in 0 until assets.length()) {
                val a = assets.getJSONObject(i)
                val m = Regex("kivo-(\\d+(?:\\.\\d+)*)\\.apk").find(a.getString("name")) ?: continue
                version = m.groupValues[1]; url = a.getString("browser_download_url")
            }
            val latest = version ?: throw java.io.IOException("no APK in the release")
            Result(latest, compare(latest, current) > 0, url)
        } finally {
            conn.disconnect()
        }
    }

    /** Compares dotted version numbers: 1.10.0 > 1.9.2. */
    fun compare(a: String, b: String): Int {
        val x = a.split('.').map { it.toIntOrNull() ?: 0 }; val y = b.split('.').map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(x.size, y.size)) {
            val d = x.getOrElse(i) { 0 } - y.getOrElse(i) { 0 }
            if (d != 0) return d
        }
        return 0
    }
}
