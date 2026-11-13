package com.livingai.core

/** Two-language text for everything a person reads. The app sets [thai] from the device language. */
object Lang {
    @Volatile var thai: Boolean = true
    fun tr(th: String, en: String): String = if (thai) th else en
}

object Persona {
    /** The assistant's name, the same in every language. */
    const val NAME = "Kivo"
}
