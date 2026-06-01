using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// MGS-style chaff grenade. Brief, small-radius cloud of metallic particles
/// that scrambles drone signals — applies a short-duration jam to every
/// drone in radius. No damage to soldiers.
/// </summary>
[Title( "Chaff Grenade" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "blur_on" )]
public sealed class ChaffGrenade : ThrowableGrenade
{
	const string DefaultEffectPrefabPath = "prefabs/effects/chaff_burst.prefab";

	[Property] public float Radius { get; set; } = 600f;
	[Property] public float JamDuration { get; set; } = 3f;
	[Property, Range( 0f, 1f )] public float Strength { get; set; } = 1f;
	[Property] public GameObject EffectPrefab { get; set; }

	protected override void OnDetonate( Vector3 worldPos )
	{
		BroadcastEffect( worldPos );
		ApplyJamArea( worldPos, Radius, Strength, JamDuration, GameObject.Id );
	}

	[Rpc.Broadcast]
	void ApplyJamArea( Vector3 center, float radius, float strength, float duration, System.Guid sourceId )
	{
		if ( !Networking.IsHost ) return;

		foreach ( var receiver in Scene.GetAllComponents<JammingReceiver>() )
		{
			if ( !receiver.IsValid() ) continue;
			var dist = (receiver.WorldPosition - center).Length;
			if ( dist > radius ) continue;
			receiver.ApplyJam( sourceId, strength, duration );
		}
	}

	[Rpc.Broadcast]
	void BroadcastEffect( Vector3 center )
	{
		var effectPrefab = EffectPrefab.IsValid()
			? EffectPrefab
			: GameObject.GetPrefab( DefaultEffectPrefabPath );

		if ( GrenadeEffectVisual.TrySpawnPrefab( effectPrefab, center, GrenadeEffectKind.Chaff, Radius ) )
			return;

		GrenadeEffectVisual.Spawn( center, GrenadeEffectKind.Chaff, Radius );
	}
}
