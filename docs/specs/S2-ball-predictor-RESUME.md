# S2 analytic ball predictor resume note

Branch: `slice/ball-path-predictor`

## Scope completed

- Added direct acceptance coverage for `BallPathPredictor.advance()` from RE 06 §2.5.
- Locked the 0.1 m rest centre, ballistic segment, vertical bounce restitution (0.55), and
  horizontal retention (0.885) with B-02 numeric assertions.
- Covered later-segment-only rolling below 0.01 s and the 1.25 s cap at 0.8/s deceleration.
- Covered non-finite contact-time termination without extrapolating that segment.
- Documented that the optional initial controller force is omitted until a caller injects an
  explicit policy. Prediction remains separate from rigid-body contact physics.

## Verification

- `scripts/test.sh res://tests/unit/physics/test_ball_path_predictor.gd`: 3/3 passed.
- `scripts/test.sh`: 167/167 passed across 32 suites.
- `gdlint` and `gdformat --check --line-length 100` on changed GDScript: passed.
- `scripts/hygiene.sh`: passed.
- Godot safety gate passed before each test invocation. Godot exited 0; it logged its existing
  port-0 remote-debug warning plus ObjectDB/resource teardown warnings.

## Next

- Obtain an independent review of the predictor against RE 06 §2.5 and this slice's acceptance
  criteria before merging.
- Keep the controller-force policy unresolved until a caller supplies explicit force data; do not
  infer it from velocity.
