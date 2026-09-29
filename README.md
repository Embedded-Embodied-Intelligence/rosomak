# Rosomak — Milestone 2

A minimal controller-first third-person prototype in Godot 4. The project lives
in `wolverine/`. It contains a primitive arena, an animated humanoid, analog
movement, an independent orbit camera, capsule collision, an A-button dodge,
and a temporary RT melee animation. Milestone 1's movement/camera settings,
arena, and capsule are preserved.

## Run on macOS

1. Open Godot 4 (the existing project targets 4.7).
2. Import `wolverine/project.godot` and open the project.
3. Connect your Xbox controller to macOS and press **F6** with
   `scenes/test_arena.tscn` open, or **F5** to run the configured main scene.
4. Focus the game window. Godot's **Output** panel prints `IDLE`, `RUN`, `DODGE`,
   and `ATTACK` whenever the state changes, including `IDLE` on launch.
   Keep Output visible beside the game to check the current state; there is no HUD.
5. Stop the run with **F8** in the editor or close the game window.

If Godot is installed in Downloads, you can also run from the repository root:

```sh
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --path wolverine
```

The game runs natively through Godot on macOS; no additional packages or assets
are needed. A standalone distributable is outside this milestone.

## Scene hierarchy

```text
TestArena (scenes/test_arena.tscn)
├── WorldEnvironment
├── Sun (DirectionalLight3D)
├── Geometry
│   └── Floor, four walls, three blocks (StaticBody3D each)
│       ├── Mesh (MeshInstance3D)
│       └── Collision (CollisionShape3D)
└── Player (instance of scenes/player.tscn; CharacterBody3D)
    ├── CollisionShape3D (capsule)
    ├── Visuals
    │   └── Humanoid (Kenney GLB instance, faces local -Z)
    │       ├── Articulated head, torso, arms, and legs
    │       └── AnimationPlayer
    └── CameraPivot (horizontal orbit)
        └── SpringArm3D (vertical orbit and camera collision)
            └── Camera3D
```

`scripts/player.gd` is the only gameplay script. Each physics tick, it reads the
sticks through `Input.get_vector()`, rotates the camera, and converts the left
stick into a direction relative to the camera's horizontal angle. Stick magnitude
controls speed (up to 5 m/s); diagonal input is capped. Horizontal velocity eases
toward the requested speed and slows to a stop on release. Gravity and
`move_and_slide()` handle the capsule's floor and wall collisions.

Only `Visuals` turns toward movement, so the camera can orbit independently,
including during dodge and attack. Attack holds the character's facing until it ends.
Camera pitch is limited to -60° through +25°. The 5 m spring arm retracts when
the camera approaches geometry and excludes the player's own collider.

## Character and animation states

The model is the free CC0 `figurine-cube-detailed.glb` from
[Kenney Prototype Kit](https://kenney.nl/assets/prototype-kit): 254 triangles,
six mesh parts, one shared small color texture. The model, texture, and original
license are included in `assets/kenney/`; no manual download or import is needed.
`Humanoid` is scaled 3× to fit the capsule and rotated 180° to face -Z.

`player.gd` owns one four-value `State` enum and the action timers. The imported
`AnimationPlayer` handles playback and short crossfades; there is no extra state
framework or root motion. Idle and Run loop through the GLB import settings.

| State | Animation | Behavior |
| --- | --- | --- |
| `IDLE` | Kenney `idle` | Resting or blocked against geometry |
| `RUN` | Kenney `sprint` | Actual horizontal speed controls playback rate |
| `DODGE` | Project-authored `actions/dodge` | Leaning dash at 11 m/s for 0.32 s |
| `ATTACK` | Kenney `attack-melee-right` | One melee swing over 0.50 s |

Actual speed selects Idle/Run with small separate enter/exit thresholds to avoid
flickering near zero. `animations/dodge.tres` is a standard AnimationLibrary,
added to the model's AnimationPlayer on startup. All poses animate only visuals;
the existing capsule is still the sole gameplay collider.

A captures the current camera-relative stick direction. With no stick input it
uses the character's facing, even if the camera looks elsewhere. The direction
stays fixed during the dodge; turning the camera cannot bend the dash. After
0.32 s, ordinary movement resumes immediately, followed by 0.28 s of cooldown
before another dodge can start (0.60 s minimum between starts).

RT starts a 0.50 s attack, brakes horizontal movement, and holds facing. Afterward,
held movement resumes. Both actions require the player to be grounded, cannot
interrupt each other, and ignore further action presses until finished. A wins
if A and RT are pressed together. Inputs are not queued; holding a button does
not repeat its action, so release and press again after the lockout/cooldown.

`is_invulnerable` is a read-only hook for future combat: true only from 0.05 s
through just before 0.22 s of Dodge. It does not change collision or interact with
damage. Speed, durations, cooldown, and iframe bounds are exported on Player for
tuning; keep `0 <= dodge_iframe_start < dodge_iframe_end <= dodge_duration`.

## Xbox input

Bindings live in **Project → Project Settings → Input Map** (`project.godot`).
They accept any controller device (`device = -1`) and contain only joypad events.
This uses Godot's built-in [controller input and deadzone support](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html).

| Control | Actions | Godot axis | Deadzone |
| --- | --- | --- | --- |
| Left stick horizontal | `move_left`, `move_right` | Left X (0), −/+ | 0.20 |
| Left stick vertical | `move_forward`, `move_back` | Left Y (1), −/+ | 0.20 |
| Right stick horizontal | `look_left`, `look_right` | Right X (2), −/+ | 0.20 |
| Right stick vertical | `look_up`, `look_down` | Right Y (3), −/+ | 0.20 |
| RT | `attack` | Right trigger (5), + | 0.50 |
| A | `dodge` | Joypad button 0 | — |

The sticks use circular deadzones. Camera input is not inverted: right turns the
view right; up looks up. RT is an analog trigger with a 50% press threshold.
There are no keyboard/mouse gameplay bindings.

## Manual checks

1. Launch: see the humanoid settle on the floor, play its idle animation, and
   print `IDLE`. Neither stick should drift when untouched.
2. Move with shallow/full left-stick input and diagonals: see `RUN`, with slower
   animation at lower speed. Release: decelerate and return to `IDLE`.
3. Orbit the camera while standing and running. The character should smoothly
   face movement without dragging the camera. Check both vertical camera limits.
4. Hold a direction and tap A: see `DODGE`, a quick leaning dash, then `RUN` if
   still moving. Turn the camera/change stick direction mid-dodge: the active
   dash should keep its original direction. Movement follows the new input afterward.
5. Stop, orbit the camera to the character's side, and tap A without touching the
   left stick: dodge toward the character's facing, then return to `IDLE`.
6. Hold A and try rapidly tapping it: it must not loop while held or restart
   during the dash/recovery. Release and press after 0.60 s to dodge again.
7. Pull RT while idle, then while running: see one `ATTACK` and the arm swing.
   Movement brakes, the camera still responds, and held movement resumes after
   0.50 s. Hold RT to confirm it does not repeat. Release and pull again to attack.
8. Press RT during Dodge and A during Attack: the current action should finish
   without interruption or a queued action. Press both together while free: A wins.
9. Run/dodge into walls and blocks: the capsule must stop/slide without passing
   through. Orbit near geometry: the spring arm should retract and extend normally.
10. Disconnect/reconnect the controller and confirm input resumes.

To inspect the future iframe hook without adding UI, use Godot's Remote inspector
on Player during Dodge: `is_invulnerable` is only true inside the configured window.

## Rendering budget

Compatibility renderer, 1280×720 viewport, 60 FPS cap, physics interpolation,
primitive arena meshes, a 254-triangle humanoid with one color texture,
one directional light with a 1024 px shadow map, and shared simple materials.
There are no enemies, damage, hitboxes, combos, stamina, HUD, or VFX.

## Validation

Validated with Godot 4.7.2 on macOS / Apple M1: project import, native Compatibility
rendering, and runtime checks using simulated joypad axis/button events. Checks
cover the four states, animation loops, analog speed, independent facing/camera,
directional and neutral-stick dodges, action lockouts, cooldown, iframe timing,
attack-to-movement recovery, collision, camera retraction, and camera pitch limits.
Milestone 1 was manually verified with an Xbox controller; Milestone 2's action
feel and physical-controller behavior still need the manual checks above.
