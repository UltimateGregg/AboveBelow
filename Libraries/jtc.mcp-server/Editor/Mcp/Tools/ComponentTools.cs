using Sandbox;
using System.ComponentModel;
using System.Threading.Tasks;
using SboxMcp.Handlers;

namespace SboxMcp.Mcp.Tools;

[McpToolGroup]
public static class ComponentTools
{
	[McpTool( "component_list", Description = "List all components on a GameObject" )]
	public static Task<object> ListComponents(
		[Description( "The ID of the GameObject" )] string id ) =>
		HandlerDispatcher.InvokeAsync( "component.list", new { id }, ComponentHandler.ListComponents );

	[McpTool( "component_get", Description = "Get a component's properties and values" )]
	public static Task<object> GetComponent(
		[Description( "The ID of the GameObject" )] string id,
		[Description( "The component type name" )] string type ) =>
		HandlerDispatcher.InvokeAsync( "component.get", new { id, type }, ComponentHandler.GetComponent );

	[McpTool( "component_set", Description = "Set a property value on a component" )]
	public static Task<object> SetComponent(
		[Description( "The ID of the GameObject" )] string id,
		[Description( "The component type name" )] string type,
		[Description( "The property name to set" )] string property,
		[Description( "The value to assign" )] string value ) =>
		HandlerDispatcher.InvokeAsync( "component.set", new { id, type, property, value }, ComponentHandler.SetComponent );

	[McpTool( "component_add", Description = "Add a component to a GameObject" )]
	public static Task<object> AddComponent(
		[Description( "The ID of the GameObject" )] string id,
		[Description( "The component type name to add" )] string type ) =>
		HandlerDispatcher.InvokeAsync( "component.add", new { id, type }, ComponentHandler.AddComponent );

	[McpTool( "component_remove", Description = "Remove a component from a GameObject" )]
	public static Task<object> RemoveComponent(
		[Description( "The ID of the GameObject" )] string id,
		[Description( "The component type name to remove" )] string type ) =>
		HandlerDispatcher.InvokeAsync( "component.remove", new { id, type }, ComponentHandler.RemoveComponent );
}
