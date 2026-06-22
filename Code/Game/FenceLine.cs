using Sandbox;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Lays a whole run of fence sections in one step. Drop this on an empty GameObject,
/// assign the <c>FenceSplitRail</c> prefab as <see cref="SectionPrefab"/>, and set
/// <see cref="Count"/> — a continuous fence is generated along this object's local +X.
/// Move/rotate this object to position and aim the run; change Count/Spacing to extend
/// it; set <see cref="CurvePerSection"/> to sweep it into an arc.
///
/// The sections tile cleanly because each <c>FenceSplitRail</c> bay has one post at its
/// origin and rails reaching the next post one bay (~3 m) along, so the default
/// <see cref="Spacing"/> of 118 units (≈ 3 m at 39.37 u/m) lands a single shared post at
/// every joint. Optionally cap the far end with <see cref="EndPostPrefab"/>
/// (e.g. <c>FenceSplitRailCorner</c>).
///
/// Generated sections are regenerated each load and flagged <see cref="GameObjectFlags.NotSaved"/>,
/// so the component stays the single source of truth and the scene file is not bloated.
/// When you are happy with the layout, press <b>Bake to scene</b> to freeze the current
/// run into permanent, individually editable instances.
/// </summary>
[Title( "Fence Line" )]
[Category( "Drone vs Players/Environment" )]
[Icon( "fence" )]
public sealed class FenceLine : Component, Component.ExecuteInEditor
{
	const string GenTag = "fenceline_gen";

	/// <summary>The fence-section prefab to repeat (normally FenceSplitRail).</summary>
	[Property] public GameObject SectionPrefab { get; set; }

	/// <summary>How many sections to place in the run.</summary>
	[Property, Range( 1, 200 )] public int Count { get; set; } = 8;

	/// <summary>Distance between section origins, in world units. 118 ≈ one 3 m split-rail bay.</summary>
	[Property, Range( 24f, 400f )] public float Spacing { get; set; } = 118f;

	/// <summary>Yaw added per section (degrees) to sweep the run into an arc. 0 = dead straight.</summary>
	[Property, Range( -20f, 20f )] public float CurvePerSection { get; set; } = 0f;

	/// <summary>Optional post placed at the far end of the run (e.g. FenceSplitRailCorner).</summary>
	[Property] public GameObject EndPostPrefab { get; set; }

	string _lastSig;

	protected override void OnEnabled() => _lastSig = null;   // force a rebuild on enable
	protected override void OnDisabled() => ClearGenerated();

	protected override void OnUpdate()
	{
		// Only rebuild when an input actually changed (cheap signature compare each tick).
		var sig = Signature();
		if ( sig == _lastSig )
			return;
		_lastSig = sig;
		Rebuild();
	}

	string Signature()
	{
		var sp = SectionPrefab.IsValid() ? SectionPrefab.Id.ToString() : "none";
		var ep = EndPostPrefab.IsValid() ? EndPostPrefab.Id.ToString() : "none";
		return $"{sp}|{ep}|{Count}|{Spacing}|{CurvePerSection}";
	}

	void ClearGenerated()
	{
		foreach ( var child in GameObject.Children.Where( c => c.Tags.Has( GenTag ) ).ToList() )
			child.Destroy();
	}

	void Rebuild()
	{
		ClearGenerated();
		if ( !SectionPrefab.IsValid() || Count < 1 )
			return;

		var pos = Vector3.Zero;
		var heading = 0f;
		for ( int i = 0; i < Count; i++ )
		{
			// A split-rail bay's rails run along the model's local +Y (Blender +X maps to
			// s&box +Y on export), so face each section heading-90 to lay the rails ALONG
			// the run; the run itself advances down this object's local +X.
			Place( SectionPrefab, pos, heading - 90f, $"Section_{i:00}" );
			pos += Rotation.FromYaw( heading ).Forward * Spacing;
			heading += CurvePerSection;
		}

		if ( EndPostPrefab.IsValid() )
			Place( EndPostPrefab, pos, heading - 90f, "EndPost" );
	}

	void Place( GameObject prefab, Vector3 localPos, float localYaw, string name )
	{
		var clone = prefab.Clone( new CloneConfig
		{
			Transform = WorldTransform,
			Parent = GameObject,
			StartEnabled = true,
			Name = name,
		} );
		if ( !clone.IsValid() )
			return;

		// Place relative to this object so moving/rotating it carries the whole run.
		clone.LocalPosition = localPos;
		clone.LocalRotation = Rotation.FromYaw( localYaw );
		clone.Tags.Add( GenTag );
		clone.Flags |= GameObjectFlags.NotSaved;
	}

	/// <summary>
	/// Freeze the current run: drop the generated/not-saved flags so the sections become
	/// permanent, individually editable instances, then disable this builder so it stops
	/// regenerating. Delete the component afterwards if you no longer need to re-lay it.
	/// </summary>
	[Button( "Bake to scene (freeze)" )]
	public void BakeToScene()
	{
		foreach ( var child in GameObject.Children.Where( c => c.Tags.Has( GenTag ) ).ToList() )
		{
			child.Tags.Remove( GenTag );
			child.Flags &= ~GameObjectFlags.NotSaved;
		}
		_lastSig = "baked";   // don't immediately regenerate a second run on top
		Enabled = false;
	}
}
