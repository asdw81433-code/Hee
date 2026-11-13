package com.livingai.core

import com.livingai.core.resource.*
import kotlin.test.*

class ResourceManagerTest {
    private val mb = 1L shl 20

    /** A resource that really takes memory away from the fake phone while loaded. */
    private inner class Res(override val name: String, private val sizeMb: Long, private val probe: FakeProbe) : ManagedResource {
        override val estimatedBytes get() = sizeMb * mb
        override var isLoaded = false
        fun load() { if (!isLoaded) { isLoaded = true; probe.available -= estimatedBytes } }
        override fun unload() { if (isLoaded) { isLoaded = false; probe.available += estimatedBytes } }
    }

    private var now = 1_000_000L
    private fun manager(probe: FakeProbe, idleMs: Long = 300_000L) = ResourceManager(probe, { now }, { idleMs }, safetyMarginBytes = 300 * mb)

    @Test fun `with plenty of memory several resources stay loaded together`() {
        val probe = FakeProbe(available = 2000 * mb)
        val rm = manager(probe)
        val llm = Res("AI model", 500, probe); val ocr = Res("OCR", 60, probe)
        rm.register(llm, ResourceMode.CONVERSATION); rm.register(ocr, ResourceMode.VISION)
        assertEquals(ResourceMode.NORMAL, rm.mode)
        assertIs<Admission.Granted>(rm.acquire(llm)); llm.load(); rm.release(llm)
        assertEquals(ResourceMode.CONVERSATION, rm.mode)
        assertIs<Admission.Granted>(rm.acquire(ocr)); ocr.load(); rm.release(ocr)
        assertTrue(llm.isLoaded && ocr.isLoaded)
        assertEquals(ResourceMode.VISION, rm.mode)
        assertEquals(listOf("AI model", "OCR"), rm.snapshot().loaded)
    }

    @Test fun `when memory is tight the least recently used idle resource makes room`() {
        val probe = FakeProbe(available = 900 * mb)
        val rm = manager(probe)
        val llm = Res("AI model", 500, probe); val ocr = Res("OCR", 200, probe); val voice = Res("Voice", 150, probe)
        listOf(llm to ResourceMode.CONVERSATION, ocr to ResourceMode.VISION, voice to ResourceMode.VOICE).forEach { rm.register(it.first, it.second) }
        assertIs<Admission.Granted>(rm.acquire(llm)); llm.load(); rm.release(llm)   // 400 left
        now += 1000
        assertIs<Admission.Granted>(rm.acquire(ocr))                                  // 400-200 < 300 → the model is unloaded first
        assertFalse(llm.isLoaded); ocr.load(); rm.release(ocr)
        now += 1000
        assertIs<Admission.Granted>(rm.acquire(voice)); voice.load()                  // 700-150 fits next to OCR
        assertTrue(ocr.isLoaded && voice.isLoaded)
    }

    @Test fun `a resource in use is never unloaded and an impossible load is refused with a reason`() {
        val probe = FakeProbe(available = 700 * mb)
        val rm = manager(probe)
        val llm = Res("AI model", 350, probe); val big = Res("Big model", 1200, probe)
        rm.register(llm, ResourceMode.CONVERSATION); rm.register(big, ResourceMode.CONVERSATION)
        assertIs<Admission.Granted>(rm.acquire(llm)); llm.load()                      // still in use (not released)
        val denied = rm.acquire(big)
        assertIs<Admission.Denied>(denied)
        assertTrue(denied.reason.contains("Big model"))
        assertTrue(llm.isLoaded, "a busy resource must survive")
        rm.onMemoryPressure(Pressure.CRITICAL)
        assertTrue(llm.isLoaded)
        rm.release(llm)
        assertEquals(listOf("AI model"), rm.onMemoryPressure(Pressure.CRITICAL))
        assertFalse(llm.isLoaded)
    }

    @Test fun `idle resources are released and memory pressure switches to low-ram mode`() {
        val probe = FakeProbe(available = 2000 * mb)
        val rm = manager(probe, idleMs = 60_000L)
        val llm = Res("AI model", 500, probe)
        rm.register(llm, ResourceMode.CONVERSATION)
        rm.acquire(llm); llm.load(); rm.release(llm)
        now += 30_000
        assertTrue(rm.onIdleTick().isEmpty()); assertTrue(llm.isLoaded)
        now += 31_000
        assertEquals(listOf("AI model"), rm.onIdleTick()); assertFalse(llm.isLoaded)
        assertEquals(ResourceMode.NORMAL, rm.mode)

        rm.acquire(llm); llm.load(); rm.release(llm)
        now += 5_000
        assertTrue(rm.onMemoryPressure(Pressure.MODERATE).isEmpty(), "used 5 s ago: kept on moderate pressure")
        assertTrue(rm.lowRam); assertEquals(ResourceMode.LOW_RAM, rm.mode)
        now += 61_000
        assertFalse(rm.lowRam)
        probe.low = true
        assertTrue(rm.lowRam, "the OS flag alone is enough")
    }
}
