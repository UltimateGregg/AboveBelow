using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Editor;
using Sandbox;

namespace BlenderBridge
{
	/// <summary>
	/// Persistence layer for bridge mesh data.
	/// Writes a sidecar manifest (.bridge.json) alongside the scene file
	/// and binary mesh cache files so geometry survives play mode without
	/// bloating the scene JSON.
	/// </summary>
	internal static class BridgePersistence
	{
		private const string CacheDirName = ".sbox_bridge_cache";
		private const int ManifestVersion = 1;

		// ── Public API ────────────────────────────────────────────────────────

		/// <summary>Save manifest and binary cache after a create or mesh update.</summary>
		internal static void SaveAfterChange( Scene scene, string bridgeId, GameObject go )
		{
			if ( scene == null || go == null ) return;

			try
			{
				var meshComp = go.Components.Get<MeshComponent>();
				if ( meshComp?.Mesh == null ) return;

				var extracted = BlenderBridgeDispatcher.ExtractMeshData( meshComp.Mesh );
				if ( extracted == null ) return;

				// Save binary cache
				var cachePath = GetCachePath( scene, bridgeId );
				if ( cachePath != null )
				{
					SaveMeshCache( cachePath, extracted.Value.Vertices, extracted.Value.Faces );
				}

				// Update manifest
				SaveManifest( scene );
			}
			catch ( Exception ex )
			{
				BlenderBridgeServer.LogInfo( $"Persistence save error: {ex.Message}" );
			}
		}

		/// <summary>Remove cache file for a deleted bridge object.</summary>
		internal static void RemoveFromCache( string bridgeId )
		{
			try
			{
				var scene = BridgeSceneHelper.ResolveScene();
				if ( scene == null ) return;

				var cachePath = GetCachePath( scene, bridgeId );
				if ( cachePath != null && File.Exists( cachePath ) )
					File.Delete( cachePath );

				SaveManifest( scene );
			}
			catch { }
		}

		/// <summary>Restore mesh data from cache for bridge objects missing geometry.
		/// Called on server start and after exiting play mode.</summary>
		internal static void RestoreFromCache( Scene scene )
		{
			if ( scene == null ) return;

			var cacheDir = GetCacheDir( scene );
			if ( cacheDir == null || !Directory.Exists( cacheDir ) ) return;

			int restored = 0;

			foreach ( var root in scene.Children )
			{
				RestoreSubtree( root, cacheDir, ref restored );
			}

			if ( restored > 0 )
				BlenderBridgeServer.LogInfo( $"Restored {restored} mesh(es) from cache" );
		}

		/// <summary>Check if any bridge state has been saved.</summary>
		internal static bool HasSavedState( Scene scene )
		{
			if ( scene == null ) return false;
			var manifestPath = GetManifestPath( scene );
			return manifestPath != null && File.Exists( manifestPath );
		}

		// ── Manifest ──────────────────────────────────────────────────────────

		private static void SaveManifest( Scene scene )
		{
			var manifestPath = GetManifestPath( scene );
			if ( manifestPath == null ) return;

			var objects = new Dictionary<string, object>();

			foreach ( var root in scene.Children )
				CollectManifestEntries( root, objects );

			var manifest = new
			{
				version = ManifestVersion,
				savedAt = DateTime.UtcNow.ToString( "o" ),
				objects
			};

			var json = JsonSerializer.Serialize( manifest, new JsonSerializerOptions
			{
				WriteIndented = true,
				PropertyNamingPolicy = JsonNamingPolicy.CamelCase
			} );

			File.WriteAllText( manifestPath, json );
		}

		private static void CollectManifestEntries( GameObject node, Dictionary<string, object> entries )
		{
			foreach ( var tag in node.Tags.TryGetAll() )
			{
				if ( tag.StartsWith( "bridge_" ) && tag != "bridge_group" )
				{
					var bridgeId = tag.Substring( 7 );
					var pos = node.WorldPosition;
					var rot = node.WorldRotation.Angles();

					var meshComp = node.Components.Get<MeshComponent>();
					int vertCount = 0, faceCount = 0;
					if ( meshComp?.Mesh != null )
					{
						vertCount = meshComp.Mesh.VertexHandles?.Count() ?? 0;
						faceCount = meshComp.Mesh.FaceHandles?.Count() ?? 0;
					}

					entries[bridgeId] = new
					{
						name = node.Name,
						vertexCount = vertCount,
						faceCount = faceCount,
						position = new { x = pos.x, y = pos.y, z = pos.z },
						rotation = new { pitch = rot.pitch, yaw = rot.yaw, roll = rot.roll }
					};
					break;
				}
			}

			foreach ( var child in node.Children )
				CollectManifestEntries( child, entries );
		}

		// ── Binary Cache ──────────────────────────────────────────────────────

		/// <summary>Write binary mesh cache: [uint32 vertCount][uint32 faceDataLen][float32[] verts][int32[] faces]</summary>
		private static void SaveMeshCache( string path, float[] vertices, int[] faces )
		{
			var dir = Path.GetDirectoryName( path );
			if ( dir != null )
				Directory.CreateDirectory( dir );

			using var fs = new FileStream( path, FileMode.Create );
			using var bw = new BinaryWriter( fs );

			bw.Write( (uint)(vertices.Length / 3) );
			bw.Write( (uint)faces.Length );

			foreach ( var v in vertices )
				bw.Write( v );

			foreach ( var f in faces )
				bw.Write( f );
		}

		/// <summary>Read binary mesh cache and rebuild PolygonMesh on a GameObject.</summary>
		private static bool RestoreMeshFromCache( string cachePath, GameObject go )
		{
			if ( !File.Exists( cachePath ) ) return false;

			try
			{
				using var fs = new FileStream( cachePath, FileMode.Open );
				using var br = new BinaryReader( fs );

				var vertCount = br.ReadUInt32();
				var faceDataLen = br.ReadUInt32();

				var vertices = new Vector3[vertCount];
				for ( int i = 0; i < vertCount; i++ )
				{
					float x = br.ReadSingle();
					float y = br.ReadSingle();
					float z = br.ReadSingle();
					vertices[i] = new Vector3( x, y, z );
				}

				var faceData = new int[faceDataLen];
				for ( int i = 0; i < faceDataLen; i++ )
					faceData[i] = br.ReadInt32();

				// Parse face groups
				var faceGroups = new List<int[]>();
				int idx = 0;
				while ( idx < faceData.Length )
				{
					int fvc = faceData[idx++];
					if ( idx + fvc > faceData.Length ) break;
					var face = new int[fvc];
					for ( int i = 0; i < fvc; i++ )
						face[i] = faceData[idx++];
					faceGroups.Add( face );
				}

				// Build PolygonMesh
				var mesh = new PolygonMesh();
				var hVertices = mesh.AddVertices( vertices );

				var defaultMat = Material.Load( "materials/dev/reflectivity_30.vmat" );

				foreach ( var faceGroup in faceGroups )
				{
					var faceVerts = faceGroup
						.Where( fi => fi >= 0 && fi < hVertices.Length )
						.Select( fi => hVertices[fi] )
						.ToArray();
					if ( faceVerts.Length >= 3 )
					{
						var hFace = mesh.AddFace( faceVerts );
						mesh.SetFaceMaterial( hFace, defaultMat );
					}
				}

				mesh.TextureAlignToGrid( mesh.Transform );
				mesh.SetSmoothingAngle( 40.0f );

				var existingMr = go.Components.Get<ModelRenderer>();
				if ( existingMr != null )
					existingMr.Destroy();

				var meshComp = go.Components.Get<MeshComponent>();
				if ( meshComp == null )
					meshComp = go.Components.Create<MeshComponent>();

				meshComp.Mesh = mesh;
				return true;
			}
			catch ( Exception ex )
			{
				BlenderBridgeServer.LogInfo( $"Cache restore failed for {cachePath}: {ex.Message}" );
				return false;
			}
		}

		private static void RestoreSubtree( GameObject node, string cacheDir, ref int restored )
		{
			foreach ( var tag in node.Tags.TryGetAll() )
			{
				if ( tag.StartsWith( "bridge_" ) && tag != "bridge_group" )
				{
					var bridgeId = tag.Substring( 7 );

					// Only restore if the object has no mesh currently
					var meshComp = node.Components.Get<MeshComponent>();
					if ( meshComp?.Mesh == null || (meshComp.Mesh.VertexHandles?.Count() ?? 0) == 0 )
					{
						var cachePath = Path.Combine( cacheDir, $"{bridgeId}.meshcache" );
						if ( RestoreMeshFromCache( cachePath, node ) )
							restored++;
					}
					break;
				}
			}

			foreach ( var child in node.Children )
				RestoreSubtree( child, cacheDir, ref restored );
		}

		// ── Path helpers ──────────────────────────────────────────────────────

		private static string GetManifestPath( Scene scene )
		{
			try
			{
				var scenePath = scene.Source?.ResourcePath;
				if ( string.IsNullOrEmpty( scenePath ) ) return null;

				var fullPath = Sandbox.FileSystem.Mounted.GetFullPath( scenePath );
				if ( string.IsNullOrEmpty( fullPath ) ) return null;

				var dir = Path.GetDirectoryName( fullPath );
				var name = Path.GetFileNameWithoutExtension( fullPath );
				return Path.Combine( dir, $"{name}.bridge.json" );
			}
			catch
			{
				return null;
			}
		}

		private static string GetCacheDir( Scene scene )
		{
			try
			{
				var assetsDir = BlenderBridgeDispatcher.GetProjectAssetsDir();
				if ( assetsDir == null ) return null;

				var projectRoot = Path.GetDirectoryName( assetsDir );
				if ( projectRoot == null ) return null;

				return Path.Combine( projectRoot, CacheDirName );
			}
			catch
			{
				return null;
			}
		}

		private static string GetCachePath( Scene scene, string bridgeId )
		{
			var dir = GetCacheDir( scene );
			if ( dir == null ) return null;
			return Path.Combine( dir, $"{bridgeId}.meshcache" );
		}
	}
}
