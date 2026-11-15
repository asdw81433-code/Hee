package com.livingai.core.robot

/** What sits on top of the head. */
enum class Topper { ANTENNA, TWIN_ANTENNA, PROPELLER, BUNNY_EARS, CAT_EARS, SPROUT, CREST, HORN, HALO, NONE }

/** What is under the body. */
enum class Base { JET, RING, CLOUD }

/**
 * The shape of a hovering robot character: head and body proportions, face screen, eyes, ears,
 * what sits on the head, hands and base, plus its own colours (0 = use the skin's).
 * [CLASSIC] is the original Kivo; the others are new characters to choose from.
 */
data class BotDesign(
    val id: String,
    val nameTh: String,
    val nameEn: String,
    val body: Int = 0,
    val accent: Int = 0,
    val visor: Int = 0,
    /** head ellipsoid radii (x, y, z) */
    val headR: Triple<Float, Float, Float> = Triple(0.66f, 0.56f, 0.6f),
    /** body ellipsoid radii; null = no body, the head floats alone */
    val bodyR: Triple<Float, Float, Float>? = Triple(0.37f, 0.34f, 0.33f),
    /** face screen radii (x, y, z) and its height on the head */
    val visorR: Triple<Float, Float, Float> = Triple(0.52f, 0.34f, 0.33f),
    val visorY: Float = 0.37f,
    val oneEye: Boolean = false,
    val eyeScale: Float = 1f,
    val earPods: Boolean = true,
    val headphones: Boolean = false,
    val topper: Topper = Topper.ANTENNA,
    val base: Base = Base.JET,
    val hands: Boolean = true,
    val handSize: Float = 1f,
    val blush: Boolean = false,
    val whiskers: Boolean = false,
    val tummyLight: Boolean = true,
) {
    companion object {
        val CLASSIC = BotDesign("classic", "คลาสสิก", "Classic")

        val PIP = BotDesign(
            "pip", "ปิ๊บ", "Pip", body = 0xFF5ED6C0.toInt(), accent = 0xFFFFB347.toInt(), visor = 0xFF14303A.toInt(),
            headR = Triple(0.72f, 0.7f, 0.7f), bodyR = null, visorR = Triple(0.42f, 0.42f, 0.36f), visorY = 0.42f,
            oneEye = true, eyeScale = 1.9f, earPods = false, topper = Topper.PROPELLER, handSize = 0.8f, tummyLight = false,
        )
        val MOCHI = BotDesign(
            "mochi", "โมจิ", "Mochi", body = 0xFFFFE3EC.toInt(), accent = 0xFFFF8FB1.toInt(), visor = 0xFF3A2433.toInt(),
            headR = Triple(0.78f, 0.52f, 0.62f), bodyR = Triple(0.34f, 0.28f, 0.3f), visorR = Triple(0.6f, 0.3f, 0.36f), visorY = 0.36f,
            earPods = false, topper = Topper.BUNNY_EARS, base = Base.CLOUD, blush = true, handSize = 0.9f,
        )
        val BOLT = BotDesign(
            "bolt", "โบลต์", "Bolt", body = 0xFFFFD43B.toInt(), accent = 0xFF2B2B36.toInt(), visor = 0xFF101018.toInt(),
            headR = Triple(0.56f, 0.66f, 0.54f), bodyR = Triple(0.3f, 0.36f, 0.3f), visorR = Triple(0.5f, 0.17f, 0.32f), visorY = 0.42f,
            eyeScale = 0.85f, topper = Topper.TWIN_ANTENNA, handSize = 1.05f,
        )
        val NEKO = BotDesign(
            "neko", "เนโกะ", "Neko", body = 0xFFC9B6FF.toInt(), accent = 0xFF7B5CFF.toInt(), visor = 0xFF1E1638.toInt(),
            headR = Triple(0.68f, 0.58f, 0.6f), bodyR = Triple(0.33f, 0.32f, 0.3f), visorR = Triple(0.5f, 0.36f, 0.33f),
            earPods = false, topper = Topper.CAT_EARS, whiskers = true, blush = true,
        )
        val ORBIT = BotDesign(
            "orbit", "ออร์บิต", "Orbit", body = 0xFF3D5AFE.toInt(), accent = 0xFFFF9F43.toInt(), visor = 0xFF0B1030.toInt(),
            headR = Triple(0.62f, 0.6f, 0.6f), bodyR = Triple(0.42f, 0.4f, 0.4f), visorR = Triple(0.46f, 0.34f, 0.33f),
            earPods = false, headphones = true, topper = Topper.NONE, base = Base.RING,
        )
        val SPROUT = BotDesign(
            "sprout", "สเปราต์", "Sprout", body = 0xFFF4EBD0.toInt(), accent = 0xFF4CAF50.toInt(), visor = 0xFF1F2B1C.toInt(),
            headR = Triple(0.7f, 0.6f, 0.62f), bodyR = Triple(0.36f, 0.34f, 0.32f), visorR = Triple(0.44f, 0.3f, 0.34f), visorY = 0.35f,
            earPods = false, topper = Topper.SPROUT, handSize = 1.25f, blush = true,
        )
        val KNIGHT = BotDesign(
            "knight", "ไนต์", "Knight", body = 0xFFC7CEDB.toInt(), accent = 0xFFE53950.toInt(), visor = 0xFF0E0F14.toInt(),
            headR = Triple(0.6f, 0.62f, 0.6f), bodyR = Triple(0.4f, 0.36f, 0.34f), visorR = Triple(0.5f, 0.12f, 0.34f), visorY = 0.38f,
            eyeScale = 0.75f, topper = Topper.CREST, handSize = 1.15f,
        )
        val COSMO = BotDesign(
            "cosmo", "คอสโม", "Cosmo", body = 0xFFFFFFFF.toInt(), accent = 0xFFFF7A1A.toInt(), visor = 0xFFC8962E.toInt(),
            headR = Triple(0.7f, 0.64f, 0.66f), bodyR = Triple(0.4f, 0.34f, 0.36f), visorR = Triple(0.56f, 0.44f, 0.38f), visorY = 0.38f,
            earPods = false, headphones = true, topper = Topper.ANTENNA,
        )
        val GHOSTY = BotDesign(
            "ghosty", "โกสตี้", "Ghosty", body = 0xFFE6F4FF.toInt(), accent = 0xFF7FD3FF.toInt(), visor = 0xFF1A2A3A.toInt(),
            headR = Triple(0.66f, 0.62f, 0.6f), bodyR = Triple(0.44f, 0.42f, 0.42f), visorR = Triple(0.48f, 0.36f, 0.33f), visorY = 0.4f,
            earPods = false, topper = Topper.HALO, hands = false, base = Base.CLOUD, blush = true, tummyLight = false,
        )
        val FLARE = BotDesign(
            "flare", "แฟลร์", "Flare", body = 0xFFFF7A6B.toInt(), accent = 0xFFFFE07A.toInt(), visor = 0xFF2A0F14.toInt(),
            headR = Triple(0.66f, 0.56f, 0.6f), bodyR = Triple(0.34f, 0.3f, 0.3f), visorR = Triple(0.54f, 0.36f, 0.34f),
            earPods = true, topper = Topper.HORN, blush = false, eyeScale = 1.15f,
        )
        /** The ten new characters (the original stays available as [CLASSIC]). */
        val NEW = listOf(PIP, MOCHI, BOLT, NEKO, ORBIT, SPROUT, KNIGHT, COSMO, GHOSTY, FLARE)
        val ALL = listOf(CLASSIC) + NEW

        fun byId(id: String?) = ALL.firstOrNull { it.id == id } ?: CLASSIC
    }
}
