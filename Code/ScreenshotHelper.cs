using Sandbox;

public class ScreenshotHelper : Component
{
	/// <summary>
	/// Takes a high-resolution screenshot using the console command.
	/// Call via: new ScreenshotHelper().TakeScreenshot("filename");
	/// </summary>
	public void TakeScreenshot( string filename = "screenshot" )
	{
		ConsoleSystem.Run( $"screenshot_highres {filename}" );
	}

	/// <summary>
	/// Takes a screenshot and saves it with timestamp.
	/// </summary>
	public void TakeTimestampedScreenshot()
	{
		var timestamp = System.DateTime.Now.ToString( "yyyy-MM-dd_HH-mm-ss" );
		TakeScreenshot( $"screenshot_{timestamp}" );
	}

	/// <summary>
	/// Continuous screenshot capture at specified intervals (in seconds).
	/// </summary>
	public async void StartContinuousCapture( float intervalSeconds = 5f )
	{
		int frameCount = 0;
		while ( true )
		{
			await Task.Delay( (int)(intervalSeconds * 1000) );
			TakeScreenshot( $"capture_{frameCount:D4}" );
			frameCount++;
		}
	}
}
