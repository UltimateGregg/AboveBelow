using Sandbox;
using System.Threading.Tasks;
using SboxMcp.Handlers;

namespace SboxMcp.Mcp.Tools;

[McpToolGroup]
public static class ControlPlaneTools
{
	[McpTool( "control_plane_status", Description = "Read-only status for the unified S&Box editor MCP control plane: server, scene, domains, and sound inventory health." )]
	public static Task<object> Status() =>
		HandlerDispatcher.InvokeAsync( "control_plane.status", null, ControlPlaneHandler.Status );

	[McpTool( "control_plane_capabilities", Description = "List MCP tools grouped by domain so agents can choose the right editor-native workflow." )]
	public static Task<object> Capabilities() =>
		HandlerDispatcher.InvokeAsync( "control_plane.capabilities", null, ControlPlaneHandler.Capabilities );
}
