# S9-input: actions, bindings, remapping, per-tick input frames

- Slice: S9. Architecture: [ADR-004](../adr/ADR-004-core-architecture.md) section 6, ADR-001.
- Depends on: S1-core `InputFrame` and `InputSource` (`game/match/`), defined in
  [S1-core](S1-core.md) section 2.2 and 3.1. Do not redefine them.
- Action role defaults follow the observed Rugby 08 controls in
  [the input RE](../re/11-input-camera-hud-save.md). The action list remains a provisional subset
  of those context-sensitive roles; changing bindings is a data edit to `default_action_set.tres`.
- Reimplementation, not a port (PLAN section 4 rule 0, CONVENTIONS "Reimplementation, not a
  port"): only Rugby 08's observable behaviour and numeric constants are carried over, always
  into named Resource fields with units. Names, structure, update order and data layouts are
  ours; when RE findings land they fill data, never reshape these classes after the original.
- Out of scope: rebinding UI and controller glyphs (S8/S11), local multiplayer device-to-slot
  assignment (v1 samples all devices into slot 0), touch input.

## 1. Files and classes

| Path | `class_name` | Base |
|---|---|---|
| `game/platform/input/input_action_def.gd` | `InputActionDef` | `Resource` |
| `game/platform/input/input_axis_def.gd` | `InputAxisDef` | `Resource` |
| `game/platform/input/input_action_set.gd` | `InputActionSet` | `Resource` |
| `game/platform/input/input_event_codec.gd` | `InputEventCodec` | `RefCounted` (static) |
| `game/platform/input/input_bindings.gd` | `InputBindings` | `RefCounted` |
| `game/platform/input/input_sampler.gd` | `InputSampler` | `InputSource` |
| `game/platform/input/default_action_set.tres` | (an `InputActionSet`) | |

`autoload/game_settings.gd` gains a public `input_bindings: InputBindings` built in `_ready`
(section 5). No new autoloads.

## 2. Action data

`InputActionDef` (`Resource`):
`enum Context { MATCH, UI, SYSTEM }`;
`@export var id: StringName`;
`@export var context: Context = Context.MATCH` (MATCH: read by the sim through `InputFrame`;
UI: menus; SYSTEM: active during a match but never in the frame, e.g. `pause`);
`@export var display_name_key: String` (translation key);
`@export var remappable: bool = true`;
`@export var deadzone: float = 0.2`;
`@export var gamepad_events: Array[InputEvent] = []` (default gamepad bindings);
`@export var keyboard_events: Array[InputEvent] = []` (default keyboard bindings);
`@export var provisional: bool = true`.

`InputAxisDef` (`Resource`): `@export var id: StringName`, `@export var negative_x: StringName`,
`@export var positive_x: StringName`, `@export var negative_y: StringName`,
`@export var positive_y: StringName` (action ids).

`InputActionSet` (`Resource`):
`@export var id: StringName = &"default"`, `@export var actions: Array[InputActionDef] = []`,
`@export var axes: Array[InputAxisDef] = []`;
- `get_action(action_id: StringName) -> InputActionDef` (null if absent)
- `button_actions() -> Array[StringName]`: MATCH actions not referenced by any axis, in array
  order. Bit `i` of an `InputFrame` slot is `button_actions()[i]`.
- `bit_of(action_id: StringName) -> int` (-1 if not a button action)
- `axes_per_slot() -> int` = `2 * axes.size()`; `axis_index(axis_id: StringName,
  component: int) -> int` = `2 * position + component` (component 0 = x, 1 = y; -1 if unknown)
- `layout_hash() -> String`: lowercase hex SHA-256 of the UTF-8 text made of one line
  `button:<id>` per button action in bit order, then one line
  `axis:<id>:<negative_x>,<positive_x>,<negative_y>,<positive_y>` per axis, joined with `"\n"`.
- `make_frame(slot_count: int = 1) -> InputFrame` = `InputFrame.new(slot_count, axes_per_slot())`
- `validate() -> PackedStringArray`: empty or duplicate action id; axis id empty or duplicate; axis
  referencing an unknown action or a non-MATCH action; more than 63 button actions.

Event types supported for bindings: gamepad device kind = `InputEventJoypadButton`,
`InputEventJoypadMotion`; keyboard device kind = `InputEventKey` (bound by `physical_keycode`,
so layouts like AZERTY keep positions), `InputEventMouseButton`. All bound events use device
`-1` (all devices).

### 2.1 Default action set (`default_action_set.tres`), all PROVISIONAL

Gamepad names use Godot's SDL layout (`JOY_BUTTON_*`, `JOY_AXIS_*`).

| id | context | gamepad default | keyboard default | display key |
|---|---|---|---|---|
| `move_up` | MATCH | left stick Y negative | Up | `INPUT_ACTION_MOVE_UP` |
| `move_down` | MATCH | left stick Y positive | Down | `INPUT_ACTION_MOVE_DOWN` |
| `move_left` | MATCH | left stick X negative | Left | `INPUT_ACTION_MOVE_LEFT` |
| `move_right` | MATCH | left stick X positive | Right | `INPUT_ACTION_MOVE_RIGHT` |
| `sprint` | MATCH | right trigger (digital, axis positive) | Space | `INPUT_ACTION_SPRINT` |
| `pass_left` | MATCH | left shoulder | A | `INPUT_ACTION_PASS_LEFT` |
| `pass_right` | MATCH | right shoulder | D | `INPUT_ACTION_PASS_RIGHT` |
| `kick` | MATCH | X / Cross | S | `INPUT_ACTION_KICK` |
| `tackle` | MATCH | X / Cross (shared role by game context) | S | `INPUT_ACTION_TACKLE` |
| `switch_player` | MATCH | left trigger (digital, axis positive) | Left Shift | `INPUT_ACTION_SWITCH_PLAYER` |
| `pause` | SYSTEM | Start | Escape | `INPUT_ACTION_PAUSE` |
| `ui_accept` | UI | X / Cross | Enter, Space, S | `INPUT_ACTION_UI_ACCEPT` |
| `ui_cancel` | UI | Triangle | Escape, Backspace, W | `INPUT_ACTION_UI_CANCEL` |
| `ui_up` | UI | D-pad up | Up | `INPUT_ACTION_UI_UP` |
| `ui_down` | UI | D-pad down | Down | `INPUT_ACTION_UI_DOWN` |
| `ui_left` | UI | D-pad left | Left | `INPUT_ACTION_UI_LEFT` |
| `ui_right` | UI | D-pad right | Right | `INPUT_ACTION_UI_RIGHT` |

Axes: one, `move` = (`move_left`, `move_right`, `move_up`, `move_down`). Movement actions use a
0.5 deadzone. Godot's `Input.get_vector` supplies the observed unit-disc clamp, and all non-stick
roles (including sprint and triggers) are digital held actions; pressure is not sampled. Button bits therefore:
`sprint` 0, `pass_left` 1, `pass_right` 2, `kick` 3, `tackle` 4, `switch_player` 5;
`axes_per_slot() == 2`, matching `MatchConfig.axes_per_slot`'s default. Joypad motion defaults use
`axis_value` of exactly `-1.0` or `1.0`. All actions are remappable (keyboard-only play must stay
viable, PLAN 1c).

## 3. Event codec

`InputEventCodec`: `static encode(event: InputEvent) -> Dictionary` and
`static decode(data: Dictionary) -> InputEvent` (null when invalid or unsupported):

| type | fields |
|---|---|
| `"key"` | `physical_keycode: int` |
| `"joy_button"` | `button_index: int` |
| `"joy_axis"` | `axis: int`, `axis_value: float` (sign only: `-1.0` or `1.0`) |
| `"mouse_button"` | `button_index: int` |

`encode` of an unsupported event returns `{}`. Decoded events have `device = -1`.
`static same_binding(a: InputEvent, b: InputEvent) -> bool`: same type and same fields above
(for keys, `physical_keycode`; for joy axes, `axis` and the sign of `axis_value`), device ignored.
`static device_of(event: InputEvent) -> int`: `InputBindings.Device.GAMEPAD`, `KEYBOARD`, or -1.

## 4. Bindings, remapping, persistence

`InputBindings` (`RefCounted`):
`enum Device { GAMEPAD, KEYBOARD }`, `const SCHEMA_VERSION: int = 1`,
`const DEFAULT_PATH: String = "user://input_bindings.cfg"`, `var action_set: InputActionSet`.

- `_init(p_action_set: InputActionSet)`
- `apply_defaults() -> void`: for every action: add it to `InputMap` if missing, set its
  deadzone, erase all its events (this also replaces Godot's built-in `ui_*` events), add the
  default gamepad then keyboard events (each with `device = -1`). Emits
  `EventBus.input_bindings_changed` once.
- `get_events(action_id: StringName, device: Device) -> Array[InputEvent]`: current `InputMap`
  events of that device kind, in `InputMap` order.
- `rebind(action_id: StringName, device: Device, index: int, event: InputEvent) -> Error`:
  replaces the `index`-th event of that device kind (`index == count` appends).
  `ERR_DOES_NOT_EXIST` for an unknown action, `ERR_UNAVAILABLE` if not remappable,
  `ERR_INVALID_PARAMETER` if the event's kind differs from `device`, the type is unsupported or the
  index is out of range. Does not resolve conflicts. Emits `input_bindings_changed` on success.
- `unbind(action_id: StringName, device: Device, index: int) -> Error`: removes that event; same
  errors as `rebind`. Emits on success.
- `find_conflicts(action_id: StringName, event: InputEvent) -> Array[StringName]`: other actions
  that already have a `same_binding` event and are co-active with `action_id`. Co-active:
  same context, or one is SYSTEM and the other MATCH. UI and MATCH are never co-active.
- `reset_action(action_id: StringName) -> void`: that action back to its defaults. Emits.
- `reset_all() -> void`: same as `apply_defaults()`.
- `save_to(path: String = DEFAULT_PATH) -> Error`: writes a `ConfigFile`:
  section `meta` keys `schema_version` (int) and `action_set` (String); sections `gamepad` and
  `keyboard` with one key per remappable action id whose value is an `Array` of encoded
  dictionaries. Returns the `ConfigFile.save` result.
- `load_from(path: String = DEFAULT_PATH) -> Error`: `ERR_FILE_NOT_FOUND` if absent and
  `ERR_FILE_UNRECOGNIZED` if `meta/schema_version` is missing, not an int or greater than
  `SCHEMA_VERSION`; in both cases nothing changes. Otherwise migrates older versions (none exist
  yet), then for each remappable action present in a device section replaces that device kind's
  events with the decoded ones (invalid entries skipped); actions or devices absent from the file
  keep their current events; unknown action ids are ignored. Emits once, returns `OK`.
- Nothing in this class writes to `res://`.

## 5. Sampling into frames

`InputSampler` extends `InputSource`:
`_init(p_action_set: InputActionSet, p_slot_count: int = 1)`;
`fill_frame(tick: int, frame: InputFrame) -> bool`: sets `frame.tick = tick`, clears it, then for
slot 0 sets bit `i` when `Input.is_action_pressed(button_actions()[i])`, and for each axis sets
x = `clampi(roundi(v.x * 127.0), -127, 127)` and y likewise, where
`v = Input.get_vector(negative_x, positive_x, negative_y, positive_y)`. Other slots stay zero.
Returns true. No allocations per call (cache the action id arrays in `_init`).
`layout_hash() -> String` returns `action_set.layout_hash()`.

The sim reads only the frame; nothing under `game/match/` reads `Input`.

`GameSettings._ready()` loads `res://game/platform/input/default_action_set.tres`, creates
`input_bindings`, calls `apply_defaults()`, then `load_from()` (a missing file is fine).

## 6. Acceptance criteria

Tests in `tests/unit/platform/input/`. Tests that change `InputMap` or `Input` state restore it
(`reset_all()`, `Input.action_release`) and use temporary `user://` paths, never
`DEFAULT_PATH`.

- I-01 `default_action_set.tres` loads as an `InputActionSet`, `validate()` is empty, and it
  contains the 17 actions of 2.1 with their contexts and display keys.
- I-02 Every action in the default set has at least one gamepad and one keyboard default, and every
  `display_name_key` exists in `localization/translations.csv`.
- I-03 `button_actions()` is `[sprint, pass_left, pass_right, kick, tackle, switch_player]`;
  `bit_of(&"kick") == 3`; `bit_of(&"move_up") == -1`; `bit_of(&"pause") == -1`;
  `axes_per_slot() == 2`; `axis_index(&"move", 1) == 1`.
- I-04 `layout_hash()` equals SHA-256 of the text defined in section 2 (test builds the text
  itself); it changes when two button actions swap order; it is stable across two loads.
- I-05 `validate()` reports a duplicate action id, an axis naming an unknown action, and an axis
  naming a UI action (one test each).
- I-06 `make_frame(3)` returns an `InputFrame` with `slot_count == 3` and `axes_per_slot == 2`.
- I-07 Codec round-trip: key, joy button, joy axis and mouse button events encode and decode to a
  `same_binding` event with `device == -1`; an `InputEventMouseMotion` encodes to `{}`;
  `decode({"type": "nope"})` is null.
- I-08 After `apply_defaults()`, `InputMap.has_action` is true for all 17 actions and
  `get_events(&"kick", GAMEPAD)` holds exactly the default X / Cross button event.
- I-09 `rebind(&"kick", KEYBOARD, 0, <key P>)` returns `OK`, `InputMap.action_has_event` is true
  for key P and false for the old S, and `EventBus.input_bindings_changed` was emitted.
- I-10 `rebind` errors: unknown action `ERR_DOES_NOT_EXIST`; non-remappable action (test set)
  `ERR_UNAVAILABLE`; gamepad event for `KEYBOARD` `ERR_INVALID_PARAMETER`; index past the end
  `ERR_INVALID_PARAMETER`.
- I-11 `find_conflicts(&"kick", <key S>)` returns `[tackle]`;
  `find_conflicts(&"ui_cancel", <key Escape>)` does not contain `pause`;
  `find_conflicts(&"kick", <key Escape>)` contains `pause`.
- I-12 `reset_action(&"kick")` after a rebind restores exactly the defaults.
- I-13 Persistence: rebind two actions, `save_to(tmp)`, `reset_all()`, `load_from(tmp)` restores
  both rebinds and leaves other actions at defaults. The file has `meta/schema_version == 1`.
- I-14 `load_from` returns `ERR_FILE_NOT_FOUND` for a missing file and `ERR_FILE_UNRECOGNIZED` for
  a file with `schema_version = 2`, and in both cases bindings are unchanged.
- I-15 `load_from` ignores unknown action ids and invalid event entries in the file.
- I-16 Sampler: kick is a digital held role (not analog pressure). With
  `Input.action_press(&"kick")` and `Input.action_press(&"move_right")`,
  `fill_frame(7, frame)` gives `frame.tick == 7`, bit 3 set, no other bits, axis 0 == 127 and
  axis 1 == 0; after releasing both, a second fill gives all zeros.
- I-17 Sampler with `move_left` and `move_up` pressed fully gives axes (-90, -90) (`get_vector`
  normalises the diagonal to length 1, and `roundi(-0.70711 * 127) == -90`); `layout_hash()`
  equals the set's.
- I-18 No `.gd` under `game/platform/input/` writes to a `res://` path, and none under
  `game/match/` references `Input.` (shared with S1-core C-43).
- I-19 `GameSettings.input_bindings` is non-null at test time and `InputMap.has_action(&"kick")`.
