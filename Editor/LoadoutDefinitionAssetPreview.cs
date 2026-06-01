#if DEBUG
namespace DroneVsPlayers;

/// <summary>
/// Registers the custom loadout resource extension with the editor preview
/// pipeline. Rich thumbnail rendering can be added after the exact editor
/// preview renderer API is verified; for now the resource itself carries
/// preview model/image metadata.
/// </summary>
[AssetPreview("dvploadout")]
public sealed class LoadoutDefinitionAssetPreview
{
}
#endif
