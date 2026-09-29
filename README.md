# Rosomak — PROJECT CLAW Mission Demo

Controller-first third-person claw-fighter in Godot **4.7**. Project root: `wolverine/`.

**Default launch** is a linear **10–15 minute** industrial facility mission
(**PROJECT CLAW**). The original single-wave arena (`scenes/game.tscn`) remains as a
combat reference/test scene.

## Launch (macOS)

1. Install [Godot 4.7.x](https://godotengine.org/download) (validated on **4.7.2**).
2. Open `wolverine/project.godot`.
3. Press **F5** (main scene `scenes/mission/main_menu.tscn`), or:

```sh
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --path wolverine
```

4. Title: **A / Enter** = PLAY, **B / Esc** = QUIT.
5. Combat arena only: open `scenes/game.tscn` or `scenes/test_arena.tscn` and **F6**.

## macOS export (standalone)

1. Install Godot **4.7.2 export templates** once: Editor → Manage Export Templates → Download and Install
   (or download `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz`
   and install via Manage Export Templates → Install from File).
2. In Godot: **Project → Export… → macOS** (preset in `export_presets.cfg`).
3. Export to `build/macos/Rosomak.app` (create `build/macos/` if needed).
4. Or CLI:

```sh
mkdir -p build/macos
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path wolverine \
  --export-release "macOS" ../build/macos/Rosomak.app
```

5. Run: `open build/macos/Rosomak.app`

Unsigned local builds may need **System Settings → Privacy & Security → Open Anyway**.

**Without templates:** run from the editor (F5) or `Godot --path wolverine` — fully playable.

## Mission flow

```
START (exterior) → TRAVERSAL (maintenance) → ENCOUNTER 1 (warehouse)
  → BREATHER (research) → AMBUSH EVENT → ENCOUNTER 2 (lab)
  → TRANSITION (emergency) → FINAL (experiment chamber) → COMPLETE
```

Checkpoints (session-only): Mission Start · After Encounter 1 · Before Final.
Death → **YOU DIED** (1–2s, skippable) → restore active checkpoint.

## Controls

| Action | Xbox | Keyboard / mouse |
| --- | --- | --- |
| Move | Left stick | WASD |
| Camera | Right stick | Mouse (captured) / arrows |
| Light combo (3 hits, buffered) | RT | J / LMB |
| Heavy attack | RB | K / RMB |
| Dodge (i-frames) | A | Space / Shift |
| Rage (when full) | Y | Q |
| Pause | Start | Esc |
| Confirm / Replay | A | Enter |
| Cancel / Exit | B | Esc |

## Automated tests

```sh
# Combat regression (existing)
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path wolverine \
  --fixed-fps 60 --script res://tests/combat_smoke.gd

# Mission systems
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path wolverine \
  --fixed-fps 60 --script res://tests/mission_smoke.gd

# Scripted full playthrough (phase/door/checkpoint logic)
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path wolverine \
  --fixed-fps 60 --script res://tests/mission_playthrough.gd
```

Expect `RESULT: … checks, 0 failures` and exit code `0`.

## Performance notes (M1 8GB)

Compatibility renderer, 1280×720, 60 FPS cap, Jolt physics, modular box geometry,
shared materials, no realtime shadow cascade on fill lights, synthesized audio.
Target: stable 60 FPS with ≤5 active enemies.

## Architecture (short)

| Piece | Role |
| --- | --- |
| `Player` / `Enemy` | Existing combat (unchanged feel) |
| `MissionController` | Linear phase machine |
| `EncounterDirector` | Staged waves + door entry spawns |
| `MissionDoor` / `CheckpointSystem` | Gates + session restore |
| `FacilityBuilder` | Modular industrial level |
| `MissionGame` | Wires mission flow |
| `game.gd` | Legacy arena wave slice |

## License

Kenney Prototype Kit: CC0 (`assets/kenney/License.txt`). Runtime SFX: see
`assets/AUDIO_LICENSE.md`. Game code: project authors.
