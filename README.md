# Rosomak — Milestone 1

A minimal controller-first third-person prototype in Godot 4. The project lives
in `wolverine/`. It contains a primitive arena, a capsule player, movement,
an orbit camera, gravity/collision, and a temporary RT attack that prints `ATTACK`.

## Run on macOS

1. Open Godot 4 (the existing project targets 4.7).
2. Import `wolverine/project.godot` and open the project.
3. Connect your Xbox controller to macOS and press **F6** with
   `scenes/test_arena.tscn` open, or **F5** to run the configured main scene.
4. Focus the game window. Pull RT and check Godot's **Output** panel for `ATTACK`.
   Stop the run with **F8** in the editor or close the game window.

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
    │   ├── Body (capsule mesh)
    │   └── FacingMarker (small box pointing along local -Z)
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

Only `Visuals` turns toward movement, so the camera can orbit independently.
Camera pitch is limited to -60° through +25°. The 5 m spring arm retracts when
the camera approaches geometry and excludes the player's own collider.

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

The sticks use circular deadzones. Camera input is not inverted: right turns the
view right; up looks up. RT prints once when crossing the threshold, not every
frame while held; release it before attacking again. There are no keyboard/mouse
gameplay bindings.

## Manual checks

- On launch, the player drops slightly and rests on the floor.
- Leave both sticks untouched: the player and camera should remain still.
- Try every left-stick direction, shallow input, and diagonals. Movement should
  stay relative to the camera, with slower movement for shallow input.
- Orbit with the right stick while standing and while moving. Check both pitch
  limits and that the facing marker follows movement without turning the camera.
- Walk into every wall and block, then push diagonally along their edges. The
  player should collide and slide. Orbit near walls/blocks: the camera should
  pull in and extend again when clear.
- Pull and hold RT: see one `ATTACK` in Output. Release and pull again: see one
  more. Check that LT does not attack and RT also works while moving.
- Disconnect and reconnect the controller, then check that controls resume.

## Rendering budget

Compatibility renderer, 1280×720 viewport, 60 FPS cap, physics interpolation,
low-detail primitive meshes, one directional light with a 1024 px shadow map,
and shared simple materials. No external textures, post-processing, or additional
gameplay systems are included.

## Validation

Validated with Godot 4.7.2 on macOS / Apple M1: project import, native Compatibility
rendering, and runtime checks using simulated joypad axis events for movement,
analog speed/deadzones, camera-relative directions, pitch limits, gravity,
floor/wall/block collision, camera retraction, and RT press/hold/release.
Physical Xbox pairing, reconnect behavior, and control feel still need the
manual checks above.
