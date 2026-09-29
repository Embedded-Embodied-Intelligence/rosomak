# Prototype humanoid

Source: [Kenney Prototype Kit 1.0](https://kenney.nl/assets/prototype-kit).
License: CC0; original notice is included in `License.txt`.

Only `Models/GLB format/figurine-cube-detailed.glb` and its
`Textures/colormap.png` are included from the pack. The original files are
unmodified: 254 triangles, six small mesh parts, one shared color texture.

The player scene scales the model 3× and rotates it 180° to face Godot's -Z.
Import settings loop `idle` and `sprint` and include a RESET pose. The prototype
also uses the included `attack-melee-right` clip. `animations/dodge.tres` is a
project-authored leaning dash pose using the same part transforms. All animation
is visual; the capsule and player script remain responsible for world movement.
