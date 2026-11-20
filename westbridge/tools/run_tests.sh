#!/bin/bash
# Runs every automated check for Westbridge. Exit code 0 = all green.
#   1. compile every GDScript file
#   2. unit + integration tests (save, mesh, animation, balance, memory, city, NPC AI, 2-day sim)
#   3. physics lab (balance, steps, ragdoll, joint limits, get-up, stairs, slopes, falls)
#   4. in-world test (NPC bodies, punch reactions, memories, talk, save, sleep, load)
# Set GODOT=/path/to/godot to use your own binary.
cd "$(dirname "$0")/.." || exit 1
source tools/env.sh
fail=0
echo "== compile =="; ./tools/check.sh || fail=1
filter() { grep -E "PASS|FAIL|RESULT|TESTS|SCRIPT ERROR"; }
echo "== unit/integration =="; timeout 600 $GODOT --headless --path . res://tests/test_runner.tscn 2>&1 | filter; [ ${PIPESTATUS[0]} -eq 0 ] || fail=1
echo "== physics lab =="; timeout 600 $GODOT --headless --path . res://scenes/physics_lab.tscn -- labtest 2>&1 | filter; [ ${PIPESTATUS[0]} -eq 0 ] || fail=1
echo "== world =="; timeout 600 $GODOT --headless --path . res://scenes/game_world.tscn -- worldtest 2>&1 | filter; [ ${PIPESTATUS[0]} -eq 0 ] || fail=1
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
