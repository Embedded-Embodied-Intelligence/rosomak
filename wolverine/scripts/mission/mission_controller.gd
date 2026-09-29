class_name MissionController
extends Node

## Linear mission phase machine. Owns phase progression and high-level signals.
## EncounterDirector / doors / checkpoints react to these; they do not drive the phase list.

enum Phase {
	MISSION_START,
	APPROACH,
	ENCOUNTER_01,
	TRANSITION_01,
	AMBUSH,
	ENCOUNTER_02,
	TRANSITION_02,
	FINAL_ENCOUNTER,
	MISSION_COMPLETE,
}

signal phase_changed(phase: Phase, previous: Phase)
signal encounter_cleared(encounter_id: StringName)
signal mission_complete
signal checkpoint_reached(checkpoint_id: StringName)
signal player_died_in_mission
signal objective_requested(text: String)

const PHASE_ORDER: Array[Phase] = [
	Phase.MISSION_START,
	Phase.APPROACH,
	Phase.ENCOUNTER_01,
	Phase.TRANSITION_01,
	Phase.AMBUSH,
	Phase.ENCOUNTER_02,
	Phase.TRANSITION_02,
	Phase.FINAL_ENCOUNTER,
	Phase.MISSION_COMPLETE,
]

var phase: Phase = Phase.MISSION_START
var phase_time: float = 0.0
var encounter_alive: Dictionary = {} ## encounter_id -> remaining living enemies
var mission_elapsed: float = 0.0
var mission_running: bool = false
var kills: int = 0


func _process(delta: float) -> void:
	if not mission_running:
		return
	# Unscaled clock so brief combat kill slow-mo does not stall mission timers.
	var real_delta := delta / maxf(Engine.time_scale, 0.05)
	phase_time += real_delta
	mission_elapsed += real_delta


func start_mission() -> void:
	mission_running = true
	mission_elapsed = 0.0
	kills = 0
	encounter_alive.clear()
	var previous := phase
	phase = Phase.MISSION_START
	phase_time = 0.0
	phase_changed.emit(phase, previous)
	objective_requested.emit("INFILTRATE THE FACILITY")


func advance_phase() -> void:
	var index := PHASE_ORDER.find(phase)
	if index < 0 or index >= PHASE_ORDER.size() - 1:
		return
	set_phase(PHASE_ORDER[index + 1])


func set_phase(next: Phase) -> void:
	if phase == next:
		return
	var previous := phase
	phase = next
	phase_time = 0.0
	phase_changed.emit(phase, previous)
	if phase == Phase.MISSION_COMPLETE:
		mission_running = false
		mission_complete.emit()


## Force phase without early-out (checkpoint restore).
func restore_phase(next: Phase) -> void:
	var previous := phase
	phase = next
	phase_time = 0.0
	mission_running = next != Phase.MISSION_COMPLETE
	phase_changed.emit(phase, previous)


func notify_encounter_spawned(encounter_id: StringName, count: int) -> void:
	encounter_alive[encounter_id] = maxi(0, int(encounter_alive.get(encounter_id, 0)) + count)


func notify_enemy_died(encounter_id: StringName) -> void:
	kills += 1
	if not encounter_alive.has(encounter_id):
		return
	encounter_alive[encounter_id] = maxi(0, int(encounter_alive[encounter_id]) - 1)
	if int(encounter_alive[encounter_id]) == 0:
		encounter_cleared.emit(encounter_id)


func is_encounter_clear(encounter_id: StringName) -> bool:
	return int(encounter_alive.get(encounter_id, 0)) == 0


func remaining_in(encounter_id: StringName) -> int:
	return int(encounter_alive.get(encounter_id, 0))


func notify_checkpoint(checkpoint_id: StringName) -> void:
	checkpoint_reached.emit(checkpoint_id)


func notify_player_died() -> void:
	player_died_in_mission.emit()


static func phase_name(p: Phase) -> String:
	return Phase.keys()[p]
