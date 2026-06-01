#if DEBUG
using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace DroneVsPlayers.Editor;

/// <summary>
/// Editor-only helpers for native terrain scene wiring.
/// </summary>
public static class ArenaTerrainEditorCommands
{
	const string ArenaFloorGuid = "11111111-0001-8010-0000-000000000001";
	const string ArenaTerrainPath = "terrain/arena_floor.terrain";
	static readonly string[] ArenaTerrainMaterialPaths =
	{
		"materials/arena/grass_ground.tmat",
		"materials/arena/terrain_dirt_patch.tmat"
	};
	const int ArenaTerrainResolution = 512;
	const float ArenaTerrainSize = 21600f;
	const float ArenaTerrainHeight = 512f;
	const float RoadCenterX = 416.190948f;
	const float RoadProtectedHalfWidth = 720f;
	const float RoadProtectedHalfLength = 5700f;
	const float RoadProtectedFade = 650f;
	static readonly Vector3 ArenaTerrainOrigin = new( -ArenaTerrainSize * 0.5f, -ArenaTerrainSize * 0.5f, -8f );

	[ConCmd( "dvp_link_arena_terrain" )]
	public static async void LinkArenaTerrain()
	{
		WriteResult( "started" );

		var session = SceneEditorSession.Active;
		var scene = session?.Scene;
		if ( scene is null )
		{
			WriteResult( "no active scene editor session" );
			Log.Warning( "[ArenaTerrain] No active scene editor session." );
			return;
		}

		var floor = ResolveArenaFloor( scene );
		if ( !floor.IsValid() )
		{
			WriteResult( "ArenaFloor not found" );
			Log.Warning( "[ArenaTerrain] ArenaFloor not found." );
			return;
		}

		var storage = await LoadOrRepairTerrainStorage();
		if ( storage is null )
		{
			WriteResult( $"could not create or load terrain storage {ArenaTerrainPath}" );
			Log.Warning( $"[ArenaTerrain] Could not create or load terrain storage '{ArenaTerrainPath}'." );
			return;
		}

		using ( session.UndoScope( "Link Arena Terrain" ).Push() )
		{
			foreach ( var renderer in floor.Components.GetAll<ModelRenderer>().ToArray() )
				renderer.Destroy();

			foreach ( var collider in floor.Components.GetAll<BoxCollider>().ToArray() )
				collider.Destroy();

			floor.LocalPosition = ArenaTerrainOrigin;
			floor.LocalRotation = Rotation.Identity;
			floor.LocalScale = Vector3.One;

			var terrain = floor.Components.Get<Terrain>();
			if ( !terrain.IsValid() )
				terrain = floor.Components.Create<Terrain>( false );

			terrain.Storage = storage;
			terrain.EnableCollision = true;
			terrain.RenderType = ModelRenderer.ShadowRenderType.On;
			terrain.TerrainSize = storage.TerrainSize;
			terrain.TerrainHeight = storage.TerrainHeight;
			terrain.Enabled = true;
			terrain.Create();

			session.Selection.Clear();
			session.Selection.Add( floor );
		}

		session.Save( false );
		WriteResult( $"linked {ArenaTerrainPath} resolution={storage.Resolution} size={storage.TerrainSize} height={storage.TerrainHeight}" );
		Log.Info( $"[ArenaTerrain] Linked ArenaFloor to {ArenaTerrainPath} ({storage.Resolution}x{storage.Resolution}, size {storage.TerrainSize}, height {storage.TerrainHeight})." );
	}

	[ConCmd( "dvp_generate_arena_terrain_variance" )]
	public static async void GenerateArenaTerrainVariance()
	{
		WriteResult( "variance generation started" );

		var storage = await LoadOrRepairTerrainStorage();
		if ( storage is null )
		{
			WriteResult( $"could not create or load terrain storage {ArenaTerrainPath}" );
			Log.Warning( $"[ArenaTerrain] Could not create or load terrain storage '{ArenaTerrainPath}'." );
			return;
		}

		ApplyTerrainStorageDefaults( storage );
		GenerateTerrainMaps( storage, out var maxHeightUnits, out var raisedPixels, out var grassOverlayPixels, out var protectedViolations );

		var asset = FindArenaTerrainAsset();
		if ( asset is null )
		{
			WriteResult( $"terrain asset missing after repair {ArenaTerrainPath}" );
			Log.Warning( $"[ArenaTerrain] Terrain asset missing after repair '{ArenaTerrainPath}'." );
			return;
		}

		if ( !asset.SaveToDisk( storage ) )
		{
			WriteResult( $"SaveToDisk failed for {ArenaTerrainPath}" );
			return;
		}

		await asset.CompileIfNeededAsync();

		var session = SceneEditorSession.Active;
		var scene = session?.Scene;
		if ( scene is not null )
		{
			var floor = ResolveArenaFloor( scene );
			if ( floor.IsValid() )
			{
				floor.LocalPosition = ArenaTerrainOrigin;
				floor.LocalRotation = Rotation.Identity;
				floor.LocalScale = Vector3.One;

				var terrain = floor.Components.Get<Terrain>();
				if ( terrain.IsValid() )
				{
					terrain.Storage = storage;
					terrain.EnableCollision = true;
					terrain.TerrainSize = storage.TerrainSize;
					terrain.TerrainHeight = storage.TerrainHeight;
					terrain.Enabled = true;
					terrain.Create();
				}

				session.Save( false );
			}
		}

		var result = $"variance generated {ArenaTerrainPath} maxHeight={maxHeightUnits:0.0} raisedPixels={raisedPixels} grassOverlayPixels={grassOverlayPixels} protectedViolations={protectedViolations}";
		WriteResult( result );
		Log.Info( $"[ArenaTerrain] {result}" );
	}

	static async Task<TerrainStorage> LoadOrRepairTerrainStorage()
	{
		var asset = FindArenaTerrainAsset();

		if ( asset is not null && asset.TryLoadResource<TerrainStorage>( out var existing ) && existing is not null )
		{
			if ( StorageMatchesExpected( existing ) )
				return existing;

			ApplyTerrainStorageDefaults( existing );
			if ( !asset.SaveToDisk( existing ) )
			{
				WriteResult( $"SaveToDisk failed for {ArenaTerrainPath}" );
				return null;
			}

			await asset.CompileIfNeededAsync();

			if ( asset.TryLoadResource<TerrainStorage>( out var updated ) && updated is not null )
				return updated;

			return existing;
		}

		var assetsPath = Project.Current?.GetAssetsPath();
		if ( string.IsNullOrWhiteSpace( assetsPath ) )
		{
			WriteResult( "project assets path unavailable" );
			return null;
		}

		var fullPath = Path.Combine( assetsPath, ArenaTerrainPath.Replace( '/', Path.DirectorySeparatorChar ) );
		Directory.CreateDirectory( Path.GetDirectoryName( fullPath )! );
		asset ??= AssetSystem.CreateResource( "terrain", fullPath );
		if ( asset is null )
		{
			WriteResult( $"AssetSystem.CreateResource failed for {fullPath}" );
			return null;
		}

		var storage = new TerrainStorage();
		ApplyTerrainStorageDefaults( storage );

		if ( !asset.SaveToDisk( storage ) )
		{
			WriteResult( $"SaveToDisk failed for {ArenaTerrainPath}" );
			return null;
		}

		await asset.CompileIfNeededAsync();

		if ( asset.TryLoadResource<TerrainStorage>( out var repaired ) && repaired is not null )
			return repaired;

		WriteResult( $"TryLoadResource still failed after repair for {ArenaTerrainPath}" );
		return null;
	}

	static bool StorageMatchesExpected( TerrainStorage storage )
	{
		return storage.Resolution == ArenaTerrainResolution
			&& MathF.Abs( storage.TerrainSize - ArenaTerrainSize ) < 0.01f
			&& MathF.Abs( storage.TerrainHeight - ArenaTerrainHeight ) < 0.01f
			&& storage.MaterialSettings is not null
			&& storage.MaterialSettings.HeightBlendEnabled
			&& MathF.Abs( storage.MaterialSettings.HeightBlendSharpness - 0.87f ) < 0.01f
			&& storage.HeightMap is { Length: ArenaTerrainResolution * ArenaTerrainResolution }
			&& storage.ControlMap is { Length: ArenaTerrainResolution * ArenaTerrainResolution }
			&& storage.Materials is { Count: >= 2 };
	}

	static void ApplyTerrainStorageDefaults( TerrainStorage storage )
	{
		if ( storage.Resolution != ArenaTerrainResolution )
			storage.SetResolution( ArenaTerrainResolution );

		storage.TerrainSize = ArenaTerrainSize;
		storage.TerrainHeight = ArenaTerrainHeight;
		storage.MaterialSettings ??= new TerrainStorage.TerrainMaterialSettings();
		storage.MaterialSettings.HeightBlendEnabled = true;
		storage.MaterialSettings.HeightBlendSharpness = 0.87f;

		storage.Materials.Clear();
		foreach ( var path in ArenaTerrainMaterialPaths )
		{
			if ( TryLoadTerrainMaterial( path, out var material ) )
				storage.Materials.Add( material );
		}
	}

	static bool TryLoadTerrainMaterial( string path, out TerrainMaterial material )
	{
		material = null;

		var asset = AssetSystem.FindByPath( path )
			?? AssetSystem.FindByPath( $"Assets/{path}" );

		if ( asset is not null && asset.TryLoadResource<TerrainMaterial>( out material ) && material is not null )
			return true;

		WriteResult( $"terrain material unavailable {path}" );
		Log.Warning( $"[ArenaTerrain] Terrain material unavailable: {path}" );
		return false;
	}

	static Asset FindArenaTerrainAsset()
	{
		return AssetSystem.FindByPath( ArenaTerrainPath )
			?? AssetSystem.FindByPath( $"Assets/{ArenaTerrainPath}" );
	}

	static void GenerateTerrainMaps( TerrainStorage storage, out float maxHeightUnits, out int raisedPixels, out int grassOverlayPixels, out int protectedViolations )
	{
		var resolution = storage.Resolution;
		var pixelCount = resolution * resolution;

		if ( storage.HeightMap is null || storage.HeightMap.Length != pixelCount )
			storage.HeightMap = new ushort[pixelCount];

		if ( storage.ControlMap is null || storage.ControlMap.Length != pixelCount )
			storage.ControlMap = new uint[pixelCount];

		maxHeightUnits = 0f;
		raisedPixels = 0;
		grassOverlayPixels = 0;
		protectedViolations = 0;

		for ( var y = 0; y < resolution; y++ )
		{
			var v = resolution <= 1 ? 0f : y / (float)(resolution - 1);
			var worldY = ArenaTerrainOrigin.y + v * ArenaTerrainSize;

			for ( var x = 0; x < resolution; x++ )
			{
				var u = resolution <= 1 ? 0f : x / (float)(resolution - 1);
				var worldX = ArenaTerrainOrigin.x + u * ArenaTerrainSize;
				var index = x + y * resolution;

				var protection = GetTerrainProtection( worldX, worldY );
				var open = 1f - protection;
				var outer = SmoothStep( 5000f, 8200f, MathF.Max( MathF.Abs( worldX ), MathF.Abs( worldY ) ) );
				var broad = FractalNoise( worldX * 0.00033f + 17.3f, worldY * 0.00033f - 91.7f );
				var detail = FractalNoise( worldX * 0.00115f - 43.1f, worldY * 0.00115f + 12.6f );
				var mound = MathF.Pow( MathF.Max( 0f, broad ), 1.12f );
				var field = mound * 0.72f + detail * 0.28f;
				var amplitude = Lerp( 72f, 260f, outer );
				var heightUnits = MathF.Pow( field, 1.08f ) * amplitude * open;

				if ( protection > 0.995f && heightUnits > 0.75f )
					protectedViolations++;

				heightUnits = MathF.Min( heightUnits, 280f );
				storage.HeightMap[index] = ToHeightMapValue( heightUnits );

				if ( heightUnits > 1.5f )
					raisedPixels++;

				maxHeightUnits = MathF.Max( maxHeightUnits, heightUnits );

				var grassTextureBreakup = SmoothStep( 0.58f, 0.82f, FractalNoise( worldX * 0.0008f + 103.4f, worldY * 0.0008f - 57.8f ) );
				var heightPatch = SmoothStep( 10f, 48f, heightUnits );
				var grassOverlayWeight = MathF.Max( heightPatch, grassTextureBreakup * SmoothStep( 0.2f, 0.9f, outer ) * 0.65f ) * open;
				var blend = (byte)Math.Clamp( (int)MathF.Round( grassOverlayWeight * 160f ), 0, 190 );
				storage.ControlMap[index] = new CompactTerrainMaterial( 0, 1, blend, false ).Packed;

				if ( blend > 16 )
					grassOverlayPixels++;
			}
		}
	}

	static ushort ToHeightMapValue( float heightUnits )
	{
		var normalized = Math.Clamp( heightUnits / ArenaTerrainHeight, 0f, 1f );
		return (ushort)Math.Clamp( (int)MathF.Round( normalized * ushort.MaxValue ), 0, ushort.MaxValue );
	}

	static float GetTerrainProtection( float x, float y )
	{
		var protection = 0f;

		protection = MathF.Max( protection, RectProtection( x, y, RoadCenterX, 0f, RoadProtectedHalfWidth, RoadProtectedHalfLength, RoadProtectedFade ) );
		protection = MathF.Max( protection, BoundaryProtection( x, y ) );

		protection = MathF.Max( protection, RotatedRectProtection( x, y, -1680f, 1520f, 12f, 920f, 860f, 620f ) );
		protection = MathF.Max( protection, RotatedRectProtection( x, y, -1740f, -1540f, -12f, 920f, 860f, 620f ) );
		protection = MathF.Max( protection, RotatedRectProtection( x, y, 1120f, 1680f, -18f, 720f, 650f, 520f ) );
		protection = MathF.Max( protection, RotatedRectProtection( x, y, 1340f, -1660f, 22f, 720f, 650f, 520f ) );
		protection = MathF.Max( protection, RotatedRectProtection( x, y, 2050f, 620f, -30f, 720f, 650f, 520f ) );
		protection = MathF.Max( protection, RotatedRectProtection( x, y, -2220f, 620f, 30f, 720f, 650f, 520f ) );

		return Math.Clamp( protection, 0f, 1f );
	}

	static float BoundaryProtection( float x, float y )
	{
		var protection = 0f;

		if ( MathF.Abs( y ) <= 5900f )
			protection = MathF.Max( protection, 1f - SmoothStep( 0f, 450f, MathF.Abs( MathF.Abs( x ) - 5400f ) ) );

		if ( MathF.Abs( x ) <= 5900f )
			protection = MathF.Max( protection, 1f - SmoothStep( 0f, 450f, MathF.Abs( MathF.Abs( y ) - 5400f ) ) );

		return protection;
	}

	static float RectProtection( float x, float y, float centerX, float centerY, float halfX, float halfY, float fade )
	{
		return RectProtectionLocal( x - centerX, y - centerY, halfX, halfY, fade );
	}

	static float RotatedRectProtection( float x, float y, float centerX, float centerY, float yawDegrees, float halfX, float halfY, float fade )
	{
		var radians = -yawDegrees * MathF.PI / 180f;
		var sin = MathF.Sin( radians );
		var cos = MathF.Cos( radians );
		var dx = x - centerX;
		var dy = y - centerY;
		var localX = dx * cos - dy * sin;
		var localY = dx * sin + dy * cos;

		return RectProtectionLocal( localX, localY, halfX, halfY, fade );
	}

	static float RectProtectionLocal( float localX, float localY, float halfX, float halfY, float fade )
	{
		var dx = MathF.Abs( localX ) - halfX;
		var dy = MathF.Abs( localY ) - halfY;
		var outsideX = MathF.Max( dx, 0f );
		var outsideY = MathF.Max( dy, 0f );
		var outsideDistance = MathF.Sqrt( outsideX * outsideX + outsideY * outsideY );

		if ( dx <= 0f && dy <= 0f )
			return 1f;

		return 1f - SmoothStep( 0f, fade, outsideDistance );
	}

	static float FractalNoise( float x, float y )
	{
		var value = 0f;
		var amplitude = 0.5f;
		var frequency = 1f;
		var total = 0f;

		for ( var octave = 0; octave < 4; octave++ )
		{
			value += ValueNoise( x * frequency, y * frequency ) * amplitude;
			total += amplitude;
			amplitude *= 0.5f;
			frequency *= 2f;
		}

		return total <= 0f ? 0f : value / total;
	}

	static float ValueNoise( float x, float y )
	{
		var x0 = (int)MathF.Floor( x );
		var y0 = (int)MathF.Floor( y );
		var tx = x - x0;
		var ty = y - y0;
		var sx = tx * tx * (3f - 2f * tx);
		var sy = ty * ty * (3f - 2f * ty);

		var a = Hash01( x0, y0 );
		var b = Hash01( x0 + 1, y0 );
		var c = Hash01( x0, y0 + 1 );
		var d = Hash01( x0 + 1, y0 + 1 );

		return Lerp( Lerp( a, b, sx ), Lerp( c, d, sx ), sy );
	}

	static float Hash01( int x, int y )
	{
		unchecked
		{
			var hash = (uint)(x * 374761393 + y * 668265263);
			hash = (hash ^ (hash >> 13)) * 1274126177u;
			hash ^= hash >> 16;
			return (hash & 0x00FFFFFF) / 16777215f;
		}
	}

	static float SmoothStep( float edge0, float edge1, float value )
	{
		var t = Math.Clamp( (value - edge0) / (edge1 - edge0), 0f, 1f );
		return t * t * (3f - 2f * t);
	}

	static float Lerp( float a, float b, float t )
	{
		return a + (b - a) * Math.Clamp( t, 0f, 1f );
	}

	static GameObject ResolveArenaFloor( Scene scene )
	{
		if ( Guid.TryParse( ArenaFloorGuid, out var guid ) )
		{
			var byGuid = scene.Directory.FindByGuid( guid );
			if ( byGuid.IsValid() )
				return byGuid;
		}

		return scene.GetAllObjects( false ).FirstOrDefault( x => x.Name == "ArenaFloor" );
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
			File.WriteAllText( Path.Combine( directory, "arena_terrain_link_result.txt" ), $"{DateTime.UtcNow:o} {message}" );
		}
		catch
		{
			// Best-effort diagnostics for editor automation.
		}
	}
}
#endif
