using Sandbox;
using System.ComponentModel;
using System.Threading.Tasks;
using SboxMcp.Handlers;

namespace SboxMcp.Mcp.Tools;

[McpToolGroup]
public static class SoundTools
{
	[McpTool( "sound_list", Description = "List local project SoundEvent (.sound) assets, with source and missing-source summary." )]
	public static Task<object> ListSounds(
		[Description( "Optional case-insensitive path/name filter." )] string query = null ) =>
		HandlerDispatcher.InvokeAsync( "sound.list", new { query }, SoundHandler.ListSounds );

	[McpTool( "sound_inspect", Description = "Inspect a local project SoundEvent, or an editor-resolvable mounted SoundEvent for discovery only." )]
	public static Task<object> InspectSound(
		[Description( "SoundEvent path or name, e.g. sounds/drone_hum.sound, drone_hum, or sounds/assault_rifle_fire.sound." )] string sound ) =>
		HandlerDispatcher.InvokeAsync( "sound.inspect", new { sound }, SoundHandler.InspectSound );

	[McpTool( "sound_create_event", Description = "Create a local SoundEvent wrapper from one or more existing source audio files under Assets/sounds." )]
	public static Task<object> CreateSoundEvent(
		[Description( "New SoundEvent name. .sound is optional." )] string name,
		[Description( "One or more source audio paths." )] string[] sources,
		[Description( "Output resource directory, default sounds." )] string directory = null,
		[Description( "Whether this is flat 2D UI audio." )] bool? ui = null,
		[Description( "Volume scalar as a string, default 1." )] string volume = null,
		[Description( "Pitch scalar as a string, default 1." )] string pitch = null,
		[Description( "Audible distance for 3D sounds." )] float? distance = null,
		[Description( "Decibel loudness value." )] int? decibels = null ) =>
		HandlerDispatcher.InvokeAsync( "sound.create_event", new { name, sources, directory, ui, volume, pitch, distance, decibels }, SoundHandler.CreateSoundEvent );

	[McpTool( "sound_preview", Description = "Play a local project SoundEvent in the editor at the listener, a world position, or a target GameObject." )]
	public static Task<object> PreviewSound(
		[Description( "SoundEvent path or name, e.g. sounds/drone_hum.sound, drone_hum, or sounds/assault_rifle_fire.sound." )] string sound,
		[Description( "Optional world position as x,y,z." )] string position = null,
		[Description( "Optional target GameObject id. Overrides position when supplied." )] string objectId = null,
		[Description( "Whether the preview should follow objectId." )] bool? followObject = null,
		[Description( "Preview volume scalar." )] float? volume = null,
		[Description( "Fade-in seconds." )] float? fadeIn = null ) =>
		HandlerDispatcher.InvokeAsync( "sound.preview", new { sound, position, objectId, followObject, volume, fadeIn }, SoundHandler.PreviewSound );

	[McpTool( "sound_place_point", Description = "Create a GameObject with SoundPointComponent wired to a SoundEvent in the active scene." )]
	public static Task<object> PlaceSoundPoint(
		[Description( "SoundEvent path or name." )] string sound,
		[Description( "World position as x,y,z. Defaults to origin." )] string position = null,
		[Description( "Optional GameObject name." )] string name = null,
		[Description( "Optional parent GameObject id." )] string parentId = null,
		[Description( "Start the sound immediately after creating the component." )] bool? startNow = null ) =>
		HandlerDispatcher.InvokeAsync( "sound.place_point", new { sound, position, name, parentId, startNow }, SoundHandler.PlaceSoundPoint );

	[McpTool( "sound_find_hooks", Description = "Find SoundEvent properties on components in the active scene so they can be inspected or wired." )]
	public static Task<object> FindSoundHooks() =>
		HandlerDispatcher.InvokeAsync( "sound.find_hooks", null, SoundHandler.FindSoundHooks );
}
