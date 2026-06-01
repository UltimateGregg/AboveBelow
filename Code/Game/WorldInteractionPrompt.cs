using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Lightweight world prompt source for objects that can be inspected, used,
/// resupplied, deployed, or otherwise surfaced through the HUD.
/// </summary>
[Title( "World Interaction Prompt" )]
[Category( "Drone vs Players/UI" )]
[Icon( "ads_click" )]
public sealed class WorldInteractionPrompt : Component
{
	[Property] public string DisplayText { get; set; } = "Interact";
	[Property] public string InputGlyph { get; set; } = "E";
	[Property] public string PromptClass { get; set; } = "";
	[Property, Range( 64f, 1200f )] public float MaxDistance { get; set; } = 220f;
	[Property] public PlayerRole VisibleToRole { get; set; } = PlayerRole.Spectator;
	[Property] public bool RequireLineOfSight { get; set; }

	public bool IsAvailableFor( Vector3 viewerPosition, PlayerRole viewerRole )
	{
		if ( !Enabled )
			return false;

		if ( VisibleToRole is PlayerRole.Pilot or PlayerRole.Soldier && VisibleToRole != viewerRole )
			return false;

		if ( viewerPosition.Distance( WorldPosition ) > MaxDistance )
			return false;

		if ( RequireLineOfSight && !HasLineOfSight( viewerPosition ) )
			return false;

		return !string.IsNullOrWhiteSpace( DisplayText );
	}

	bool HasLineOfSight( Vector3 viewerPosition )
	{
		var tr = Scene.Trace
			.Ray( viewerPosition, WorldPosition )
			.WithoutTags( "trigger" )
			.Run();

		return !tr.Hit || IsSelfOrDescendant( tr.GameObject );
	}

	bool IsSelfOrDescendant( GameObject candidate )
	{
		for ( var current = candidate; current.IsValid(); current = current.Parent )
		{
			if ( current == GameObject )
				return true;
		}

		return false;
	}

	public int StableHash => HashCode.Combine(
		DisplayText ?? "",
		InputGlyph ?? "",
		PromptClass ?? "",
		VisibleToRole,
		Enabled );
}
