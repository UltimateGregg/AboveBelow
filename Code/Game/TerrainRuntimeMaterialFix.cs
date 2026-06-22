using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Rebuilds the terrain's material GPU buffer at runtime so the painted terrain
/// renders correctly in play mode.
///
/// On this project's (patched) engine build the editor builds the terrain material
/// buffer automatically on load, but the play scene does NOT — leaving the terrain
/// with an empty material buffer that falls back to the magenta missing-material
/// checker (with no error logged). The editor-only <c>dvp_fix_arena_sand_material</c>
/// ConCmd can't help play because it targets the editor session.
///
/// This component lives on the terrain GameObject (ArenaFloor) and calls
/// <see cref="Terrain.UpdateMaterialsBuffer"/> for the first few frames after start —
/// a few frames because the terrain's Storage/Materials can finish loading a frame or
/// two after OnStart. Local GPU-only work, so it runs on every peer (no networking).
/// </summary>
[Title( "Terrain Runtime Material Fix" )]
[Category( "Game" )]
[Icon( "terrain" )]
public sealed class TerrainRuntimeMaterialFix : Component
{
	[Property] public int RefreshFrames { get; set; } = 8;

	private Terrain _terrain;
	private int _framesLeft;
	private bool _logged;

	protected override void OnStart()
	{
		_framesLeft = RefreshFrames;
		Refresh();
	}

	protected override void OnUpdate()
	{
		if ( _framesLeft <= 0 )
			return;

		_framesLeft--;
		Refresh();
	}

	private void Refresh()
	{
		if ( !_terrain.IsValid() )
			_terrain = GameObject.Components.Get<Terrain>();

		if ( !_terrain.IsValid() || _terrain.Storage?.Materials is null )
			return;

		_terrain.UpdateMaterialsBuffer();

		if ( !_logged )
		{
			Log.Info( $"[TerrainRuntimeMaterialFix] rebuilt terrain material buffer (materials={_terrain.Storage.Materials.Count})." );
			_logged = true;
		}
	}
}
