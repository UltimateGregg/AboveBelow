namespace DroneVsPlayers;

/// <summary>
/// One attributed item in the credits list. <see cref="Author"/> and
/// <see cref="Detail"/> are optional (e.g. a heading-only "thanks" line).
/// </summary>
public readonly record struct CreditEntry( string Title, string Author = "", string Detail = "" );

/// <summary>
/// A titled group of <see cref="CreditEntry"/> rows shown in the credits overlay.
/// </summary>
public readonly record struct CreditSection( string Heading, CreditEntry[] Entries );

/// <summary>
/// Source-of-truth for the main-menu credits overlay. Edit this list to update
/// attribution; the active HUD main menu renders it.
///
/// Authors are taken from the asset.party package idents (<c>author.asset</c>) in
/// <c>dronevsplayers.sbproj</c> PackageReferences and from each library's LICENSE.
/// </summary>
public static class CreditsData
{
	public static readonly CreditSection[] Sections =
	{
		new( "Engine & Platform", new CreditEntry[]
		{
			new( "s&box", "Facepunch Studios", "Engine, Citizen model & base content" ),
		} ),

		new( "Libraries", new CreditEntry[]
		{
			new( "WaterTool", "K3rhos", "MIT License — © 2026 K3rhos" ),
		} ),

		new( "Environment & Art", new CreditEntry[]
		{
			new( "Blue Cloud Skybox", "semxy" ),
			new( "Concrete Barrier & Barrier Post", "way" ),
			new( "Military Radio", "defqwop" ),
			new( "Rock", "pundalf" ),
			new( "Rocks, Tent & Spruce Trees", "fish" ),
			new( "Low Poly Tree", "titanovsky" ),
		} ),

		new( "Facepunch Asset Packs", new CreditEntry[]
		{
			new( "Beech & Pine Shrubs, Bench Table, Fence Panels", "Facepunch" ),
			new( "Stock Weapon Viewmodels (sboxweapons)", "Facepunch" ),
		} ),

		new( "To Verify", new CreditEntry[]
		{
			new( "Sound effects", "", "Confirm whether original or sourced" ),
			new( "Assault rifle (M4) model", "", "Imported — original source unknown" ),
			new( "Terrain sand textures", "", "Confirm whether generated or sourced" ),
		} ),

		new( "Development Tools", new CreditEntry[]
		{
			new( "s&box MCP Server", "jtc" ),
			new( "Blender Bridge", "kamishell" ),
			new( "Claude Bridge", "sboxskinsgg" ),
		} ),

		new( "Special Thanks", new CreditEntry[]
		{
			new( "The s&box community" ),
		} ),
	};
}
