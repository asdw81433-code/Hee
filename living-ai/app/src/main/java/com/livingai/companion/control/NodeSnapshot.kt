package com.livingai.companion.control

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import com.livingai.core.perception.Bounds
import com.livingai.core.perception.UiElement

/**
 * A frozen view of the accessibility node tree: the elements handed to the agents plus the
 * live nodes behind each element id, so actions always hit a node that was really observed.
 */
class NodeSnapshot(
    val timestampMs: Long,
    val packageName: String,
    val elements: List<UiElement>,
    private val nodes: Map<Int, AccessibilityNodeInfo>,
) {
    fun node(id: Int): AccessibilityNodeInfo? = nodes[id]

    companion object {
        private const val MAX_ELEMENTS = 140
        private const val MAX_VISITED = 1500
        private const val MAX_DEPTH = 40

        val EMPTY = NodeSnapshot(0L, "", emptyList(), emptyMap())

        fun capture(root: AccessibilityNodeInfo?, screenW: Int, screenH: Int, now: Long): NodeSnapshot {
            if (root == null) return NodeSnapshot(now, "", emptyList(), emptyMap())
            val b = Builder(screenW, screenH)
            b.walk(root, 0)
            return NodeSnapshot(now, root.packageName?.toString().orEmpty(), b.elements, b.nodes)
        }
    }

    private class Builder(val screenW: Int, val screenH: Int) {
        val elements = ArrayList<UiElement>()
        val nodes = HashMap<Int, AccessibilityNodeInfo>()
        private var visited = 0
        private val rect = Rect()

        /** Depth-first walk. Returns the texts found in this subtree (to label icon-only containers). */
        fun walk(node: AccessibilityNodeInfo, depth: Int): List<String> {
            if (++visited > MAX_VISITED || depth > MAX_DEPTH || !node.isVisibleToUser) return emptyList()

            val password = node.isPassword
            val text = if (password) "" else node.text?.toString()?.trim().orEmpty().take(200)
            val desc = if (password) "" else (node.contentDescription?.toString()?.trim().orEmpty().ifEmpty {
                // hint of an empty input field
                if (node.isEditable && text.isEmpty()) node.hintText?.toString()?.trim().orEmpty() else ""
            }).take(200)

            node.getBoundsInScreen(rect)
            val onScreen = !rect.isEmpty && rect.right > 0 && rect.bottom > 0 && rect.left < screenW && rect.top < screenH
            val interactive = node.isClickable || node.isEditable || node.isScrollable || node.isCheckable
            val keep = onScreen && (interactive || text.isNotEmpty() || desc.isNotEmpty()) && elements.size < MAX_ELEMENTS

            var index = -1
            if (keep) {
                index = elements.size
                val id = index + 1
                elements.add(
                    UiElement(
                        id = id,
                        role = node.className?.toString()?.substringAfterLast('.').orEmpty().ifEmpty { "View" },
                        text = text,
                        description = desc,
                        viewId = node.viewIdResourceName.orEmpty(),
                        bounds = Bounds(rect.left, rect.top, rect.right, rect.bottom),
                        clickable = node.isClickable,
                        editable = node.isEditable,
                        scrollable = node.isScrollable,
                        checkable = node.isCheckable,
                        checked = node.isChecked,
                        focused = node.isFocused || node.isAccessibilityFocused,
                        enabled = node.isEnabled,
                        password = password,
                    )
                )
                nodes[id] = node
            }

            val childTexts = ArrayList<String>()
            for (i in 0 until node.childCount) {
                val child = try { node.getChild(i) } catch (e: Exception) { null } ?: continue
                childTexts.addAll(walk(child, depth + 1))
            }

            // A clickable row without its own label is described by what it contains.
            if (index >= 0 && text.isEmpty() && desc.isEmpty() && node.isClickable && childTexts.isNotEmpty()) {
                elements[index] = elements[index].copy(description = childTexts.take(3).joinToString(" · ").take(120))
            }
            return when {
                password -> emptyList()
                text.isNotEmpty() -> listOf(text) + childTexts
                desc.isNotEmpty() -> listOf(desc) + childTexts
                else -> childTexts
            }.take(6)
        }
    }
}
