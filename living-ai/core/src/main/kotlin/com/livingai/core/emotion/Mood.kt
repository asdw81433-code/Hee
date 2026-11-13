package com.livingai.core.emotion

/**
 * Kivo's simulated emotional state. It is a state machine that drives expression (face, body,
 * voice, wording); it is not a claim that the software feels anything.
 * FOCUSED is the "working" face shown while a task runs.
 */
enum class Mood { CALM, HAPPY, SAD, CURIOUS, EXCITED, SLEEPY, CONFUSED, FRUSTRATED, FOCUSED }
