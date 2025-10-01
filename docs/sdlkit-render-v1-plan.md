# SDLKit Render API Versioning Strategy

## Overview
The SDLKit 3D effort introduces a dedicated render and compute control surface that lives alongside the existing GUI-oriented protocol. This document proposes the `sdlkit.render.v1` namespace as the forward-compatible contract while maintaining `sdlkit.gui.v1` for legacy 2D workflows. Both APIs are served from the same agent process so clients can migrate incrementally.

## Versioning Principles
1. **Semantic versioning for OpenAPI artifacts** – the new specification starts at `1.0.0` and increments the patch version for additive schema updates, the minor version for backward-compatible endpoint additions, and the major version for breaking changes.
2. **Namespace separation** – endpoints that manage GPU backends, scenes, materials, and compute workloads are grouped under `/agent/render`, `/agent/scene`, `/agent/compute`, and `/agent/system`. The legacy 2D commands remain under `/agent/gui` and are marked as deprecated to steer clients to the new API surface.
3. **Dual publication window** – both the legacy and render specifications are shipped together until the 3D stack reaches milestone M6. During this window the GUI spec only receives bug fixes while the render spec accumulates the new features.
4. **Capability negotiation** – clients call `/version` to discover supported protocol tags (`sdlkit.gui.v1`, `sdlkit.render.v1`) and use `/agent/system/native-handles` to determine which GPU backends are available on the host.

## Migration Guidance
- **New integrations** should target `sdlkit.render.v1` exclusively. Window lifecycle calls (`/agent/gui/window/*`) stay stable and are shared by both 2D and 3D pipelines.
- **Existing 2D clients** continue to use the GUI endpoints but will see deprecation markers in the OpenAPI and future release notes. They can migrate gradually by first consuming the shared window endpoints, then adopting resource creation and scene submission APIs.
- **Shader and compute tooling** now reference shared handle schemas defined once in `sdlkit.render.v1`. The render spec exposes validation endpoints that mirror the agent hand-offs described in `AGENTS.md`.

## Deliverables in this PR
- Publish the initial `sdlkit.render.v1` OpenAPI document with system negotiation, resource management, scene graph, material, and compute endpoints required for milestones M0–M5.
- Update `sdlkit.gui.v1.yaml` to mark 2D drawing commands as legacy and document the availability of `sdlkit.render.v1`.
- Provide asynchronous job tracking primitives and synchronization token schemas so compute workloads can feed graphics draws without stalling HTTP clients.

## Follow-up Considerations
- Automate cross-spec linting to ensure shared components (handles, binding sets) stay consistent.
- Add example payloads and Postman collections for the new endpoints ahead of milestone M6 documentation deliverables.
- Explore gRPC/WS transports if latency requirements exceed the comfort zone of HTTP for high-frequency submissions.
