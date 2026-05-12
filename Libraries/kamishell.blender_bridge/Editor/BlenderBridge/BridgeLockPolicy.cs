using System;
using System.Linq;
using Editor;
using Sandbox;

namespace BlenderBridge
{
	/// <summary>
	/// Per-object sync rules for the Blender bridge.
	/// </summary>
	[Flags]
	public enum BridgeLockFlags
	{
		None      = 0,
		/// <summary>Block all Blender → s&amp;box updates for this object.</summary>
		Inbound   = 1 << 0,
		/// <summary>Block all s&amp;box → Blender pushes for this object.</summary>
		Outbound  = 1 << 1,
		/// <summary>Allow geometry/transform updates from Blender, but never overwrite materials.</summary>
		Materials = 1 << 2,
		/// <summary>Allow material/transform updates from Blender, but never overwrite mesh geometry.</summary>
		Geometry  = 1 << 3,
		/// <summary>Allow geometry/material updates from Blender, but never overwrite position/rotation.</summary>
		Transform = 1 << 4,
	}

	/// <summary>
	/// Resolves and mutates per-GameObject lock policy. Single source of truth for
	/// "is this object syncing from Blender / to Blender / for materials / etc."
	///
	/// Storage: one tag of the form <c>bridge_lock_&lt;int&gt;</c> on the GameObject,
	/// plus implicit auto-locks:
	///   - <see cref="Sandbox.Terrain"/> components imply Inbound | Geometry | Materials.
	///   - The legacy <c>bridge_locked</c> tag (pre-flags) is treated as Inbound.
	///
	/// NOTE on the prefix: s&amp;box GameTags accept only [a-zA-Z0-9._-] (32 chars max).
	/// An earlier iteration used a colon ("bridge_lock:") which s&amp;box silently
	/// rejected as invalid, leaving the lock state with nowhere to persist. The
	/// underscore form is what actually round-trips through the tag system.
	/// </summary>
	internal static class BridgeLockPolicy
	{
		/// <summary>Pre-flags lock tag, kept for backward compatibility.</summary>
		internal const string LegacyLockTag = "bridge_locked";
		internal const string FlagTagPrefix = "bridge_lock_";

		/// <summary>Read the effective lock flags for a GameObject — explicit + implicit.</summary>
		public static BridgeLockFlags GetFlags( GameObject go )
		{
			if ( go == null ) return BridgeLockFlags.None;
			var flags = BridgeLockFlags.None;

			// Implicit: terrain components are read-only display from Blender.
			if ( go.Components.Get<Terrain>() != null )
				flags |= BridgeLockFlags.Inbound | BridgeLockFlags.Geometry | BridgeLockFlags.Materials;

			// Legacy tag = full inbound lock.
			if ( go.Tags.Has( LegacyLockTag ) )
				flags |= BridgeLockFlags.Inbound;

			// Explicit flag tag.
			foreach ( var tag in go.Tags.TryGetAll() )
			{
				if ( !tag.StartsWith( FlagTagPrefix, StringComparison.Ordinal ) ) continue;
				if ( int.TryParse( tag.Substring( FlagTagPrefix.Length ), out var v ) )
					flags |= (BridgeLockFlags)v;
			}

			return flags;
		}

		/// <summary>Replace the explicit flag tag on this GameObject. Implicit flags (Terrain) are unaffected.</summary>
		public static void SetExplicitFlags( GameObject go, BridgeLockFlags flags )
		{
			if ( go == null ) return;

			// Remove any prior explicit flag tag(s).
			foreach ( var tag in go.Tags.TryGetAll().ToList() )
			{
				if ( tag.StartsWith( FlagTagPrefix, StringComparison.Ordinal ) )
					go.Tags.Remove( tag );
			}

			if ( flags != BridgeLockFlags.None )
				go.Tags.Add( FlagTagPrefix + ((int)flags).ToString() );
		}

		/// <summary>Read the explicit (user-set) flags only — excludes Terrain auto-lock and legacy tag.</summary>
		public static BridgeLockFlags GetExplicitFlags( GameObject go )
		{
			if ( go == null ) return BridgeLockFlags.None;
			var flags = BridgeLockFlags.None;
			foreach ( var tag in go.Tags.TryGetAll() )
			{
				if ( !tag.StartsWith( FlagTagPrefix, StringComparison.Ordinal ) ) continue;
				if ( int.TryParse( tag.Substring( FlagTagPrefix.Length ), out var v ) )
					flags |= (BridgeLockFlags)v;
			}
			return flags;
		}

		/// <summary>Toggle a single flag on the explicit tag. Returns the new effective flag-set.</summary>
		public static BridgeLockFlags ToggleExplicit( GameObject go, BridgeLockFlags flag )
		{
			var current = GetExplicitFlags( go );
			var next = current.HasFlag( flag ) ? (current & ~flag) : (current | flag);
			SetExplicitFlags( go, next );
			return next;
		}

		// ── Decision helpers — what each handler asks ───────────────────────

		public static bool AllowsInbound( GameObject go )
			=> !GetFlags( go ).HasFlag( BridgeLockFlags.Inbound );

		public static bool AllowsOutbound( GameObject go )
			=> !GetFlags( go ).HasFlag( BridgeLockFlags.Outbound );

		public static bool AllowsTransformChange( GameObject go )
		{
			var f = GetFlags( go );
			return !f.HasFlag( BridgeLockFlags.Inbound ) && !f.HasFlag( BridgeLockFlags.Transform );
		}

		public static bool AllowsGeometryChange( GameObject go )
		{
			var f = GetFlags( go );
			return !f.HasFlag( BridgeLockFlags.Inbound ) && !f.HasFlag( BridgeLockFlags.Geometry );
		}

		public static bool AllowsMaterialChange( GameObject go )
		{
			var f = GetFlags( go );
			return !f.HasFlag( BridgeLockFlags.Inbound ) && !f.HasFlag( BridgeLockFlags.Materials );
		}
	}
}
