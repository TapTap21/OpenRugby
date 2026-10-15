# Ground-plane contact source resume

## Slice status

Branch: `slice/ground-contact-source`.

`GroundPlaneContactSource` implements only the y = 0 ellipsoid-plane detector
from RE 06 §2.4. It reads semi-axes from `BallPhysicsParams`, transforms the
world plane normal into the normalized body orientation, computes scaled
distance `d' = position.y / |n'|`, and emits one stable contact only for
`0 < d' < 1`. Penetration is `(1 - d') * |n'|`. The contact point is the
ellipsoid's downward support point projected onto the ground plane.

## Coverage and limits

- Tests cover unrotated numeric penetration, tilted ellipsoid support,
  strict lower and upper boundaries, and stable contact identity/order.
- This is not a complete stadium collision provider. It has no editable
  stadium triangle data and supplies no face, edge, vertex, post, or board
  contacts. Do not wire it as complete Classic stadium geometry.
- `is_available()` means this provider can supply its configured ground-plane
  subset. It does not attest that stadium mesh geometry is present or that
  complete Classic match collision coverage is available.
- Ground plane contact identity currently uses the `BallContact` ground kind
  and stable zero body/feature/subfeature/ordinal fields.

## Integration contract

`BallPhysicsSystem._detect_contacts()` currently emits a hard-coded ground
contact before appending contacts from its injected `BallContactSource`. Wiring
`GroundPlaneContactSource` unchanged would therefore emit two ground rows for
the same overlap. Before integration, either remove/disable the built-in ground
fallback when this provider supplies ground contacts, or suppress the provider
ground row when the fallback is active. Do not combine both rows unchanged.
This duplicate-row issue is separate from the missing stadium mesh coverage:
even after ground contact is composed once, editable stadium triangle contacts
are still required for complete Classic collision geometry.

## Verification

- `scripts/check-godot-safe.sh`: pass before Godot.
- Focused `scripts/test.sh res://tests/unit/physics/test_ground_plane_contact_source.gd`:
  4/4 pass.
- Full `scripts/test.sh`: 179/179 pass.
- `gdlint .`: pass.
- `gdformat --check --line-length 100` for the two changed GDScript files: pass.
- Repository-wide formatter scan flags existing vendored gdUnit4 files; those
  files were not changed.
- `scripts/hygiene.sh`: pass.

## Next steps

Keep the provider uncomposed until integration handles the duplicate ground
row and an editable stadium collision mesh provider exists. The composition
must guarantee full geometry coverage before it can claim complete Classic
stadium collision support.
