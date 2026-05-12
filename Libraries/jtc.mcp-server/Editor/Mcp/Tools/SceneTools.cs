using Sandbox;
using System.ComponentModel;
using System.Threading.Tasks;
using SboxMcp.Handlers;

namespace SboxMcp.Mcp.Tools;

/// <summary>
/// Scene-graph operations: list, create, query, transform, reparent, load.
/// All tools dispatch to the existing s&amp;box <see cref="SceneHandler"/>
/// implementations on the editor main thread.
/// </summary>
[McpToolGroup]
public static class SceneTools
{
	[McpTool( "scene_list_objects", Description = "List all GameObjects in the current s&box scene hierarchy" )]
	public static Task<object> ListObjects() =>
		HandlerDispatcher.InvokeAsync( "scene.list", null, SceneHandler.ListObjects );

	[McpTool( "scene_get_object", Description = "Get detailed info about a GameObject including components and properties" )]
	public static Task<object> GetObject(
		[Description( "The ID of the GameObject to retrieve" )] string id ) =>
		HandlerDispatcher.InvokeAsync( "scene.get", new { id }, SceneHandler.GetObject );

	[McpTool( "scene_create_object", Description = "Create a new GameObject in the scene" )]
	public static Task<object> CreateObject(
		[Description( "Name for the new GameObject" )] string name,
		[Description( "Optional parent GameObject ID" )] string parentId = null,
		[Description( "Optional position as 'x,y,z' string" )] string position = null ) =>
		HandlerDispatcher.InvokeAsync( "scene.create", new { name, parentId, position }, SceneHandler.CreateObject );

	[McpTool( "scene_delete_object", Description = "Delete a GameObject from the scene" )]
	public static Task<object> DeleteObject(
		[Description( "The ID of the GameObject to delete" )] string id ) =>
		HandlerDispatcher.InvokeAsync( "scene.delete", new { id }, SceneHandler.DeleteObject );

	[McpTool( "scene_find_objects", Description = "Search for GameObjects by name (supports * wildcards)" )]
	public static Task<object> FindObjects(
		[Description( "Search pattern, supports * wildcards" )] string pattern ) =>
		HandlerDispatcher.InvokeAsync( "scene.find", new { pattern }, SceneHandler.FindObjects );

	[McpTool( "scene_set_transform", Description = "Set a GameObject's position, rotation, and/or scale" )]
	public static Task<object> SetTransform(
		[Description( "The ID of the GameObject to transform" )] string id,
		[Description( "Optional position as 'x,y,z'" )] string position = null,
		[Description( "Optional rotation as 'x,y,z'" )] string rotation = null,
		[Description( "Optional scale as 'x,y,z'" )] string scale = null ) =>
		HandlerDispatcher.InvokeAsync( "scene.set_transform", new { id, position, rotation, scale }, SceneHandler.SetTransform );

	[McpTool( "scene_get_hierarchy", Description = "Get the full scene hierarchy as indented text for easy reading" )]
	public static Task<object> GetHierarchy() =>
		HandlerDispatcher.InvokeAsync( "scene.hierarchy", null, SceneHandler.GetHierarchy );

	[McpTool( "scene_clone_object", Description = "Clone a GameObject in the scene" )]
	public static Task<object> CloneObject(
		[Description( "The ID of the GameObject to clone" )] string id ) =>
		HandlerDispatcher.InvokeAsync( "scene.clone", new { id }, SceneHandler.CloneObject );

	[McpTool( "scene_reparent_object", Description = "Reparent a GameObject to a new parent" )]
	public static Task<object> ReparentObject(
		[Description( "The ID of the GameObject to reparent" )] string id,
		[Description( "The ID of the new parent GameObject" )] string parentId ) =>
		HandlerDispatcher.InvokeAsync( "scene.reparent", new { id, parentId }, SceneHandler.ReparentObject );

	[McpTool( "scene_find_by_component", Description = "Find all GameObjects that have a specific component type" )]
	public static Task<object> FindByComponent(
		[Description( "The component type name to search for" )] string type ) =>
		HandlerDispatcher.InvokeAsync( "scene.find_by_component", new { type }, SceneHandler.FindByComponent );

	[McpTool( "scene_find_by_tag", Description = "Find all GameObjects that have a specific tag" )]
	public static Task<object> FindByTag(
		[Description( "The tag to search for" )] string tag ) =>
		HandlerDispatcher.InvokeAsync( "scene.find_by_tag", new { tag }, SceneHandler.FindByTag );

	[McpTool( "scene_load", Description = "Load a scene from a file path" )]
	public static Task<object> LoadScene(
		[Description( "The file path of the scene to load" )] string path ) =>
		HandlerDispatcher.InvokeAsync( "scene.load", new { path }, SceneHandler.LoadScene );

	[McpTool( "scene_open", Description = "Open a scene or prefab from a local project file path" )]
	public static Task<object> OpenScene(
		[Description( "The file path of the scene or prefab to open" )] string path ) =>
		HandlerDispatcher.InvokeAsync( "scene.open", new { path }, SceneHandler.OpenScene );

	// --- Tag tools (live in SceneHandler too) ---

	[McpTool( "tag_add", Description = "Add a tag to a GameObject" )]
	public static Task<object> TagAdd(
		[Description( "The ID of the GameObject" )] string id,
		[Description( "The tag to add" )] string tag ) =>
		HandlerDispatcher.InvokeAsync( "tag.add", new { id, tag }, SceneHandler.TagAdd );

	[McpTool( "tag_remove", Description = "Remove a tag from a GameObject" )]
	public static Task<object> TagRemove(
		[Description( "The ID of the GameObject" )] string id,
		[Description( "The tag to remove" )] string tag ) =>
		HandlerDispatcher.InvokeAsync( "tag.remove", new { id, tag }, SceneHandler.TagRemove );

	[McpTool( "tag_list", Description = "List all tags on a GameObject" )]
	public static Task<object> TagList(
		[Description( "The ID of the GameObject" )] string id ) =>
		HandlerDispatcher.InvokeAsync( "tag.list", new { id }, SceneHandler.TagList );
}
