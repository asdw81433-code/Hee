package com.livingai.core.tools

import com.livingai.core.Lang
import com.livingai.core.Lang.tr
import com.livingai.core.ai.Json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Looks a topic up in Wikipedia (Thai first, then English) and returns a short summary with its
 * source link. Used only when the user asks for it; what comes back is treated as text to read,
 * never as instructions.
 */
class WebLookup(private val fetch: suspend (String) -> String? = ::httpGet) {
    data class Result(val title: String, val summary: String, val url: String)

    suspend fun lookup(query: String): Result? {
        val langs = if (Lang.thai || query.any { it in '฀'..'๿' }) listOf("th", "en") else listOf("en")
        for (lang in langs) {
            val q = URLEncoder.encode(query.trim(), "UTF-8")
            val search = fetch("https://$lang.wikipedia.org/w/api.php?action=opensearch&search=$q&limit=1&namespace=0&format=json") ?: continue
            // ["query",["Title"],[""],["url"]]
            val title = Regex("^\\s*\\[\\s*\"(?:\\\\.|[^\"\\\\])*\"\\s*,\\s*\\[\\s*\"((?:\\\\.|[^\"\\\\])*)\"").find(search)?.groupValues?.get(1)?.let { Json.unescape(it) } ?: continue
            val page = fetch("https://$lang.wikipedia.org/api/rest_v1/page/summary/" + URLEncoder.encode(title.replace(' ', '_'), "UTF-8").replace("+", "%20")) ?: continue
            val extract = Json.field(page, "extract")?.trim().orEmpty()
            if (extract.length < 20) continue
            return Result(title, extract.take(600), "https://$lang.wikipedia.org/wiki/" + title.replace(' ', '_'))
        }
        return null
    }

    fun format(r: Result): String = "${r.title}: ${r.summary}\n" + tr("ที่มา: ", "Source: ") + r.url

    companion object {
        suspend fun httpGet(url: String): String? = withContext(Dispatchers.IO) {
            try {
                val c = URL(url).openConnection() as HttpURLConnection
                c.connectTimeout = 10_000; c.readTimeout = 12_000
                c.setRequestProperty("User-Agent", "Kivo-Android/2 (personal assistant)")
                try { if (c.responseCode == 200) c.inputStream.bufferedReader().readText() else null } finally { c.disconnect() }
            } catch (e: Exception) { null }
        }
    }
}
