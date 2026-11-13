package com.livingai.companion.data

import android.content.Context
import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import com.livingai.core.memory.MemoryStore
import com.livingai.core.memory.ChatLine
import com.livingai.core.memory.MemoryEvent
import com.livingai.core.memory.MemoryFact

@Entity(tableName = "facts")
data class FactEntity(
    @PrimaryKey val key: String,
    val value: String,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
)

@Entity(tableName = "events")
data class EventEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Long,
    @ColumnInfo(name = "package_name") val packageName: String,
    val summary: String,
)

@Entity(tableName = "chat")
data class ChatEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Long,
    @ColumnInfo(name = "from_user") val fromUser: Boolean,
    val text: String,
)

@Dao
interface MemoryDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun putFact(fact: FactEntity)

    @Query("SELECT * FROM facts WHERE `key` LIKE '%' || :q || '%' OR value LIKE '%' || :q || '%' ORDER BY updated_at DESC LIMIT :limit")
    suspend fun searchFacts(q: String, limit: Int): List<FactEntity>

    @Query("SELECT * FROM facts ORDER BY updated_at DESC LIMIT :limit")
    suspend fun recentFacts(limit: Int): List<FactEntity>

    @Insert
    suspend fun addEvent(event: EventEntity)

    @Query("SELECT * FROM events ORDER BY id DESC LIMIT :limit")
    suspend fun recentEvents(limit: Int): List<EventEntity>

    @Query("DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT 300)")
    suspend fun trimEvents()

    @Insert
    suspend fun addChat(line: ChatEntity)

    @Query("SELECT * FROM chat ORDER BY id DESC LIMIT :limit")
    suspend fun recentChat(limit: Int): List<ChatEntity>

    @Query("DELETE FROM chat WHERE id NOT IN (SELECT id FROM chat ORDER BY id DESC LIMIT 300)")
    suspend fun trimChat()

    @Query("DELETE FROM facts")
    suspend fun clearFacts()

    @Query("DELETE FROM events")
    suspend fun clearEvents()

    @Query("DELETE FROM chat")
    suspend fun clearChat()
}

@Database(entities = [FactEntity::class, EventEntity::class, ChatEntity::class], version = 1, exportSchema = false)
abstract class MemoryDb : RoomDatabase() {
    abstract fun dao(): MemoryDao
}

/** Room-backed long-term memory. Stays on the device; excluded from backups. */
class RoomMemoryStore(context: Context) : MemoryStore {
    private val dao: MemoryDao by lazy {
        Room.databaseBuilder(context.applicationContext, MemoryDb::class.java, "living_memory.db").build().dao()
    }
    private var writes = 0

    override suspend fun putFact(key: String, value: String) = dao.putFact(FactEntity(key, value, System.currentTimeMillis()))
    override suspend fun searchFacts(query: String, limit: Int) = dao.searchFacts(query, limit).map { MemoryFact(it.key, it.value, it.updatedAt) }
    override suspend fun recentFacts(limit: Int) = dao.recentFacts(limit).map { MemoryFact(it.key, it.value, it.updatedAt) }

    override suspend fun addEvent(packageName: String, summary: String) {
        dao.addEvent(EventEntity(timestamp = System.currentTimeMillis(), packageName = packageName, summary = summary))
        if (++writes % 50 == 0) dao.trimEvents()
    }

    override suspend fun recentEvents(limit: Int) = dao.recentEvents(limit).map { MemoryEvent(it.timestamp, it.packageName, it.summary) }

    override suspend fun addChat(fromUser: Boolean, text: String) {
        dao.addChat(ChatEntity(timestamp = System.currentTimeMillis(), fromUser = fromUser, text = text))
        if (++writes % 50 == 0) dao.trimChat()
    }

    override suspend fun recentChat(limit: Int) = dao.recentChat(limit).map { ChatLine(it.timestamp, it.fromUser, it.text) }

    suspend fun clearAll() {
        dao.clearFacts(); dao.clearEvents(); dao.clearChat()
    }
}
