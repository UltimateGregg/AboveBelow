using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Small networked slot selector for soldier loadouts. Slot 1 is the primary
/// weapon and slot 2 is the class equipment.
/// </summary>
[Title( "Soldier Loadout" )]
[Category( "Drone vs Players/Player" )]
[Icon( "inventory_2" )]
public sealed class SoldierLoadout : Component
{
	public const int PrimarySlot = 1;
	public const int EquipmentSlot = 2;

	[Sync] public int SelectedSlot { get; set; } = PrimarySlot;

	int _localSelectedSlot = PrimarySlot;

	/// <summary>
	/// Slot used for local visuals and input gating. Non-host owners predict
	/// this immediately so weapon/grenade visibility does not wait for a sync
	/// round trip; proxies keep using the authoritative synced slot.
	/// </summary>
	public int ActiveSlot => !IsProxy && IsValidSlot( _localSelectedSlot )
		? _localSelectedSlot
		: SelectedSlot;

	public bool IsPrimarySelected => ActiveSlot == PrimarySlot;
	public bool IsEquipmentSelected => ActiveSlot == EquipmentSlot;

	protected override void OnStart()
	{
		if ( CanMutateState() && !IsValidSlot( SelectedSlot ) )
			SelectedSlot = PrimarySlot;

		_localSelectedSlot = IsValidSlot( SelectedSlot ) ? SelectedSlot : PrimarySlot;
		ApplyHeldItemVisibility();
	}

	protected override void OnUpdate()
	{
		if ( IsProxy )
			_localSelectedSlot = IsValidSlot( SelectedSlot ) ? SelectedSlot : PrimarySlot;

		ApplyHeldItemVisibility();

		if ( !IsProxy && !LocalOptionsState.ConsumesGameplayInput )
		{
			if ( Input.Pressed( "Slot1" ) )
				SelectSlot( PrimarySlot );

			if ( Input.Pressed( "Slot2" ) )
				SelectSlot( EquipmentSlot );
		}

		ApplyHeldItemVisibility();
	}

	/// <summary>
	/// Requests a loadout slot change. The host owns the replicated slot state.
	/// </summary>
	public void SelectSlot( int slot )
	{
		if ( !IsValidSlot( slot ) ) return;
		if ( ActiveSlot == slot && SelectedSlot == slot ) return;

		if ( !IsProxy )
			_localSelectedSlot = slot;

		ApplyHeldItemVisibility();
		RequestSelectSlot( slot );
	}

	[Rpc.Broadcast]
	void RequestSelectSlot( int slot )
	{
		if ( !CanMutateState() ) return;
		if ( !IsValidSlot( slot ) ) return;

		SelectedSlot = slot;
		_localSelectedSlot = slot;
		ApplyHeldItemVisibility();
	}

	void ApplyHeldItemVisibility()
	{
		foreach ( var weapon in Components.GetAll<HitscanWeapon>( FindMode.EverythingInSelfAndDescendants ) )
			weapon.ApplySelectionVisualState();

		foreach ( var weapon in Components.GetAll<ShotgunWeapon>( FindMode.EverythingInSelfAndDescendants ) )
			weapon.ApplySelectionVisualState();

		foreach ( var weapon in Components.GetAll<DroneJammerGun>( FindMode.EverythingInSelfAndDescendants ) )
			weapon.ApplySelectionVisualState();

		foreach ( var grenade in Components.GetAll<ThrowableGrenade>( FindMode.EverythingInSelfAndDescendants ) )
			grenade.ApplySelectionVisualState();

		foreach ( var deployer in Components.GetAll<DroneDeployer>( FindMode.EverythingInSelfAndDescendants ) )
			deployer.ApplySelectionVisualState();
	}

	static bool IsValidSlot( int slot ) => slot is PrimarySlot or EquipmentSlot;

	static bool CanMutateState() => !Networking.IsActive || Networking.IsHost;
}
