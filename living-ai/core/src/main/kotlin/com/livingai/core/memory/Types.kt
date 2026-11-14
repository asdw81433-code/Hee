package com.livingai.core.memory

/**
 * What Kivo can remember.
 *  FACT      long-term: things about the user (name, likes, birthday…)
 *  EPISODE   episodic: something that happened / was done together
 *  KNOWLEDGE things the user taught it on purpose
 *  NOTE      notes the user dictated
 *  TODO      items of the to-do list ([Memory.done])
 * Short-term memory is the running conversation ([ChatLine]).
 */
enum class MemoryKind { FACT, EPISODE, KNOWLEDGE, NOTE, TODO }

data class Memory(
    val id: Long = 0,
    val kind: MemoryKind,
    val title: String,
    val content: String,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    val importance: Int = 1,
    val done: Boolean = false,
)

data class ChatLine(val timestampMs: Long, val fromUser: Boolean, val text: String)

/** Persistent memory. SQLite on Android, [InMemoryMemoryStore] in tests. All data stays on the device. */
interface MemoryStore {
    /** Inserts (id = 0) or updates. A FACT with a title that already exists replaces the old one. Returns the id. */
    suspend fun save(memory: Memory): Long
    suspend fun delete(id: Long)
    /** Newest first. */
    suspend fun list(kind: MemoryKind?, limit: Int): List<Memory>
    /** The memories most relevant to [query], best first. Only relevant ones are returned. */
    suspend fun search(query: String, limit: Int, kind: MemoryKind? = null): List<Memory>
    suspend fun addChat(fromUser: Boolean, text: String)
    /** The last [limit] lines in chronological order. */
    suspend fun recentChat(limit: Int): List<ChatLine>
    suspend fun clearChat()
    /** Deletes every memory and the whole conversation. */
    suspend fun clearAll()
}

/**
 * Text → search keys that work for Thai. Thai is written without spaces, so word-based full-text
 * search finds nothing; overlapping character 2- and 3-grams do. Latin words are kept whole.
 */
object Grams {
    private fun isThai(c: Char) = c in '฀'..'๿'

    fun of(text: String): Set<String> {
        val out = HashSet<String>()
        val t = text.lowercase()
        var i = 0
        while (i < t.length) {
            val c = t[i]
            when {
                isThai(c) -> {
                    var j = i
                    while (j < t.length && isThai(t[j])) j++
                    val run = t.substring(i, j)
                    for (k in 0 until run.length - 1) out.add(run.substring(k, k + 2))
                    for (k in 0 until run.length - 2) out.add(run.substring(k, k + 3))
                    if (run.length == 1) out.add(run)
                    i = j
                }
                c.isLetterOrDigit() -> {
                    var j = i
                    while (j < t.length && t[j].isLetterOrDigit() && !isThai(t[j])) j++
                    if (j - i >= 2) out.add(t.substring(i, j))
                    i = j
                }
                else -> i++
            }
        }
        return out
    }

    /** Share of the query's keys found in the document, 0…1. */
    fun score(query: Set<String>, doc: Set<String>): Float {
        if (query.isEmpty()) return 0f
        var hit = 0
        for (g in query) if (g in doc) hit++
        return hit.toFloat() / query.size
    }

    const val RELEVANT = 0.22f

    /** Orders candidates by relevance (then importance, then recency) and drops the irrelevant ones. */
    fun rank(query: String, candidates: List<Memory>, limit: Int): List<Memory> {
        val q = of(query)
        return candidates.map { it to score(q, of(it.title + " " + it.content)) }
            .filter { it.second >= RELEVANT }
            .sortedWith(compareByDescending<Pair<Memory, Float>> { it.second + it.first.importance * 0.03f }.thenByDescending { it.first.updatedAt })
            .take(limit).map { it.first }
    }
}

class InMemoryMemoryStore(private val clock: () -> Long = { System.currentTimeMillis() }) : MemoryStore {
    private val items = ArrayList<Memory>()
    private val chat = ArrayList<ChatLine>()
    private var nextId = 1L

    override suspend fun save(memory: Memory): Long {
        val now = clock()
        val existing = items.indexOfFirst { it.id == memory.id && memory.id != 0L }
            .takeIf { it >= 0 } ?: if (memory.kind == MemoryKind.FACT) items.indexOfFirst { it.kind == MemoryKind.FACT && it.title == memory.title }.takeIf { it >= 0 } else null
        if (existing != null) {
            val old = items[existing]
            items[existing] = memory.copy(id = old.id, createdAt = old.createdAt, updatedAt = now)
            return old.id
        }
        val id = nextId++
        items.add(memory.copy(id = id, createdAt = if (memory.createdAt == 0L) now else memory.createdAt, updatedAt = now))
        return id
    }

    override suspend fun delete(id: Long) { items.removeAll { it.id == id } }
    override suspend fun list(kind: MemoryKind?, limit: Int) = items.filter { kind == null || it.kind == kind }.sortedByDescending { it.updatedAt * 1000 + it.id }.take(limit)
    override suspend fun search(query: String, limit: Int, kind: MemoryKind?) = Grams.rank(query, items.filter { kind == null || it.kind == kind }, limit)
    override suspend fun addChat(fromUser: Boolean, text: String) { chat.add(ChatLine(clock(), fromUser, text)) }
    override suspend fun recentChat(limit: Int) = chat.takeLast(limit)
    override suspend fun clearChat() { chat.clear() }
    override suspend fun clearAll() { items.clear(); chat.clear() }
}

/** Everything Kivo remembers as one JSON document the user can keep or inspect. */
object MemoryExport {
    private fun esc(s: String) = buildString {
        for (c in s) when (c) {
            '"' -> append("\\\""); '\\' -> append("\\\\"); '\n' -> append("\\n"); '\r' -> append("\\r"); '\t' -> append("\\t")
            else -> if (c < ' ') append("\\u%04x".format(c.code)) else append(c)
        }
    }

    fun toJson(memories: List<Memory>, chat: List<ChatLine>): String = buildString {
        append("{\n  \"app\": \"Kivo\",\n  \"memories\": [\n")
        memories.forEachIndexed { i, m ->
            append("    {\"id\": ${m.id}, \"kind\": \"${m.kind.name}\", \"title\": \"${esc(m.title)}\", \"content\": \"${esc(m.content)}\", ")
            append("\"createdAt\": ${m.createdAt}, \"updatedAt\": ${m.updatedAt}, \"importance\": ${m.importance}, \"done\": ${m.done}}")
            append(if (i < memories.size - 1) ",\n" else "\n")
        }
        append("  ],\n  \"conversation\": [\n")
        chat.forEachIndexed { i, c ->
            append("    {\"time\": ${c.timestampMs}, \"from\": \"${if (c.fromUser) "user" else "kivo"}\", \"text\": \"${esc(c.text)}\"}")
            append(if (i < chat.size - 1) ",\n" else "\n")
        }
        append("  ]\n}\n")
    }
}
