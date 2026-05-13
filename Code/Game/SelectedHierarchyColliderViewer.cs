using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Draws this object's child collider bounds in the editor whenever this
/// object or one of its children is selected.
/// </summary>
[Title( "Selected Hierarchy Collider Viewer" )]
[Category( "Drone vs Players/Editor" )]
[Icon( "select_all" )]
public sealed class SelectedHierarchyColliderViewer : Component, Component.ExecuteInEditor
{
	[Property] public bool IncludeTriggers { get; set; } = true;
	[Property] public Color SolidColliderColor { get; set; } = new( 1f, 0.55f, 0.12f, 1f );
	[Property] public Color TriggerColliderColor { get; set; } = new( 0.25f, 0.75f, 1f, 1f );

	protected override void OnUpdate()
	{
		if ( !Gizmo.IsSelected && !Gizmo.IsChildSelected )
			return;

		foreach ( var collider in Components.GetAll<BoxCollider>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !collider.IsValid() ) continue;
			if ( collider.IsTrigger && !IncludeTriggers ) continue;

			using ( Gizmo.Scope( $"selected_box_{collider.Id}", collider.WorldTransform ) )
			{
				Gizmo.Draw.Color = collider.IsTrigger ? TriggerColliderColor : SolidColliderColor;
				var center = collider.Center;
				var half = collider.Scale * 0.5f;
				Gizmo.Draw.LineBBox( new BBox( center - half, center + half ) );
			}
		}

		foreach ( var collider in Components.GetAll<SphereCollider>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !collider.IsValid() ) continue;
			if ( collider.IsTrigger && !IncludeTriggers ) continue;

			using ( Gizmo.Scope( $"selected_sphere_{collider.Id}", collider.WorldTransform ) )
			{
				Gizmo.Draw.Color = collider.IsTrigger ? TriggerColliderColor : SolidColliderColor;
				Gizmo.Draw.LineSphere( collider.Center, collider.Radius );
			}
		}

		foreach ( var collider in Components.GetAll<CapsuleCollider>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !collider.IsValid() ) continue;
			if ( collider.IsTrigger && !IncludeTriggers ) continue;

			using ( Gizmo.Scope( $"selected_capsule_{collider.Id}", collider.WorldTransform ) )
			{
				Gizmo.Draw.Color = collider.IsTrigger ? TriggerColliderColor : SolidColliderColor;
				Gizmo.Draw.LineSphere( collider.Start, collider.Radius );
				Gizmo.Draw.LineSphere( collider.End, collider.Radius );
				Gizmo.Draw.Line( collider.Start, collider.End );
			}
		}
	}
}
