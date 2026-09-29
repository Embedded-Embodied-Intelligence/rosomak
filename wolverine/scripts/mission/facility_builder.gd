class_name FacilityBuilder
extends Node

## Builds the linear industrial research facility from modular CSG/box pieces.
## Layout runs along +Z: entrance → corridor → warehouse → research → lab → emergency → final.

signal built(level_root: Node3D)

const ROOM_W := 14.0
const CORRIDOR_W := 5.0
const WALL_H := 4.2
const THICK := 0.5

## Section Z ranges (min, max) — player walks +Z.
const SEC_ENTRANCE := Vector2(0.0, 14.0)
const SEC_MAINT := Vector2(14.0, 32.0)
const SEC_WAREHOUSE := Vector2(32.0, 54.0)
const SEC_RESEARCH := Vector2(54.0, 78.0)
const SEC_LAB := Vector2(78.0, 104.0)
const SEC_EMERGENCY := Vector2(104.0, 126.0)
const SEC_FINAL := Vector2(126.0, 160.0)

var root: Node3D
var doors: Dictionary = {} ## id -> MissionDoor
var triggers: Dictionary = {} ## id -> MissionTrigger
var entries: Dictionary = {} ## id -> SpawnEntry
var zones: Array = []
var lights: Dictionary = {} ## section -> Array[Light3D]
var env_fx: Dictionary = {} ## named MeshInstance3D / nodes for scripted feedback
var player_spawn: Vector3 = Vector3(0, 0.05, 4.0)
var materials: Dictionary = {}


func build(parent: Node3D) -> Node3D:
	root = Node3D.new()
	root.name = "Facility"
	parent.add_child(root)
	_make_materials()
	_build_world_env(parent)
	_box_room("Entrance", SEC_ENTRANCE, ROOM_W, Color(0.45, 0.48, 0.42), &"exterior")
	_corridor("MaintCorridor", SEC_MAINT, CORRIDOR_W, Color(0.35, 0.38, 0.4), &"hum")
	_box_room("Warehouse", SEC_WAREHOUSE, 18.0, Color(0.4, 0.36, 0.3), &"hum")
	_corridor("ResearchCorridor", SEC_RESEARCH, CORRIDOR_W + 1.0, Color(0.32, 0.4, 0.45), &"lab")
	_box_room("Lab", SEC_LAB, 16.0, Color(0.28, 0.34, 0.4), &"lab")
	_corridor("EmergencyCorridor", SEC_EMERGENCY, CORRIDOR_W, Color(0.35, 0.18, 0.16), &"alarm")
	_box_room("FinalChamber", SEC_FINAL, 22.0, Color(0.22, 0.24, 0.3), &"alarm", 7.5)
	_connect_openings()
	_decorate()
	_place_doors()
	_place_triggers()
	_place_spawns()
	_place_lights()
	_place_ambient_zones()
	built.emit(root)
	return root


func _make_materials() -> void:
	materials["concrete"] = _mat(Color(0.38, 0.39, 0.4), 0.95, 0.05)
	materials["metal"] = _mat(Color(0.22, 0.24, 0.27), 0.45, 0.65)
	materials["floor"] = _mat(Color(0.28, 0.29, 0.31), 0.85, 0.2)
	materials["floor_warn"] = _mat(Color(0.35, 0.22, 0.12), 0.9, 0.1)
	materials["accent"] = _mat(Color(0.15, 0.45, 0.55), 0.4, 0.5, Color(0.1, 0.5, 0.65), 0.4)
	materials["crate"] = _mat(Color(0.42, 0.3, 0.18), 1.0, 0.0)
	materials["glass"] = _mat(Color(0.55, 0.7, 0.8, 0.35), 0.15, 0.1)
	materials["glass"].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materials["danger"] = _mat(Color(0.55, 0.12, 0.08), 0.7, 0.2, Color(0.9, 0.15, 0.05), 0.8)
	materials["machine"] = _mat(Color(0.18, 0.2, 0.28), 0.5, 0.7, Color(0.2, 0.4, 0.9), 0.5)


func _mat(albedo: Color, roughness: float, metallic: float, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = metallic
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


func _build_world_env(parent: Node3D) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.14, 0.16)
	env.fog_density = 0.008
	we.environment = env
	we.name = "WorldEnvironment"
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(25), 0)
	sun.light_color = Color(0.75, 0.82, 0.9)
	sun.light_energy = 0.55
	sun.shadow_enabled = false
	parent.add_child(sun)


func _box_room(name: String, span: Vector2, width: float, tint: Color, _mood: StringName, height: float = WALL_H) -> void:
	var room := Node3D.new()
	room.name = name
	root.add_child(room)
	var depth := span.y - span.x
	var z_center := (span.x + span.y) * 0.5
	_static_box(room, "Floor", Vector3(0, -0.25, z_center), Vector3(width, 0.5, depth), materials["floor"])
	_static_box(room, "Ceiling", Vector3(0, height + 0.2, z_center), Vector3(width, 0.4, depth), materials["metal"])
	_static_box(room, "WallL", Vector3(-width * 0.5, height * 0.5, z_center), Vector3(THICK, height, depth), materials["concrete"])
	_static_box(room, "WallR", Vector3(width * 0.5, height * 0.5, z_center), Vector3(THICK, height, depth), materials["concrete"])
	# Soft tint fill light per room identity.
	var fill := OmniLight3D.new()
	fill.name = "Fill"
	fill.position = Vector3(0, height - 0.8, z_center)
	fill.light_color = tint
	fill.light_energy = 1.1
	fill.omni_range = maxf(width, depth) * 0.75
	fill.shadow_enabled = false
	room.add_child(fill)
	lights[name] = [fill]


func _corridor(name: String, span: Vector2, width: float, tint: Color, _mood: StringName) -> void:
	_box_room(name, span, width, tint, _mood, WALL_H)


func _connect_openings() -> void:
	# Carve implied openings by not placing end walls between linked sections;
	# add thin door frames at junctions for readability.
	var junctions := [
		{"z": SEC_ENTRANCE.y, "w": CORRIDOR_W, "id": &"frame_to_maint"},
		{"z": SEC_MAINT.y, "w": CORRIDOR_W, "id": &"frame_to_wh"},
		{"z": SEC_WAREHOUSE.y, "w": CORRIDOR_W + 1.0, "id": &"frame_to_research"},
		{"z": SEC_RESEARCH.y, "w": CORRIDOR_W + 1.0, "id": &"frame_to_lab"},
		{"z": SEC_LAB.y, "w": CORRIDOR_W, "id": &"frame_to_emergency"},
		{"z": SEC_EMERGENCY.y, "w": CORRIDOR_W + 2.0, "id": &"frame_to_final"},
	]
	var frames := Node3D.new()
	frames.name = "Frames"
	root.add_child(frames)
	for j in junctions:
		var z: float = j.z
		var w: float = j.w
		_static_box(frames, str(j.id) + "_L", Vector3(-w * 0.5 - 0.35, WALL_H * 0.5, z), Vector3(0.7, WALL_H, 0.6), materials["metal"])
		_static_box(frames, str(j.id) + "_R", Vector3(w * 0.5 + 0.35, WALL_H * 0.5, z), Vector3(0.7, WALL_H, 0.6), materials["metal"])
		_static_box(frames, str(j.id) + "_top", Vector3(0, WALL_H - 0.15, z), Vector3(w + 1.4, 0.3, 0.6), materials["accent"])


func _decorate() -> void:
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	# Entrance: exterior crates + pipe.
	_crate(props, Vector3(-4, 0.5, 6), Vector3(1.4, 1.0, 1.4))
	_crate(props, Vector3(4.5, 0.5, 8), Vector3(1.2, 1.0, 1.2))
	_pipe(props, Vector3(2.2, 3.2, 20), 10.0)
	# Warehouse: cargo stacks + damaged crate for env feedback.
	for i in 5:
		_crate(props, Vector3(-6.5 + (i % 2) * 2.0, 0.55, 36 + i * 2.8), Vector3(1.5, 1.1, 1.5))
		_crate(props, Vector3(6.0, 0.55, 38 + i * 2.5), Vector3(1.3, 1.0, 1.3))
	var nudge_crate := _crate(props, Vector3(3.5, 0.55, 44), Vector3(1.4, 1.0, 1.4))
	nudge_crate.name = "NudgeCrate"
	env_fx["nudge_crate"] = nudge_crate
	# Research: glass panels + consoles (storytelling).
	for i in 4:
		var panel := _static_box(props, "Glass%d" % i, Vector3(-2.6 if i % 2 == 0 else 2.6, 1.6, 58 + i * 4.5), Vector3(0.12, 2.4, 2.8), materials["glass"])
		if i == 2:
			panel.name = "BreakGlass"
			env_fx["break_glass"] = panel
	_static_box(props, "ConsoleA", Vector3(0, 0.7, 66), Vector3(2.2, 1.2, 0.8), materials["machine"])
	_static_box(props, "ConsoleB", Vector3(-1.5, 0.7, 72), Vector3(1.6, 1.2, 0.7), materials["machine"])
	_static_box(props, "BloodMark", Vector3(1.2, 0.02, 70), Vector3(1.8, 0.04, 0.9), materials["danger"])
	# Lab: shutter for ambush event.
	var shutter := _static_box(props, "Shutter", Vector3(7.2, 1.8, 92), Vector3(0.2, 3.0, 4.0), materials["metal"])
	env_fx["shutter"] = shutter
	_static_box(props, "LabBench", Vector3(-4, 0.6, 90), Vector3(3.0, 1.0, 1.2), materials["metal"])
	_static_box(props, "ServerRack", Vector3(5, 1.5, 98), Vector3(1.2, 3.0, 2.0), materials["machine"])
	# Emergency: warning floor strip + sparks anchor.
	_static_box(props, "WarnStrip", Vector3(0, 0.02, 115), Vector3(4.5, 0.05, 18), materials["floor_warn"])
	var spark_anchor := Marker3D.new()
	spark_anchor.name = "SparkAnchor"
	spark_anchor.position = Vector3(-1.5, 2.5, 118)
	props.add_child(spark_anchor)
	env_fx["spark_anchor"] = spark_anchor
	# Final: focal machinery.
	var core := _static_box(props, "ExperimentCore", Vector3(0, 2.2, 145), Vector3(4.5, 4.0, 4.5), materials["machine"])
	env_fx["experiment_core"] = core
	_static_box(props, "CoreRing", Vector3(0, 0.4, 145), Vector3(8.0, 0.5, 8.0), materials["accent"])
	for angle in [0.0, 90.0, 180.0, 270.0]:
		var rad := deg_to_rad(angle)
		_crate(props, Vector3(cos(rad) * 8.0, 0.6, 145 + sin(rad) * 8.0), Vector3(1.6, 1.2, 1.6))
	# Fake damage mesh near final entrance.
	var damage := _static_box(props, "FakeDamage", Vector3(-5, 1.5, 128), Vector3(2.5, 2.5, 0.3), materials["danger"])
	env_fx["fake_damage"] = damage


func _place_doors() -> void:
	var door_defs := [
		{"id": &"door_entrance", "z": SEC_ENTRANCE.y, "locked": false},
		{"id": &"door_warehouse_in", "z": SEC_WAREHOUSE.x, "locked": false},
		{"id": &"door_warehouse_out", "z": SEC_WAREHOUSE.y, "locked": true},
		{"id": &"door_lab_in", "z": SEC_LAB.x, "locked": false},
		{"id": &"door_lab_side", "z": 94.0, "x": 7.5, "locked": true, "rot_y": 90.0},
		{"id": &"door_lab_out", "z": SEC_LAB.y, "locked": true},
		{"id": &"door_final_in", "z": SEC_FINAL.x, "locked": true},
		{"id": &"door_final_a", "z": 138.0, "x": -10.0, "locked": true, "rot_y": 90.0},
		{"id": &"door_final_b", "z": 138.0, "x": 10.0, "locked": true, "rot_y": -90.0},
		{"id": &"door_final_c", "z": 152.0, "locked": true},
	]
	var door_root := Node3D.new()
	door_root.name = "Doors"
	root.add_child(door_root)
	for def in door_defs:
		var door := MissionDoor.new()
		door.name = String(def.id)
		door.door_id = def.id
		door.start_locked = bool(def.locked)
		door.position = Vector3(float(def.get("x", 0.0)), 1.5, float(def.z))
		if def.has("rot_y"):
			door.rotation_degrees.y = float(def.rot_y)
		door.configure()
		door_root.add_child(door)
		doors[def.id] = door
	# Start with entrance open.
	doors[&"door_entrance"].force_open()
	doors[&"door_warehouse_in"].force_open()
	doors[&"door_lab_in"].force_open()


func _place_triggers() -> void:
	var defs := [
		{"id": &"trg_approach", "z": 16.0, "size": Vector3(8, 4, 3)},
		{"id": &"trg_e1", "z": 36.0, "size": Vector3(14, 4, 4)},
		{"id": &"trg_breather", "z": 58.0, "size": Vector3(8, 4, 3)},
		{"id": &"trg_ambush", "z": 88.0, "size": Vector3(12, 4, 3)},
		{"id": &"trg_e2_clear_gate", "z": 100.0, "size": Vector3(12, 4, 3), "enabled": false},
		{"id": &"trg_transition2", "z": 110.0, "size": Vector3(8, 4, 3)},
		{"id": &"trg_final", "z": 132.0, "size": Vector3(16, 4, 4)},
		{"id": &"trg_cp_after_e1", "z": 56.0, "size": Vector3(8, 4, 2)},
		{"id": &"trg_cp_before_final", "z": 124.0, "size": Vector3(8, 4, 2)},
	]
	var trg_root := Node3D.new()
	trg_root.name = "Triggers"
	root.add_child(trg_root)
	for def in defs:
		var t := MissionTrigger.new()
		t.name = String(def.id)
		t.trigger_id = def.id
		t.position = Vector3(0, 0, float(def.z))
		t.enabled = bool(def.get("enabled", true))
		t.configure(def.size)
		trg_root.add_child(t)
		triggers[def.id] = t


func _place_spawns() -> void:
	var defs := [
		{"id": &"e1_a", "pos": Vector3(-6, 0, 50), "door": &"door_warehouse_out"},
		{"id": &"e1_b", "pos": Vector3(6, 0, 50), "door": &"door_warehouse_out"},
		{"id": &"e1_c", "pos": Vector3(0, 0, 51), "door": &"door_warehouse_out"},
		{"id": &"e2_a", "pos": Vector3(-5, 0, 100), "door": &"door_lab_out"},
		{"id": &"e2_b", "pos": Vector3(5, 0, 100), "door": &"door_lab_out"},
		{"id": &"e2_side", "pos": Vector3(6.5, 0, 94), "door": &"door_lab_side"},
		{"id": &"e2_heavy", "pos": Vector3(0, 0, 101), "door": &"door_lab_out"},
		{"id": &"fin_a", "pos": Vector3(-9, 0, 138), "door": &"door_final_a"},
		{"id": &"fin_b", "pos": Vector3(9, 0, 138), "door": &"door_final_b"},
		{"id": &"fin_c", "pos": Vector3(0, 0, 152), "door": &"door_final_c"},
		{"id": &"fin_d", "pos": Vector3(-7, 0, 148), "door": &"door_final_a"},
		{"id": &"fin_e", "pos": Vector3(7, 0, 148), "door": &"door_final_b"},
	]
	var spawn_root := Node3D.new()
	spawn_root.name = "SpawnEntries"
	root.add_child(spawn_root)
	for def in defs:
		var entry := SpawnEntry.new()
		entry.name = String(def.id)
		entry.entry_id = def.id
		entry.position = def.pos
		spawn_root.add_child(entry)
		# Link door after doors exist (path relative to entry).
		if doors.has(def.door):
			entry.linked_door = doors[def.door]
		entries[def.id] = entry


func _place_lights() -> void:
	# Guided path lights down corridors.
	var guide := Node3D.new()
	guide.name = "GuideLights"
	root.add_child(guide)
	for z in range(18, 32, 4):
		_spot(guide, Vector3(0, 3.6, z), Color(0.7, 0.85, 1.0), 1.4)
	for z in range(56, 78, 5):
		_spot(guide, Vector3(0, 3.6, z), Color(0.55, 0.85, 0.95), 1.2)
	# Emergency reds (start dim; mission turns them up).
	var emergency := Node3D.new()
	emergency.name = "EmergencyLights"
	root.add_child(emergency)
	for z in range(106, 126, 4):
		var light := _omni(emergency, Vector3(0, 3.2, z), Color(1.0, 0.15, 0.08), 0.15)
		light.set_meta("emergency", true)
	env_fx["emergency_lights"] = emergency
	# Final focal.
	var core_light := _omni(guide, Vector3(0, 5.5, 145), Color(0.35, 0.55, 1.0), 2.2)
	core_light.omni_range = 18.0
	env_fx["core_light"] = core_light


func _place_ambient_zones() -> void:
	var zone_defs := [
		{"id": &"zone_exterior", "z": 7.0, "size": Vector3(14, 6, 14), "mood": AmbientAudioZone.Mood.EXTERIOR},
		{"id": &"zone_maint", "z": 23.0, "size": Vector3(6, 6, 18), "mood": AmbientAudioZone.Mood.HUM},
		{"id": &"zone_warehouse", "z": 43.0, "size": Vector3(18, 6, 22), "mood": AmbientAudioZone.Mood.HUM, "vol": -20.0},
		{"id": &"zone_research", "z": 66.0, "size": Vector3(7, 6, 24), "mood": AmbientAudioZone.Mood.LAB},
		{"id": &"zone_lab", "z": 91.0, "size": Vector3(16, 6, 26), "mood": AmbientAudioZone.Mood.LAB, "vol": -18.0},
		{"id": &"zone_emergency", "z": 115.0, "size": Vector3(6, 6, 22), "mood": AmbientAudioZone.Mood.ALARM, "vol": -16.0},
		{"id": &"zone_final", "z": 143.0, "size": Vector3(22, 8, 34), "mood": AmbientAudioZone.Mood.ALARM, "vol": -18.0},
	]
	var zone_root := Node3D.new()
	zone_root.name = "AmbientZones"
	root.add_child(zone_root)
	for def in zone_defs:
		var zone := AmbientAudioZone.new()
		zone.name = String(def.id)
		zone.zone_id = def.id
		zone.mood = def.mood
		zone.volume_db = float(def.get("vol", -22.0))
		zone.position = Vector3(0, 0, float(def.z))
		zone.configure(def.size)
		zone_root.add_child(zone)
		zones.append(zone)


func _static_box(parent: Node, name: String, pos: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


func _crate(parent: Node, pos: Vector3, size: Vector3) -> StaticBody3D:
	return _static_box(parent, "Crate", pos, size, materials["crate"])


func _pipe(parent: Node, pos: Vector3, length: float) -> void:
	_static_box(parent, "Pipe", pos, Vector3(0.35, 0.35, length), materials["metal"])


func _spot(parent: Node, pos: Vector3, color: Color, energy: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.position = pos
	light.rotation_degrees = Vector3(-90, 0, 0)
	light.light_color = color
	light.light_energy = energy
	light.spot_range = 10.0
	light.spot_angle = 45.0
	light.shadow_enabled = false
	parent.add_child(light)
	return light


func _omni(parent: Node, pos: Vector3, color: Color, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 10.0
	light.shadow_enabled = false
	parent.add_child(light)
	return light
