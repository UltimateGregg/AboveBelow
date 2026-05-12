using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Standard fragmentation grenade. Damages soldiers and drones in radius
/// with line-of-sight checked falloff (mirrors the existing kamikaze AoE
/// in DroneWeapon). No jamming.
/// </summary>
[Title( "Frag Grenade" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "scatter_plot" )]
public sealed class FragGrenade : ThrowableGrenade
{
	[Property] public string WeaponDisplayName { get; set; } = "Frag Grenade";
	[Property] public float Radius { get; set; } = 320f;
	[Property] public float Damage { get; set; } = 130f;
	[Property, Range( 0f, 1f )] public float Falloff { get; set; } = 0.6f;
	[Property] public GameObject ExplosionPrefab { get; set; }

	protected override void OnDetonate( Vector3 worldPos )
	{
		BroadcastExplosionFx( worldPos );
		RequestExplosion( worldPos, Radius, Damage, Falloff, GameObject.Id, WeaponDisplayName );
	}

	[Rpc.Broadcast]
	void RequestExplosion( Vector3 center, float radius, float damage, float falloff, System.Guid attackerId, string weaponName )
	{
		if ( !Networking.IsHost ) return;

		foreach ( var h in Scene.GetAllComponents<Health>() )
		{
			if ( !h.IsValid() ) continue;
			var dist = (h.WorldPosition - center).Length;
			if ( dist > radius ) continue;

			var tr = Scene.Trace.Ray( center, h.WorldPosition )
				.WithoutTags( "trigger" )
				.IgnoreGameObjectHierarchy( h.GameObject )
				.Run();
			if ( tr.Hit ) continue;

			var t = (dist / radius).Clamp( 0f, 1f );
			var dmg = damage * (1f - t * falloff);
			h.TakeDamage( new DamageInfo { Amount = dmg, AttackerId = attackerId, Position = center, WeaponName = weaponName } );
		}
	}

	[Rpc.Broadcast]
	void BroadcastExplosionFx( Vector3 center )
	{
		if ( ExplosionPrefab.IsValid() )
		{
			ExplosionPrefab.Clone( center );
			return;
		}

		GrenadeEffectVisual.Spawn( center, GrenadeEffectKind.Frag, Radius );
	}
}
