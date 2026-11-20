extends Node
## Global signal hub. Systems talk to each other through these signals instead of
## holding hard references, so modules (NPC, police, phone, economy...) stay decoupled.

# --- World / time -------------------------------------------------------------
signal hour_changed(day: int, hour: int)
signal day_changed(day: int)
signal weather_changed(weather_id: StringName)

# --- Player -------------------------------------------------------------------
signal player_spawned(player: Node)
signal money_changed(new_amount: int, delta: int, reason: String)
signal interaction_prompt_changed(text: String, available: bool)
signal stats_changed(stats: Dictionary)

# --- Characters / physics -----------------------------------------------------
## Fired for every impact a humanoid receives. `info` contains the ImpactData dictionary.
signal character_impacted(body: Node, info: Dictionary)
signal character_fell(body: Node)
signal character_recovered(body: Node)

## Generic world event used by the perception system (fights, crashes, noises...).
## Keys: type, position, radius, severity, instigator, victim, time
signal world_event(event: Dictionary)

# --- NPC ----------------------------------------------------------------------
signal npc_action_changed(npc_id: int, action_name: String, reason: String)
signal npc_selected(npc_id: int)

# --- UI -----------------------------------------------------------------------
signal toast(text: String)
signal save_finished(slot: int, ok: bool, message: String)
signal load_finished(slot: int, ok: bool, message: String)
signal settings_applied
signal controls_layout_changed
