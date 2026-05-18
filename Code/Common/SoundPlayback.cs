using Sandbox;

namespace DroneVsPlayers;

internal static class SoundPlayback
{
	public static SoundHandle PlayAttached( SoundEvent sound, Component owner, Vector3 worldPosition, float fadeTime = 0f )
	{
		return PlayAttached( sound, owner?.GameObject, worldPosition, fadeTime );
	}

	public static SoundHandle PlayAttached( SoundEvent sound, GameObject parent, Vector3 worldPosition, float fadeTime = 0f )
	{
		if ( sound is null )
			return null;

		var handle = Sound.Play( sound, worldPosition, fadeTime );
		UpdateAttached( handle, parent, worldPosition );
		return handle;
	}

	public static void UpdateAttached( SoundHandle handle, GameObject parent, Vector3 worldPosition )
	{
		if ( handle is null || !handle.IsValid )
			return;

		if ( parent.IsValid() )
			handle.Parent = parent;

		handle.Position = worldPosition;
	}
}
