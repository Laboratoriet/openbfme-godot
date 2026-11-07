# Object shadow maps (S-3304)

The Godot renderer uses directional shadow maps for volume-shadow objects. This is a presentation substitute, not a reproduction of SAGE's CPU-extruded stencil volumes or RotWK's shadow-map shaders. It changes no simulation state or random stream.

## Implemented

- Object-template `Shadow` bits select `SHADOW_VOLUME`, `SHADOW_VOLUME_NEW` and their `OR_DECAL` forms. A model state's shadow description overrides the template; `ShadowForceDisable` wins. `SHADOW_DECAL` objects (infantry, optimized trees) are a projected blob texture in retail, not a silhouette, so they cast no map. Floors, particles, UI models, decal objects and projection-only objects do not become mesh casters.
- Each instancer creates shadow-only MultiMeshes lazily. They share the visible mesh, materials and bone palette, but contain only eligible instances. Hidden subobjects, invisible pivots, zero opacity and removed instances are omitted by the same visibility pass. Skinning, alpha cutouts and vegetation sway run through the same vertex/fragment shaders.
- While a shadow map is drawn, casters continue posing outside the presentation camera's frustum: an off-screen object can cast an on-screen shadow. This deliberately trades some pose-culling savings for correct animation; with ShadowLOD Off or Low they are pose-culled like any instance. No new per-object scene nodes are created.
- Opaque W3D surfaces, terrain and roads receive shadows. The custom light function uses only directional-light shadow coverage; it does not replace the existing retail lighting calculations with Godot lighting. UI/standalone W3D instancers do not receive shadows unless explicitly enabled. Terrain selection and radius overlays remain above shadows.
- The existing main object light supplies the direction. `ShadowLOD` now controls Off/Low (no volume maps), Medium and High (2048) and UltraHigh (4096) directional atlases. Each of the four cascades gets a quarter of the atlas, i.e. RotWK's own shadow map size: the `ShadowMap` block's `MapSize` (retail 1024, RW 0x47B69E), raised to at least 2048 at UltraHigh (RW 0x47B2B5); retail draws no shadow map at Medium, which keeps High's size. Turning the maps off restores Godot's default 4096 atlas. All enabled levels use four cascades, a 4000-world-unit range and 32-bit depth. Changing the setting applies during a game.

## Decal shadows (the blobs)

`SHADOW_DECAL` objects (infantry, the Angmar hill and snow trolls, optimized trees) get RotWK's projected blob, a port of the retail path, not a substitute (`engine/src/GameEngineDevice/W3DDevice/GameClient/Shadow/W3DProjectedShadow.h` has the RW addresses):

- **Which record.** A draw module's model condition state with a shadow of a nonzero type gives it; otherwise the object's own `Shadow` / `ShadowTexture` / `ShadowSizeX/Y` / `ShadowOffsetX/Y` fields are used (all 442 retail `SHADOW_DECAL` rows are object fields). `ShadowForceDisable` makes none.
- **When.** `SHADOW_VOLUME_OR_DECAL` and `SHADOW_VOLUME_NEW_OR_DECAL` become decals without `UseShadowVolumes`. A decal is made only with the static LOD level's `UseShadowDecals` (ShadowLOD **Low and Medium**) or the record's `ShadowOverrideLODVisibility`. At High and UltraHigh retail draws the shadow map instead and no blob. The game pushes the level's two flags to the HUD (`game.gd _push_shadow_decals`, `InGameHudNode.set_shadow_decals`).
- **Texture and size.** The texture is `ShadowTexture` + `.tga` (`shadow` when empty), sized by `ShadowSizeX/Y`, offset along the drawable's turned axes, turning with it.
- **How it is drawn.** The diffuse is white and the surface is multiplied by the texel (ZERO / SRC_COLOR). It is drawn on the terrain and on wall tops / bridges within 20 of its height, before the selection's decals, by the same per-pixel grid as the selection decals (`selection_decals.gdshaderinc`, `sel_alpha_at` with a per-channel `keep`).
- **When it is skipped.** A hidden or fully fogged drawable, a dead object's `SHADOW_DECAL`, or a drawable 20 or more above the floor (no terrain part).
- **Cost.** No draw calls: the terrain and W3D shaders evaluate the grid they already sample. CPU: the list is built every frame (about 0.03–0.06 ms of the HUD's update for 60 blobs on the Mac). The grid is uploaded again whenever a blob moves.

Not ported (S-3304): decals sized by the render object's bounds (counted in `get_state().drawable_shadow_decals.bounds_sized`), `SHADOW_MERGE_DECAL` / `SHADOW_SUBTRACT_DECAL_DYNAMIC` drawable shadows, the `_DYNAMIC` opacity fade, the decal's fog and depth bias, and RotWK's projected terrain mesh (per pixel here).

## Evidence and limits

The original GPL [ZH W3DShadowManager::setTimeOfDay](https://github.com/electronicarts/CnC_Generals_Zero_Hour/blob/main/GeneralsMD/Code/GameEngineDevice/Source/W3DDevice/GameClient/Shadow/W3DShadow.cpp) uses the first object light. [W3DVolumetricShadowManager::renderStencilShadows](https://github.com/electronicarts/CnC_Generals_Zero_Hour/blob/main/GeneralsMD/Code/GameEngineDevice/Source/W3DDevice/GameClient/Shadow/W3DVolumetricShadow.cpp) multiplies framebuffer RGB by the shadow colour (`DESTCOLOR`, `ZERO`); its alpha is not the blend weight. This implementation applies that multiplier in gamma space, before the final output conversion. Applying this donor composite to RotWK shadow-map coverage is an **inference**, not target-binary verification. This does not reproduce BFME2 High's main-light-only shadow attenuation; all enabled presets currently use the same donor composite. Fully lit pixels retain the pre-shadow output; overlapping casters do not repeatedly darken it.

Godot's [spatial shader documentation](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html) distinguishes the light's shadow-pass view from `MAIN_CAM_INV_VIEW_MATRIX`. Camera-facing W3D geometry uses the latter to keep its visible orientation in the shadow pass. Opaque and transparent shader permutations explicitly share instance-uniform indices, so adding reception cannot move the tint slot. The fragment-to-light colour replaces an unused varying, preserving the existing interpolation budget.

Still S-3304: the decal shadows listed above as not ported, dynamic/directional projected shadows, non-self volume variants, per-object sun-angle/height restrictions, shadow-opacity curves, translucent placement ghosts, water reception and transparent W3D reception. The Godot maps use alpha-cutout silhouettes rather than retail stencil geometry. Resolution, bias, cascade filtering and distance fade are Godot presentation choices; they are not retail parity claims. Rendered on Vulkan Forward+ only; Metal, mobile and Compatibility need separate validation.

## Validation

Native tests cover template/state eligibility, force-disable, shader generation/interpolator budget, existing lighting math and the enabled options row; `test_shadow1_decal_shadows.cpp` covers the decal shadows' record, routing, gate, texture, decal and the grid's multiply (the shaders' arithmetic in C++). `game.gd --auto --play1=decalshadows --screens=DIR` draws the trolls and some infantry with and without the decal shadows (Forward+ and `--rendering-method mobile`). GPU tests:

- `godot/tests/object_shadow_render_test.gd`: actual terrain shader; numeric gamma-space shadow colour, unchanged unshadowed output, moving caster, runtime off.
- `godot/tests/object_shadow_instances_test.gd`: shared-model eligibility, transforms, off-camera animation, hidden subobjects, opacity and removal. Requires retail assets and a real rendering backend for buffer readback.
- `godot/tests/object_shadow_building_test.gd`: a retail barracks on synthetic terrain casts/receives a visible shadow, never adds light, and restores the exact baseline when disabled. Optional `OPENBFME_SHADOW_CAPTURE_DIR` saves local evidence; no game-derived images belong in the repository.
- Existing `shader_test.gd` and `building_render_test.gd`: terrain compositing, real-map rendering and normal-mapped/team-colour building permutations.

Run GPU scripts without `--headless`, with `--path godot --script res://tests/<name>.gd`. Retail tests require `ROTWK_INSTALL` and `BFME2_INSTALL`.
