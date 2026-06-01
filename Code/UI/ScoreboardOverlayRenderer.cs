using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Rendering;
using System;
using System.Collections.Generic;

namespace DroneVsPlayers;

public static class ScoreboardOverlayRenderer
{
	public static RenderFragment Render( IReadOnlyList<ScoreboardRow> rows ) => builder =>
	{
		var seq = 0;
		rows ??= Array.Empty<ScoreboardRow>();

		builder.OpenElement( seq++, "div" );
		builder.AddAttribute( seq++, "class", "scoreboard-overlay scoreboard" );

		builder.OpenElement( seq++, "div" );
		builder.AddAttribute( seq++, "class", "scoreboard-inner" );

		builder.OpenElement( seq++, "div" );
		builder.AddAttribute( seq++, "class", "scoreboard-title" );
		builder.AddContent( seq++, "SCOREBOARD" );
		builder.CloseElement();

		builder.OpenElement( seq++, "div" );
		builder.AddAttribute( seq++, "class", "scoreboard-table" );

		builder.OpenElement( seq++, "div" );
		builder.AddAttribute( seq++, "class", "scoreboard-header" );
		AddCell( builder, ref seq, "col-name", "Player" );
		AddCell( builder, ref seq, "col-k", "K" );
		AddCell( builder, ref seq, "col-d", "D" );
		AddCell( builder, ref seq, "col-s", "Score" );
		builder.CloseElement();

		foreach ( var row in rows )
		{
			builder.OpenElement( seq++, "div" );
			builder.AddAttribute( seq++, "class", "scoreboard-row" );
			AddCell( builder, ref seq, "col-name", row.Name );
			AddCell( builder, ref seq, "col-k", row.Kills );
			AddCell( builder, ref seq, "col-d", row.Deaths );
			AddCell( builder, ref seq, "col-s", row.Score );
			builder.CloseElement();
		}

		builder.CloseElement();
		builder.CloseElement();
		builder.CloseElement();
	};

	static void AddCell( RenderTreeBuilder builder, ref int seq, string className, object value )
	{
		builder.OpenElement( seq++, "span" );
		builder.AddAttribute( seq++, "class", className );
		builder.AddContent( seq++, value );
		builder.CloseElement();
	}
}
