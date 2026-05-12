using System.Collections.Concurrent;
using System.IO;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace DroneVsPlayers.Editor;

/// <summary>
/// HTTP bridge that exposes editor introspection / mutation to an external MCP
/// server. Designed for local-only use during development; do not enable on
/// shared machines.
///
/// Architecture:
///   - HttpListener thread receives requests, places them on a queue.
///   - [EditorEvent.Frame] pump drains the queue on the editor thread, runs the
///     handler against SceneEditorSession.Active, and signals completion.
///   - HTTP thread serializes the result and sends the response.
///
/// All scene access happens on the editor thread, which matches how the
/// engine's own tools manipulate the scene (see SceneEditorSession usage in
/// addons/tools/Code/Scene/).
/// </summary>
public static class CoworkBridge
{
	const int Port = 38080;
	const string Prefix = "http://127.0.0.1:38080/";

	static HttpListener _listener;
	static Thread _listenerThread;
	static CancellationTokenSource _cts;
	static readonly ConcurrentQueue<PendingRequest> _queue = new();
	public static bool IsRunning => _listener?.IsListening ?? false;

	class PendingRequest
	{
		public HttpListenerContext Context;
		public ManualResetEventSlim Done = new( false );
		public string ResponseBody;
		public int ResponseStatus = 200;
	}

	[Menu( "Editor", "Cowork/Start MCP Bridge" )]
	public static void Start()
	{
		if ( IsRunning )
		{
			Log.Info( "[CoworkBridge] Already running on " + Prefix );
			return;
		}

		_listener = new HttpListener();
		_listener.Prefixes.Add( Prefix );

		try
		{
			_listener.Start();
		}
		catch ( HttpListenerException e )
		{
			Log.Error( $"[CoworkBridge] Failed to start: {e.Message}. " +
				"Try running the editor as administrator the first time, or run " +
				"this in elevated cmd: netsh http add urlacl url=" + Prefix + " user=Everyone" );
			_listener = null;
			return;
		}

		_cts = new CancellationTokenSource();
		_listenerThread = new Thread( ListenerLoop ) { IsBackground = true, Name = "CoworkBridge-Listener" };
		_listenerThread.Start();

		Log.Info( $"[CoworkBridge] Listening on {Prefix}" );
	}

	[Menu( "Editor", "Cowork/Stop MCP Bridge" )]
	public static void Stop()
	{
		if ( !IsRunning ) return;

		_cts?.Cancel();
		try { _listener?.Stop(); } catch { }
		try { _listener?.Close(); } catch { }
		_listener = null;
		Log.Info( "[CoworkBridge] Stopped." );
	}

	static void ListenerLoop()
	{
		while ( !_cts.IsCancellationRequested && _listener != null && _listener.IsListening )
		{
			HttpListenerContext ctx;
			try { ctx = _listener.GetContext(); }
			catch { return; }

			// Queue the request for the editor-thread pump to handle.
			var pending = new PendingRequest { Context = ctx };
			_queue.Enqueue( pending );

			// Wait for the editor thread to fill in the response, then send.
			Task.Run( () => SendWhenReady( pending ) );
		}
	}

	static void SendWhenReady( PendingRequest p )
	{
		// Cap at 30s so a stuck request doesn't tie up the connection forever.
		p.Done.Wait( TimeSpan.FromSeconds( 30 ) );

		try
		{
			var body = p.ResponseBody ?? "{\"error\":\"timeout\"}";
			var bytes = Encoding.UTF8.GetBytes( body );
			p.Context.Response.StatusCode = p.ResponseStatus;
			p.Context.Response.ContentType = "application/json; charset=utf-8";
			p.Context.Response.ContentLength64 = bytes.Length;
			p.Context.Response.OutputStream.Write( bytes, 0, bytes.Length );
		}
		catch ( Exception e )
		{
			try { Log.Warning( $"[CoworkBridge] Send error: {e.Message}" ); } catch { }
		}
		finally
		{
			try { p.Context.Response.Close(); } catch { }
		}
	}

	[EditorEvent.Frame]
	static void Pump()
	{
		while ( _queue.TryDequeue( out var p ) )
		{
			HandleOnEditorThread( p );
		}
	}

	static void HandleOnEditorThread( PendingRequest p )
	{
		try
		{
			var path = p.Context.Request.Url.AbsolutePath.TrimEnd( '/' );
			var bodyStr = ReadBody( p.Context.Request );
			var args = string.IsNullOrWhiteSpace( bodyStr )
				? new Dictionary<string, JsonElement>()
				: JsonSerializer.Deserialize<Dictionary<string, JsonElement>>( bodyStr );

			object result = path switch
			{
				"/ping" => CoworkBridgeHandlers.Ping(),
				"/scene/info" => CoworkBridgeHandlers.SceneInfo(),
				"/scene/tree" => CoworkBridgeHandlers.SceneTree(),
				"/scene/open" => CoworkBridgeHandlers.SceneOpen( args ),
				"/scene/save" => CoworkBridgeHandlers.SceneSave(),
				"/gameobject/get" => CoworkBridgeHandlers.GameObjectGet( args ),
				"/gameobject/select" => CoworkBridgeHandlers.GameObjectSelect( args ),
				"/component/set_property" => CoworkBridgeHandlers.ComponentSetProperty( args ),
				"/component/wire_reference" => CoworkBridgeHandlers.ComponentWireReference( args ),
				"/console/log" => CoworkBridgeHandlers.ConsoleLog( args ),
				_ => new { error = $"unknown route: {path}" },
			};

			p.ResponseBody = JsonSerializer.Serialize( result, new JsonSerializerOptions { WriteIndented = false } );
		}
		catch ( Exception e )
		{
			p.ResponseStatus = 500;
			p.ResponseBody = JsonSerializer.Serialize( new { error = e.Message, stack = e.StackTrace } );
		}
		finally
		{
			p.Done.Set();
		}
	}

	static string ReadBody( HttpListenerRequest req )
	{
		if ( !req.HasEntityBody ) return null;
		using var reader = new StreamReader( req.InputStream, req.ContentEncoding );
		return reader.ReadToEnd();
	}

	[EditorEvent.Hotload]
	static void OnHotload()
	{
		// Auto-restart so the bridge survives code reloads.
		if ( IsRunning )
		{
			Stop();
			Start();
		}
	}
}
