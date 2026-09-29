# Rosomak — Combat Vertical Slice

Controller-first third-person claw-fighter slice in Godot **4.7**. Project root:
`wolverine/`.

Clear a single arena wave (7 enemies: grunts, runners, one brute), then **AREA CLEAR**.
Death offers Restart / Exit. Xbox pad is primary; keyboard/mouse also bound.

## Launch (macOS)

1. Install [Godot 4.7.x](https://godotengine.org/download) (validated on **4.7.2**).
2. Open `wolverine/project.godot`.
3. Press **F5** (main scene `scenes/game.tscn`), or:

```sh
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --path wolverine
```

4. Focus the game window. Title: **A / Enter** to fight, **B / Esc** to quit.

Training sandbox (no waves): open `scenes/test_arena.tscn` and press **F6**.

## macOS export (standalone)

1. Install Godot **4.7.2 export templates** once: Editor → Manage Export Templates → Download and Install
   (or download `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz`
   and install via Manage Export Templates → Install from File).
2. In Godot: **Project → Export… → macOS** (preset in `export_presets.cfg`).
   Project already enables ETC2/ASTC import for arm64 Macs.
3. Export to `build/macos/Rosomak.app` (create `build/macos/` if needed).
4. Or CLI:

```sh
mkdir -p build/macos
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path wolverine \
  --export-release "macOS" ../build/macos/Rosomak.app
```

5. Run: `open build/macos/Rosomak.app`

Unsigned local builds may need **System Settings → Privacy & Security → Open Anyway**.
Notarization / Steam packaging is out of scope.

**Without templates:** run from the editor (F5) or `Godot --path wolverine` — fully playable.

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
| Confirm / Restart | A | Enter |
| Cancel / Exit | B | Esc |

## What you get

- Third-person SpringArm camera, analog move, dodge with i-frames
- Light 3-hit combo with input buffer; separate heavy
- Melee hitbox / hurtbox (active frames, once per target per swing)
- On **hit** only: hit-stop (~50–70 ms), camera impulse, rumble, slash VFX, layered SFX
- Player HP 100, hurt reaction, post-hit grace i-frames, regen after ~3 s (~10 HP/s), death + retry
- Enemy AI: spawn → chase → telegraphed windup → strike → recover; stagger / death
- Archetypes sharing `enemy.gd`: **grunt** (standard), **runner** (fast), **brute** (heavy/poise)
- Attack-token pacing (max 2 simultaneous attackers)
- Soft aim-assist + attack lunge toward nearby enemies
- One wave (~7), victory **AREA CLEAR**, Restart / Exit
- Minimal HUD (health + light encounter info)
- Original claw-fighter look (dark body + steel blades; not a copyrighted costume)
- Synthesized CC0-style SFX (see `assets/AUDIO_LICENSE.md`); Kenney CC0 figurine

## Automated tests

```sh
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path wolverine \
  --fixed-fps 60 --script res://tests/combat_smoke.gd
```

Expect `RESULT: … checks, 0 failures` and exit code `0`.

## Performance notes (M1 8GB)

Compatibility renderer, 1280×720, 60 FPS cap, Jolt physics, low-poly Kenney meshes,
shared materials, short-lived hit flashes, synthesized audio (no large audio assets).
Target: stable 60 FPS in the 7-enemy arena.

## Architecture (short)

| Piece | Role |
| --- | --- |
| `Player` | States IDLE/RUN/DODGE/ATTACK/HURT/DEAD; combo + heavy; vitals |
| `Enemy` | Shared AI + exported archetype stats; attack slots |
| `MeleeHitbox` / `Hurtbox` | Active-frame queries; non-body collision layers |
| `game.gd` | Title → one wave → victory / death |
| `Sfx` autoload | Runtime-generated one-shots |

## Manual checklist

1. Title → start; camera orbit and analog move feel stable.
2. RT three-hit buffer; RB heavy separate from the string.
3. Hits produce stop / shake / rumble / VFX / hit SFX; misses do not.
4. Dodge through a telegraphed enemy swing (no damage in i-frames).
5. Take a hit: reaction, blink grace, regen after ~3 s idle of damage.
6. Clear all 7 (incl. purple brute) → AREA CLEAR → Restart / Exit.
7. Die → Restart / Exit.
8. Pause with Start/Esc mid-fight.

## License

Kenney Prototype Kit: CC0 (`assets/kenney/License.txt`). Runtime SFX: see
`assets/AUDIO_LICENSE.md`. Game code: project authors.
