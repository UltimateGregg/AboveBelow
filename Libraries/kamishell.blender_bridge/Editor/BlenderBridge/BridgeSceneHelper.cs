using System;
using System.Collections.Generic;
using Editor;
using Sandbox;

namespace BlenderBridge;

/// <summary>
/// Standalone scene helpers for the Blender Bridge — no MCP dependencies.
/// </summary>
internal static class BridgeSceneHelper
{
	/// <summary>
	/// Returns the best available scene:
	/// 1. Active SceneEditorSession.Scene (editor)
	/// 2. Any available editor session
	/// 3. Game.ActiveScene (play mode)
	/// </summary>
	internal static Scene ResolveScene()
	{
		try
		{
			var active = SceneEditorSession.Active;
			if ( active?.Scene != null ) return active.Scene;
			foreach ( var s in SceneEditorSession.All )
				if ( s?.Scene != null ) return s.Scene;
		}
		catch { }

		if ( Game.ActiveScene != null ) return Game.ActiveScene;
		return null;
	}

	/// <summary>Walk all GameObjects in the scene, including children.</summary>
	internal static IEnumerable<GameObject> WalkAll( Scene scene, bool includeDisabled = true )
	{
		foreach ( var root in scene.Children )
			foreach ( var go in WalkSubtree( root, includeDisabled ) )
				yield return go;
	}

	private static IEnumerable<GameObject> WalkSubtree( GameObject root, bool includeDisabled )
	{
		if ( !includeDisabled && !root.Enabled ) yield break;
		yield return root;
		foreach ( var child in root.Children )
			foreach ( var go in WalkSubtree( child, includeDisabled ) )
				yield return go;
	}
}
