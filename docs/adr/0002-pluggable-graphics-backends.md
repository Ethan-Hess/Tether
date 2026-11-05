# ADR 0002: Pluggable graphics backends

**Status:** Accepted

## Context
No single DirectX → Metal translator covers every game well today. DXMT is Metal-native but limited to D3D10/11. DXVK + MoltenVK has the broadest D3D9–11 coverage but adds a Vulkan hop. Apple's D3DMetal is the strongest D3D12 path, but its license forbids redistribution.

## Decision
Define a `GraphicsBackend` protocol that describes DLLs, overrides, and environment, with no runtime hooks. Ship open-source backends with the runtime. Support D3DMetal only as a **user-imported** component (`UserComponents/d3dmetal`). Resolve per launch: bottle choice → profile preference → `dxmt, d3dmetal, dxvk, wined3d`, skipping unavailable backends.

## Consequences
- Each game can use its lowest-overhead working path.
- Tether stays fully redistributable under LGPL-2.1.
- Users who want D3D12 via D3DMetal must download GPTK from Apple themselves.
- Switching backends rewrites a few DLLs in the prefix, which is cheap.
