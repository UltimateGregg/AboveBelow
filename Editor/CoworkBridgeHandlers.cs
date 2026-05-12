using System.Reflection;
using System.Text.Json;

namespace DroneVsPlayers.Editor;

/// <summary>
/// Endpoint implementations for CoworkBridge. Each handler runs on the editor
/// thread, so SceneEditorSession.Active is safe to access. Handlers return
/// plain CLR objects which CoworkBridge serializes to JSON.
/// </summary>
internal static class CoworkBridgeHandlers
{
	// ----- Read-only -----

	public static object Ping() => new
	{
		ok = true,
		message = "cowork bridge alive",
		editor_version = "sbox-dev",
		time = DateTime.UtcNow.ToString( "o" ),
	};

	public static object SceneInfo()
	{
		var session = SceneEditorSession.Active;
		if ( session is null )
			return new { error = "no active scene editor session" };

		var scene = session.Scene;
		var rootCount = scene?.GetAllObjects( false )?.Count() ?? 0;

		return new
		{
			ok = true,
			scene_name = scene?.Name ?? "(unnamed)",
			scene_guid = scene?.Id.ToString() ?? "",
			is_prefab_scene = scene is PrefabScene,
			root_object_count = rootCount,
		};
	}

	public static object SceneTree()
	{
		var session = SceneEditorSession.Active;
		if ( session?.Scene is null ) return new { error = "no scene" };

		var roots = session.Scene.Children
			.Select( SerializeNode )
			.ToList();

		return new { ok = true, roots };
	}

	public static object SceneOpen( Dictionary<string, JsonElement> args )
	{
		if ( !args.TryGetValue( "path", out var pEl ) )
			return new { error = "missing path" };

		var rawPath = pEl.GetString();
		if ( string.IsNullOrWhiteSpace( rawPath ) )
			return new { error = "path is empty" };

		var normalizedPath = NormalizeAssetPath( rawPath );
		var extension = System.IO.Path.GetExtension( normalizedPath );
		if ( !string.Equals( extension, ".scene", StringComparison.OrdinalIgnoreCase ) &&
		     !string.Equals( extension, ".prefab", StringComparison.OrdinalIgnoreCase ) )
		{
			return new { error = "path must point to a .scene or .prefab asset" };
		}

		var diskPath = ResolveProjectAssetDiskPath( normalizedPath );
		if ( diskPath is not null && !System.IO.File.Exists( diskPath ) )
			return new { error = "asset file not found", path = rawPath, resolved_disk_path = diskPath };

		var attempts = new List<object>();
		Exception lastError = null;
		foreach ( var candidate in GetSceneOpenCandidates( normalizedPath ) )
		{
			try
			{
				CreateSceneEditorSessionFromPath( candidate );

				var session = SceneEditorSession.Active;
				var scene = session?.Scene;
				var sourcePath = NormalizeAssetPath( scene?.Source?.ResourcePath ?? "" );
				if ( !SceneSourceMatches( sourcePath, candidate, normalizedPath ) )
				{
					attempts.Add( new
					{
						path = candidate,
						error = string.IsNullOrWhiteSpace( sourcePath )
							? "editor did not report an active source path"
							: $"editor stayed on '{sourcePath}'",
					} );
					continue;
				}

				return new
				{
					ok = true,
					path = rawPath,
					opened_path = candidate,
					source_path = sourcePath,
					asset_kind = extension.Equals( ".prefab", StringComparison.OrdinalIgnoreCase ) ? "prefab" : "scene",
					scene_name = scene?.Name ?? "",
					scene_guid = scene?.Id.ToString() ?? "",
					is_prefab_scene = scene is PrefabScene,
				};
			}
			catch ( Exception e )
			{
				lastError = e;
				attempts.Add( new { path = candidate, error = e.Message } );
			}
		}

		return new
		{
			error = "open failed: " + (lastError?.Message ?? "unknown error"),
			path = rawPath,
			attempts,
		};
	}

	public static object GameObjectGet( Dictionary<string, JsonElement> args )
	{
		var go = ResolveGameObject( args );
		if ( go is null ) return new { error = "gameobject not found" };

		var components = go.Components.GetAll().Select( c => new
		{
			type = c.GetType().FullName,
			guid = c.Id.ToString(),
			enabled = c.Enabled,
			properties = ListProperties( c ),
		} ).ToList();

		return new
		{
			ok = true,
			guid = go.Id.ToString(),
			name = go.Name,
			enabled = go.Enabled,
			parent_guid = go.Parent?.Id.ToString(),
			position = Vec3( go.LocalPosition ),
			rotation_euler = Vec3( go.LocalRotation.Angles().AsVector3() ),
			scale = Vec3( go.LocalScale ),
			children_guids = go.Children.Select( c => c.Id.ToString() ).ToList(),
			components,
		};
	}

	// ----- Selection / view -----

	public static object GameObjectSelect( Dictionary<string, JsonElement> args )
	{
		var session = SceneEditorSession.Active;
		if ( session is null ) return new { error = "no session" };

		var go = ResolveGameObject( args );
		if ( go is null ) return new { error = "gameobject not found" };

		session.Selection.Clear();
		session.Selection.Add( go );
		return new { ok = true, selected = go.Id.ToString() };
	}

	// ----- Mutation -----

	public static object SceneSave()
	{
		var session = SceneEditorSession.Active;
		if ( session is null ) return new { error = "no session" };

		try
		{
			// SceneEditorSession.Save(bool saveAs). Pass false to save in place,
			// true to prompt for a new path.
			session.Save( false );
			return new { ok = true, saved = session.Scene?.Name };
		}
		catch ( Exception e )
		{
			return new { error = "save failed: " + e.Message };
		}
	}

	public static object ComponentSetProperty( Dictionary<string, JsonElement> args )
	{
		// Args: { component_guid: "...", property_name: "...", value: <json> }
		if ( !args.TryGetValue( "component_guid", out var gEl ) ||
		     !args.TryGetValue( "property_name", out var nEl ) ||
		     !args.TryGetValue( "value", out var vEl ) )
			return new { error = "missing component_guid / property_name / value" };

		var componentGuid = Guid.Parse( gEl.GetString() );
		var propName = nEl.GetString();

		var component = FindComponent( componentGuid );
		if ( component is null ) return new { error = "component not found" };

		var prop = component.GetType().GetProperty( propName,
			BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase );
		if ( prop is null || !prop.CanWrite ) return new { error = $"no writable property '{propName}'" };

		try
		{
			var converted = ConvertJsonToType( vEl, prop.PropertyType );
			using ( SceneEditorSession.Active.UndoScope( $"Set {propName}" ).WithComponentChanges( component ).Push() )
			{
				prop.SetValue( component, converted );
			}
			return new { ok = true, property = propName, value_type = prop.PropertyType.FullName };
		}
		catch ( Exception e )
		{
			return new { error = "set failed: " + e.Message };
		}
	}

	public static object ComponentWireReference( Dictionary<string, JsonElement> args )
	{
		// The high-value tool: wire a GameObject or Component reference on a component.
		// Args: { component_guid, property_name, target_guid, target_kind: "gameobject"|"component" }
		if ( !args.TryGetValue( "component_guid", out var cgEl ) ||
		     !args.TryGetValue( "property_name", out var pnEl ) ||
		     !args.TryGetValue( "target_guid", out var tgEl ) )
			return new { error = "missing component_guid / property_name / target_guid" };

		var componentGuid = Guid.Parse( cgEl.GetString() );
		var propName = pnEl.GetString();
		var targetGuid = Guid.Parse( tgEl.GetString() );
		var kind = args.TryGetValue( "target_kind", out var kEl ) ? kEl.GetString() : "gameobject";

		var component = FindComponent( componentGuid );
		if ( component is null ) return new { error = "component not found" };

		var prop = component.GetType().GetProperty( propName,
			BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase );
		if ( prop is null || !prop.CanWrite ) return new { error = $"no writable property '{propName}'" };

		object value = kind switch
		{
			"gameobject" => SceneEditorSession.Active.Scene.Directory.FindByGuid( targetGuid ),
			"component" => FindComponent( targetGuid ),
			_ => null,
		};
		if ( value is null ) return new { error = "target not found" };

		try
		{
			using ( SceneEditorSession.Active.UndoScope( $"Wire {propName}" ).WithComponentChanges( component ).Push() )
			{
				prop.SetValue( component, value );
			}
			return new { ok = true, wired = propName, target = targetGuid.ToString() };
		}
		catch ( Exception e )
		{
			return new { error = "wire failed: " + e.Message };
		}
	}

	public static object ConsoleLog( Dictionary<string, JsonElement> args )
	{
		var msg = args.TryGetValue( "message", out var mEl ) ? mEl.GetString() : "(empty)";
		var level = args.TryGetValue( "level", out var lEl ) ? lEl.GetString() : "info";
		switch ( level?.ToLowerInvariant() )
		{
			case "warn": case "warning": Log.Warning( msg ); break;
			case "error": Log.Error( msg ); break;
			default: Log.Info( msg ); break;
		}
		return new { ok = true };
	}

	// ----- Helpers -----

	static GameObject ResolveGameObject( Dictionary<string, JsonElement> args )
	{
		var session = SceneEditorSession.Active;
		if ( session?.Scene is null ) return null;

		if ( args.TryGetValue( "guid", out var g ) )
		{
			if ( Guid.TryParse( g.GetString(), out var guid ) )
				return session.Scene.Directory.FindByGuid( guid );
		}
		if ( args.TryGetValue( "name", out var n ) )
		{
			var name = n.GetString();
			return session.Scene.GetAllObjects( false ).FirstOrDefault( o => o.Name == name );
		}
		return null;
	}

	static string NormalizeAssetPath( string path )
	{
		var normalized = path.Trim().Trim( '"' ).Replace( '\\', '/' );
		if ( !System.IO.Path.IsPathRooted( normalized ) )
			normalized = normalized.TrimStart( '/' );
		return normalized.TrimEnd( '/' );
	}

	static IEnumerable<string> GetSceneOpenCandidates( string normalizedPath )
	{
		var candidates = new List<string>();

		if ( System.IO.Path.IsPathRooted( normalizedPath ) )
		{
			var rootPath = Project.Current?.GetRootPath();
			if ( !string.IsNullOrWhiteSpace( rootPath ) )
			{
				var root = NormalizeAssetPath( rootPath );
				if ( normalizedPath.StartsWith( root + "/", StringComparison.OrdinalIgnoreCase ) )
				{
					var projectRelative = normalizedPath.Substring( root.Length + 1 );
					if ( projectRelative.StartsWith( "Assets/", StringComparison.OrdinalIgnoreCase ) )
						candidates.Add( projectRelative.Substring( "Assets/".Length ) );
					candidates.Add( projectRelative );
				}
			}
			candidates.Add( normalizedPath );
		}
		else if ( normalizedPath.StartsWith( "Assets/", StringComparison.OrdinalIgnoreCase ) )
		{
			candidates.Add( normalizedPath.Substring( "Assets/".Length ) );
			candidates.Add( normalizedPath );
		}
		else
		{
			candidates.Add( normalizedPath );
			candidates.Add( "Assets/" + normalizedPath );
		}

		return candidates
			.Where( c => !string.IsNullOrWhiteSpace( c ) )
			.Distinct( StringComparer.OrdinalIgnoreCase );
	}

	static bool SceneSourceMatches( string activeSourcePath, string openedPath, string requestedPath )
	{
		if ( string.IsNullOrWhiteSpace( activeSourcePath ) )
			return false;

		var source = StripAssetsPrefix( activeSourcePath );
		return string.Equals( source, StripAssetsPrefix( openedPath ), StringComparison.OrdinalIgnoreCase ) ||
		       string.Equals( source, StripAssetsPrefix( requestedPath ), StringComparison.OrdinalIgnoreCase );
	}

	static string StripAssetsPrefix( string path )
	{
		var normalized = NormalizeAssetPath( path );
		return normalized.StartsWith( "Assets/", StringComparison.OrdinalIgnoreCase )
			? normalized.Substring( "Assets/".Length )
			: normalized;
	}

	static string ResolveProjectAssetDiskPath( string normalizedPath )
	{
		if ( System.IO.Path.IsPathRooted( normalizedPath ) )
			return normalizedPath;

		var assetsPath = Project.Current?.GetAssetsPath();
		if ( string.IsNullOrWhiteSpace( assetsPath ) ) return null;

		var relativePath = normalizedPath;
		if ( normalizedPath.StartsWith( "Assets/", StringComparison.OrdinalIgnoreCase ) )
		{
			var rootPath = Project.Current?.GetRootPath();
			if ( !string.IsNullOrWhiteSpace( rootPath ) )
				return System.IO.Path.Combine( rootPath, normalizedPath.Replace( '/', System.IO.Path.DirectorySeparatorChar ) );

			relativePath = normalizedPath.Substring( "Assets/".Length );
		}

		return System.IO.Path.Combine( assetsPath, relativePath.Replace( '/', System.IO.Path.DirectorySeparatorChar ) );
	}

	static void CreateSceneEditorSessionFromPath( string path )
	{
		var method = typeof( SceneEditorSession ).GetMethod( "CreateFromPath", BindingFlags.Public | BindingFlags.Static );
		if ( method is null )
			throw new MissingMethodException( nameof( SceneEditorSession ), "CreateFromPath" );

		try
		{
			method.Invoke( null, new object[] { path } );
		}
		catch ( TargetInvocationException e ) when ( e.InnerException is not null )
		{
			throw e.InnerException;
		}
	}

	static Component FindComponent( Guid guid )
	{
		var scene = SceneEditorSession.Active?.Scene;
		if ( scene is null ) return null;
		foreach ( var go in scene.GetAllObjects( true ) )
		{
			foreach ( var c in go.Components.GetAll() )
				if ( c.Id == guid ) return c;
		}
		return null;
	}

	static object SerializeNode( GameObject go )
	{
		return new
		{
			guid = go.Id.ToString(),
			name = go.Name,
			enabled = go.Enabled,
			component_types = go.Components.GetAll().Select( c => c.GetType().FullName ).ToList(),
			children = go.Children.Select( SerializeNode ).ToList(),
		};
	}

	static object[] Vec3( Vector3 v ) => new object[] { v.x, v.y, v.z };

	static IEnumerable<object> ListProperties( Component c )
	{
		// Only PropertyAttribute-marked or simple gettable properties. Avoid
		// dumping the whole reflective surface to keep responses small.
		return c.GetType()
			.GetProperties( BindingFlags.Public | BindingFlags.Instance )
			.Where( p => p.CanRead && p.GetCustomAttribute<PropertyAttribute>() != null )
			.Select( p =>
			{
				object val = null;
				try { val = p.GetValue( c ); } catch { }
				return new
				{
					name = p.Name,
					type = p.PropertyType.FullName,
					value = SafeStringify( val ),
				} as object;
			} );
	}

	static string SafeStringify( object v )
	{
		if ( v is null ) return null;
		if ( v is GameObject go ) return $"GameObject:{go.Id}:{go.Name}";
		if ( v is Component co ) return $"Component:{co.GetType().Name}:{co.Id}";
		if ( v is Vector3 vec ) return $"{vec.x},{vec.y},{vec.z}";
		if ( v is Rotation rot ) return rot.Angles().ToString();
		return v.ToString();
	}

	static object ConvertJsonToType( JsonElement el, Type t )
	{
		if ( t == typeof( string ) ) return el.GetString();
		if ( t == typeof( int ) ) return el.GetInt32();
		if ( t == typeof( long ) ) return el.GetInt64();
		if ( t == typeof( float ) ) return (float)el.GetDouble();
		if ( t == typeof( double ) ) return el.GetDouble();
		if ( t == typeof( bool ) ) return el.GetBoolean();
		if ( t == typeof( Vector3 ) )
		{
			// Accept either "x,y,z" string or array [x,y,z]
			if ( el.ValueKind == JsonValueKind.String )
			{
				var parts = el.GetString().Split( ',' );
				return new Vector3( float.Parse( parts[0] ), float.Parse( parts[1] ), float.Parse( parts[2] ) );
			}
			if ( el.ValueKind == JsonValueKind.Array )
			{
				var arr = el.EnumerateArray().ToArray();
				return new Vector3( (float)arr[0].GetDouble(), (float)arr[1].GetDouble(), (float)arr[2].GetDouble() );
			}
		}
		if ( t.IsEnum ) return Enum.Parse( t, el.GetString(), true );
		// Fallback: deserialize directly
		return JsonSerializer.Deserialize( el.GetRawText(), t );
	}
}
