using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Listens for every Health.OnKilled event in the scene and accumulates a
/// rolling list of kill-feed entries (newest first), pruning anything older
/// than <see cref="EntryLifetimeSeconds"/>. The HUD reads <see cref="Entries"/>
/// each frame to render the feed in the corner.
///
/// Place this component on the GameManager so it spans the whole match. It
/// auto-subscribes to Health components as they appear in the scene.
/// </summary>
[Title( "Kill Feed Tracker" )]
[Category( "Drone vs Players" )]
[Icon( "list_alt" )]
public sealed class KillFeedTracker : Component
{
	[Property, Range( 1f, 15f )] public float EntryLifetimeSeconds { get; set; } = 5.5f;
	[Property, Range( 4, 32 )] public int MaxEntries { get; set; } = 8;

	public readonly struct Entry
	{
		public readonly float Time;
		public readonly string AttackerName;
		public readonly string WeaponName;
		public readonly string VictimName;
		public readonly bool LocalIsAttacker;
		public readonly bool LocalIsVictim;

		public Entry( float time, string attackerName, string weaponName, string victimName, bool localAttacker, bool localVictim )
		{
			Time = time;
			AttackerName = attackerName;
			WeaponName = weaponName;
			VictimName = victimName;
			LocalIsAttacker = localAttacker;
			LocalIsVictim = localVictim;
		}
	}

	readonly List<Entry> _entries = new();
	readonly Dictionary<Health, Action<DamageInfo>> _handlers = new();

	public IReadOnlyList<Entry> Entries => _entries;

	protected override void OnStart()
	{
		// Pick up health components already in the scene.
		RescanHealths();
	}

	protected override void OnUpdate()
	{
		// Periodically rescan so newly-spawned pawns get hooked up.
		// Cheap enough at the ~30 Hz update rate to do every frame.
		RescanHealths();

		// Prune old entries.
		var cutoff = Time.Now - EntryLifetimeSeconds;
		_entries.RemoveAll( e => e.Time < cutoff );
	}

	protected override void OnDestroy()
	{
		foreach ( var (health, handler) in _handlers )
		{
			if ( health.IsValid() )
				health.OnKilled -= handler;
		}
		_handlers.Clear();
	}

	void RescanHealths()
	{
		// Add subscriptions for any Health we haven't seen yet.
		foreach ( var h in Scene.GetAllComponents<Health>() )
		{
			if ( !h.IsValid() ) continue;
			if ( _handlers.ContainsKey( h ) ) continue;

			Action<DamageInfo> handler = info => OnHealthKilled( h, info );
			h.OnKilled += handler;
			_handlers[h] = handler;
		}

		// Clean up dead refs.
		var stale = _handlers.Keys.Where( k => !k.IsValid() ).ToList();
		foreach ( var k in stale )
			_handlers.Remove( k );
	}

	void OnHealthKilled( Health victim, DamageInfo info )
	{
		var stats = Scene.GetAllComponents<GameStats>().FirstOrDefault();
		var victimConn = victim.GameObject.Network.Owner;
		var victimId = victimConn?.Id ?? default;

		var attackerName = ResolveName( stats, info.AttackerId );
		var victimName = ResolveName( stats, victimId, fallback: victim.GameObject.Name );
		var weapon = string.IsNullOrWhiteSpace( info.WeaponName ) ? "—" : info.WeaponName;

		var localId = Connection.Local?.Id ?? default;
		var localIsAttacker = localId != default && localId == info.AttackerId;
		var localIsVictim = localId != default && localId == victimId;

		_entries.Insert( 0, new Entry( Time.Now, attackerName, weapon, victimName, localIsAttacker, localIsVictim ) );

		if ( _entries.Count > MaxEntries )
			_entries.RemoveAt( _entries.Count - 1 );
	}

	static string ResolveName( GameStats stats, Guid connectionId, string fallback = "Unknown" )
	{
		if ( connectionId == default ) return fallback;
		if ( stats.IsValid() && stats.PlayerNames.TryGetValue( connectionId, out var name ) && !string.IsNullOrWhiteSpace( name ) )
			return name;

		// Fallback: live connection lookup.
		var conn = Connection.All.FirstOrDefault( c => c.Id == connectionId );
		return conn?.DisplayName ?? fallback;
	}
}
