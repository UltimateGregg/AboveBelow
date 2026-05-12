using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Toggleable wireframe overlay of every collider in the scene. Useful when
/// you're getting blocked by an "invisible wall" and want to see exactly
/// what's there. Attach to a single GameObject in main.scene (e.g.
/// GameManager) and flip the component on/off in the inspector.
///
/// Drawing happens via the Gizmo API in <c>OnUpdate</c> so it shows up in
/// the editor's main viewport whenever this component is selected. To
/// always-draw in play mode, set <see cref="AlwaysDraw"/>.
/// </summary>
[Title( "Collision Debug Viewer" )]
[Category( "Drone vs Players" )]
[Icon( "view_in_ar" )]
public sealed class CollisionDebugViewer : Component, Component.ExecuteInEditor
{
	[Property] public bool AlwaysDraw { get; set; } = true;
	[Property] public Color BoxColor { get; set; } = new Color( 1f, 0.4f, 0.1f, 1f );
	[Property] public Color SphereColor { get; set; } = new Color( 0.2f, 1f, 0.4f, 1f );

	protected override void OnUpdate()
	{
		if ( !AlwaysDraw && !Gizmo.IsSelected ) return;

		// Box colliders
		foreach ( var bc in Scene.GetAllComponents<BoxCollider>() )
		{
			if ( !bc.IsValid() ) continue;
			using ( Gizmo.Scope( $"box_{bc.Id}", bc.WorldTransform ) )
			{
				Gizmo.Draw.Color = BoxColor;
				var center = bc.Center;
				var half = bc.Scale * 0.5f;
				Gizmo.Draw.LineBBox( new BBox( center - half, center + half ) );
			}
		}

		// Sphere colliders
		foreach ( var sc in Scene.GetAllComponents<SphereCollider>() )
		{
			if ( !sc.IsValid() ) continue;
			using ( Gizmo.Scope( $"sphere_{sc.Id}", sc.WorldTransform ) )
			{
				Gizmo.Draw.Color = SphereColor;
				Gizmo.Draw.LineSphere( sc.Center, sc.Radius );
			}
		}

		// Capsule colliders (rendered as line + cap spheres)
		foreach ( var cc in Scene.GetAllComponents<CapsuleCollider>() )
		{
			if ( !cc.IsValid() ) continue;
			using ( Gizmo.Scope( $"capsule_{cc.Id}", cc.WorldTransform ) )
			{
				Gizmo.Draw.Color = SphereColor;
				Gizmo.Draw.LineSphere( cc.Start, cc.Radius );
				Gizmo.Draw.LineSphere( cc.End, cc.Radius );
				Gizmo.Draw.Line( cc.Start, cc.End );
			}
		}
	}
}
