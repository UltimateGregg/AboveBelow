using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Rendering;

namespace DroneVsPlayers;

public static class InteractionPromptRenderer
{
	public static RenderFragment Render( string className, string inputGlyph, string label ) => builder =>
	{
		var seq = 0;
		var glyph = string.IsNullOrWhiteSpace( inputGlyph ) ? "E" : inputGlyph.Trim();

		builder.OpenElement( seq++, "div" );
		builder.AddAttribute( seq++, "class", className );

		if ( glyph.Equals( "LMB", System.StringComparison.OrdinalIgnoreCase ) )
		{
			builder.OpenElement( seq++, "div" );
			builder.AddAttribute( seq++, "class", "mouse-icon lmb" );
			builder.OpenElement( seq++, "div" );
			builder.AddAttribute( seq++, "class", "mouse-button left" );
			builder.CloseElement();
			builder.OpenElement( seq++, "div" );
			builder.AddAttribute( seq++, "class", "mouse-button right" );
			builder.CloseElement();
			builder.OpenElement( seq++, "div" );
			builder.AddAttribute( seq++, "class", "mouse-wheel" );
			builder.CloseElement();
			builder.CloseElement();
		}
		else
		{
			builder.OpenElement( seq++, "div" );
			builder.AddAttribute( seq++, "class", "key-icon" );
			builder.AddContent( seq++, glyph.ToUpperInvariant() );
			builder.CloseElement();
		}

		builder.OpenElement( seq++, "div" );
		builder.AddAttribute( seq++, "class", "interaction-prompt-copy drone-action-copy" );
		builder.AddContent( seq++, label );
		builder.CloseElement();

		builder.CloseElement();
	};
}
