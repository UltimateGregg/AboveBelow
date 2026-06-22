#if DEBUG
using System;
using System.IO;
using System.Linq;
using Sandbox;
using Sandbox.Clutter;
using SboxMcp.Handlers;

namespace DroneVsPlayers;

/// <summary>
/// Editor-only repair commands for painted grass and bush clutter that drifted above terrain.
/// </summary>
public static class FloatingClutterGroundingCommands
{
	const string ArenaFloorGuid = "11111111-0001-8010-0000-000000000001";
	const string PaintedClutterTag = "clutter_painted";

	[ConCmd( "dvp_audit_painted_clutter_grounding" )]
	public static void AuditPaintedClutterGrounding( float tolerance = 24f )
	{
		var report = ProcessPaintedClutter( MathF.Max( tolerance, 0f ), snap: false );
		WriteResult( report );
		Log.Info( $"[FloatingClutter] {report}" );
	}

	[ConCmd( "dvp_snap_painted_clutter_to_terrain" )]
	public static void SnapPaintedClutterToTerrain( float tolerance = 24f )
	{
		var report = ProcessPaintedClutter( MathF.Max( tolerance, 0f ), snap: true );
		WriteResult( report );
		Log.Info( $"[FloatingClutter] {report}" );
	}

	static string ProcessPaintedClutter( float tolerance, bool snap )
	{
		var session = SceneEditorSession.Active;
		var scene = session?.Scene ?? EditorSession.ActiveScene ?? Game.ActiveScene;
		if ( scene is null )
			return "failed: no active scene";

		var terrain = ResolveArenaTerrain( scene );
		if ( !terrain.IsValid() )
			return "failed: ArenaFloor terrain not found";

		var candidates = scene.FindAllWithTag( PaintedClutterTag )
			.Where( IsGrassOrBushClutter )
			.ToArray();

		var checkedCount = 0;
		var floatingCount = 0;
		var snappedCount = 0;
		var skippedNoTerrain = 0;
		var maxOffset = 0f;

		using var batch = scene.BatchGroup();
		var undo = snap ? session?.UndoScope( "Snap Painted Grass/Bush Clutter To Terrain" ).Push() : null;
		try
		{
			foreach ( var go in candidates )
			{
				if ( !go.IsValid() )
					continue;

				checkedCount++;
				var position = go.WorldPosition;
				if ( !TryGetTerrainSurfaceWorldHeight( terrain, position, out var terrainZ ) )
				{
					skippedNoTerrain++;
					continue;
				}

				var offset = position.z - terrainZ;
				if ( offset <= tolerance )
					continue;

				floatingCount++;
				maxOffset = MathF.Max( maxOffset, offset );

				if ( !snap )
					continue;

				go.WorldPosition = new Vector3( position.x, position.y, terrainZ );
				snappedCount++;
			}
		}
		finally
		{
			undo?.Dispose();
		}

		if ( snap && snappedCount > 0 )
		{
			scene.GetSystem<ClutterGridSystem>()?.Flush();
			EditorChanges.MarkDirty( "Snap painted grass/bush clutter to terrain" );
		}

		return $"mode={(snap ? "snap" : "audit")} checked={checkedCount} floating={floatingCount} snapped={snappedCount} skippedNoTerrain={skippedNoTerrain} tolerance={tolerance:0.##} maxOffset={maxOffset:0.##}";
	}

	static bool IsGrassOrBushClutter( GameObject go )
	{
		if ( !go.IsValid() || !go.Tags.Has( PaintedClutterTag, includeAncestors: false ) )
			return false;

		var name = go.Name ?? "";
		return name.Contains( "grass", StringComparison.OrdinalIgnoreCase )
			|| name.Contains( "bush", StringComparison.OrdinalIgnoreCase )
			|| name.Contains( "shrub", StringComparison.OrdinalIgnoreCase );
	}

	static Terrain ResolveArenaTerrain( Scene scene )
	{
		GameObject floor = null;
		if ( Guid.TryParse( ArenaFloorGuid, out var guid ) )
			floor = scene.Directory.FindByGuid( guid );

		floor ??= scene.GetAllObjects( false ).FirstOrDefault( x => x.Name == "ArenaFloor" );
		return floor?.Components.Get<Terrain>();
	}

	static bool TryGetTerrainSurfaceWorldHeight( Terrain terrain, Vector3 worldPoint, out float sampledWorldHeight )
	{
		sampledWorldHeight = 0f;

		var storage = terrain.Storage;
		if ( storage is null || storage.HeightMap is null || storage.Resolution <= 1 )
			return false;

		var localPoint = terrain.WorldTransform.PointToLocal( worldPoint );
		if ( localPoint.x < 0f || localPoint.y < 0f || localPoint.x > storage.TerrainSize || localPoint.y > storage.TerrainSize )
			return false;

		var resolution = storage.Resolution;
		var gridX = (localPoint.x / storage.TerrainSize) * (resolution - 1);
		var gridY = (localPoint.y / storage.TerrainSize) * (resolution - 1);
		var x0 = Math.Clamp( (int)MathF.Floor( gridX ), 0, resolution - 1 );
		var y0 = Math.Clamp( (int)MathF.Floor( gridY ), 0, resolution - 1 );
		var x1 = Math.Clamp( x0 + 1, 0, resolution - 1 );
		var y1 = Math.Clamp( y0 + 1, 0, resolution - 1 );

		if ( storage.ControlMap is not null && storage.ControlMap.Length > x0 + y0 * resolution )
		{
			var control = new CompactTerrainMaterial( storage.ControlMap[x0 + y0 * resolution] );
			if ( control.IsHole )
				return false;
		}

		var tx = gridX - x0;
		var ty = gridY - y0;
		var h00 = storage.HeightMap[x0 + y0 * resolution];
		var h10 = storage.HeightMap[x1 + y0 * resolution];
		var h01 = storage.HeightMap[x0 + y1 * resolution];
		var h11 = storage.HeightMap[x1 + y1 * resolution];
		var hx0 = Lerp( h00, h10, tx );
		var hx1 = Lerp( h01, h11, tx );
		var sampledLocalHeight = Lerp( hx0, hx1, ty ) * (storage.TerrainHeight / ushort.MaxValue);

		sampledWorldHeight = terrain.WorldTransform.PointToWorld( new Vector3( localPoint.x, localPoint.y, sampledLocalHeight ) ).z;
		return true;
	}

	static float Lerp( float a, float b, float t )
	{
		return a + (b - a) * Math.Clamp( t, 0f, 1f );
	}

	static void WriteResult( string message )
	{
		try
		{
			var root = Project.Current?.GetRootPath();
			if ( string.IsNullOrWhiteSpace( root ) )
				return;

			var directory = Path.Combine( root, ".tmp" );
			Directory.CreateDirectory( directory );
			File.WriteAllText( Path.Combine( directory, "floating_clutter_grounding_result.txt" ), $"{DateTime.UtcNow:o} {message}" );
		}
		catch
		{
			// Best-effort diagnostics for editor automation.
		}
	}
}
#endif
