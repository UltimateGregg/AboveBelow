#if DEBUG
using System;
using System.IO;
using System.Linq;

namespace DroneVsPlayers.Editor;

/// <summary>
/// TEMPORARY one-off editor helper. Raises the ArenaFloor terrain heightmap AND every
/// top-level scene object by a uniform number of world units, so there is room to carve a
/// riverbed *below* the road (the terrain lower brush otherwise bottoms out at heightmap 0,
/// i.e. the road level).
///
/// The terrain GameObject itself is deliberately left where it is — only its heightmap
/// *values* rise — because moving the terrain object would move its 0-plane (the brush
/// floor) up with it, gaining no dig-down room. Every non-terrain root rises by the same
/// amount so nothing shifts relative to the new surface.
///
/// Does NOT save: the user reviews in-editor, then saves (heightmap -> arena_floor.terrain*,
/// object moves -> main.scene). Safe to delete once the world has been raised.
/// </summary>
public static class TerrainWorldRaise
{
	const string ArenaFloorGuid = "11111111-0001-8010-0000-000000000001";

	[ConCmd( "dvp_raise_world" )]
	public static void RaiseWorld( float units = 84f )
	{
		var terrain = ResolveTerrain( out var error );
		if ( terrain is null )
		{
			Report( $"raise failed: {error}" );
			return;
		}

		var storage = terrain.Storage;
		var heightMap = storage?.HeightMap;
		if ( heightMap is null || heightMap.Length == 0 )
		{
			Report( "raise failed: terrain has no HeightMap" );
			return;
		}

		var scene = terrain.GameObject.Scene;
		if ( scene is null )
		{
			Report( "raise failed: terrain has no scene" );
			return;
		}

		// ushort offset for the requested world height (TerrainHeight maps to ushort 65535).
		var off = (int)MathF.Round( units / terrain.TerrainHeight * 65535f );

		// Scan current min/max and guard against clipping the top of the height range.
		ushort min = ushort.MaxValue, max = 0;
		foreach ( var v in heightMap )
		{
			if ( v < min ) min = v;
			if ( v > max ) max = v;
		}

		if ( max + off > 65535 )
		{
			Report( $"raise aborted: would clip. max={max} + off={off} = {max + off} > 65535. " +
				$"Reduce units (current {units})." );
			return;
		}

		// Raise every heightmap sample uniformly.
		for ( var i = 0; i < heightMap.Length; i++ )
		{
			var raised = heightMap[i] + off;
			heightMap[i] = (ushort)(raised > 65535 ? 65535 : raised);
		}

		// Push CPU edits to the GPU, then sync back to update collider data + mark saveable.
		var res = storage.Resolution;
		terrain.SyncGPUTexture();
		terrain.SyncCPUTexture( Terrain.SyncFlags.Height, new RectInt( 0, 0, res, res ) );

		// Raise every top-level object, then cancel the move on the terrain GO so only its
		// heightmap surface rose (its base / 0-plane stays put for consistent carve depth).
		var up = Vector3.Up * units;
		var roots = scene.Children.ToList();
		var raisedRoots = 0;
		foreach ( var go in roots )
		{
			if ( !go.IsValid() )
				continue;

			go.WorldPosition += up;
			raisedRoots++;
		}

		terrain.GameObject.WorldPosition -= up;

		Report( $"raise ok: units={units} off={off} heightMin={min} heightMax={max} -> " +
			$"newMax={max + off}; rootsRaised={raisedRoots}; terrainGO net 0 " +
			$"(worldZ={terrain.GameObject.WorldPosition.z}); NOT saved." );
	}

	[ConCmd( "dvp_dump_terrain_height" )]
	public static void DumpTerrainHeight()
	{
		var terrain = ResolveTerrain( out var error );
		if ( terrain is null )
		{
			Report( $"dump failed: {error}" );
			return;
		}

		var hm = terrain.Storage?.HeightMap;
		if ( hm is null || hm.Length == 0 )
		{
			Report( "dump failed: no HeightMap" );
			return;
		}

		var res = terrain.Storage.Resolution;
		ushort min = ushort.MaxValue, max = 0;
		long sum = 0;
		var zeros = 0;
		foreach ( var v in hm )
		{
			if ( v < min ) min = v;
			if ( v > max ) max = v;
			if ( v == 0 ) zeros++;
			sum += v;
		}

		// Sample a few interior texels (center + quarter points) to see the playable area.
		ushort Sample( float fx, float fy )
		{
			var x = (int)(fx * (res - 1));
			var y = (int)(fy * (res - 1));
			return hm[y * res + x];
		}

		// How many texels sit below one/two raises (impossible if every texel got raised)?
		var below1 = 0; var below2 = 0;
		foreach ( var v in hm )
		{
			if ( v < 10752 ) below1++;
			if ( v < 21504 ) below2++;
		}

		var center = Sample( 0.5f, 0.5f );
		var q = $"q[{Sample( 0.25f, 0.25f )},{Sample( 0.75f, 0.25f )},{Sample( 0.25f, 0.75f )},{Sample( 0.75f, 0.75f )}]";
		Report( $"dump: res={res} len={hm.Length} min={min} max={max} mean={sum / hm.Length} zeros={zeros} below10752={below1} below21504={below2} center={center} {q}" );
	}

	static Terrain ResolveTerrain( out string error )
	{
		error = null;

		var session = SceneEditorSession.Active;
		var scene = session?.Scene;
		if ( scene is null )
		{
			error = "no active scene editor session";
			return null;
		}

		GameObject floor = null;
		if ( Guid.TryParse( ArenaFloorGuid, out var guid ) )
			floor = scene.Directory.FindByGuid( guid );
		floor ??= scene.GetAllObjects( false ).FirstOrDefault( x => x.Name == "ArenaFloor" );

		if ( !floor.IsValid() )
		{
			error = "ArenaFloor not found";
			return null;
		}

		var terrain = floor.Components.Get<Terrain>();
		if ( !terrain.IsValid() )
		{
			error = "Terrain component not found on ArenaFloor";
			return null;
		}

		return terrain;
	}

	static void Report( string message )
	{
		Log.Info( $"[TerrainWorldRaise] {message}" );
		try
		{
			var root = Project.Current?.GetRootPath();
			if ( string.IsNullOrWhiteSpace( root ) )
				return;

			var directory = Path.Combine( root, ".tmp" );
			Directory.CreateDirectory( directory );
			File.WriteAllText( Path.Combine( directory, "terrain_world_raise_result.txt" ), $"{DateTime.UtcNow:o} {message}" );
		}
		catch
		{
			// Best-effort diagnostics for editor automation.
		}
	}
}
#endif
