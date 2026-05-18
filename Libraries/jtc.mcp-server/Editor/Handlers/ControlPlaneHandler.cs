using Sandbox;
using SboxMcp;
using SboxMcp.Mcp;

namespace SboxMcp.Handlers;

/// <summary>
/// Read-only MCP control-plane status and capability reporting.
/// </summary>
public static class ControlPlaneHandler
{
	public static Task<object> Status( HandlerRequest request )
	{
		var scene = EditorSession.ActiveScene ?? Game.ActiveScene;
		var tools = ToolRegistry.List();
		var toolNames = tools.Select( x => x.Name ).ToList();
		var soundInventory = SoundHandler.BuildSoundInventory();
		var soundWithMissingSources = soundInventory.Count( HasMissingSources );

		return Task.FromResult<object>( (object)new
		{
			status = McpHttpServer.Instance is { IsListening: true }
				? $"Listening on http://localhost:{McpHttpServer.Instance.Port}"
				: "Not listening",
			project = Project.Current?.Config?.Title ?? "",
			scene = scene is null ? null : new
			{
				name = scene.Name ?? "",
				sourcePath = scene.Source?.ResourcePath ?? "",
				hasUnsavedChanges = EditorSession.HasUnsavedChanges,
				isPlaying = EditorSession.IsPlaying,
				gameObjectCount = scene.GetAllObjects( false ).Count(),
			},
			toolCount = tools.Count,
			domains = BuildDomains( toolNames ),
			sound = new
			{
				eventCount = soundInventory.Count,
				missingSourceEventCount = soundWithMissingSources,
			},
		} );
	}

	public static Task<object> Capabilities( HandlerRequest request )
	{
		var tools = ToolRegistry.List();
		var grouped = tools
			.GroupBy( x => GetDomain( x.Name ) )
			.OrderBy( x => x.Key )
			.ToDictionary(
				x => x.Key,
				x => x.Select( tool => new { tool.Name, tool.Description } ).OrderBy( tool => tool.Name ).ToList() );

		return Task.FromResult<object>( (object)new
		{
			toolCount = tools.Count,
			groups = grouped,
		} );
	}

	private static object BuildDomains( List<string> toolNames )
	{
		string[] domains =
		{
			"asset",
			"component",
			"console",
			"control_plane",
			"editor",
			"execute",
			"file",
			"project",
			"sbox",
			"scene",
			"sound",
			"tag",
		};

		return domains.ToDictionary(
			domain => domain,
			domain => toolNames.Count( name => name.StartsWith( domain + "_", StringComparison.OrdinalIgnoreCase ) ) );
	}

	private static string GetDomain( string toolName )
	{
		var index = toolName.IndexOf( '_' );
		return index <= 0 ? "misc" : toolName.Substring( 0, index );
	}

	private static bool HasMissingSources( object metadata )
	{
		var prop = metadata.GetType().GetProperty( "missingSources" );
		if ( prop?.GetValue( metadata ) is System.Collections.ICollection collection )
			return collection.Count > 0;
		return false;
	}
}
