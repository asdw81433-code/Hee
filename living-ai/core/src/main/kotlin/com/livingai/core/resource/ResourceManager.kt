package com.livingai.core.resource

import com.livingai.core.Clock
import com.livingai.core.Lang.tr

/** How much memory the phone has. Implemented on Android with ActivityManager. */
interface MemoryProbe {
    /** RAM the system could still hand out, in bytes. */
    fun availableBytes(): Long
    fun totalBytes(): Long
    /** The OS itself reports memory pressure. */
    fun isLowMemory(): Boolean
    /** Memory used by this app, in bytes (for display). */
    fun appUsedBytes(): Long
}

/** Anything big that should only be in memory while it is needed: AI model, OCR, voice, capture. */
interface ManagedResource {
    val name: String
    /** RAM needed while loaded, in bytes. */
    val estimatedBytes: Long
    val isLoaded: Boolean
    fun unload()
}

enum class ResourceMode { NORMAL, CONVERSATION, VOICE, VISION, LOW_RAM }
enum class Pressure { MODERATE, CRITICAL }

sealed interface Admission {
    data object Granted : Admission
    data class Denied(val reason: String) : Admission
}

data class ResourceSnapshot(
    val mode: ResourceMode,
    val availableMb: Long,
    val totalMb: Long,
    val appUsedMb: Long,
    val loaded: List<String>,
)

/**
 * Decides what may be in memory at the same time on a small phone.
 *
 *  - nothing heavy is loaded until it is asked for ([acquire]);
 *  - before a load, other idle resources are unloaded (least recently used first) until the new
 *    one fits while leaving [safetyMarginBytes] for Android and the foreground app;
 *  - if it still does not fit, the load is refused with a reason instead of risking a crash;
 *  - resources nobody used for [idleUnloadMs] are released ([onIdleTick]);
 *  - on memory pressure everything that is not in use right now is released ([onMemoryPressure]).
 */
class ResourceManager(
    private val probe: MemoryProbe,
    private val clock: Clock,
    private val idleUnloadMs: () -> Long = { 5 * 60_000L },
    private val safetyMarginBytes: Long = 300L shl 20,
) {
    private class Entry(val resource: ManagedResource, val mode: ResourceMode) {
        var lastUsedMs = 0L
        var users = 0
    }

    private val entries = LinkedHashMap<String, Entry>()
    private var lowRamUntilMs = 0L
    private var lastMode = ResourceMode.NORMAL

    @Synchronized
    fun register(resource: ManagedResource, mode: ResourceMode) {
        entries[resource.name] = Entry(resource, mode)
    }

    /**
     * Call before loading or using [resource]. Granted means: go ahead (and call [release] when
     * done). Denied means there is not enough memory even after freeing everything else.
     */
    @Synchronized
    fun acquire(resource: ManagedResource): Admission {
        val entry = entries[resource.name] ?: Entry(resource, ResourceMode.NORMAL).also { entries[resource.name] = it }
        val now = clock.nowMs()
        if (!resource.isLoaded) {
            val needed = resource.estimatedBytes
            var available = probe.availableBytes()
            if (available - needed < safetyMarginBytes) {
                // Free the least recently used idle resources first.
                val victims = entries.values.filter { it !== entry && it.resource.isLoaded && it.users == 0 }.sortedBy { it.lastUsedMs }
                for (v in victims) {
                    v.resource.unload()
                    available = probe.availableBytes()
                    if (available - needed >= safetyMarginBytes) break
                }
            }
            if (available - needed < safetyMarginBytes) {
                return Admission.Denied(
                    tr(
                        "หน่วยความจำไม่พอสำหรับ ${resource.name} (ต้องใช้ ~${needed shr 20} MB ว่างอยู่ ${available shr 20} MB) ลองปิดแอปอื่นก่อน",
                        "Not enough memory for ${resource.name} (needs ~${needed shr 20} MB, ${available shr 20} MB free). Close other apps first.",
                    )
                )
            }
        }
        entry.users++
        entry.lastUsedMs = now
        lastMode = entry.mode
        return Admission.Granted
    }

    /** The caller finished using [resource]; it stays loaded until idle or until memory is needed. */
    @Synchronized
    fun release(resource: ManagedResource) {
        val entry = entries[resource.name] ?: return
        if (entry.users > 0) entry.users--
        entry.lastUsedMs = clock.nowMs()
    }

    /** Unloads resources nobody used for a while. Returns the names that were released. */
    @Synchronized
    fun onIdleTick(): List<String> {
        val now = clock.nowMs()
        val limit = idleUnloadMs()
        val released = ArrayList<String>()
        for (e in entries.values) {
            if (limit > 0 && e.resource.isLoaded && e.users == 0 && now - e.lastUsedMs >= limit) {
                e.resource.unload()
                released.add(e.resource.name)
            }
        }
        return released
    }

    /** The OS asked for memory back. Returns the names that were released. */
    @Synchronized
    fun onMemoryPressure(level: Pressure): List<String> {
        val now = clock.nowMs()
        lowRamUntilMs = now + if (level == Pressure.CRITICAL) 120_000L else 60_000L
        val released = ArrayList<String>()
        for (e in entries.values) {
            val idleEnough = level == Pressure.CRITICAL || now - e.lastUsedMs >= 20_000L
            if (e.resource.isLoaded && e.users == 0 && idleEnough) {
                e.resource.unload()
                released.add(e.resource.name)
            }
        }
        return released
    }

    /** True while the phone is short of memory: animations should slow down and nothing optional should load. */
    val lowRam: Boolean
        @Synchronized get() = clock.nowMs() < lowRamUntilMs || probe.isLowMemory()

    val mode: ResourceMode
        @Synchronized get() = when {
            lowRam -> ResourceMode.LOW_RAM
            entries.values.none { it.resource.isLoaded } -> ResourceMode.NORMAL
            else -> lastMode
        }

    @Synchronized
    fun snapshot(): ResourceSnapshot = ResourceSnapshot(
        mode = mode,
        availableMb = probe.availableBytes() shr 20,
        totalMb = probe.totalBytes() shr 20,
        appUsedMb = probe.appUsedBytes() shr 20,
        loaded = entries.values.filter { it.resource.isLoaded }.map { it.resource.name },
    )
}
