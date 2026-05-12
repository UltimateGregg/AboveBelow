using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Networked health with host-authoritative damage. The host is the single
/// source of truth: any peer can request damage via <see cref="RequestDamage"/>,
/// but only the host actually mutates HP. Synced fields propagate to clients.
/// </summary>
[Title( "Health" )]
[Category( "Drone vs Players" )]
[Icon( "favorite" )]
public sealed class Health : Component
{
	[Property] public float MaxHealth { get; set; } = 100f;

	[Sync] public float CurrentHealth { get; set; } = 100f;
	[Sync] public bool IsDead { get; set; }

	/// <summary>
	/// Fired locally on every peer when the entity dies. Includes the damage
	/// info that produced the killing blow.
	/// </summary>
	public event Action<DamageInfo> OnKilled;

	/// <summary>
	/// Fired locally on every peer when this entity takes damage (fatal or
	/// not). HUD layers (damage-direction arc, hitmarker) hang off this.
	/// </summary>
	public event Action<DamageInfo> OnDamaged;

	protected override void OnStart()
	{
		if ( Networking.IsHost )
			CurrentHealth = MaxHealth;
	}

	/// <summary>
	/// Direct damage application. Caller must be the host.
	/// </summary>
	public void TakeDamage( DamageInfo info )
	{
		if ( !Networking.IsHost ) return;
		if ( IsDead ) return;

		CurrentHealth = Math.Max( 0f, CurrentHealth - info.Amount );

		BroadcastDamaged( info.AttackerId, info.Amount, info.Position, info.WeaponName ?? string.Empty );

		if ( CurrentHealth <= 0f )
		{
			IsDead = true;
			BroadcastKilled( info.AttackerId, info.Amount, info.Position, info.WeaponName ?? string.Empty );
		}
	}

	/// <summary>
	/// Damage request from any peer. Broadcasts to all peers; only the host
	/// applies the change. Visual effects can subscribe via OnKilled which
	/// fires on every peer.
	/// </summary>
	[Rpc.Broadcast]
	public void RequestDamage( float amount, Guid attackerId, Vector3 position )
	{
		if ( !Networking.IsHost ) return;
		TakeDamage( new DamageInfo { Amount = amount, AttackerId = attackerId, Position = position } );
	}

	/// <summary>
	/// Damage request with attribution (for the kill feed). Same flow as
	/// <see cref="RequestDamage"/> but lets the caller name the weapon.
	/// </summary>
	[Rpc.Broadcast]
	public void RequestDamageNamed( float amount, Guid attackerId, Vector3 position, string weaponName )
	{
		if ( !Networking.IsHost ) return;
		TakeDamage( new DamageInfo { Amount = amount, AttackerId = attackerId, Position = position, WeaponName = weaponName } );
	}

	[Rpc.Broadcast]
	private void BroadcastDamaged( Guid attackerId, float amount, Vector3 position, string weaponName )
	{
		OnDamaged?.Invoke( new DamageInfo
		{
			Amount = amount,
			AttackerId = attackerId,
			Position = position,
			WeaponName = weaponName,
		} );
	}

	[Rpc.Broadcast]
	private void BroadcastKilled( Guid attackerId, float amount, Vector3 position, string weaponName )
	{
		OnKilled?.Invoke( new DamageInfo
		{
			Amount = amount,
			AttackerId = attackerId,
			Position = position,
			WeaponName = weaponName,
		} );
	}

	public void Revive()
	{
		if ( !Networking.IsHost ) return;
		CurrentHealth = MaxHealth;
		IsDead = false;
	}
}

public struct DamageInfo
{
	public float Amount;
	public Guid AttackerId;
	public Vector3 Position;
	public string WeaponName;
}
