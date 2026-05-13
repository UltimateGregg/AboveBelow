using Sandbox;
using System;

namespace DroneVsPlayers;

internal static class LocalOptionsState
{
	const string UiScaleCookieKey = "dvplayers.ui_scale";
	const string LookSensitivityCookieKey = "dvplayers.look_sensitivity";

	internal const float MinUiScale = 0.75f;
	internal const float MaxUiScale = 1.4f;
	internal const float UiScaleStep = 0.05f;
	internal const float MinLookSensitivity = 0.2f;
	internal const float MaxLookSensitivity = 3f;
	internal const float LookSensitivityStep = 0.05f;

	static readonly string[] GameplayActions =
	{
		"Attack1",
		"Attack2",
		"Reload",
		"Use",
		"Slot1",
		"Slot2",
		"Slot3",
		"Slot4",
		"Slot5",
		"Slot6",
		"Slot7",
		"Slot8",
		"Slot9",
		"Slot0",
		"SlotPrev",
		"SlotNext",
		"Run",
		"Duck",
		"Crouch",
		"Jump",
		"ToggleDroneCamera",
		"TogglePilotControl"
	};

	static bool _settingsLoaded;
	static float _uiScale = 1f;
	static float _lookSensitivity = 1f;

	internal static bool IsOpen { get; private set; }
	internal static bool ConsumesGameplayInput => IsOpen;

	internal static float UiScale
	{
		get
		{
			EnsureSettingsLoaded();
			return _uiScale;
		}
	}

	internal static int UiScalePercent => (int)MathF.Round( UiScale * 100f );

	internal static float LookSensitivity
	{
		get
		{
			EnsureSettingsLoaded();
			return _lookSensitivity;
		}
	}

	internal static void ToggleOpen()
	{
		SetOpen( !IsOpen );
	}

	internal static void SetOpen( bool open )
	{
		IsOpen = open;
		if ( IsOpen )
			ClearGameplayActions();
	}

	internal static void AdjustUiScale( float delta )
	{
		SetUiScale( UiScale + delta );
	}

	internal static void ResetUiScale()
	{
		SetUiScale( 1f );
	}

	internal static void AdjustLookSensitivity( float delta )
	{
		SetLookSensitivity( LookSensitivity + delta );
	}

	internal static void ApplyTo( ScreenPanel screenPanel )
	{
		if ( !screenPanel.IsValid() ) return;
		screenPanel.Scale = UiScale;
	}

	internal static void ClearGameplayActions()
	{
		foreach ( var action in GameplayActions )
			Input.Clear( action );
	}

	static void EnsureSettingsLoaded()
	{
		if ( _settingsLoaded ) return;

		_uiScale = SnapScale( Game.Cookies.Get( UiScaleCookieKey, 1f ) );
		_lookSensitivity = SnapLookSensitivity( Game.Cookies.Get( LookSensitivityCookieKey, 1f ) );
		_settingsLoaded = true;
	}

	static void SetUiScale( float scale )
	{
		EnsureSettingsLoaded();

		var snapped = SnapScale( scale );
		if ( MathF.Abs( _uiScale - snapped ) < 0.001f )
			return;

		_uiScale = snapped;
		Game.Cookies.Set( UiScaleCookieKey, _uiScale );
	}

	static void SetLookSensitivity( float sensitivity )
	{
		EnsureSettingsLoaded();

		var snapped = SnapLookSensitivity( sensitivity );
		if ( MathF.Abs( _lookSensitivity - snapped ) < 0.001f )
			return;

		_lookSensitivity = snapped;
		Game.Cookies.Set( LookSensitivityCookieKey, _lookSensitivity );
	}

	static float SnapScale( float value )
	{
		var clamped = Math.Clamp( value, MinUiScale, MaxUiScale );
		return MathF.Round( clamped / UiScaleStep ) * UiScaleStep;
	}

	static float SnapLookSensitivity( float value )
	{
		var clamped = Math.Clamp( value, MinLookSensitivity, MaxLookSensitivity );
		return MathF.Round( clamped / LookSensitivityStep ) * LookSensitivityStep;
	}
}
