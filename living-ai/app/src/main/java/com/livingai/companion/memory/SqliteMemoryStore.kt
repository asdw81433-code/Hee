package com.livingai.companion.memory

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.livingai.core.memory.ChatLine
import com.livingai.core.memory.Grams
import com.livingai.core.memory.Memory
import com.livingai.core.memory.MemoryKind
import com.livingai.core.memory.MemoryStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Kivo's memory in a private SQLite database on the phone (never backed up, never uploaded).
 *
 *  memories  one row per fact / episode / knowledge / note / to-do
 *  grams     inverted index of character n-grams (see [Grams]) → relevance search that works for
 *            Thai, where word-based full-text search cannot split the text
 *  chat      the conversation log (short-term memory)
 *
 * On first start the data of the previous version (Room database "living_memory.db") is imported.
 */
class SqliteMemoryStore(private val context: Context) : MemoryStore {

    private val helper = object : SQLiteOpenHelper(context.applicationContext, DB_NAME, null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE memories (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, title TEXT NOT NULL, content TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, importance INTEGER NOT NULL, done INTEGER NOT NULL)")
            db.execSQL("CREATE INDEX idx_memories_kind ON memories(kind, updated_at)")
            db.execSQL("CREATE TABLE grams (gram TEXT NOT NULL, memory_id INTEGER NOT NULL, PRIMARY KEY (gram, memory_id)) WITHOUT ROWID")
            db.execSQL("CREATE INDEX idx_grams_memory ON grams(memory_id)")
            db.execSQL("CREATE TABLE chat (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, from_user INTEGER NOT NULL, text TEXT NOT NULL)")
            importLegacy(db)
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
    }

    /** Copies facts, events and chat from the old Room database, if there is one. The old file is left untouched. */
    private fun importLegacy(db: SQLiteDatabase) {
        val file = context.getDatabasePath(LEGACY_DB)
        if (!file.exists()) return
        try {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use { old ->
                old.rawQuery("SELECT `key`, value, updated_at FROM facts", null).use { c ->
                    while (c.moveToNext()) insert(db, Memory(kind = MemoryKind.FACT, title = c.getString(0), content = c.getString(1), createdAt = c.getLong(2), updatedAt = c.getLong(2), importance = 2))
                }
                old.rawQuery("SELECT timestamp, summary FROM events ORDER BY id DESC LIMIT 100", null).use { c ->
                    while (c.moveToNext()) insert(db, Memory(kind = MemoryKind.EPISODE, title = c.getString(1), content = "", createdAt = c.getLong(0), updatedAt = c.getLong(0)))
                }
                old.rawQuery("SELECT timestamp, from_user, text FROM chat ORDER BY id DESC LIMIT 200", null).use { c ->
                    val rows = ArrayList<ContentValues>()
                    while (c.moveToNext()) rows.add(ContentValues().apply { put("timestamp", c.getLong(0)); put("from_user", c.getInt(1)); put("text", c.getString(2)) })
                    rows.reversed().forEach { db.insert("chat", null, it) }
                }
            }
        } catch (e: Exception) {
            // an unreadable old database must never stop the app from starting
        }
    }

    private fun values(m: Memory) = ContentValues().apply {
        put("kind", m.kind.name); put("title", m.title); put("content", m.content)
        put("created_at", m.createdAt); put("updated_at", m.updatedAt); put("importance", m.importance); put("done", if (m.done) 1 else 0)
    }

    private fun index(db: SQLiteDatabase, id: Long, m: Memory) {
        db.delete("grams", "memory_id = ?", arrayOf(id.toString()))
        val st = db.compileStatement("INSERT OR IGNORE INTO grams (gram, memory_id) VALUES (?, ?)")
        for (g in Grams.of(m.title + " " + m.content)) { st.bindString(1, g); st.bindLong(2, id); st.executeInsert() }
        st.close()
    }

    private fun insert(db: SQLiteDatabase, m: Memory): Long {
        val id = db.insert("memories", null, values(m))
        if (id > 0) index(db, id, m)
        return id
    }

    private fun row(c: Cursor) = Memory(
        id = c.getLong(0), kind = runCatching { MemoryKind.valueOf(c.getString(1)) }.getOrDefault(MemoryKind.NOTE), title = c.getString(2), content = c.getString(3),
        createdAt = c.getLong(4), updatedAt = c.getLong(5), importance = c.getInt(6), done = c.getInt(7) != 0,
    )

    override suspend fun save(memory: Memory): Long = withContext(Dispatchers.IO) {
        val db = helper.writableDatabase
        val now = System.currentTimeMillis()
        db.beginTransaction()
        try {
            var id = memory.id
            var created = if (memory.createdAt == 0L) now else memory.createdAt
            if (id == 0L && memory.kind == MemoryKind.FACT) {
                db.rawQuery("SELECT id, created_at FROM memories WHERE kind = 'FACT' AND title = ? LIMIT 1", arrayOf(memory.title)).use { c ->
                    if (c.moveToFirst()) { id = c.getLong(0); created = c.getLong(1) }
                }
            }
            val m = memory.copy(createdAt = created, updatedAt = now)
            if (id == 0L) {
                id = insert(db, m)
            } else {
                db.update("memories", values(m), "id = ?", arrayOf(id.toString()))
                index(db, id, m)
            }
            db.setTransactionSuccessful()
            id
        } finally {
            db.endTransaction()
        }
    }

    override suspend fun delete(id: Long): Unit = withContext(Dispatchers.IO) {
        val db = helper.writableDatabase
        db.delete("grams", "memory_id = ?", arrayOf(id.toString()))
        db.delete("memories", "id = ?", arrayOf(id.toString()))
    }

    override suspend fun list(kind: MemoryKind?, limit: Int): List<Memory> = withContext(Dispatchers.IO) {
        val out = ArrayList<Memory>()
        val (where, args) = if (kind == null) "" to emptyArray() else "WHERE kind = ?" to arrayOf(kind.name)
        helper.readableDatabase.rawQuery("SELECT $COLS FROM memories $where ORDER BY updated_at DESC, id DESC LIMIT $limit", args).use { c ->
            while (c.moveToNext()) out.add(row(c))
        }
        out
    }

    override suspend fun search(query: String, limit: Int, kind: MemoryKind?): List<Memory> = withContext(Dispatchers.IO) {
        val grams = Grams.of(query).take(60)
        if (grams.isEmpty()) return@withContext emptyList()
        // the index narrows thousands of rows down to a few candidates; the final ranking is shared with the tests
        val marks = grams.joinToString(",") { "?" }
        val ids = ArrayList<Long>()
        helper.readableDatabase.rawQuery("SELECT memory_id, COUNT(*) AS hits FROM grams WHERE gram IN ($marks) GROUP BY memory_id ORDER BY hits DESC LIMIT 40", grams.toTypedArray()).use { c ->
            while (c.moveToNext()) ids.add(c.getLong(0))
        }
        if (ids.isEmpty()) return@withContext emptyList()
        val candidates = ArrayList<Memory>()
        helper.readableDatabase.rawQuery("SELECT $COLS FROM memories WHERE id IN (${ids.joinToString(",")})", null).use { c ->
            while (c.moveToNext()) row(c).let { if (kind == null || it.kind == kind) candidates.add(it) }
        }
        Grams.rank(query, candidates, limit)
    }

    override suspend fun addChat(fromUser: Boolean, text: String): Unit = withContext(Dispatchers.IO) {
        val db = helper.writableDatabase
        db.insert("chat", null, ContentValues().apply { put("timestamp", System.currentTimeMillis()); put("from_user", if (fromUser) 1 else 0); put("text", text) })
        db.execSQL("DELETE FROM chat WHERE id <= (SELECT MAX(id) FROM chat) - $CHAT_KEEP")
    }

    override suspend fun recentChat(limit: Int): List<ChatLine> = withContext(Dispatchers.IO) {
        val out = ArrayList<ChatLine>()
        helper.readableDatabase.rawQuery("SELECT timestamp, from_user, text FROM chat ORDER BY id DESC LIMIT $limit", null).use { c ->
            while (c.moveToNext()) out.add(ChatLine(c.getLong(0), c.getInt(1) != 0, c.getString(2)))
        }
        out.reversed()
    }

    override suspend fun clearChat(): Unit = withContext(Dispatchers.IO) { helper.writableDatabase.delete("chat", null, null) }

    override suspend fun clearAll(): Unit = withContext(Dispatchers.IO) {
        val db = helper.writableDatabase
        db.delete("grams", null, null); db.delete("memories", null, null); db.delete("chat", null, null)
        // the imported old database must not come back either
        context.deleteDatabase(LEGACY_DB)
    }

    companion object {
        const val DB_NAME = "kivo_memory.db"
        const val LEGACY_DB = "living_memory.db"
        private const val COLS = "id, kind, title, content, created_at, updated_at, importance, done"
        private const val CHAT_KEEP = 500
    }
}
