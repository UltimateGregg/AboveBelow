#if DEBUG
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DroneVsPlayers.Editor;

/// <summary>
/// TEMPORARY one-off editor helper to repair the live ArenaFloor terrain's sand
/// material slot without disturbing the painted control map.
///
/// The painted sand layer was bound to a broken cloud material
/// (terrain/material/sand.tmat) which renders as the magenta missing-texture
/// checker. A clean local replacement lives at materials/arena/sand_terrain.tmat.
/// These commands swap ONLY the broken Materials[] slot for the local material and
/// re-upload the terrain materials buffer. They never touch HeightMap/ControlMap and
/// never save, so the user's painted control map and unsaved scene work are preserved.
///
/// Safe to delete once the live terrain renders correctly.
/// </summary>
public static class TerrainSandMaterialFix
{
	const string ArenaFloorGuid = "11111111-0001-8010-0000-000000000001";
	const string GoodSandPath = "materials/arena/sand_terrain.tmat";
	const string LocalArenaPrefix = "materials/arena/";

	[ConCmd( "dvp_dump_arena_terrain_materials" )]
	public static void DumpArenaTerrainMaterials()
	{
		var terrain = ResolveTerrain( out var error );
		if ( terrain is null )
		{
			Report( $"dump failed: {error}" );
			return;
		}

		var storage = terrain.Storage;
		if ( storage is null )
		{
			Report( "dump failed: terrain has no Storage" );
			return;
		}

		var sb = new StringBuilder();
		sb.AppendLine( $"materials={storage.Materials?.Count ?? 0} resolution={storage.Resolution} controlMapLen={storage.ControlMap?.Length ?? 0} heightMapLen={storage.HeightMap?.Length ?? 0}" );
		if ( storage.Materials is not null )
		{
			for ( var i = 0; i < storage.Materials.Count; i++ )
			{
				var m = storage.Materials[i];
				if ( m is null )
				{
					sb.AppendLine( $"  [{i}] <null>" );
					continue;
				}

				var bcr = m.BCRTexture is null ? "null" : "ok";
				var nho = m.NHOTexture is null ? "null" : "ok";
				sb.AppendLine( $"  [{i}] albedo={m.AlbedoImage ?? "<none>"} normal={m.NormalImage ?? "<none>"} bcr={bcr} nho={nho} local={IsLocalArena( m, null )}" );
			}
		}

		Report( sb.ToString() );
	}

	[ConCmd( "dvp_fix_arena_sand_material" )]
	public static async void FixArenaSandMaterial()
	{
		var terrain = ResolveTerrain( out var error );
		if ( terrain is null )
		{
			Report( $"fix failed: {error}" );
			return;
		}

		var storage = terrain.Storage;
		if ( storage?.Materials is null )
		{
			Report( "fix failed: terrain has no Storage/Materials" );
			return;
		}

		// Load (and compile if needed) the good local sand terrain material.
		var sandAsset = AssetSystem.FindByPath( GoodSandPath ) ?? AssetSystem.FindByPath( $"Assets/{GoodSandPath}" );
		if ( sandAsset is null )
		{
			Report( $"fix failed: asset not found {GoodSandPath}" );
			return;
		}

		await sandAsset.CompileIfNeededAsync();

		if ( !sandAsset.TryLoadResource<TerrainMaterial>( out var sandMat ) || sandMat is null )
		{
			Report( $"fix failed: could not load TerrainMaterial {GoodSandPath}" );
			return;
		}

		var materials = storage.Materials;

		// Already referencing the good local sand material? Just refresh it in place.
		var existingGoodIndex = materials.FindIndex( m => IsLocalArena( m, "sand_terrain" ) );
		// Otherwise find the broken / non-local (cloud) slot to replace.
		var badIndex = materials.FindIndex( m => m is null || !IsLocalArena( m, null ) );

		string action;
		int targetIndex;
		if ( existingGoodIndex >= 0 )
		{
			targetIndex = existingGoodIndex;
			materials[existingGoodIndex] = sandMat;
			action = $"refreshed existing local sand at slot {existingGoodIndex}";
		}
		else if ( badIndex >= 0 )
		{
			targetIndex = badIndex;
			materials[badIndex] = sandMat;
			action = $"replaced broken slot {badIndex} with {GoodSandPath}";
		}
		else
		{
			materials.Add( sandMat );
			targetIndex = materials.Count - 1;
			action = $"appended {GoodSandPath} as new slot {targetIndex}";
		}

		// Re-upload ONLY the materials buffer. HeightMap and ControlMap (the painted
		// splat data) are deliberately left untouched so the paint is preserved exactly.
		terrain.UpdateMaterialsBuffer();

		Report( $"fix ok: {action}; materials now={materials.Count}; targetIndex={targetIndex}; controlMapLen={storage.ControlMap?.Length ?? 0} (unchanged); NOT saved." );
	}

	static bool IsLocalArena( TerrainMaterial m, string nameContains )
	{
		if ( m is null )
			return false;

		var albedo = m.AlbedoImage ?? string.Empty;
		var isLocal = albedo.StartsWith( LocalArenaPrefix, StringComparison.OrdinalIgnoreCase );
		if ( !isLocal )
			return false;

		if ( string.IsNullOrEmpty( nameContains ) )
			return true;

		return albedo.Contains( nameContains, StringComparison.OrdinalIgnoreCase );
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
		Log.Info( $"[TerrainSandFix] {message}" );
		try
		{
			var root = Project.Current?.GetRootPath();
			if ( string.IsNullOrWhiteSpace( root ) )
				return;

			var directory = Path.Combine( root, ".tmp" );
			Directory.CreateDirectory( directory );
			File.WriteAllText( Path.Combine( directory, "terrain_sand_fix_result.txt" ), $"{DateTime.UtcNow:o} {message}" );
		}
		catch
		{
			// Best-effort diagnostics for editor automation.
		}
	}
}
#endif
