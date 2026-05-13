using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Resolves gameplay attribution from spawned objects back to player
/// connections. Weapons are often child GameObjects, so owner lookup walks
/// up the hierarchy before giving up.
/// </summary>
public static class DamageAttribution
{
	public static Guid OwnerConnectionId( Component component )
	{
		return component is null ? default : OwnerConnectionId( component.GameObject );
	}

	public static Guid OwnerConnectionId( GameObject gameObject )
	{
		var current = gameObject;
		while ( current.IsValid() )
		{
			if ( current.Network.Owner is not null )
				return current.Network.Owner.Id;

			current = current.Parent;
		}

		return default;
	}
}
