using Sandbox;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Voice component that routes microphone traffic only between players on the
/// same Drone Pilot or Hunter team.
/// </summary>
[Title( "Team Voice" )]
[Category( "Drone vs Players/Game" )]
[Icon( "record_voice_over" )]
public sealed class TeamVoice : Voice
{
	[Property] public GameSetup Setup { get; set; }
	[Property] public bool TeamOnly { get; set; } = true;
	[Property] public bool RoleAwareRouting { get; set; } = true;
	[Property, Range( 256f, 5000f )] public float HunterProximityDistance { get; set; } = 1400f;
	[Property, Range( 0f, 2f )] public float PilotRadioVolume { get; set; } = 1f;
	[Property, Range( 0f, 2f )] public float HunterProximityVolume { get; set; } = 0.92f;

	public string VoiceRouteLabel => ResolveLocalVoiceRole() == PlayerRole.Pilot
		? "RADIO"
		: "PROXIMITY";

	protected override void OnStart()
	{
		base.OnStart();
		ResolveSetup();
		Mode = ActivateMode.PushToTalk;
		PushToTalkInput = "Voice";
		ApplyVoiceRoutingProfile();
	}

	protected override bool ShouldHearVoice( Connection connection )
	{
		ApplyVoiceRoutingProfile();

		if ( !TeamOnly )
			return base.ShouldHearVoice( connection );

		var local = Connection.Local;
		if ( local is null || connection is null )
			return false;

		ResolveSetup();
		return Setup.IsValid() && Setup.AreSameTeam( local.Id, connection.Id );
	}

	protected override IEnumerable<Connection> ExcludeFilter()
	{
		ApplyVoiceRoutingProfile();

		if ( !TeamOnly )
			return base.ExcludeFilter();

		var local = Connection.Local;
		if ( local is null )
			return Connection.All;

		ResolveSetup();
		if ( !Setup.IsValid() )
			return Connection.All.Where( c => c.Id != local.Id );

		return Connection.All.Where( c => !Setup.AreSameTeam( local.Id, c.Id ) );
	}

	void ResolveSetup()
	{
		if ( Setup.IsValid() )
			return;

		Setup = Scene.GetAllComponents<GameSetup>().FirstOrDefault();
	}

	public void ApplyVoiceRoutingProfile()
	{
		if ( !RoleAwareRouting )
		{
			WorldspacePlayback = false;
			Volume = 1f;
			return;
		}

		var role = ResolveLocalVoiceRole();
		if ( role == PlayerRole.Pilot )
		{
			WorldspacePlayback = false;
			Volume = PilotRadioVolume;
			return;
		}

		WorldspacePlayback = true;
		Distance = HunterProximityDistance;
		Volume = HunterProximityVolume;
	}

	PlayerRole ResolveLocalVoiceRole()
	{
		ResolveSetup();

		var ownerId = GameObject.Network.Owner?.Id ?? default;
		if ( ownerId != default && Setup.IsValid() )
		{
			var role = Setup.GetConnectionRole( ownerId );
			if ( role is PlayerRole.Pilot or PlayerRole.Soldier )
				return role;
		}

		if ( Components.Get<PilotSoldier>( FindMode.EverythingInSelfAndDescendants ).IsValid() )
			return PlayerRole.Pilot;

		if ( Components.Get<SoldierBase>( FindMode.EverythingInSelfAndDescendants ).IsValid() )
			return PlayerRole.Soldier;

		return PlayerRole.Soldier;
	}
}
