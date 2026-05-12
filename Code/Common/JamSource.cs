using System;

namespace DroneVsPlayers;

/// <summary>
/// One active jamming influence on a drone. Tracked host-side by JammingReceiver.
/// Multiple sources stack; the strongest contribution wins.
/// </summary>
public struct JamSource
{
	public Guid SourceId;
	public float Strength;
	public float ExpiresAt;
}
