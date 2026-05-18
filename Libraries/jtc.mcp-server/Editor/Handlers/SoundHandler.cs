using Sandbox;
using SboxMcp;

namespace SboxMcp.Handlers;

/// <summary>
/// Native editor sound operations for MCP: inspect local SoundEvent wrappers,
/// preview audio, place point emitters, and discover SoundEvent component hooks.
/// </summary>
public static class SoundHandler
{
	public static Task<object> ListSounds( HandlerRequest request )
	{
		var query = GetParamOptional( request, "query" ) ?? "";
		var sounds = BuildSoundInventory( query );

		return Task.FromResult<object>( (object)new
		{
			count = sounds.Count,
			sounds,
		} );
	}

	public static Task<object> InspectSound( HandlerRequest request )
	{
		var sound = GetParam( request, "sound" );
		var resourcePath = NormalizeSoundResourcePath( sound );
		var fullPath = ResolveProjectResourcePath( resourcePath );
		if ( fullPath is not null && File.Exists( fullPath ) )
			return Task.FromResult<object>( ReadSoundMetadata( fullPath ) );

		var mountedSound = ResourceLibrary.Get<SoundEvent>( resourcePath );
		if ( mountedSound is null )
			throw new FileNotFoundException( $"SoundEvent not found: {resourcePath}" );

		return Task.FromResult<object>( (object)new
		{
			path = resourcePath,
			name = Path.GetFileNameWithoutExtension( resourcePath ),
			local = false,
			mounted = true,
			loaded = true,
			ui = false,
			volume = "",
			pitch = "",
			decibels = 0,
			selectionMode = "",
			occlusion = false,
			distanceAttenuation = false,
			distance = 0f,
			sourceCount = 0,
			sources = Array.Empty<string>(),
			missingSources = Array.Empty<string>(),
		} );
	}

	public static Task<object> CreateSoundEvent( HandlerRequest request )
	{
		var name = GetParam( request, "name" );
		var sources = GetStringArrayParam( request, "sources" );
		if ( sources.Count == 0 )
			throw new ArgumentException( "Provide at least one source audio path." );

		var directory = GetParamOptional( request, "directory" ) ?? "sounds";
		directory = directory.Trim().Replace( '\\', '/' ).Trim( '/' );
		if ( !directory.StartsWith( "sounds", StringComparison.OrdinalIgnoreCase ) )
			directory = $"sounds/{directory}";
		var fileName = name.EndsWith( ".sound", StringComparison.OrdinalIgnoreCase ) ? name : $"{name}.sound";
		var resourcePath = NormalizeSoundResourcePath( $"{directory}/{fileName}" );
		var fullPath = ResolveProjectResourcePath( resourcePath )
			?? throw new InvalidOperationException( $"Could not resolve output path: {resourcePath}" );

		if ( File.Exists( fullPath ) )
			throw new IOException( $"SoundEvent already exists: {resourcePath}" );

		foreach ( var source in sources )
		{
			var resolved = ResolveProjectResourcePath( NormalizeAudioResourcePath( source ) );
			if ( resolved is null || !File.Exists( resolved ) )
				throw new FileNotFoundException( $"Source audio not found: {source}" );
		}

		Directory.CreateDirectory( Path.GetDirectoryName( fullPath )! );
		var ui = GetBoolParam( request, "ui", false );
		var volume = GetStringParam( request, "volume", "1" );
		var pitch = GetStringParam( request, "pitch", "1" );
		var distance = GetFloatParam( request, "distance", ui ? 0f : 1500f );
		var decibels = GetIntParam( request, "decibels", ui ? 50 : 62 );

		var data = new Dictionary<string, object>
		{
			["UI"] = ui,
			["Volume"] = volume,
			["Pitch"] = pitch,
			["Decibels"] = decibels,
			["SelectionMode"] = sources.Count > 1 ? "Random" : "Random",
			["Sounds"] = sources.Select( NormalizeAudioResourcePath ).ToArray(),
			["Occlusion"] = !ui,
			["Reflections"] = false,
			["AirAbsorption"] = !ui,
			["Transmission"] = false,
			["OcclusionRadius"] = ui ? 0 : 32,
			["DistanceAttenuation"] = !ui,
			["Distance"] = distance,
			["DefaultMixer"] = new Dictionary<string, object>
			{
				["Name"] = "unknown",
				["Id"] = "00000000-0000-0000-0000-000000000000",
			},
			["__references"] = Array.Empty<object>(),
			["__version"] = 1,
		};

		File.WriteAllText( fullPath, JsonSerializer.Serialize( data, new JsonSerializerOptions { WriteIndented = true } ) );
		Log.Info( $"[MCP] sound.create_event '{resourcePath}'" );
		return Task.FromResult<object>( (object)new
		{
			created = true,
			path = resourcePath,
			sourceCount = sources.Count,
		} );
	}

	public static Task<object> PreviewSound( HandlerRequest request )
	{
		var sound = NormalizeSoundResourcePath( GetParam( request, "sound" ) );
		var soundEvent = ResourceLibrary.Get<SoundEvent>( sound );
		if ( soundEvent is null )
			throw new InvalidOperationException( $"Could not load SoundEvent: {sound}" );

		var objectId = GetParamOptional( request, "objectId" );
		var positionText = GetParamOptional( request, "position" );
		var fadeIn = GetFloatParam( request, "fadeIn", 0f );
		var volume = GetFloatParam( request, "volume", 1f );
		var followObject = GetBoolParam( request, "followObject", false );

		GameObject target = null;
		if ( !string.IsNullOrWhiteSpace( objectId ) )
		{
			if ( !Guid.TryParse( objectId, out var guid ) )
				throw new ArgumentException( $"Invalid objectId: {objectId}" );
			target = SceneHandler.FindObjectById( guid )
				?? throw new KeyNotFoundException( $"GameObject not found: {objectId}" );
		}

		SoundHandle handle;
		if ( target is not null )
		{
			handle = Sound.Play( soundEvent, target.WorldPosition, fadeIn );
			if ( followObject )
			{
				handle.Parent = target;
				handle.FollowParent = true;
			}
		}
		else if ( !string.IsNullOrWhiteSpace( positionText ) )
		{
			handle = Sound.Play( soundEvent, SceneHandler.ParseVector3( positionText ), fadeIn );
		}
		else
		{
			handle = Sound.Play( soundEvent, fadeIn );
		}

		if ( handle is not null && handle.IsValid )
			handle.Volume = volume;

		Log.Info( $"[MCP] sound.preview '{sound}'" );
		return Task.FromResult<object>( (object)new
		{
			played = true,
			sound,
			target = target?.Name ?? "",
			followObject,
			volume,
		} );
	}

	public static Task<object> PlaceSoundPoint( HandlerRequest request )
	{
		var sound = NormalizeSoundResourcePath( GetParam( request, "sound" ) );
		var soundEvent = ResourceLibrary.Get<SoundEvent>( sound );
		if ( soundEvent is null )
			throw new InvalidOperationException( $"Could not load SoundEvent: {sound}" );

		var scene = EditorSession.ActiveScene ?? Game.ActiveScene
			?? throw new InvalidOperationException( "No active scene." );

		var name = GetParamOptional( request, "name" );
		if ( string.IsNullOrWhiteSpace( name ) )
			name = $"SoundPoint_{Path.GetFileNameWithoutExtension( sound )}";

		var position = SceneHandler.ParseVector3( GetParamOptional( request, "position" ) ?? "0,0,0" );
		var parentId = GetParamOptional( request, "parentId" );
		var startNow = GetBoolParam( request, "startNow", false );

		var go = scene.CreateObject();
		go.Name = name;
		go.WorldPosition = position;

		if ( !string.IsNullOrWhiteSpace( parentId ) && Guid.TryParse( parentId, out var pguid ) )
		{
			var parent = SceneHandler.FindObjectById( pguid );
			if ( parent is not null )
				go.SetParent( parent );
		}

		var point = go.Components.Get<SoundPointComponent>();
		if ( point is null || !point.IsValid() )
			point = go.Components.Create<SoundPointComponent>();
		point.SoundEvent = soundEvent;

		if ( startNow )
			point.StartSound();

		EditorChanges.MarkDirty();
		Log.Info( $"[MCP] sound.place_point '{name}' -> {sound}" );
		return Task.FromResult<object>( (object)new
		{
			created = true,
			id = go.Id.ToString(),
			name = go.Name,
			sound,
			startNow,
		} );
	}

	public static Task<object> FindSoundHooks( HandlerRequest request )
	{
		var scene = EditorSession.ActiveScene ?? Game.ActiveScene
			?? throw new InvalidOperationException( "No active scene." );

		var results = new List<object>();
		foreach ( var go in scene.GetAllObjects( false ) )
		{
			foreach ( var comp in go.Components.GetAll() )
			{
				var td = TypeLibrary.GetType( comp.GetType() );
				if ( td is null ) continue;

				foreach ( var prop in td.Properties )
				{
					if ( prop.PropertyType?.Name != "SoundEvent" )
						continue;

					object value = null;
					try { value = prop.GetValue( comp ); }
					catch { }

					results.Add( new
					{
						objectId = go.Id.ToString(),
						objectName = go.Name,
						component = comp.GetType().Name,
						property = prop.Name,
						value = value?.ToString() ?? "",
					} );
				}
			}
		}

		return Task.FromResult<object>( (object)new
		{
			count = results.Count,
			hooks = results,
		} );
	}

	public static List<object> BuildSoundInventory( string query = "" )
	{
		var root = Project.Current?.GetRootPath() ?? Environment.CurrentDirectory;
		var soundRoot = Path.Combine( root, "Assets", "sounds" );
		var results = new List<object>();
		if ( !Directory.Exists( soundRoot ) )
			return results;

		foreach ( var file in Directory.GetFiles( soundRoot, "*.sound", SearchOption.AllDirectories ) )
		{
			var relative = Path.GetRelativePath( Path.Combine( root, "Assets" ), file ).Replace( '\\', '/' );
			if ( !relative.StartsWith( "sounds/", StringComparison.OrdinalIgnoreCase ) )
				relative = "sounds/" + relative;

			if ( !string.IsNullOrWhiteSpace( query )
				&& !relative.Contains( query, StringComparison.OrdinalIgnoreCase )
				&& !Path.GetFileNameWithoutExtension( relative ).Contains( query, StringComparison.OrdinalIgnoreCase ) )
				continue;

			results.Add( ReadSoundMetadata( file ) );
		}

		return results;
	}

	public static string NormalizeSoundResourcePath( string path )
	{
		var normalized = (path ?? "").Trim().Trim( '"' ).Replace( '\\', '/' ).TrimStart( '/' );
		if ( normalized.StartsWith( "Assets/", StringComparison.OrdinalIgnoreCase ) )
			normalized = normalized.Substring( "Assets/".Length );
		if ( !normalized.EndsWith( ".sound", StringComparison.OrdinalIgnoreCase ) )
			normalized += ".sound";

		// Short names are project-local convenience aliases. Full resource paths
		// may be editor/package assets for discovery, so do not force them under
		// Assets/sounds here; gameplay wiring still uses local wrappers.
		if ( !normalized.Contains( '/' ) && !normalized.StartsWith( "sounds/", StringComparison.OrdinalIgnoreCase ) )
			normalized = "sounds/" + normalized;
		return normalized;
	}

	private static string NormalizeAudioResourcePath( string path )
	{
		var normalized = (path ?? "").Trim().Trim( '"' ).Replace( '\\', '/' ).TrimStart( '/' );
		if ( normalized.StartsWith( "Assets/", StringComparison.OrdinalIgnoreCase ) )
			normalized = normalized.Substring( "Assets/".Length );
		if ( !normalized.StartsWith( "sounds/", StringComparison.OrdinalIgnoreCase ) )
			normalized = "sounds/" + normalized;
		return normalized;
	}

	private static object ReadSoundMetadata( string fullPath )
	{
		var root = Project.Current?.GetRootPath() ?? Environment.CurrentDirectory;
		var assetRoot = Path.Combine( root, "Assets" );
		var resourcePath = Path.GetRelativePath( assetRoot, fullPath ).Replace( '\\', '/' );
		var json = JsonDocument.Parse( File.ReadAllText( fullPath ) ).RootElement;
		var sources = ReadStringArray( json, "Sounds" );
		var missingSources = new List<string>();

		foreach ( var source in sources )
		{
			var resolved = ResolveProjectResourcePath( NormalizeAudioResourcePath( source ) );
			if ( resolved is null || !File.Exists( resolved ) )
				missingSources.Add( source );
		}

		return new
		{
			path = resourcePath,
			name = Path.GetFileNameWithoutExtension( fullPath ),
			ui = ReadBool( json, "UI", false ),
			volume = ReadScalarString( json, "Volume" ),
			pitch = ReadScalarString( json, "Pitch" ),
			decibels = ReadInt( json, "Decibels", 0 ),
			selectionMode = ReadScalarString( json, "SelectionMode" ),
			occlusion = ReadBool( json, "Occlusion", false ),
			distanceAttenuation = ReadBool( json, "DistanceAttenuation", false ),
			distance = ReadFloat( json, "Distance", 0f ),
			sourceCount = sources.Count,
			sources,
			missingSources,
		};
	}

	private static string ResolveProjectResourcePath( string resourcePath )
	{
		var normalized = (resourcePath ?? "").Replace( '\\', '/' ).TrimStart( '/' );
		var root = Project.Current?.GetRootPath() ?? Environment.CurrentDirectory;
		if ( normalized.StartsWith( "Assets/", StringComparison.OrdinalIgnoreCase ) )
			return Path.Combine( root, normalized.Replace( '/', Path.DirectorySeparatorChar ) );
		if ( normalized.StartsWith( "sounds/", StringComparison.OrdinalIgnoreCase ) )
			return Path.Combine( root, "Assets", normalized.Replace( '/', Path.DirectorySeparatorChar ) );
		return null;
	}

	private static List<string> ReadStringArray( JsonElement json, string property )
	{
		var result = new List<string>();
		if ( !json.TryGetProperty( property, out var value ) )
			return result;

		if ( value.ValueKind == JsonValueKind.Array )
		{
			foreach ( var item in value.EnumerateArray() )
				result.Add( item.ValueKind == JsonValueKind.String ? item.GetString() : item.ToString() );
		}
		else if ( value.ValueKind == JsonValueKind.String )
		{
			result.Add( value.GetString() );
		}

		return result.Where( x => !string.IsNullOrWhiteSpace( x ) ).ToList();
	}

	private static string ReadScalarString( JsonElement json, string property )
	{
		return json.TryGetProperty( property, out var value )
			? value.ValueKind == JsonValueKind.String ? value.GetString() : value.ToString()
			: "";
	}

	private static bool ReadBool( JsonElement json, string property, bool fallback )
	{
		if ( !json.TryGetProperty( property, out var value ) )
			return fallback;
		if ( value.ValueKind == JsonValueKind.True || value.ValueKind == JsonValueKind.False )
			return value.GetBoolean();
		return bool.TryParse( value.ToString(), out var parsed ) ? parsed : fallback;
	}

	private static int ReadInt( JsonElement json, string property, int fallback )
	{
		if ( !json.TryGetProperty( property, out var value ) )
			return fallback;
		if ( value.ValueKind == JsonValueKind.Number && value.TryGetInt32( out var parsed ) )
			return parsed;
		return int.TryParse( value.ToString(), out parsed ) ? parsed : fallback;
	}

	private static float ReadFloat( JsonElement json, string property, float fallback )
	{
		if ( !json.TryGetProperty( property, out var value ) )
			return fallback;
		if ( value.ValueKind == JsonValueKind.Number && value.TryGetSingle( out var parsed ) )
			return parsed;
		return float.TryParse( value.ToString(), out parsed ) ? parsed : fallback;
	}

	private static string GetParam( HandlerRequest request, string key )
	{
		var val = GetParamOptional( request, key );
		if ( val is null )
			throw new ArgumentException( $"Missing required parameter: {key}" );
		return val;
	}

	private static string GetParamOptional( HandlerRequest request, string key )
	{
		if ( request.Params is not JsonElement el )
			return null;
		if ( el.TryGetProperty( key, out var prop ) )
			return prop.ValueKind == JsonValueKind.String ? prop.GetString() : prop.ToString();
		return null;
	}

	private static List<string> GetStringArrayParam( HandlerRequest request, string key )
	{
		var result = new List<string>();
		if ( request.Params is not JsonElement el || !el.TryGetProperty( key, out var prop ) )
			return result;

		if ( prop.ValueKind == JsonValueKind.Array )
		{
			foreach ( var item in prop.EnumerateArray() )
				result.Add( item.ValueKind == JsonValueKind.String ? item.GetString() : item.ToString() );
		}
		else if ( prop.ValueKind == JsonValueKind.String )
		{
			result.Add( prop.GetString() );
		}

		return result.Where( x => !string.IsNullOrWhiteSpace( x ) ).ToList();
	}

	private static bool GetBoolParam( HandlerRequest request, string key, bool fallback )
	{
		var raw = GetParamOptional( request, key );
		return bool.TryParse( raw, out var parsed ) ? parsed : fallback;
	}

	private static int GetIntParam( HandlerRequest request, string key, int fallback )
	{
		var raw = GetParamOptional( request, key );
		return int.TryParse( raw, out var parsed ) ? parsed : fallback;
	}

	private static float GetFloatParam( HandlerRequest request, string key, float fallback )
	{
		var raw = GetParamOptional( request, key );
		return float.TryParse( raw, out var parsed ) ? parsed : fallback;
	}

	private static string GetStringParam( HandlerRequest request, string key, string fallback )
	{
		return GetParamOptional( request, key ) ?? fallback;
	}
}
