# ADR-002: Compatibility renderer by default

- Status: Accepted
- Date: 2026-10-14

## Context

Targets are 60 fps at 1080p on integrated graphics (Intel UHD 620 class), the Steam Deck and
2015-era laptops, and Linux without Vulkan. The art direction is stylised: flat-ish lighting,
simple materials, no PBR-heavy materials or expensive post-processing.

## Decision

Use the Compatibility renderer (OpenGL 3.3 / ES 3.0, `gl_compatibility`) for all platforms. The
Windows Direct3D 12 override is removed. ETC2/ASTC import is enabled so the macOS universal
export is valid. Materials stay simple so that switching to Forward+ later is a settings change.

## Consequences

- Broadest hardware reach, including old Intel Macs and VMs.
- No Forward+ only features (e.g. SDFGI, volumetric fog, some post-processing); art direction
  must not depend on them.
- Graphics presets (Low / Medium / High) only vary shadows, crowd density, MSAA and draw distance.
- A benchmark scene in `tests/sim/` guards the frame-time budget.
