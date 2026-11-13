package com.livingai.companion.resource

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import com.livingai.core.resource.MemoryProbe

/** Real memory numbers of this phone, from ActivityManager. */
class AndroidMemoryProbe(context: Context) : MemoryProbe {
    private val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

    private fun info() = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }

    override fun availableBytes(): Long = info().availMem
    override fun totalBytes(): Long = info().totalMem
    override fun isLowMemory(): Boolean = info().lowMemory

    /** Java heap in use plus native heap (the AI model's working memory lives there). */
    override fun appUsedBytes(): Long {
        val rt = Runtime.getRuntime()
        return (rt.totalMemory() - rt.freeMemory()) + Debug.getNativeHeapAllocatedSize()
    }
}
