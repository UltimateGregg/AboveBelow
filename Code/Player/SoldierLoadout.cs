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

	public bool IsPrimarySelected => SelectedSlot == PrimarySlot;
	public bool IsEquipmentSelected => SelectedSlot == EquipmentSlot;

	protected override void OnStart()
	{
		if ( CanMutateState() && !IsValidSlot( SelectedSlot ) )
			SelectedSlot = PrimarySlot;
	}

	protected override void OnUpdate()
	{
		if ( IsProxy ) return;

		if ( Input.Pressed( "Slot1" ) )
			SelectSlot( PrimarySlot );

		if ( Input.Pressed( "Slot2" ) )
			SelectSlot( EquipmentSlot );
	}

	/// <summary>
	/// Requests a loadout slot change. The host owns the replicated slot state.
	/// </summary>
	public void SelectSlot( int slot )
	{
		if ( !IsValidSlot( slot ) ) return;
		if ( SelectedSlot == slot ) return;

		RequestSelectSlot( slot );
	}

	[Rpc.Broadcast]
	void RequestSelectSlot( int slot )
	{
		if ( !CanMutateState() ) return;
		if ( !IsValidSlot( slot ) ) return;

		SelectedSlot = slot;
	}

	static bool IsValidSlot( int slot ) => slot is PrimarySlot or EquipmentSlot;

	static bool CanMutateState() => !Networking.IsActive || Networking.IsHost;
}
