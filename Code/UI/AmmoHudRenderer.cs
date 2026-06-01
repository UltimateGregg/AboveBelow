using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Rendering;

namespace DroneVsPlayers;

public static class AmmoHudRenderer
{
	public static RenderFragment Render( string roleClass, string label, string value ) => builder =>
	{
		var seq = 0;

		builder.OpenElement( seq++, "div" );
		builder.AddAttribute( seq++, "class", $"ammo-hud bottom-right-ammo {roleClass}".Trim() );

		builder.OpenElement( seq++, "div" );
		builder.AddAttribute( seq++, "class", "ammo-label" );
		builder.AddContent( seq++, label );
		builder.CloseElement();

		builder.OpenElement( seq++, "div" );
		builder.AddAttribute( seq++, "class", "ammo-value" );
		builder.AddContent( seq++, value );
		builder.CloseElement();

		builder.CloseElement();
	};
}
