#if DEBUG
using Sandbox;
using SboxMcp.Handlers;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Editor-only recovery command for syncing pine collision helpers into a live
/// scene when the editor keeps a stale scene graph after source JSON changes.
/// </summary>
public static class PineTreeCollisionEditorCommands
{
	enum PineVariant
	{
		Default,
		Broad,
		Windswept
	}

	readonly record struct BranchSpec( string Name, Vector3 Start, Vector3 End, float Radius, string Kind );
	readonly record struct CollisionSpec( string Name, Vector3 Position, Rotation Rotation, Vector3 Scale );

	[ConCmd( "dvp_sync_pine_branch_collision" )]
	public static void SyncPineBranchCollision()
	{
		var scene = EditorSession.ActiveScene ?? Game.ActiveScene;
		if ( scene is null )
		{
			Log.Warning( "[PineCollisionSync] No active scene." );
			return;
		}

		var pineTrees = scene.GetAllObjects( false )
			.Where( TryGetPineVariant )
			.ToList();

		var synced = 0;
		foreach ( var tree in pineTrees )
		{
			if ( !TryGetPineVariant( tree, out var variant ) )
				continue;

			RemoveRootColliders( tree );
			RemoveGeneratedCollisionChildren( tree );

			foreach ( var spec in BuildCollisionSpecs( variant ) )
				CreateCollisionChild( tree, spec );

			synced++;
		}

		EditorChanges.MarkDirty( "Sync pine tree collision" );
		Log.Info( $"[PineCollisionSync] Synced {synced} pine tree(s): 1 trunk BoxCollider + {BranchSpecs.Count} branch BoxCollider children each. Oak/tree_oak models are ignored." );
	}

	static bool TryGetPineVariant( GameObject tree )
	{
		return TryGetPineVariant( tree, out _ );
	}

	static bool TryGetPineVariant( GameObject tree, out PineVariant variant )
	{
		variant = PineVariant.Default;
		var renderer = tree.Components.Get<ModelRenderer>();
		var modelName = renderer?.Model?.Name?.ToLowerInvariant() ?? "";
		if ( string.IsNullOrWhiteSpace( modelName ) )
			return false;

		if ( modelName.EndsWith( "terrain_pine_broad", StringComparison.OrdinalIgnoreCase ) )
		{
			variant = PineVariant.Broad;
			return true;
		}

		if ( modelName.EndsWith( "terrain_pine_windswept", StringComparison.OrdinalIgnoreCase ) )
		{
			variant = PineVariant.Windswept;
			return true;
		}

		if ( modelName.EndsWith( "terrain_assets", StringComparison.OrdinalIgnoreCase )
			|| modelName.EndsWith( "terrain_pine", StringComparison.OrdinalIgnoreCase ) )
		{
			variant = PineVariant.Default;
			return true;
		}

		return false;
	}

	static void RemoveRootColliders( GameObject tree )
	{
		foreach ( var collider in tree.Components.GetAll().OfType<Collider>().ToList() )
			collider.Destroy();
	}

	static void RemoveGeneratedCollisionChildren( GameObject tree )
	{
		foreach ( var child in tree.Children.ToList() )
		{
			if ( child.Name.StartsWith( "Collision_Trunk", StringComparison.OrdinalIgnoreCase )
				|| child.Name.StartsWith( "Collision_Branch_", StringComparison.OrdinalIgnoreCase ) )
			{
				child.Destroy();
			}
		}
	}

	static IEnumerable<CollisionSpec> BuildCollisionSpecs( PineVariant variant )
	{
		yield return BuildTrunkSpec( variant );
		foreach ( var branch in BranchSpecs )
			yield return BuildBranchSpec( variant, branch );
	}

	static CollisionSpec BuildTrunkSpec( PineVariant variant )
	{
		var start = ToSboxUnits( Vector3.Zero, variant );
		var end = ToSboxUnits( new Vector3( 0f, 0f, 15.2f ), variant );
		var delta = end - start;
		var width = variant == PineVariant.Broad ? 90f : 82f;
		return new CollisionSpec(
			"Collision_Trunk",
			(start + end) * 0.5f,
			RotationFromXAxis( delta ),
			new Vector3( delta.Length + 10f, width, width ) );
	}

	static CollisionSpec BuildBranchSpec( PineVariant variant, BranchSpec branch )
	{
		var start = ToSboxUnits( branch.Start, variant );
		var end = ToSboxUnits( branch.End, variant );
		var delta = end - start;
		var thickness = GetBranchThickness( branch, variant );
		return new CollisionSpec(
			branch.Name,
			(start + end) * 0.5f,
			RotationFromXAxis( delta ),
			new Vector3( delta.Length + MathF.Max( 10f, thickness * 0.25f ), thickness, thickness ) );
	}

	static void CreateCollisionChild( GameObject tree, CollisionSpec spec )
	{
		var child = new GameObject( tree, true, spec.Name )
		{
			LocalPosition = spec.Position,
			LocalRotation = spec.Rotation,
			LocalScale = Vector3.One
		};

		var collider = child.Components.Create<BoxCollider>();
		collider.Center = Vector3.Zero;
		collider.Scale = spec.Scale;
		collider.IsTrigger = false;
		collider.Static = true;
	}

	static float GetBranchThickness( BranchSpec branch, PineVariant variant )
	{
		var baseThickness = branch.Radius * 200f;
		var thickness = branch.Kind switch
		{
			"whorl" => MathF.Max( 56f, baseThickness + 32f ),
			"root_flare" => MathF.Max( 32f, baseThickness + 18f ),
			_ => MathF.Max( 24f, baseThickness + 16f )
		};

		return variant switch
		{
			PineVariant.Broad => thickness * 1.12f,
			PineVariant.Windswept => thickness * 0.94f,
			_ => thickness
		};
	}

	static Vector3 ToSboxUnits( Vector3 point, PineVariant variant )
	{
		var deformed = DeformPoint( point, variant );
		return deformed * 100f;
	}

	static Vector3 DeformPoint( Vector3 point, PineVariant variant )
	{
		var heightFactor = Math.Clamp( (point.z - 8.2f) / 6.8f, 0f, 1f );
		switch ( variant )
		{
			case PineVariant.Windswept:
			{
				var lean = MathF.Pow( heightFactor, 1.35f );
				return new Vector3(
					point.x * (0.82f + heightFactor * 0.08f) + lean * 0.82f,
					point.y * (0.78f + heightFactor * 0.12f),
					point.z * 1.08f );
			}
			case PineVariant.Broad:
			{
				var crown = MathF.Pow( heightFactor, 0.75f );
				return new Vector3(
					point.x * (1.05f + crown * 0.32f),
					point.y * (1.08f + crown * 0.24f),
					point.z * (0.90f + heightFactor * 0.03f) );
			}
			default:
				return point;
		}
	}

	static Rotation RotationFromXAxis( Vector3 direction )
	{
		var target = direction.Normal;
		var dot = Math.Clamp( target.x, -1f, 1f );
		if ( dot > 0.999999f )
			return Rotation.Identity;
		if ( dot < -0.999999f )
			return new Rotation( 0f, 0f, 1f, 0f );

		var quat = new Rotation( 0f, -target.z, target.y, 1f + dot );
		return quat.Normal;
	}

	static readonly IReadOnlyList<BranchSpec> BranchSpecs = new List<BranchSpec>
	{
		new( "Collision_Branch_RootFlare_01", PointFromAngle( 18f, 0.11f, 0.24f ), PointFromAngle( 18f, 0.72f, 0.08f ), 0.085f, "root_flare" ),
		new( "Collision_Branch_RootFlare_02", PointFromAngle( 93f, 0.11f, 0.24f ), PointFromAngle( 93f, 0.72f, 0.08f ), 0.085f, "root_flare" ),
		new( "Collision_Branch_RootFlare_03", PointFromAngle( 161f, 0.11f, 0.24f ), PointFromAngle( 161f, 0.72f, 0.08f ), 0.085f, "root_flare" ),
		new( "Collision_Branch_RootFlare_04", PointFromAngle( 232f, 0.11f, 0.24f ), PointFromAngle( 232f, 0.72f, 0.08f ), 0.085f, "root_flare" ),
		new( "Collision_Branch_RootFlare_05", PointFromAngle( 306f, 0.11f, 0.24f ), PointFromAngle( 306f, 0.72f, 0.08f ), 0.085f, "root_flare" ),
		new( "Collision_Branch_DeadStub_01", PointFromAngle( 72f, 0.10f, 3.1f ), PointFromAngle( 72f, 0.34f, 3.18f ), 0.045f, "dead_stub" ),
		new( "Collision_Branch_DeadStub_02", PointFromAngle( 25f, 0.10f, 4.15f ), PointFromAngle( 25f, 0.55f, 4.23f ), 0.045f, "dead_stub" ),
		new( "Collision_Branch_DeadStub_03", PointFromAngle( 205f, 0.10f, 5.4f ), PointFromAngle( 205f, 0.72f, 5.48f ), 0.045f, "dead_stub" ),
		new( "Collision_Branch_DeadStub_04", PointFromAngle( 325f, 0.10f, 6.55f ), PointFromAngle( 325f, 0.62f, 6.63f ), 0.045f, "dead_stub" ),
		new( "Collision_Branch_DeadStub_05", PointFromAngle( 145f, 0.10f, 7.8f ), PointFromAngle( 145f, 0.82f, 7.88f ), 0.045f, "dead_stub" ),
		new( "Collision_Branch_DeadStub_06", PointFromAngle( 268f, 0.10f, 8.75f ), PointFromAngle( 268f, 0.58f, 8.83f ), 0.045f, "dead_stub" ),
		new( "Collision_Branch_Whorl_01", new Vector3( 0.118142f, 0.021851f, 9.35f ), new Vector3( 3.244810f, 0.600207f, 9.642680f ), 0.066f, "whorl" ),
		new( "Collision_Branch_Whorl_02", new Vector3( -0.001464f, 0.119991f, 9.35f ), new Vector3( -0.040420f, 3.299752f, 9.575643f ), 0.066f, "whorl" ),
		new( "Collision_Branch_Whorl_03", new Vector3( -0.116520f, -0.028684f, 9.35f ), new Vector3( -3.204312f, -0.788999f, 9.595297f ), 0.066f, "whorl" ),
		new( "Collision_Branch_Whorl_04", new Vector3( 0.021727f, -0.118016f, 9.35f ), new Vector3( 0.597743f, -3.245342f, 9.539740f ), 0.066f, "whorl" ),
		new( "Collision_Branch_Whorl_05", new Vector3( 0.089814f, 0.079604f, 10.05f ), new Vector3( 2.282367f, 2.023112f, 10.284553f ), 0.060f, "whorl" ),
		new( "Collision_Branch_Whorl_06", new Vector3( -0.094636f, 0.073729f, 10.05f ), new Vector3( -2.405826f, 1.873398f, 10.378502f ), 0.060f, "whorl" ),
		new( "Collision_Branch_Whorl_07", new Vector3( -0.073817f, -0.094568f, 10.05f ), new Vector3( -1.875184f, -2.404435f, 10.285994f ), 0.060f, "whorl" ),
		new( "Collision_Branch_Whorl_08", new Vector3( 0.086461f, -0.083212f, 10.05f ), new Vector3( 2.197577f, -2.114824f, 10.308852f ), 0.060f, "whorl" ),
		new( "Collision_Branch_Whorl_09", new Vector3( 0.115929f, 0.031002f, 10.82f ), new Vector3( 2.627543f, 0.702553f, 11.000106f ), 0.054f, "whorl" ),
		new( "Collision_Branch_Whorl_10", new Vector3( -0.044866f, 0.111303f, 10.82f ), new Vector3( -1.017935f, 2.523544f, 10.970064f ), 0.054f, "whorl" ),
		new( "Collision_Branch_Whorl_11", new Vector3( -0.116087f, -0.030386f, 10.82f ), new Vector3( -2.631266f, -0.688061f, 10.971577f ), 0.054f, "whorl" ),
		new( "Collision_Branch_Whorl_12", new Vector3( 0.049229f, -0.109444f, 10.82f ), new Vector3( 1.115719f, -2.480734f, 10.963852f ), 0.054f, "whorl" ),
		new( "Collision_Branch_Whorl_13", new Vector3( 0.077248f, 0.091835f, 11.6f ), new Vector3( 1.506456f, 1.789959f, 11.874827f ), 0.048f, "whorl" ),
		new( "Collision_Branch_Whorl_14", new Vector3( -0.119806f, 0.006821f, 11.6f ), new Vector3( -2.336210f, 0.133014f, 11.765974f ), 0.048f, "whorl" ),
		new( "Collision_Branch_Whorl_15", new Vector3( 0.063012f, -0.102127f, 11.6f ), new Vector3( 1.228094f, -1.991542f, 11.848883f ), 0.048f, "whorl" ),
		new( "Collision_Branch_Whorl_16", new Vector3( 0.087193f, 0.082410f, 12.38f ), new Vector3( 1.424235f, 1.346020f, 12.529551f ), 0.042f, "whorl" ),
		new( "Collision_Branch_Whorl_17", new Vector3( -0.094506f, 0.073896f, 12.38f ), new Vector3( -1.543594f, 1.207035f, 12.636797f ), 0.042f, "whorl" ),
		new( "Collision_Branch_Whorl_18", new Vector3( -0.014139f, -0.119164f, 12.38f ), new Vector3( -0.230687f, -1.944321f, 12.621284f ), 0.042f, "whorl" ),
		new( "Collision_Branch_Whorl_19", new Vector3( 0.003678f, 0.119944f, 13.12f ), new Vector3( 0.047953f, 1.559262f, 13.358956f ), 0.036f, "whorl" ),
		new( "Collision_Branch_Whorl_20", new Vector3( -0.112520f, -0.041702f, 13.12f ), new Vector3( -1.462239f, -0.542961f, 13.275416f ), 0.036f, "whorl" ),
		new( "Collision_Branch_Whorl_21", new Vector3( 0.107904f, -0.052528f, 13.12f ), new Vector3( 1.402412f, -0.682529f, 13.383807f ), 0.036f, "whorl" ),
		new( "Collision_Branch_Whorl_22", new Vector3( 0.102451f, 0.062507f, 13.86f ), new Vector3( 0.956919f, 0.583733f, 14.142614f ), 0.031f, "whorl" ),
		new( "Collision_Branch_Whorl_23", new Vector3( -0.117429f, 0.024699f, 13.86f ), new Vector3( -1.096005f, 0.230526f, 14.052932f ), 0.031f, "whorl" ),
		new( "Collision_Branch_Whorl_24", new Vector3( 0.031779f, -0.115716f, 13.86f ), new Vector3( 0.296602f, -1.079864f, 14.087546f ), 0.031f, "whorl" ),
		new( "Collision_Branch_Whorl_25", new Vector3( -0.019558f, 0.118396f, 14.55f ), new Vector3( -0.117532f, 0.711200f, 14.799996f ), 0.026f, "whorl" ),
		new( "Collision_Branch_Whorl_26", new Vector3( -0.053830f, -0.107248f, 14.55f ), new Vector3( -0.322944f, -0.643437f, 14.678784f ), 0.026f, "whorl" ),
	};

	static Vector3 PointFromAngle( float degrees, float radius, float z )
	{
		var radians = degrees.DegreeToRadian();
		return new Vector3( MathF.Cos( radians ) * radius, MathF.Sin( radians ) * radius, z );
	}
}
#endif
