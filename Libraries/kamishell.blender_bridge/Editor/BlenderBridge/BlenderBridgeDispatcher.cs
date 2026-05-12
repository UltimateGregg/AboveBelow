using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Editor;
using Editor.MeshEditor;
using HalfEdgeMesh;
using Sandbox;

namespace BlenderBridge
{
	/// <summary>
	/// Handles incoming bridge messages from Blender v2 and applies them to the s&amp;box scene.
	/// Sequence-based echo prevention, idempotent creates, light support, chunked mesh, hierarchy grouping.
	/// </summary>
	internal static class BlenderBridgeDispatcher
	{
		// ── Sequence state (echo prevention) ──────────────────────────────────

		/// <summary>Highest Blender seq we have processed.</summary>
		private static int _lastBlenderSeqProcessed = 0;

		/// <summary>bridgeId -> Blender seq that caused the last write. Used to suppress echo in PollForChanges.</summary>
		private static Dictionary<string, int> _lastWriteSeq = new();

		// ── Object caches ─────────────────────────────────────────────────────

		/// <summary>O(1) lookup cache: bridgeId -> GameObject. Rebuilt on cache miss via tree walk.</summary>
		private static Dictionary<string, GameObject> _bridgeObjectCache = new();

		/// <summary>Idempotency keys: key -> bridgeId. Prevents duplicate creation on network retry.</summary>
		private static Dictionary<string, string> _idempotencyKeys = new();

		/// <summary>Last-known transforms for change detection.</summary>
		private static Dictionary<string, (Vector3 pos, Rotation rot)> _lastKnown = new();

		/// <summary>Last-known mesh hash for geometry change detection.</summary>
		private static Dictionary<string, int> _lastMeshHash = new();

		/// <summary>Last-known light property hash for change detection.</summary>
		private static Dictionary<string, int> _lastLightHash = new();

		// ── Chunked mesh accumulator ──────────────────────────────────────────

		private static Dictionary<string, MeshAccumulator> _pendingChunks = new();

		private struct MeshAccumulator
		{
			public List<float> Vertices;
			public int TotalVertices;
			public int ChunksReceived;
			public int ChunkCount;
			public DateTime StartTime;
		}

		// ── Play mode ─────────────────────────────────────────────────────────

		private static bool _wasPlaying = false;

		/// <summary>Reset all state. Called on server start and hot reload.</summary>
		internal static void ResetState()
		{
			_lastBlenderSeqProcessed = 0;
			_lastWriteSeq.Clear();
			_bridgeObjectCache.Clear();
			_idempotencyKeys.Clear();
			_lastKnown.Clear();
			_lastMeshHash.Clear();
			_lastLightHash.Clear();
			_pendingChunks.Clear();
			_wasPlaying = false;
		}

		// ── Dispatch ──────────────────────────────────────────────────────────

		/// <summary>Handle an incoming message. Returns a JSON response string. Must be called on main thread.</summary>
		internal static string Dispatch( JsonElement root )
		{
			var type = root.TryGetProperty( "type", out var t ) ? t.GetString() : null;

			// Extract and update sequence tracking
			if ( root.TryGetProperty( "seq", out var seqEl ) && seqEl.ValueKind == JsonValueKind.Number )
			{
				var seq = seqEl.GetInt32();
				if ( seq > _lastBlenderSeqProcessed )
					_lastBlenderSeqProcessed = seq;
			}

			try
			{
				return type switch
				{
					"create" => HandleCreate( root ),
					"update_transform" => HandleUpdateTransform( root ),
					"update_mesh" => HandleUpdateMesh( root ),
					"delete" => HandleDelete( root ),
					"sync" => HandleSync( root ),
					"update_scene_transform" => HandleUpdateSceneTransform( root ),
					"create_light" => HandleCreateLight( root ),
					"update_light" => HandleUpdateLight( root ),
					"mesh_begin" => HandleMeshBegin( root ),
					"mesh_chunk" => HandleMeshChunk( root ),
					"mesh_end" => HandleMeshEnd( root ),
					_ => "{\"ok\":true}"
				};
			}
			catch ( Exception ex )
			{
				BlenderBridgeServer.LogError( $"Dispatch error ({type}): {ex.Message}" );
				return $"{{\"error\":\"{ex.Message}\"}}";
			}
		}

		// ── create ────────────────────────────────────────────────────────────

		private static string HandleCreate( JsonElement root )
		{
			var name = GetString( root, "name", "Blender Object" );
			var blenderSeq = GetInt( root, "seq", 0 );

			// Idempotency check: if this key was already used, return existing bridgeId
			var idemKey = GetString( root, "idempotencyKey" );
			if ( !string.IsNullOrEmpty( idemKey ) && _idempotencyKeys.TryGetValue( idemKey, out var existingId ) )
			{
				// Verify the object still exists
				var existingGo = FindByBridgeTag( existingId );
				if ( existingGo != null )
				{
					if ( BridgeLockPolicy.AllowsInbound( existingGo ) )
					{
						if ( BridgeLockPolicy.AllowsTransformChange( existingGo ) )
							ApplyTransform( existingGo, root );
						if ( BridgeLockPolicy.AllowsGeometryChange( existingGo ) && root.TryGetProperty( "meshData", out var md ) )
							ApplyMeshData( existingGo, md );
					}
					_lastWriteSeq[existingId] = blenderSeq;
					return JsonSerializer.Serialize( new { bridgeId = existingId }, BlenderBridgeServer.JsonOptions );
				}
				_idempotencyKeys.Remove( idemKey );
			}

			var scene = BridgeSceneHelper.ResolveScene();
			if ( scene == null ) return "{\"error\":\"no scene\"}";

			// Anti-duplication guard: if a GameObject in this scene already
			// shares this name AND is locked from inbound Blender updates
			// (e.g. a Terrain that was sent as a one-way proxy), assume Blender
			// lost the bridge_id on round-trip and is trying to re-create it.
			// Quietly map the new request onto the existing object instead of
			// spawning a duplicate.
			var nameClash = BridgeSceneHelper
				.WalkAll( scene )
				.FirstOrDefault( g => g.Name == name && !BridgeLockPolicy.AllowsInbound( g ) );
			if ( nameClash != null )
			{
				var existingTag = nameClash.Tags.TryGetAll().FirstOrDefault( t =>
					t.StartsWith( "bridge_" ) && t != "bridge_group"
					&& t != BridgeLockPolicy.LegacyLockTag
					&& !t.StartsWith( BridgeLockPolicy.FlagTagPrefix ) );
				var resolvedId = existingTag != null ? existingTag.Substring( 7 ) : "locked";
				BlenderBridgeServer.LogInfo( $"Suppressed duplicate create for locked '{name}' (re-binding to {resolvedId})" );
				_lastWriteSeq[resolvedId] = blenderSeq;
				if ( !string.IsNullOrEmpty( idemKey ) )
					_idempotencyKeys[idemKey] = resolvedId;
				return JsonSerializer.Serialize( new { bridgeId = resolvedId, locked = true }, BlenderBridgeServer.JsonOptions );
			}

			var bridgeId = "b_" + Guid.NewGuid().ToString( "N" ).Substring( 0, 8 );

			// Resolve hierarchy: Blender Bridge > [collection path] > object
			var parent = GetOrCreateBridgeGroup( scene );
			if ( root.TryGetProperty( "hierarchy", out var hierEl ) && hierEl.ValueKind == JsonValueKind.Array )
			{
				foreach ( var h in hierEl.EnumerateArray() )
				{
					var hName = h.GetString();
					if ( !string.IsNullOrEmpty( hName ) )
						parent = GetOrCreateChild( parent, hName );
				}
			}

			var go = scene.CreateObject();
			go.Name = name;
			go.Parent = parent;
			ApplyTransform( go, root );

			if ( root.TryGetProperty( "meshData", out var meshData ) )
				ApplyMeshData( go, meshData );

			go.Tags.Add( $"bridge_{bridgeId}" );
			_bridgeObjectCache[bridgeId] = go;
			_lastWriteSeq[bridgeId] = blenderSeq;
			_lastKnown[bridgeId] = (go.WorldPosition, go.WorldRotation);
			if ( !string.IsNullOrEmpty( idemKey ) )
				_idempotencyKeys[idemKey] = bridgeId;

			BlenderBridgeServer.LogInfo( $"Created '{name}' as {bridgeId}" );
			BridgePersistence.SaveAfterChange( scene, bridgeId, go );
			return JsonSerializer.Serialize( new { bridgeId }, BlenderBridgeServer.JsonOptions );
		}

		// ── update_transform ──────────────────────────────────────────────────

		private static string HandleUpdateTransform( JsonElement root )
		{
			var bridgeId = GetString( root, "bridgeId" );
			if ( string.IsNullOrEmpty( bridgeId ) ) return "{\"error\":\"missing bridgeId\"}";
			var blenderSeq = GetInt( root, "seq", 0 );

			var go = FindByBridgeTag( bridgeId );
			if ( go == null ) return "{\"error\":\"not found\"}";

			if ( !BridgeLockPolicy.AllowsTransformChange( go ) )
			{
				_lastWriteSeq[bridgeId] = blenderSeq;
				return "{\"ok\":true,\"locked\":true}";
			}

			ApplyTransform( go, root );
			_lastWriteSeq[bridgeId] = blenderSeq;
			_lastKnown[bridgeId] = (go.WorldPosition, go.WorldRotation);

			return "{\"ok\":true}";
		}

		// ── update_mesh ───────────────────────────────────────────────────────

		// All lock decisions go through BridgeLockPolicy. The legacy bridge_locked
		// tag is still recognized there for backward compatibility, and Terrain
		// components are auto-locked (Inbound | Geometry | Materials) so the
		// one-way proxy mesh never clobbers the heightmap-driven terrain.
		internal const string LockTag = BridgeLockPolicy.LegacyLockTag;

		internal static bool IsLockedFromBlender( GameObject go )
			=> !BridgeLockPolicy.AllowsInbound( go );

		private static string HandleUpdateMesh( JsonElement root )
		{
			var bridgeId = GetString( root, "bridgeId" );
			if ( string.IsNullOrEmpty( bridgeId ) ) return "{\"error\":\"missing bridgeId\"}";
			var blenderSeq = GetInt( root, "seq", 0 );

			var go = FindByBridgeTag( bridgeId );
			if ( go == null ) return "{\"error\":\"not found\"}";

			if ( !BridgeLockPolicy.AllowsInbound( go ) )
			{
				_lastWriteSeq[bridgeId] = blenderSeq;
				return "{\"ok\":true,\"locked\":true}";
			}

			if ( BridgeLockPolicy.AllowsTransformChange( go ) )
				ApplyTransform( go, root );

			if ( BridgeLockPolicy.AllowsGeometryChange( go ) && root.TryGetProperty( "meshData", out var meshData ) )
				ApplyMeshData( go, meshData );

			_lastWriteSeq[bridgeId] = blenderSeq;
			_lastKnown[bridgeId] = (go.WorldPosition, go.WorldRotation);

			var scene = BridgeSceneHelper.ResolveScene();
			if ( scene != null )
				BridgePersistence.SaveAfterChange( scene, bridgeId, go );

			return "{\"ok\":true}";
		}

		// ── delete ────────────────────────────────────────────────────────────

		private static string HandleDelete( JsonElement root )
		{
			var bridgeId = GetString( root, "bridgeId" );
			if ( string.IsNullOrEmpty( bridgeId ) ) return "{\"error\":\"missing bridgeId\"}";

			var go = FindByBridgeTag( bridgeId );
			if ( go != null )
				go.Destroy();

			_bridgeObjectCache.Remove( bridgeId );
			_lastKnown.Remove( bridgeId );
			_lastWriteSeq.Remove( bridgeId );
			_lastMeshHash.Remove( bridgeId );
			_idempotencyKeys.Where( kv => kv.Value == bridgeId ).Select( kv => kv.Key ).ToList()
				.ForEach( k => _idempotencyKeys.Remove( k ) );

			BridgePersistence.RemoveFromCache( bridgeId );
			BlenderBridgeServer.LogInfo( $"Deleted {bridgeId}" );
			return "{\"ok\":true}";
		}

		// ── create_light ──────────────────────────────────────────────────────

		private static string HandleCreateLight( JsonElement root )
		{
			var name = GetString( root, "name", "Blender Light" );
			var lightType = GetString( root, "lightType", "point" );
			var blenderSeq = GetInt( root, "seq", 0 );

			// Idempotency
			var idemKey = GetString( root, "idempotencyKey" );
			if ( !string.IsNullOrEmpty( idemKey ) && _idempotencyKeys.TryGetValue( idemKey, out var existingId ) )
			{
				var existingGo = FindByBridgeTag( existingId );
				if ( existingGo != null )
				{
					ApplyTransform( existingGo, root );
					ApplyLightProperties( existingGo, root );
					_lastWriteSeq[existingId] = blenderSeq;
					return JsonSerializer.Serialize( new { bridgeId = existingId }, BlenderBridgeServer.JsonOptions );
				}
				_idempotencyKeys.Remove( idemKey );
			}

			var bridgeId = "b_" + Guid.NewGuid().ToString( "N" ).Substring( 0, 8 );

			var scene = BridgeSceneHelper.ResolveScene();
			if ( scene == null ) return "{\"error\":\"no scene\"}";

			var parent = GetOrCreateBridgeGroup( scene );
			var go = scene.CreateObject();
			go.Name = name;
			go.Parent = parent;
			ApplyTransform( go, root );

			// Create appropriate light component
			switch ( lightType )
			{
				case "spot":
					go.Components.Create<SpotLight>();
					break;
				case "directional":
					go.Components.Create<DirectionalLight>();
					break;
				default:
					go.Components.Create<PointLight>();
					break;
			}

			ApplyLightProperties( go, root );

			go.Tags.Add( $"bridge_{bridgeId}" );
			_bridgeObjectCache[bridgeId] = go;
			_lastWriteSeq[bridgeId] = blenderSeq;
			_lastKnown[bridgeId] = (go.WorldPosition, go.WorldRotation);
			if ( !string.IsNullOrEmpty( idemKey ) )
				_idempotencyKeys[idemKey] = bridgeId;

			BlenderBridgeServer.LogInfo( $"Created light '{name}' as {bridgeId} ({lightType})" );
			return JsonSerializer.Serialize( new { bridgeId }, BlenderBridgeServer.JsonOptions );
		}

		// ── update_light ──────────────────────────────────────────────────────

		private static string HandleUpdateLight( JsonElement root )
		{
			var bridgeId = GetString( root, "bridgeId" );
			if ( string.IsNullOrEmpty( bridgeId ) ) return "{\"error\":\"missing bridgeId\"}";
			var blenderSeq = GetInt( root, "seq", 0 );

			var go = FindByBridgeTag( bridgeId );
			if ( go == null ) return "{\"error\":\"not found\"}";

			ApplyTransform( go, root );
			ApplyLightProperties( go, root );
			_lastWriteSeq[bridgeId] = blenderSeq;
			_lastKnown[bridgeId] = (go.WorldPosition, go.WorldRotation);

			return "{\"ok\":true}";
		}

		// ── Chunked mesh handlers ─────────────────────────────────────────────

		private static string HandleMeshBegin( JsonElement root )
		{
			var bridgeId = GetString( root, "bridgeId" );
			if ( string.IsNullOrEmpty( bridgeId ) ) return "{\"error\":\"missing bridgeId\"}";

			var totalVerts = GetInt( root, "totalVertices", 0 );
			var chunkCount = GetInt( root, "chunkCount", 0 );

			_pendingChunks[bridgeId] = new MeshAccumulator
			{
				Vertices = new List<float>( totalVerts * 3 ),
				TotalVertices = totalVerts,
				ChunksReceived = 0,
				ChunkCount = chunkCount,
				StartTime = DateTime.UtcNow,
			};

			return "{\"ok\":true}";
		}

		private static string HandleMeshChunk( JsonElement root )
		{
			var bridgeId = GetString( root, "bridgeId" );
			if ( string.IsNullOrEmpty( bridgeId ) ) return "{\"error\":\"missing bridgeId\"}";

			if ( !_pendingChunks.TryGetValue( bridgeId, out var accum ) )
				return "{\"error\":\"no pending mesh_begin\"}";

			if ( root.TryGetProperty( "vertices", out var vertsEl ) )
			{
				foreach ( var v in vertsEl.EnumerateArray() )
					accum.Vertices.Add( v.GetSingle() );
			}

			accum.ChunksReceived++;
			_pendingChunks[bridgeId] = accum;
			return "{\"ok\":true}";
		}

		private static string HandleMeshEnd( JsonElement root )
		{
			var bridgeId = GetString( root, "bridgeId" );
			if ( string.IsNullOrEmpty( bridgeId ) ) return "{\"error\":\"missing bridgeId\"}";
			var blenderSeq = GetInt( root, "seq", 0 );

			if ( !_pendingChunks.TryGetValue( bridgeId, out var accum ) )
				return "{\"error\":\"no pending mesh_begin\"}";

			_pendingChunks.Remove( bridgeId );

			// Build a complete meshData JsonElement from accumulated vertices + face data from this message
			var vertArray = accum.Vertices;

			// Parse faces from this message
			var faces = new List<int>();
			if ( root.TryGetProperty( "faces", out var facesEl ) )
				foreach ( var f in facesEl.EnumerateArray() )
					faces.Add( f.GetInt32() );

			int[] faceMaterials = null;
			if ( root.TryGetProperty( "faceMaterials", out var fmEl ) )
			{
				var fmList = new List<int>();
				foreach ( var fm in fmEl.EnumerateArray() )
					fmList.Add( fm.GetInt32() );
				faceMaterials = fmList.ToArray();
			}

			List<MaterialDef> materials = null;
			if ( root.TryGetProperty( "materials", out var matsEl ) )
				materials = ParseMaterialDefs( matsEl );

			// Build ParsedMesh
			var vertCount = vertArray.Count / 3;
			var vertices = new Vector3[vertCount];
			for ( int i = 0; i < vertCount; i++ )
				vertices[i] = new Vector3( vertArray[i * 3], vertArray[i * 3 + 1], vertArray[i * 3 + 2] );

			var faceGroups = new List<int[]>();
			int idx = 0;
			while ( idx < faces.Count )
			{
				int fvc = faces[idx++];
				if ( idx + fvc > faces.Count ) break;
				var face = new int[fvc];
				for ( int i = 0; i < fvc; i++ )
					face[i] = faces[idx++];
				faceGroups.Add( face );
			}

			var parsed = new ParsedMesh
			{
				Vertices = vertices,
				FaceGroups = faceGroups,
				FaceMaterials = faceMaterials,
				Materials = materials
			};

			// Find or create the object and apply mesh
			var go = FindByBridgeTag( bridgeId );
			if ( go == null )
				return "{\"error\":\"not found\"}";

			ApplyTransform( go, root );
			ApplyParsedMeshData( go, parsed );

			_lastWriteSeq[bridgeId] = blenderSeq;
			_lastKnown[bridgeId] = (go.WorldPosition, go.WorldRotation);

			var scene = BridgeSceneHelper.ResolveScene();
			if ( scene != null )
				BridgePersistence.SaveAfterChange( scene, bridgeId, go );

			BlenderBridgeServer.LogInfo( $"Chunked mesh assembled for {bridgeId} ({vertCount} verts)" );
			return "{\"ok\":true}";
		}

		// ── update_scene_transform ────────────────────────────────────────────

		private static string HandleUpdateSceneTransform( JsonElement root )
		{
			var sceneId = GetString( root, "sceneId" );
			if ( string.IsNullOrEmpty( sceneId ) ) return "{\"error\":\"missing sceneId\"}";
			var blenderSeq = GetInt( root, "seq", 0 );

			if ( !Guid.TryParse( sceneId, out var guid ) ) return "{\"error\":\"invalid sceneId\"}";

			var scene = BridgeSceneHelper.ResolveScene();
			if ( scene == null ) return "{\"error\":\"no scene\"}";

			GameObject go = null;
			foreach ( var root2 in scene.Children )
			{
				go = SearchTree( root2, g => g.Id == guid );
				if ( go != null ) break;
			}
			if ( go == null ) return "{\"error\":\"not found\"}";

			ApplyTransform( go, root );

			var key = $"scene_{sceneId}";
			_lastWriteSeq[key] = blenderSeq;
			_lastKnown[key] = (go.WorldPosition, go.WorldRotation);

			return "{\"ok\":true}";
		}

		// ── sync ──────────────────────────────────────────────────────────────

		private static string HandleSync( JsonElement root )
		{
			var scene = BridgeSceneHelper.ResolveScene();
			if ( scene == null ) return "{\"ok\":true}";

			// Parse what Blender knows about
			var blenderKnown = new HashSet<string>();
			if ( root.TryGetProperty( "knownObjects", out var known ) )
			{
				foreach ( var item in known.EnumerateArray() )
				{
					var bid = item.TryGetProperty( "bridgeId", out var b ) ? b.GetString() : null;
					if ( bid != null ) blenderKnown.Add( bid );
				}
			}

			var bridgeObjects = FindAllBridgeObjects( scene );
			var sboxIds = new HashSet<string>( bridgeObjects.Select( x => x.bridgeId ) );
			var objects = new List<object>();

			foreach ( var (bridgeId, go) in bridgeObjects )
			{
				_lastKnown[bridgeId] = (go.WorldPosition, go.WorldRotation);
				if ( !BridgeLockPolicy.AllowsOutbound( go ) ) continue;
				objects.Add( BuildObjectPayload( bridgeId, go ) );
			}

			// Include scene lights, models, and native MeshComponents
			foreach ( var go in BridgeSceneHelper.WalkAll( scene, true ) )
			{
				if ( go.Tags.TryGetAll().Any( tag => tag.StartsWith( "bridge_" ) ) )
					continue;

				var light = go.Components.GetAll().FirstOrDefault( c => c is Light ) as Light;
				if ( light != null )
				{
					objects.Add( BuildLightPayload( go, light ) );
					continue;
				}

				// Native MeshComponents placed in s&box — adopt as bridge objects
				var meshComp = go.Components.Get<MeshComponent>();
				if ( meshComp?.Mesh != null )
				{
					var adoptId = "b_" + Guid.NewGuid().ToString( "N" ).Substring( 0, 8 );
					go.Tags.Add( $"bridge_{adoptId}" );
					_bridgeObjectCache[adoptId] = go;
					_lastKnown[adoptId] = (go.WorldPosition, go.WorldRotation);
					objects.Add( BuildObjectPayload( adoptId, go ) );
					sboxIds.Add( adoptId );
					continue;
				}

				var anyModel = go.Components.GetAll()
					.FirstOrDefault( c => c.GetType().Name.Contains( "ModelRenderer" ) );
				if ( anyModel != null )
					objects.Add( BuildModelPayload( go, anyModel ) );
			}

			// Tell Blender to remove objects it has that s&box doesn't
			var staleInBlender = blenderKnown.Except( sboxIds );
			foreach ( var staleId in staleInBlender )
				objects.Add( new { type = "deleted", bridgeId = staleId } );

			BlenderBridgeServer.BroadcastWithSeq( new { type = "sync_response", objects } );
			BlenderBridgeServer.LogInfo( $"Sync: {bridgeObjects.Count} bridge, {objects.Count} total" );
			return "{\"ok\":true}";
		}

		// ── Poll for s&box-side changes ───────────────────────────────────────

		internal static void PollForChanges()
		{
			try
			{
				PollForChangesInternal();
			}
			catch ( Exception ex )
			{
				BlenderBridgeServer.LogInfo( $"Poll cycle skipped: {ex.Message}" );
			}
		}

		private static void PollForChangesInternal()
		{
			var scene = BridgeSceneHelper.ResolveScene();
			if ( scene == null ) return;

			// Play mode detection
			bool isPlaying = Game.IsPlaying;
			if ( isPlaying != _wasPlaying )
			{
				_wasPlaying = isPlaying;
				BlenderBridgeServer.BroadcastWithSeq( new
				{
					type = "play_mode",
					state = isPlaying ? "started" : "stopped"
				} );

				if ( !isPlaying )
				{
					// Exiting play mode — restore cached meshes
					try { BridgePersistence.RestoreFromCache( scene ); }
					catch { }
				}
			}

			// Clean up timed-out chunk accumulators
			var timedOut = _pendingChunks
				.Where( kv => (DateTime.UtcNow - kv.Value.StartTime).TotalSeconds > 30 )
				.Select( kv => kv.Key ).ToList();
			foreach ( var key in timedOut )
				_pendingChunks.Remove( key );

			var bridgeObjects = FindAllBridgeObjects( scene );
			var currentIds = new HashSet<string>();

			foreach ( var (bridgeId, go) in bridgeObjects )
			{
				if ( go == null || !go.IsValid ) continue;
				currentIds.Add( bridgeId );

				// Outbound lock: skip pushing changes to Blender for this object,
				// but keep tracking it (so deletes still propagate, etc).
				if ( !BridgeLockPolicy.AllowsOutbound( go ) )
				{
					_lastKnown[bridgeId] = (go.WorldPosition, go.WorldRotation);
					continue;
				}

				var pos = go.WorldPosition;
				var rot = go.WorldRotation;

				bool posChanged = false;
				bool rotChanged = false;

				if ( _lastKnown.TryGetValue( bridgeId, out var prev ) )
				{
					posChanged = MathF.Abs( pos.x - prev.pos.x ) > 0.01f
						|| MathF.Abs( pos.y - prev.pos.y ) > 0.01f
						|| MathF.Abs( pos.z - prev.pos.z ) > 0.01f;
					rotChanged = !rot.Equals( prev.rot );
				}

				// Check mesh changes — hash vertex positions so moves/pulls are detected
				bool meshChanged = false;
				var meshComp = go.Components.Get<MeshComponent>();
				if ( meshComp?.Mesh != null )
				{
					var meshHash = ComputeMeshGeometryHash( meshComp.Mesh );
					if ( _lastMeshHash.TryGetValue( bridgeId, out var prevHash ) && prevHash != meshHash )
						meshChanged = true;
					_lastMeshHash[bridgeId] = meshHash;
				}

				if ( (posChanged || rotChanged || meshChanged) )
				{
					// Echo suppression: if we recently applied a Blender write, suppress
					if ( _lastWriteSeq.ContainsKey( bridgeId ) )
					{
						_lastWriteSeq.Remove( bridgeId );
					}
					else
					{
						var angles = rot.Angles();
						if ( meshChanged )
						{
							var extracted = ExtractMeshData( meshComp.Mesh );
							object md = null;
							if ( extracted != null )
								md = new { vertices = extracted.Value.Vertices, faces = extracted.Value.Faces };

							BlenderBridgeServer.BroadcastWithSeq( new
							{
								type = "mesh_updated",
								bridgeId,
								position = new { x = pos.x, y = pos.y, z = pos.z },
								rotation = new { pitch = angles.pitch, yaw = angles.yaw, roll = angles.roll },
								meshData = md
							} );
						}
						else
						{
							BlenderBridgeServer.BroadcastWithSeq( new
							{
								type = "updated",
								bridgeId,
								position = new { x = pos.x, y = pos.y, z = pos.z },
								rotation = new { pitch = angles.pitch, yaw = angles.yaw, roll = angles.roll }
							} );
						}
					}
				}

				_lastKnown[bridgeId] = (pos, rot);
			}

			// Detect deletions
			foreach ( var oldId in _lastKnown.Keys.ToList() )
			{
				if ( oldId.StartsWith( "scene_" ) ) continue;
				if ( !currentIds.Contains( oldId ) )
				{
					_lastKnown.Remove( oldId );
					_lastWriteSeq.Remove( oldId );
					_lastMeshHash.Remove( oldId );
					_bridgeObjectCache.Remove( oldId );
					BlenderBridgeServer.BroadcastWithSeq( new { type = "deleted", bridgeId = oldId } );
				}
			}

			// Track scene objects (models/lights) and auto-adopt native MeshComponents
			foreach ( var go in BridgeSceneHelper.WalkAll( scene, true ) )
			{
				if ( go == null || !go.IsValid ) continue;
				if ( go.Tags.TryGetAll().Any( tag => tag.StartsWith( "bridge_" ) ) )
					continue;

				// Auto-adopt native MeshComponents that aren't bridge-tagged yet
				var nativeMesh = go.Components.Get<MeshComponent>();
				if ( nativeMesh?.Mesh != null )
				{
					var adoptId = "b_" + Guid.NewGuid().ToString( "N" ).Substring( 0, 8 );
					go.Tags.Add( $"bridge_{adoptId}" );
					_bridgeObjectCache[adoptId] = go;
					_lastKnown[adoptId] = (go.WorldPosition, go.WorldRotation);
					_lastMeshHash[adoptId] = ComputeMeshGeometryHash( nativeMesh.Mesh );

					// Broadcast the new object to Blender as a creation event
					var adoptPos = go.WorldPosition;
					var adoptRot = go.WorldRotation.Angles();
					var extracted = ExtractMeshData( nativeMesh.Mesh );
					object meshData = null;
					if ( extracted != null )
						meshData = new { vertices = extracted.Value.Vertices, faces = extracted.Value.Faces };

					BlenderBridgeServer.BroadcastWithSeq( new
					{
						type = "object_created",
						bridgeId = adoptId,
						name = go.Name,
						position = new { x = adoptPos.x, y = adoptPos.y, z = adoptPos.z },
						rotation = new { pitch = adoptRot.pitch, yaw = adoptRot.yaw, roll = adoptRot.roll },
						meshData
					} );
					BlenderBridgeServer.LogInfo( $"Auto-adopted native mesh '{go.Name}' as {adoptId}" );
					continue;
				}

				var hasModel = go.Components.GetAll().Any( c => c.GetType().Name.Contains( "ModelRenderer" ) );
				var hasLight = go.Components.GetAll().Any( c => c is Light );
				if ( !hasModel && !hasLight ) continue;

				var key = $"scene_{go.Id}";
				var pos = go.WorldPosition;
				var rot = go.WorldRotation;

				if ( _lastKnown.TryGetValue( key, out var prevScene ) )
				{
					bool sceneChanged = MathF.Abs( pos.x - prevScene.pos.x ) > 0.01f
						|| MathF.Abs( pos.y - prevScene.pos.y ) > 0.01f
						|| MathF.Abs( pos.z - prevScene.pos.z ) > 0.01f;

					if ( sceneChanged && !_lastWriteSeq.ContainsKey( key ) )
					{
						var angles = rot.Angles();
						BlenderBridgeServer.BroadcastWithSeq( new
						{
							type = "scene_updated",
							sceneId = go.Id.ToString(),
							position = new { x = pos.x, y = pos.y, z = pos.z },
							rotation = new { pitch = angles.pitch, yaw = angles.yaw, roll = angles.roll }
						} );
					}
					else if ( _lastWriteSeq.ContainsKey( key ) )
					{
						_lastWriteSeq.Remove( key );
					}
				}

				_lastKnown[key] = (pos, rot);
			}
		}

		// ── Hierarchy grouping ────────────────────────────────────────────────

		/// <summary>Find or create the "Blender Bridge" parent object identified by tag.</summary>
		private static GameObject GetOrCreateBridgeGroup( Scene scene )
		{
			// Search by tag (survives renames)
			foreach ( var root in scene.Children )
			{
				var found = SearchTree( root, g => g.Tags.Has( "bridge_group" ) );
				if ( found != null ) return found;
			}

			// Create new group
			var go = scene.CreateObject();
			go.Name = "Blender Bridge";
			go.Tags.Add( "bridge_group" );
			return go;
		}

		/// <summary>Find or create a child GameObject by name under a parent.
		/// Used to build hierarchy from Blender collection paths.</summary>
		private static GameObject GetOrCreateChild( GameObject parent, string name )
		{
			// Search existing children
			foreach ( var child in parent.Children )
			{
				if ( child.Name == name )
					return child;
			}

			// Create new empty child
			var scene = BridgeSceneHelper.ResolveScene();
			if ( scene == null ) return parent;

			var go = scene.CreateObject();
			go.Name = name;
			go.Parent = parent;
			return go;
		}

		// ── Object finders ────────────────────────────────────────────────────

		/// <summary>Find a bridge object by ID. Uses cache, falls back to tree walk.</summary>
		private static GameObject FindByBridgeTag( string bridgeId )
		{
			// Cache hit
			if ( _bridgeObjectCache.TryGetValue( bridgeId, out var cached ) && cached != null && cached.IsValid )
				return cached;

			// Cache miss — walk the scene
			var scene = BridgeSceneHelper.ResolveScene();
			if ( scene == null ) return null;

			var tag = $"bridge_{bridgeId}";
			foreach ( var root in scene.Children )
			{
				var found = SearchTree( root, tag );
				if ( found != null )
				{
					_bridgeObjectCache[bridgeId] = found;
					return found;
				}
			}
			return null;
		}

		private static GameObject SearchTree( GameObject node, string tag )
		{
			if ( node.Tags.Has( tag ) ) return node;
			foreach ( var child in node.Children )
			{
				var found = SearchTree( child, tag );
				if ( found != null ) return found;
			}
			return null;
		}

		private static GameObject SearchTree( GameObject node, Func<GameObject, bool> predicate )
		{
			if ( predicate( node ) ) return node;
			foreach ( var child in node.Children )
			{
				var found = SearchTree( child, predicate );
				if ( found != null ) return found;
			}
			return null;
		}

		private static List<(string bridgeId, GameObject go)> FindAllBridgeObjects( Scene scene )
		{
			var result = new List<(string, GameObject)>();
			foreach ( var root in scene.Children )
				CollectBridgeObjects( root, result );
			return result;
		}

		private static void CollectBridgeObjects( GameObject node, List<(string, GameObject)> result )
		{
			foreach ( var tag in node.Tags.TryGetAll() )
			{
				if ( tag.StartsWith( "bridge_" ) && tag != "bridge_group" )
				{
					var bridgeId = tag.Substring( 7 );
					result.Add( (bridgeId, node) );
					_bridgeObjectCache[bridgeId] = node; // Keep cache warm
					break;
				}
			}
			foreach ( var child in node.Children )
				CollectBridgeObjects( child, result );
		}

		// ── Light properties ──────────────────────────────────────────────────

		private static void ApplyLightProperties( GameObject go, JsonElement root )
		{
			if ( !root.TryGetProperty( "properties", out var propsEl ) )
				return;

			var light = go.Components.GetAll().FirstOrDefault( c => c is Light ) as Light;
			if ( light == null ) return;

			if ( propsEl.TryGetProperty( "color", out var colorEl ) )
			{
				var r = GetFloat( colorEl, "r", 1f );
				var g = GetFloat( colorEl, "g", 1f );
				var b = GetFloat( colorEl, "b", 1f );
				light.LightColor = new Color( r, g, b );
			}

			if ( light is PointLight point )
			{
				if ( propsEl.TryGetProperty( "radius", out var radiusEl ) )
					point.Radius = radiusEl.GetSingle();
			}
			else if ( light is SpotLight spot )
			{
				if ( propsEl.TryGetProperty( "radius", out var radiusEl ) )
					spot.Radius = radiusEl.GetSingle();
				if ( propsEl.TryGetProperty( "coneOuter", out var outerEl ) )
					spot.ConeOuter = outerEl.GetSingle();
				if ( propsEl.TryGetProperty( "coneInner", out var innerEl ) )
					spot.ConeInner = innerEl.GetSingle();
			}
		}

		// ── Mesh handling ─────────────────────────────────────────────────────

		private struct ParsedMesh
		{
			public Vector3[] Vertices;
			public List<int[]> FaceGroups;
			public int[] FaceMaterials;
			public List<MaterialDef> Materials;
			/// <summary>Per-face Blender-authored UVs, parallel to FaceGroups.
			/// Each entry has one Vector2 per face vertex. Null when Blender
			/// didn't send a UV layer; the apply path falls back to grid-align.</summary>
			public List<Vector2[]> FaceUVs;
		}

		private struct MaterialDef
		{
			public string Name;
			public float[] BaseColor;
			public float Metallic;
			public float Roughness;
			public string BaseColorTexture;
			public string RoughnessTexture;
			public string MetallicTexture;
			public string NormalTexture;
			public float NormalStrength;
			public float[] EmissionColor;
			public float EmissionStrength;
			public string VmatPath;
		}

		private static void ApplyMeshData( GameObject go, JsonElement meshData )
		{
			var parsed = ParseMeshData( meshData );
			if ( parsed == null ) return;
			ApplyParsedMeshData( go, parsed.Value );
		}

		/// <summary>
		/// Pulls the material off the first face of the GameObject's existing
		/// mesh. Used to preserve manually-authored materials (water shaders,
		/// custom vmats) when Blender resyncs without supplying material info.
		/// Returns null if there's no mesh, no faces, or only the dev default
		/// material is present (in which case the caller's fallback is fine).
		/// </summary>
		private static Material TryGetExistingDominantMaterial( GameObject go )
		{
			try
			{
				var mesh = go?.Components.Get<MeshComponent>()?.Mesh;
				if ( mesh == null ) return null;

				var getFaceMatMeth = mesh.GetType().GetMethod( "GetFaceMaterial", new[] { typeof( FaceHandle ) } );
				if ( getFaceMatMeth == null ) return null;

				foreach ( var fh in mesh.FaceHandles )
				{
					var result = getFaceMatMeth.Invoke( mesh, new object[] { fh } );
					if ( result is Material m && m != null )
					{
						// Skip the dev placeholder — using it as the "preserve"
						// fallback means we'd never escape it once it's been set.
						var path = m.ResourcePath ?? "";
						if ( path.EndsWith( "reflectivity_30.vmat", StringComparison.OrdinalIgnoreCase ) ||
							 path.EndsWith( "reflectivity_30.vmat_c", StringComparison.OrdinalIgnoreCase ) )
							return null;
						return m;
					}
					break;
				}
			}
			catch { }
			return null;
		}

		private static void ApplyParsedMeshData( GameObject go, ParsedMesh parsed )
		{
			var faceMaterials = new Material[parsed.FaceGroups.Count];
			var defaultMaterial = LoadMaterialSafe( "materials/dev/reflectivity_30.vmat" );

			// Materials lock: preserve whatever's already on the object regardless
			// of what Blender supplied. Skips the entire material-resolution path
			// and falls through to the existing-material preservation branch.
			bool forceMaterialPreserve = !BridgeLockPolicy.AllowsMaterialChange( go );

			if ( !forceMaterialPreserve && parsed.Materials != null && parsed.FaceMaterials != null )
			{
				var materialCache = new Dictionary<int, Material>();
				for ( int fi = 0; fi < parsed.FaceGroups.Count && fi < parsed.FaceMaterials.Length; fi++ )
				{
					var matIdx = parsed.FaceMaterials[fi];
					if ( !materialCache.ContainsKey( matIdx ) )
					{
						Material mat = null;
						if ( matIdx < parsed.Materials.Count )
						{
							var vmatPath = parsed.Materials[matIdx].VmatPath;
							if ( !string.IsNullOrEmpty( vmatPath ) )
								mat = LoadMaterialSafe( vmatPath );
							if ( mat == null )
								mat = GenerateOrLoadMaterial( parsed.Materials[matIdx] );
						}
						materialCache[matIdx] = mat ?? defaultMaterial;
					}
					faceMaterials[fi] = materialCache[matIdx];
				}
			}
			else
			{
				// Blender sent geometry but no material info. Before stamping
				// the dev placeholder over every face, try to preserve whatever
				// material is already on this GameObject's mesh — water shaders,
				// custom vmats, anything authored on the s&box side.
				var preserved = TryGetExistingDominantMaterial( go );
				var fallback = preserved ?? defaultMaterial;
				for ( int i = 0; i < faceMaterials.Length; i++ )
					faceMaterials[i] = fallback;
				if ( preserved != null )
					BlenderBridgeServer.LogInfo( $"Preserved existing material on '{go.Name}' (Blender sent no materials)" );
			}

			var mesh = new PolygonMesh();
			var hVertices = mesh.AddVertices( parsed.Vertices );

			bool hasBlenderUVs = parsed.FaceUVs != null && parsed.FaceUVs.Count == parsed.FaceGroups.Count;

			int faceIdx = 0;
			foreach ( var faceGroup in parsed.FaceGroups )
			{
				var faceVerts = faceGroup
					.Where( fi => fi >= 0 && fi < hVertices.Length )
					.Select( fi => hVertices[fi] )
					.ToArray();
				if ( faceVerts.Length >= 3 )
				{
					var hFace = mesh.AddFace( faceVerts );
					mesh.SetFaceMaterial( hFace, faceIdx < faceMaterials.Length ? faceMaterials[faceIdx] : defaultMaterial );
					if ( hasBlenderUVs && faceIdx < parsed.FaceUVs.Count )
					{
						// Use Blender-authored UVs verbatim. SetFaceTextureCoords
						// also recomputes the face's texture parameters from the
						// new coords, so the planar projection follows the UV
						// layout instead of fighting it.
						mesh.SetFaceTextureCoords( hFace, parsed.FaceUVs[faceIdx] );
					}
				}
				faceIdx++;
			}

			// Only fall back to grid-aligned auto-UVs if Blender didn't send a
			// UV layer. Calling TextureAlignToGrid when we have real UVs would
			// stomp them.
			if ( !hasBlenderUVs )
				mesh.TextureAlignToGrid( mesh.Transform );
			mesh.SetSmoothingAngle( 40.0f );

			// Defense in depth: never replace a Terrain component with a
			// MeshComponent. If the lock check earlier in the dispatch flow was
			// bypassed (e.g. an addon bug, a missing tag), this still blocks the
			// destructive path.
			if ( go.Components.Get<Terrain>() != null )
			{
				BlenderBridgeServer.LogInfo( $"Skipped ApplyMeshData on '{go.Name}' — has Terrain component" );
				return;
			}

			var existingMr = go.Components.Get<ModelRenderer>();
			if ( existingMr != null )
				existingMr.Destroy();

			var meshComp = go.Components.Get<MeshComponent>();
			if ( meshComp == null )
				meshComp = go.Components.Create<MeshComponent>();

			meshComp.Mesh = mesh;
		}

		// ── Material generation ───────────────────────────────────────────────

		private static Material GenerateOrLoadMaterial( MaterialDef def )
		{
			var safeName = System.Text.RegularExpressions.Regex.Replace(
				def.Name ?? "default", @"[^a-zA-Z0-9_\-]", "_" ).ToLower();
			var vmatRelPath = $"materials/blender_bridge/{safeName}.vmat";

			var assetsDir = GetProjectAssetsDir();
			if ( assetsDir == null ) return null;

			var bridgeMatDir = System.IO.Path.Combine( assetsDir, "materials", "blender_bridge" );
			System.IO.Directory.CreateDirectory( bridgeMatDir );

			var colorTexRef = CopyTextureToAssets( def.BaseColorTexture, safeName, "color", assetsDir );
			var roughTexRef = CopyTextureToAssets( def.RoughnessTexture, safeName, "rough", assetsDir );
			var metalTexRef = CopyTextureToAssets( def.MetallicTexture, safeName, "metal", assetsDir );
			var normalTexRef = CopyTextureToAssets( def.NormalTexture, safeName, "normal", assetsDir );

			var sb = new System.Text.StringBuilder();
			sb.AppendLine( "// AUTO-GENERATED BY BLENDER BRIDGE" );
			sb.AppendLine();
			sb.AppendLine( "Layer0" );
			sb.AppendLine( "{" );
			sb.AppendLine( "\tshader \"shaders/complex.shader\"" );
			sb.AppendLine();
			if ( metalTexRef != null ) sb.AppendLine( "\tF_METALNESS_TEXTURE 1" );
			sb.AppendLine( "\tF_SPECULAR 1" );
			sb.AppendLine();

			var r = def.BaseColor?.Length >= 3 ? def.BaseColor[0] : 0.8f;
			var g = def.BaseColor?.Length >= 3 ? def.BaseColor[1] : 0.8f;
			var b = def.BaseColor?.Length >= 3 ? def.BaseColor[2] : 0.8f;
			sb.AppendLine( $"\tg_flModelTintAmount \"1.000\"" );
			sb.AppendLine( $"\tg_vColorTint \"[{r:F6} {g:F6} {b:F6} 0.000000]\"" );
			if ( colorTexRef != null ) sb.AppendLine( $"\tTextureColor \"{colorTexRef}\"" );
			sb.AppendLine();
			sb.AppendLine( $"\tg_flMetalness \"{def.Metallic:F3}\"" );
			if ( metalTexRef != null ) sb.AppendLine( $"\tTextureMetalness \"{metalTexRef}\"" );
			sb.AppendLine();
			sb.AppendLine( $"\tg_flRoughnessScaleFactor \"{def.Roughness:F3}\"" );
			if ( roughTexRef != null ) sb.AppendLine( $"\tTextureRoughness \"{roughTexRef}\"" );
			sb.AppendLine();
			if ( normalTexRef != null ) { sb.AppendLine( $"\tTextureNormal \"{normalTexRef}\"" ); sb.AppendLine(); }
			if ( def.EmissionStrength > 0.001f )
			{
				var er = def.EmissionColor?.Length >= 3 ? def.EmissionColor[0] : 0f;
				var eg = def.EmissionColor?.Length >= 3 ? def.EmissionColor[1] : 0f;
				var eb = def.EmissionColor?.Length >= 3 ? def.EmissionColor[2] : 0f;
				sb.AppendLine( $"\tg_vSelfIllumTint \"[{er:F6} {eg:F6} {eb:F6} 0.000000]\"" );
				sb.AppendLine( $"\tg_flSelfIllumScale \"{def.EmissionStrength:F3}\"" );
				sb.AppendLine();
			}
			sb.AppendLine( "\tg_vTexCoordScale \"[1.000 1.000]\"" );
			sb.AppendLine( "\tg_vTexCoordOffset \"[0.000 0.000]\"" );
			sb.AppendLine( "}" );

			var vmatPath = System.IO.Path.Combine( assetsDir, vmatRelPath.Replace( "/", "\\" ) );
			System.IO.File.WriteAllText( vmatPath, sb.ToString() );

			// Register AND compile, otherwise Material.Load returns null on the
			// first call (no .vmat_c on disk yet) and we silently fall through
			// to the dev placeholder. Compile(false) is incremental and
			// synchronous — by the time it returns, the compiled resource
			// exists and Material.Load can resolve it. Re-registering an
			// already-known path is a no-op.
			try
			{
				var asset = AssetSystem.RegisterFile( vmatPath );
				asset?.Compile( full: false );
			}
			catch ( Exception ex )
			{
				BlenderBridgeServer.LogInfo( $"Vmat register/compile failed for {vmatPath}: {ex.Message}" );
			}

			return LoadMaterialSafe( vmatRelPath ) ?? LoadMaterialSafe( "materials/dev/reflectivity_30.vmat" );
		}

		private static string GenerateVmatPath( MaterialDef def )
		{
			var safeName = System.Text.RegularExpressions.Regex.Replace(
				def.Name ?? "default", @"[^a-zA-Z0-9_\-]", "_" ).ToLower();
			return $"materials/blender_bridge/{safeName}.vmat";
		}

		private static string CopyTextureToAssets( string srcPath, string matName, string suffix, string assetsDir )
		{
			if ( string.IsNullOrEmpty( srcPath ) || !System.IO.File.Exists( srcPath ) )
				return null;
			var ext = System.IO.Path.GetExtension( srcPath );
			var destName = $"{matName}_{suffix}{ext}";
			var destRelPath = $"materials/blender_bridge/{destName}";
			var destAbsPath = System.IO.Path.Combine( assetsDir, destRelPath.Replace( "/", "\\" ) );
			try
			{
				System.IO.File.Copy( srcPath, destAbsPath, overwrite: true );
				// Register + compile so the vmat that references this texture
				// can find a resolved .vtex_c on disk. Without compile, the
				// material loads but renders untextured.
				try
				{
					var asset = AssetSystem.RegisterFile( destAbsPath );
					asset?.Compile( full: false );
				}
				catch ( Exception cex )
				{
					BlenderBridgeServer.LogInfo( $"Texture register/compile failed for {destAbsPath}: {cex.Message}" );
				}
				return destRelPath;
			}
			catch ( Exception ex )
			{
				BlenderBridgeServer.LogInfo( $"Texture copy failed ({srcPath}): {ex.Message}" );
				return null;
			}
		}

		// ── Mesh parsing ──────────────────────────────────────────────────────

		private static ParsedMesh? ParseMeshData( JsonElement meshData )
		{
			if ( !meshData.TryGetProperty( "vertices", out var vertsEl ) ) return null;
			if ( !meshData.TryGetProperty( "faces", out var facesEl ) ) return null;

			var vertFloats = new List<float>();
			foreach ( var v in vertsEl.EnumerateArray() ) vertFloats.Add( v.GetSingle() );
			if ( vertFloats.Count < 9 ) return null;

			var vertCount = vertFloats.Count / 3;
			var vertices = new Vector3[vertCount];
			for ( int i = 0; i < vertCount; i++ )
				vertices[i] = new Vector3( vertFloats[i * 3], vertFloats[i * 3 + 1], vertFloats[i * 3 + 2] );

			var rawFaces = new List<int>();
			foreach ( var f in facesEl.EnumerateArray() ) rawFaces.Add( f.GetInt32() );

			var faceGroups = new List<int[]>();
			int idx = 0;
			while ( idx < rawFaces.Count )
			{
				int faceVertCount = rawFaces[idx++];
				if ( idx + faceVertCount > rawFaces.Count ) break;
				var face = new int[faceVertCount];
				for ( int i = 0; i < faceVertCount; i++ ) face[i] = rawFaces[idx++];
				faceGroups.Add( face );
			}

			int[] faceMaterials = null;
			if ( meshData.TryGetProperty( "faceMaterials", out var fmEl ) )
			{
				var fmList = new List<int>();
				foreach ( var fm in fmEl.EnumerateArray() ) fmList.Add( fm.GetInt32() );
				faceMaterials = fmList.ToArray();
			}

			List<MaterialDef> materials = null;
			if ( meshData.TryGetProperty( "materials", out var matsEl ) )
				materials = ParseMaterialDefs( matsEl );

			// Optional per-face-corner UVs. Flat [u,v,u,v,...] aligned with
			// faceGroups: face N's UVs are the next (face.Length) pairs.
			List<Vector2[]> faceUVs = null;
			if ( meshData.TryGetProperty( "faceUVs", out var uvEl ) )
			{
				var uvFloats = new List<float>();
				foreach ( var u in uvEl.EnumerateArray() ) uvFloats.Add( u.GetSingle() );
				faceUVs = new List<Vector2[]>( faceGroups.Count );
				int uvIdx = 0;
				foreach ( var face in faceGroups )
				{
					var uvs = new Vector2[face.Length];
					for ( int i = 0; i < face.Length && uvIdx + 1 < uvFloats.Count; i++ )
					{
						uvs[i] = new Vector2( uvFloats[uvIdx], uvFloats[uvIdx + 1] );
						uvIdx += 2;
					}
					faceUVs.Add( uvs );
				}
			}

			return new ParsedMesh
			{
				Vertices = vertices,
				FaceGroups = faceGroups,
				FaceMaterials = faceMaterials,
				Materials = materials,
				FaceUVs = faceUVs
			};
		}

		private static List<MaterialDef> ParseMaterialDefs( JsonElement matsEl )
		{
			var materials = new List<MaterialDef>();
			foreach ( var matEl in matsEl.EnumerateArray() )
			{
				var def = new MaterialDef
				{
					Name = matEl.TryGetProperty( "name", out var n ) ? n.GetString() : "default",
					Metallic = matEl.TryGetProperty( "metallic", out var met ) ? met.GetSingle() : 0f,
					Roughness = matEl.TryGetProperty( "roughness", out var rough ) ? rough.GetSingle() : 0.5f,
					NormalStrength = matEl.TryGetProperty( "normalStrength", out var ns ) ? ns.GetSingle() : 1f,
					EmissionStrength = matEl.TryGetProperty( "emissionStrength", out var es ) ? es.GetSingle() : 0f,
					BaseColorTexture = matEl.TryGetProperty( "baseColorTexture", out var bct ) && bct.ValueKind == JsonValueKind.String ? bct.GetString() : null,
					RoughnessTexture = matEl.TryGetProperty( "roughnessTexture", out var rt ) && rt.ValueKind == JsonValueKind.String ? rt.GetString() : null,
					MetallicTexture = matEl.TryGetProperty( "metallicTexture", out var mt ) && mt.ValueKind == JsonValueKind.String ? mt.GetString() : null,
					NormalTexture = matEl.TryGetProperty( "normalTexture", out var nt ) && nt.ValueKind == JsonValueKind.String ? nt.GetString() : null,
					VmatPath = matEl.TryGetProperty( "vmatPath", out var vp ) && vp.ValueKind == JsonValueKind.String ? vp.GetString() : null,
				};

				if ( matEl.TryGetProperty( "baseColor", out var bcEl ) && bcEl.ValueKind == JsonValueKind.Array )
				{
					var arr = new List<float>();
					foreach ( var c in bcEl.EnumerateArray() ) arr.Add( c.GetSingle() );
					def.BaseColor = arr.ToArray();
				}

				if ( matEl.TryGetProperty( "emissionColor", out var ecEl ) && ecEl.ValueKind == JsonValueKind.Array )
				{
					var arr = new List<float>();
					foreach ( var c in ecEl.EnumerateArray() ) arr.Add( c.GetSingle() );
					def.EmissionColor = arr.ToArray();
				}

				materials.Add( def );
			}
			return materials;
		}

		/// <summary>
		/// Compute a geometry hash that includes vertex positions,
		/// so moving/pulling vertices is detected as a change.
		/// </summary>
		private static int ComputeMeshGeometryHash( PolygonMesh mesh )
		{
			unchecked
			{
				int hash = 17;
				var vertHandles = mesh.VertexHandles;
				if ( vertHandles == null ) return 0;

				hash = hash * 31 + vertHandles.Count();

				var getPosMeth = mesh.GetType().GetMethod( "GetVertexPosition", new[] { typeof( VertexHandle ) } );
				if ( getPosMeth != null )
				{
					foreach ( var vh in vertHandles )
					{
						try
						{
							var result = getPosMeth.Invoke( mesh, new object[] { vh } );
							if ( result is Vector3 pos )
							{
								// Quantize to 0.001 precision to avoid float noise
								hash = hash * 31 + (int)( pos.x * 1000 );
								hash = hash * 31 + (int)( pos.y * 1000 );
								hash = hash * 31 + (int)( pos.z * 1000 );
							}
						}
						catch { break; }
					}
				}

				var faceHandles = mesh.FaceHandles;
				if ( faceHandles != null )
					hash = hash * 31 + faceHandles.Count();

				return hash;
			}
		}

		// ── Mesh extraction (s&box -> Blender) ────────────────────────────────

		internal struct ExtractedMesh
		{
			public float[] Vertices;
			public int[] Faces;
		}

		internal static ExtractedMesh? ExtractMeshData( PolygonMesh mesh )
		{
			try
			{
				var vertHandles = mesh.VertexHandles.ToList();
				if ( vertHandles.Count < 3 ) return null;

				var vertMap = new Dictionary<VertexHandle, int>();
				int vertIdx = 0;
				foreach ( var vh in vertHandles ) vertMap[vh] = vertIdx++;

				var verts = new List<float>();
				var getPosMeth = mesh.GetType().GetMethod( "GetVertexPosition", new[] { typeof( VertexHandle ) } );
				if ( getPosMeth != null )
				{
					foreach ( var vh in vertHandles )
					{
						try
						{
							var result = getPosMeth.Invoke( mesh, new object[] { vh } );
							if ( result is Vector3 pos )
							{
								verts.Add( pos.x );
								verts.Add( pos.y );
								verts.Add( pos.z );
							}
						}
						catch { break; }
					}
				}

				if ( verts.Count < 9 ) return null;

				var faces = new List<int>();
				var getFaceVertsMeth = mesh.GetType().GetMethod( "GetFaceVertices", new[] { typeof( FaceHandle ) } );
				if ( getFaceVertsMeth != null )
				{
					foreach ( var fh in mesh.FaceHandles )
					{
						var result = getFaceVertsMeth.Invoke( mesh, new object[] { fh } );
						if ( result is VertexHandle[] faceVerts )
						{
							faces.Add( faceVerts.Length );
							foreach ( var fv in faceVerts )
								faces.Add( vertMap.TryGetValue( fv, out var i ) ? i : 0 );
						}
						else if ( result is IEnumerable<VertexHandle> faceVertsEnum )
						{
							var fvList = faceVertsEnum.ToList();
							faces.Add( fvList.Count );
							foreach ( var fv in fvList )
								faces.Add( vertMap.TryGetValue( fv, out var i ) ? i : 0 );
						}
					}
				}

				if ( faces.Count == 0 ) return null;
				return new ExtractedMesh { Vertices = verts.ToArray(), Faces = faces.ToArray() };
			}
			catch ( Exception ex )
			{
				BlenderBridgeServer.LogError( $"ExtractMeshData failed: {ex.Message}" );
				return null;
			}
		}

		// ── Terrain proxy extraction (s&box -> Blender) ──────────────────────
		//
		// The Sandbox.Terrain component isn't a PolygonMesh — its data lives in
		// a TerrainStorage with a Resolution² ushort[] heightmap. Sending the
		// full heightmap to Blender is impractical (a 1024² terrain = 1M verts),
		// so we downsample to a fixed PROXY_RESOLUTION grid for a low-poly
		// reference mesh in mesh-local space. Triangulation: each cell is a
		// quad face (the wire format already supports n-gons).

		private const int TerrainProxyResolution = 128;

		internal static ExtractedMesh? ExtractTerrainProxyMesh( Terrain terrain )
		{
			try
			{
				var storage = terrain?.Storage;
				if ( storage == null ) return null;
				if ( storage.HeightMap == null || storage.HeightMap.Length == 0 ) return null;

				int srcRes = storage.Resolution;
				if ( srcRes <= 0 || storage.HeightMap.Length < srcRes * srcRes ) return null;

				int proxyRes = Math.Min( TerrainProxyResolution, srcRes );
				int vertsPerSide = proxyRes + 1;

				float terrainSize = storage.TerrainSize;
				float terrainHeight = storage.TerrainHeight;
				float cellSize = terrainSize / proxyRes;
				float invMaxHeight = 1.0f / 65535f;

				var verts = new float[vertsPerSide * vertsPerSide * 3];
				for ( int gy = 0; gy < vertsPerSide; gy++ )
				{
					int srcY = (int)((long)gy * (srcRes - 1) / proxyRes);
					for ( int gx = 0; gx < vertsPerSide; gx++ )
					{
						int srcX = (int)((long)gx * (srcRes - 1) / proxyRes);
						ushort h = storage.HeightMap[srcY * srcRes + srcX];

						int vi = (gy * vertsPerSide + gx) * 3;
						verts[vi + 0] = gx * cellSize;
						verts[vi + 1] = gy * cellSize;
						verts[vi + 2] = h * invMaxHeight * terrainHeight;
					}
				}

				// Faces: one quad per cell, [4, v00, v10, v11, v01].
				var faces = new int[proxyRes * proxyRes * 5];
				int fi = 0;
				for ( int gy = 0; gy < proxyRes; gy++ )
				{
					int row0 = gy * vertsPerSide;
					int row1 = (gy + 1) * vertsPerSide;
					for ( int gx = 0; gx < proxyRes; gx++ )
					{
						faces[fi++] = 4;
						faces[fi++] = row0 + gx;
						faces[fi++] = row0 + gx + 1;
						faces[fi++] = row1 + gx + 1;
						faces[fi++] = row1 + gx;
					}
				}

				return new ExtractedMesh { Vertices = verts, Faces = faces };
			}
			catch ( Exception ex )
			{
				BlenderBridgeServer.LogError( $"ExtractTerrainProxyMesh failed: {ex.Message}" );
				return null;
			}
		}

		/// <summary>
		/// Pulls mesh data out of either a MeshComponent or (as a downsampled
		/// proxy) a Terrain. Used by the payload builders so terrain shows up
		/// in Blender alongside regular meshes.
		/// </summary>
		private static object TryBuildMeshData( GameObject go )
		{
			var meshComp = go.Components.Get<MeshComponent>();
			if ( meshComp?.Mesh != null )
			{
				var extracted = ExtractMeshData( meshComp.Mesh );
				if ( extracted != null )
					return new { vertices = extracted.Value.Vertices, faces = extracted.Value.Faces };
			}

			var terrain = go.Components.Get<Terrain>();
			if ( terrain?.Storage != null )
			{
				var extracted = ExtractTerrainProxyMesh( terrain );
				if ( extracted != null )
					return new { vertices = extracted.Value.Vertices, faces = extracted.Value.Faces };
			}

			return null;
		}

		// ── Payload builders ──────────────────────────────────────────────────

		/// <summary>Public access to BuildObjectPayload for the editor window's Send to Blender button.</summary>
		internal static object BuildObjectPayloadPublic( string bridgeId, GameObject go )
		{
			return BuildObjectPayload( bridgeId, go );
		}

		/// <summary>Build a complete object_created message with type field for broadcasting.</summary>
		internal static object BuildObjectCreatedMessage( string bridgeId, GameObject go )
		{
			var pos = go.WorldPosition;
			var rot = go.WorldRotation.Angles();
			var meshData = TryBuildMeshData( go );

			return new
			{
				type = "object_created",
				bridgeId,
				name = go.Name,
				position = new { x = pos.x, y = pos.y, z = pos.z },
				rotation = new { pitch = rot.pitch, yaw = rot.yaw, roll = rot.roll },
				meshData
			};
		}

		private static object BuildObjectPayload( string bridgeId, GameObject go )
		{
			var pos = go.WorldPosition;
			var rot = go.WorldRotation.Angles();
			var meshData = TryBuildMeshData( go );

			// Build hierarchy path from parent chain (excluding bridge group root)
			var hierarchy = new List<string>();
			var parent = go.Parent;
			while ( parent != null && !parent.Tags.Has( "bridge_group" ) )
			{
				hierarchy.Insert( 0, parent.Name );
				parent = parent.Parent;
			}

			return new
			{
				bridgeId,
				name = go.Name,
				position = new { x = pos.x, y = pos.y, z = pos.z },
				rotation = new { pitch = rot.pitch, yaw = rot.yaw, roll = rot.roll },
				meshData,
				hierarchy
			};
		}

		private static object BuildLightPayload( GameObject go, Light light )
		{
			var pos = go.WorldPosition;
			var rot = go.WorldRotation.Angles();
			string lightType = "point";
			if ( light is SpotLight ) lightType = "spot";
			else if ( light is DirectionalLight ) lightType = "directional";

			float radius = 0f;
			float coneOuter = 0f;
			float coneInner = 0f;
			if ( light is PointLight pl ) radius = pl.Radius;
			if ( light is SpotLight spl ) { radius = spl.Radius; coneOuter = spl.ConeOuter; coneInner = spl.ConeInner; }

			object properties = new
			{
				color = new { r = light.LightColor.r, g = light.LightColor.g, b = light.LightColor.b },
				radius,
				coneOuter,
				coneInner,
			};

			return new
			{
				objectType = "light",
				lightType,
				name = go.Name,
				sceneId = go.Id.ToString(),
				position = new { x = pos.x, y = pos.y, z = pos.z },
				rotation = new { pitch = rot.pitch, yaw = rot.yaw, roll = rot.roll },
				properties
			};
		}

		private static object BuildModelPayload( GameObject go, Component modelComp )
		{
			var pos = go.WorldPosition;
			var rot = go.WorldRotation.Angles();
			var modelProp = modelComp.GetType().GetProperty( "Model" );
			var model = modelProp?.GetValue( modelComp ) as Model;
			var modelPath = model?.ResourcePath ?? "unknown";

			object bounds = null;
			if ( model != null )
			{
				try
				{
					bounds = new
					{
						mins = new { x = model.Bounds.Mins.x, y = model.Bounds.Mins.y, z = model.Bounds.Mins.z },
						maxs = new { x = model.Bounds.Maxs.x, y = model.Bounds.Maxs.y, z = model.Bounds.Maxs.z }
					};
				}
				catch { }
			}

			string fbxSourcePath = null;
			try
			{
				if ( modelPath != "unknown" )
					fbxSourcePath = ResolveFbxPath( modelPath );
			}
			catch { }

			return new
			{
				objectType = "model",
				name = go.Name,
				sceneId = go.Id.ToString(),
				modelPath,
				fbxSourcePath,
				bounds,
				position = new { x = pos.x, y = pos.y, z = pos.z },
				rotation = new { pitch = rot.pitch, yaw = rot.yaw, roll = rot.roll }
			};
		}

		private static string ResolveFbxPath( string modelPath )
		{
			try
			{
				var assetsDir = GetProjectAssetsDir();
				if ( assetsDir == null ) return null;
				var projectRoot = System.IO.Path.GetDirectoryName( assetsDir );
				var basePaths = new List<string> { assetsDir, projectRoot };
				var relativePath = modelPath.Replace( "\\", "/" );
				foreach ( var prefix in new[] { "assets/", "models/" } )
					if ( relativePath.StartsWith( prefix, StringComparison.OrdinalIgnoreCase ) )
					{ relativePath = relativePath.Substring( prefix.Length ); break; }

				string vmdlPath = null;
				string vmdlDir = null;
				foreach ( var basePath in basePaths )
				{
					if ( string.IsNullOrEmpty( basePath ) ) continue;
					var candidate = System.IO.Path.Combine( basePath, relativePath );
					if ( System.IO.File.Exists( candidate ) ) { vmdlPath = candidate; vmdlDir = System.IO.Path.GetDirectoryName( candidate ); break; }
					candidate = System.IO.Path.Combine( basePath, modelPath.Replace( "/", "\\" ) );
					if ( System.IO.File.Exists( candidate ) ) { vmdlPath = candidate; vmdlDir = System.IO.Path.GetDirectoryName( candidate ); break; }
				}
				if ( vmdlPath == null ) return null;

				var content = System.IO.File.ReadAllText( vmdlPath );
				var match = System.Text.RegularExpressions.Regex.Match( content,
					@"_class\s*=\s*""RenderMeshFile""[\s\S]*?filename\s*=\s*""([^""]+)""" );
				if ( !match.Success ) return null;

				var fbxRelative = match.Groups[1].Value.Replace( "\\", "/" );
				var fbxPath = System.IO.Path.GetFullPath( System.IO.Path.Combine( vmdlDir, fbxRelative ) );
				if ( System.IO.File.Exists( fbxPath ) ) return fbxPath;
				foreach ( var basePath in basePaths )
				{
					if ( string.IsNullOrEmpty( basePath ) ) continue;
					fbxPath = System.IO.Path.GetFullPath( System.IO.Path.Combine( basePath, fbxRelative ) );
					if ( System.IO.File.Exists( fbxPath ) ) return fbxPath;
				}
				return null;
			}
			catch { return null; }
		}

		// ── Helpers ───────────────────────────────────────────────────────────

		private static void ApplyTransform( GameObject go, JsonElement root )
		{
			if ( root.TryGetProperty( "position", out var pos ) )
			{
				go.WorldPosition = new Vector3(
					GetFloat( pos, "x", 0f ),
					GetFloat( pos, "y", 0f ),
					GetFloat( pos, "z", 0f )
				);
			}
			if ( root.TryGetProperty( "rotation", out var rot ) )
			{
				go.WorldRotation = Rotation.From(
					GetFloat( rot, "pitch", 0f ),
					GetFloat( rot, "yaw", 0f ),
					GetFloat( rot, "roll", 0f )
				);
			}
		}

		private static string GetString( JsonElement el, string prop, string fallback = null )
		{
			return el.TryGetProperty( prop, out var v ) && v.ValueKind == JsonValueKind.String ? v.GetString() : fallback;
		}

		private static float GetFloat( JsonElement el, string prop, float fallback )
		{
			if ( el.TryGetProperty( prop, out var v ) && v.ValueKind == JsonValueKind.Number ) return v.GetSingle();
			return fallback;
		}

		private static int GetInt( JsonElement el, string prop, int fallback )
		{
			if ( el.TryGetProperty( prop, out var v ) && v.ValueKind == JsonValueKind.Number ) return v.GetInt32();
			return fallback;
		}

		internal static string GetProjectAssetsDir()
		{
			try
			{
				var session = SceneEditorSession.Active;
				if ( session?.Scene != null )
				{
					var scenePath = session.Scene.Source?.ResourcePath;
					if ( !string.IsNullOrEmpty( scenePath ) )
					{
						var fullScenePath = Sandbox.FileSystem.Mounted.GetFullPath( scenePath );
						if ( !string.IsNullOrEmpty( fullScenePath ) )
						{
							var dir = System.IO.Path.GetDirectoryName( fullScenePath );
							while ( dir != null )
							{
								var candidate = System.IO.Path.Combine( dir, "Assets" );
								if ( System.IO.Directory.Exists( candidate ) ) return candidate;
								dir = System.IO.Path.GetDirectoryName( dir );
							}
						}
					}
				}
			}
			catch { }

			try
			{
				var sboxProjectsDir = System.IO.Path.Combine(
					System.Environment.GetFolderPath( System.Environment.SpecialFolder.MyDocuments ), "s&box projects" );
				if ( System.IO.Directory.Exists( sboxProjectsDir ) )
				{
					foreach ( var projDir in System.IO.Directory.GetDirectories( sboxProjectsDir ) )
					{
						var libDir = System.IO.Path.Combine( projDir, "Libraries", "ozmium.oz_mcp" );
						if ( System.IO.Directory.Exists( libDir ) )
						{
							var assetsCandidate = System.IO.Path.Combine( projDir, "Assets" );
							if ( System.IO.Directory.Exists( assetsCandidate ) ) return assetsCandidate;
						}
					}
				}
			}
			catch { }

			return null;
		}

		private static Material LoadMaterialSafe( string path )
		{
			if ( string.IsNullOrEmpty( path ) ) return null;
			try { return Material.Load( path ); }
			catch { return null; }
		}
	}
}
