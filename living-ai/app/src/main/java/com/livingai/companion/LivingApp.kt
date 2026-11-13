package com.livingai.companion

import android.app.Application
import android.content.ComponentCallbacks2
import android.content.Context
import com.livingai.companion.agent.AgentController
import com.livingai.companion.data.RoomMemoryStore
import com.livingai.companion.settings.Prefs

/** Small manual dependency graph: everything is created lazily and lives as long as the process. */
class AppGraph(context: Context) {
    val prefs = Prefs(context)
    val memoryStore = RoomMemoryStore(context)
    val controller = AgentController(context, prefs, memoryStore)
    val floating = com.livingai.companion.overlay.FloatingOrbManager(context, prefs, controller)
}

class LivingApp : Application() {
    val graph: AppGraph by lazy { AppGraph(this) }

    override fun onCreate() {
        super.onCreate()
        applyLanguage()
        // Put the orb back after the process restarts (the accessibility service takes over if it connects).
        android.os.Handler(mainLooper).post { graph.floating.apply() }
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        applyLanguage()
    }

    /** Thai on Thai devices, English everywhere else. */
    private fun applyLanguage() {
        com.livingai.core.Lang.thai = resources.configuration.locales[0].language == "th"
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        // The system is running low on memory (or we are a candidate for being killed).
        @Suppress("DEPRECATION")
        if (level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW || level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL ||
            level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND
        ) {
            graph.controller.onLowMemory()
        }
    }

    override fun onLowMemory() {
        super.onLowMemory()
        graph.controller.onLowMemory()
    }

    companion object {
        fun graph(context: Context): AppGraph = (context.applicationContext as LivingApp).graph
    }
}
