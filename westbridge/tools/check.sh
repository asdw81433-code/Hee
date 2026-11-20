#!/bin/bash
# Compiles every script; prints only errors. Exit code != 0 on failure.
cd "$(dirname "$0")/.." && source tools/env.sh
# Refresh the global class_name cache first (new scripts).
timeout 300 $GODOT --headless --path . --import >/dev/null 2>&1
timeout 120 $GODOT --headless --path . res://tools/check_scripts.tscn 2>&1 | grep -v -E "ALSA|audio|^Godot Engine|^$|GDScript backtrace|^\s+\[[0-9]+\] |ERR_CANT_OPEN|dummy driver|initialize \(servers" 
exit ${PIPESTATUS[0]}
