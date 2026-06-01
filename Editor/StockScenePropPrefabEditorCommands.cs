#if DEBUG
using Sandbox;
using SboxMcp.Handlers;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Editor-only migration helpers for replacing direct stock model placements
/// with prefab-backed scene objects once the stock prop templates exist.
/// </summary>
public static class StockScenePropPrefabEditorCommands
{
	readonly record struct StockPrefabTemplate( string ModelName, string PrefabPath );
	readonly record struct MigrationCandidate( GameObject Source, StockPrefabTemplate Template );

	static readonly StockPrefabTemplate[] Templates =
	{
		new( "beech_shrub_wide_small", "prefabs/environment/stock/beech_shrub_wide_small.prefab" ),
		new( "pine_shrub_tall_b", "prefabs/environment/stock/pine_shrub_tall_b.prefab" ),
		new( "beech_bush_medium_wall", "prefabs/environment/stock/beech_bush_medium_wall.prefab" ),
		new( "beech_bush_regular_medium_b", "prefabs/environment/stock/beech_bush_regular_medium_b.prefab" ),
		new( "beech_hedge_96x128_corner", "prefabs/environment/stock/beech_hedge_96x128_corner.prefab" ),
		new( "fence_panel_large", "prefabs/environment/stock/fence_panel_large.prefab" ),
		new( "fence_panel_large_bent", "prefabs/environment/stock/fence_panel_large_bent.prefab" ),
		new( "bench_table_01", "prefabs/environment/stock/bench_table_01.prefab" ),
		new( "old_bench", "prefabs/environment/stock/old_bench.prefab" ),
		new( "iron_fence_128", "prefabs/environment/stock/iron_fence_128.prefab" ),
		new( "tree_oak_big_a", "prefabs/environment/stock/tree_oak_big_a.prefab" ),
		new( "street_bin_rubbish", "prefabs/environment/stock/street_bin_rubbish.prefab" )
	};

	[ConCmd( "dvp_preview_stock_scene_prop_prefab_migration" )]
	public static void PreviewMigration()
	{
		var scene = GetActiveScene();
		if ( scene is null )
			return;

		var candidates = FindCandidates( scene ).ToList();
		Log.Info( $"[StockPrefabMigration] Found {candidates.Count} direct stock scene prop(s) that can be prefab-backed." );

		foreach ( var group in candidates.GroupBy( candidate => candidate.Template.PrefabPath ).OrderBy( group => group.Key ) )
			Log.Info( $"[StockPrefabMigration] {group.Count(),2} -> {group.Key}" );
	}

	[ConCmd( "dvp_migrate_stock_scene_props_to_prefabs" )]
	public static void MigrateStockScenePropsToPrefabs()
	{
		var scene = GetActiveScene();
		if ( scene is null )
			return;

		var candidates = FindCandidates( scene ).ToList();
		var migrated = 0;

		foreach ( var candidate in candidates )
		{
			var source = candidate.Source;
			if ( !source.IsValid() )
				continue;

			var clone = GameObject.Clone(
				candidate.Template.PrefabPath,
				new Transform( source.LocalPosition, source.LocalRotation, source.LocalScale ),
				source.Parent,
				source.Enabled,
				source.Name );

			if ( !clone.IsValid() )
			{
				Log.Warning( $"[StockPrefabMigration] Failed to clone {candidate.Template.PrefabPath} for '{source.Name}'." );
				continue;
			}

			clone.NetworkMode = source.NetworkMode;
			foreach ( var tag in source.Tags )
				clone.Tags.Add( tag );

			if ( string.IsNullOrWhiteSpace( clone.PrefabInstanceSource ) )
				Log.Warning( $"[StockPrefabMigration] '{clone.Name}' cloned from {candidate.Template.PrefabPath} without prefab source metadata." );

			source.Destroy();
			migrated++;
		}

		if ( migrated > 0 )
			EditorChanges.MarkDirty( "Migrate stock scene props to prefabs" );

		Log.Info( $"[StockPrefabMigration] Migrated {migrated} direct stock scene prop(s) to prefab-backed roots." );
	}

	static Scene GetActiveScene()
	{
		var scene = EditorSession.ActiveScene ?? Game.ActiveScene;
		if ( scene is null )
			Log.Warning( "[StockPrefabMigration] No active scene." );

		return scene;
	}

	static IEnumerable<MigrationCandidate> FindCandidates( Scene scene )
	{
		foreach ( var source in scene.GetAllObjects( false ) )
		{
			if ( source.IsPrefabInstance || !string.IsNullOrWhiteSpace( source.PrefabInstanceSource ) )
				continue;

			var renderer = source.Components.Get<ModelRenderer>();
			var modelName = renderer?.Model?.Name;
			if ( string.IsNullOrWhiteSpace( modelName ) )
				continue;

			foreach ( var template in Templates )
			{
				if ( modelName.Equals( template.ModelName, StringComparison.OrdinalIgnoreCase ) )
				{
					yield return new MigrationCandidate( source, template );
					break;
				}
			}
		}
	}
}
#endif
