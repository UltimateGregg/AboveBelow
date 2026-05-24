using Sandbox;
using SboxMcp.Mcp;

namespace SboxMcp;

/// <summary>
/// Starts the native MCP listener once per editor process so automation can
/// recover after an editor restart without manually reopening the dock.
/// </summary>
public static class McpAutoStart
{
	const int AutoStartPortAttempts = 4;

	static bool _attempted;

	[EditorEvent.Frame]
	public static void Frame()
	{
		if ( _attempted ) return;
		_attempted = true;

		try
		{
			var server = StartOnFirstAvailablePort();
			Log.Info( $"[MCP] Auto-started listener at {server.Url}" );
		}
		catch ( System.Exception ex )
		{
			Log.Warning( $"[MCP] Auto-start failed: {ex.Message}" );
		}
	}

	static McpHttpServer StartOnFirstAvailablePort()
	{
		System.Exception lastException = null;

		for ( var offset = 0; offset < AutoStartPortAttempts; offset++ )
		{
			var port = McpHttpServer.DefaultPort + offset;

			try
			{
				return McpHttpServer.GetOrStart( port );
			}
			catch ( System.Exception ex )
			{
				lastException = ex;
				Log.Warning( $"[MCP] Auto-start could not use port {port}: {ex.Message}" );
			}
		}

		throw new System.InvalidOperationException( "No MCP auto-start port was available.", lastException );
	}
}
