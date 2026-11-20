# Source me: sets GODOT (override with your own path) and, inside containers
# without a GPU, the software Vulkan driver used for screenshots.
export GODOT="${GODOT:-godot}"
if [ -f /opt/lavapipe/lvp_icd.json ]; then
	export VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json
fi
