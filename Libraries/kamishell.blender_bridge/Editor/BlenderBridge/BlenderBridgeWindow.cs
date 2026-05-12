using System;
using System.Collections.Generic;
using System.Linq;
using Editor;
using Sandbox;

namespace BlenderBridge
{
	/// <summary>
	/// Editor window for the Blender Bridge v2.
	/// Shows connection status, client indicator, manifest status, materials, and activity log.
	/// </summary>
	public class BlenderBridgeWindow : Widget
	{
		private Label _statusLabel;
		private Label _portLabel;
		private Label _clientLabel;
		private Label _manifestLabel;
		private Button _toggleButton;
		private Widget _logCanvas;
		private Widget _materialsCanvas;
		private ToggleSwitch _autoStartToggle;
		private bool _lastRunningState = false;
		private readonly List<(Button btn, BridgeLockFlags flag, string baseLabel)> _lockButtons = new();

		private static readonly List<string> _logEntries = new();
		private const int MaxLogEntries = 200;

		static BlenderBridgeWindow()
		{
			if ( BlenderBridgeServer.AutoStart )
			{
				GameTask.RunInThreadAsync( async () =>
				{
					await GameTask.MainThread();
					if ( !BlenderBridgeServer.IsRunning )
						BlenderBridgeServer.StartServer();
				} );
			}
		}

		[Menu( "Editor", "Blender Bridge/Open Panel" )]
		public static void OpenPanel()
		{
			var win = new BlenderBridgeWindow();
			win.Show();
		}

		public BlenderBridgeWindow() : base( null )
		{
			WindowTitle = "Blender Bridge";
			MinimumSize = new Vector2( 450, 400 );
			BuildUI();
			_pollTimer = new System.Threading.Timer( _ => _needsDrain = true, null, 500, 500 );
		}

		private System.Threading.Timer _pollTimer;
		private volatile bool _needsDrain = false;

		public override void OnDestroyed()
		{
			_pollTimer?.Dispose();
			base.OnDestroyed();
		}

		protected override void OnPaint()
		{
			base.OnPaint();
			// Cheap state-refresh tied to redraw. Reads tags from the current
			// selection — both fast operations — so it's fine to do per-paint
			// rather than wiring up a SelectionChanged event.
			RefreshLockButtonStates();
			if ( !_needsDrain ) return;
			_needsDrain = false;
			DrainLogQueue();
		}

		private void DrainLogQueue()
		{
			if ( !IsValid || _logCanvas == null ) return;

			// Update status
			if ( BlenderBridgeServer.IsRunning != _lastRunningState )
			{
				_lastRunningState = BlenderBridgeServer.IsRunning;
				if ( _lastRunningState )
				{
					_statusLabel.Text = "● Running";
					_statusLabel.SetStyles( "font-size: 15px; font-weight: bold; color: #4ade80;" );
					_toggleButton.Text = "Stop Bridge";
				}
				else
				{
					_statusLabel.Text = "● Stopped";
					_statusLabel.SetStyles( "font-size: 15px; font-weight: bold; color: #f87171;" );
					_toggleButton.Text = "Start Bridge";
				}
			}

			// Update client indicator
			if ( _clientLabel != null )
			{
				if ( BlenderBridgeServer.HasActiveClient )
				{
					_clientLabel.Text = "1 client connected";
					_clientLabel.SetStyles( "font-size: 11px; color: #4ade80;" );
				}
				else
				{
					_clientLabel.Text = "No clients";
					_clientLabel.SetStyles( "font-size: 11px; color: #9ca3af;" );
				}
			}

			// Update manifest status
			if ( _manifestLabel != null )
			{
				try
				{
					var scene = BridgeSceneHelper.ResolveScene();
					if ( scene != null && BridgePersistence.HasSavedState( scene ) )
					{
						_manifestLabel.Text = "Bridge state saved";
						_manifestLabel.SetStyles( "font-size: 11px; color: #4ade80;" );
					}
					else
					{
						_manifestLabel.Text = "No bridge state";
						_manifestLabel.SetStyles( "font-size: 11px; color: #9ca3af;" );
					}
				}
				catch
				{
					_manifestLabel.Text = "No bridge state";
					_manifestLabel.SetStyles( "font-size: 11px; color: #9ca3af;" );
				}
			}

			// Drain log queue
			int count = 0;
			while ( BlenderBridgeServer.LogQueue.TryDequeue( out var msg ) && count < 50 )
			{
				var text = $"[{DateTime.Now:HH:mm:ss}] {msg}";
				_logEntries.Add( text );
				AddLogLabel( text );
				count++;

				if ( _logEntries.Count > MaxLogEntries )
				{
					_logEntries.RemoveAt( 0 );
					var firstChild = _logCanvas?.Children?.FirstOrDefault();
					firstChild?.Destroy();
				}
			}
		}

		private void BuildUI()
		{
			var root = Layout.Column();
			root.Margin = 8;
			root.Spacing = 6;

			// ── Status Row ──────────────────────────────────────────────
			var statusRow = Layout.Row();
			statusRow.Spacing = 16;

			var statusCol = Layout.Column();
			var statusTitle = new Label( "STATUS" );
			statusTitle.SetStyles( "font-size: 10px; color: #888;" );
			statusCol.Add( statusTitle );
			_statusLabel = new Label( "● Stopped" );
			_statusLabel.SetStyles( "font-size: 15px; font-weight: bold; color: #f87171;" );
			statusCol.Add( _statusLabel );
			statusRow.Add( statusCol );

			var portCol = Layout.Column();
			var portTitle = new Label( "PORT" );
			portTitle.SetStyles( "font-size: 10px; color: #888;" );
			portCol.Add( portTitle );
			_portLabel = new Label( BlenderBridgeServer.Port.ToString() );
			_portLabel.SetStyles( "font-size: 15px; font-weight: bold;" );
			portCol.Add( _portLabel );
			statusRow.Add( portCol );

			statusRow.AddStretchCell();

			_toggleButton = new Button( "Start Bridge", "play_arrow" );
			_toggleButton.Clicked += ToggleBridge;
			statusRow.Add( _toggleButton );

			root.Add( statusRow );

			// ── Client + Manifest Indicators ────────────────────────────
			var infoRow = Layout.Row();
			infoRow.Spacing = 24;

			var clientCol = Layout.Column();
			var clientTitle = new Label( "CLIENT" );
			clientTitle.SetStyles( "font-size: 10px; color: #888;" );
			clientCol.Add( clientTitle );
			_clientLabel = new Label( "No clients" );
			_clientLabel.SetStyles( "font-size: 11px; color: #9ca3af;" );
			clientCol.Add( _clientLabel );
			infoRow.Add( clientCol );

			var manifestCol = Layout.Column();
			var manifestTitle = new Label( "PERSISTENCE" );
			manifestTitle.SetStyles( "font-size: 10px; color: #888;" );
			manifestCol.Add( manifestTitle );
			_manifestLabel = new Label( "No bridge state" );
			_manifestLabel.SetStyles( "font-size: 11px; color: #9ca3af;" );
			manifestCol.Add( _manifestLabel );
			infoRow.Add( manifestCol );

			root.Add( infoRow );

			// ── Auto-start ──────────────────────────────────────────────
			var autoRow = Layout.Row();
			autoRow.Spacing = 8;
			_autoStartToggle = new ToggleSwitch( "Auto-start Bridge on editor load" );
			_autoStartToggle.Value = BlenderBridgeServer.AutoStart;
			_autoStartToggle.MouseClick += () =>
			{
				BlenderBridgeServer.AutoStart = _autoStartToggle.Value;
			};
			autoRow.Add( _autoStartToggle );
			root.Add( autoRow );
			root.AddSeparator();

			// ── Blender Addon Download ──────────────────────────────────
			var addonBox = Layout.Column();
			addonBox.Spacing = 4;
			var addonTitle = new Label( "Blender Addon" );
			addonTitle.SetStyles( "font-weight: bold; font-size: 13px;" );
			addonBox.Add( addonTitle );

			var addonDesc = new Label( "Install the companion Blender addon (v2.0+) to connect." );
			addonDesc.SetStyles( "font-size: 11px; color: #9ca3af;" );
			addonDesc.WordWrap = true;
			addonBox.Add( addonDesc );

			var addonUrl = "https://github.com/SanicTehHedgehog/blender-sbox-bridge/releases";
			var addonLink = new Button( "Download Blender Addon", "open_in_new" );
			addonLink.Clicked += () =>
			{
				System.Diagnostics.Process.Start( new System.Diagnostics.ProcessStartInfo( addonUrl ) { UseShellExecute = true } );
			};
			addonBox.Add( addonLink );
			root.Add( addonBox );
			root.AddSeparator();

			// ── Sync Controls ───────────────────────────────────────────
			var syncBox = Layout.Column();
			syncBox.Spacing = 4;
			var syncTitle = new Label( "Sync Controls" );
			syncTitle.SetStyles( "font-weight: bold; font-size: 13px;" );
			syncBox.Add( syncTitle );

			var syncDesc = new Label( "Send or receive mesh data for selected scene objects." );
			syncDesc.SetStyles( "font-size: 11px; color: #9ca3af;" );
			syncDesc.WordWrap = true;
			syncBox.Add( syncDesc );

			var syncBtnRow = Layout.Row();
			syncBtnRow.Spacing = 4;

			var sendToBlenderBtn = new Button( "Send to Blender", "upload" );
			sendToBlenderBtn.ToolTip = "Push selected objects to Blender (adopts native MeshComponents if needed)";
			sendToBlenderBtn.Clicked += () =>
			{
				if ( !BlenderBridgeServer.IsRunning ) return;
				var scene = BridgeSceneHelper.ResolveScene();
				if ( scene == null ) return;

				// Find selected objects in the editor
				var session = SceneEditorSession.Active;
				if ( session == null ) return;

				int count = 0;
				foreach ( var sel in session.Selection )
				{
					if ( sel is not GameObject go ) continue;

					// Find existing bridge tag or adopt native MeshComponents
					var bridgeTag = go.Tags.TryGetAll().FirstOrDefault( t => t.StartsWith( "bridge_" ) && t != "bridge_group" );
					string bridgeId;

					if ( bridgeTag != null )
					{
						bridgeId = bridgeTag.Substring( 7 );
					}
					else
					{
						// Adopt native MeshComponent or Terrain if present.
						var meshComp = go.Components.Get<MeshComponent>();
						var terrain = go.Components.Get<Terrain>();
						bool hasMesh = meshComp?.Mesh != null;
						bool hasTerrain = terrain?.Storage != null;
						if ( !hasMesh && !hasTerrain ) continue;

						bridgeId = "b_" + Guid.NewGuid().ToString( "N" ).Substring( 0, 8 );
						go.Tags.Add( $"bridge_{bridgeId}" );
						var kind = hasTerrain ? "terrain" : "mesh";
						BlenderBridgeServer.LogInfo( $"Adopted '{go.Name}' as {bridgeId} ({kind})" );
					}

					// Build and broadcast as an object_created message
					var message = BlenderBridgeDispatcher.BuildObjectCreatedMessage( bridgeId, go );
					if ( message != null )
					{
						BlenderBridgeServer.BroadcastWithSeq( message );
						count++;
					}
				}

				if ( count > 0 )
					BlenderBridgeServer.LogInfo( $"Sent {count} object(s) to Blender" );
				else
					BlenderBridgeServer.LogInfo( "No mesh objects selected" );
			};
			syncBtnRow.Add( sendToBlenderBtn );

			var requestFromBlenderBtn = new Button( "Request from Blender", "download" );
			requestFromBlenderBtn.ToolTip = "Ask Blender to re-send mesh data for all bridge objects";
			requestFromBlenderBtn.Clicked += () =>
			{
				if ( !BlenderBridgeServer.IsRunning ) return;
				// Trigger a full sync — Blender will send all its objects
				BlenderBridgeServer.BroadcastWithSeq( new { type = "sync_response", objects = new object[0] } );
				BlenderBridgeServer.LogInfo( "Requested resync from Blender" );
			};
			syncBtnRow.Add( requestFromBlenderBtn );

			AddLockButton( syncBtnRow, "Lock In", "lock", BridgeLockFlags.Inbound,
				"Toggle: block all Blender → s&box updates for the selected object(s)." );

			AddLockButton( syncBtnRow, "Lock Out", "lock_outline", BridgeLockFlags.Outbound,
				"Toggle: stop pushing s&box-side changes for the selected object(s) to Blender." );

			AddLockButton( syncBtnRow, "Lock Mat", "palette", BridgeLockFlags.Materials,
				"Toggle: allow geometry/transform updates from Blender, but never overwrite materials. Use for objects with custom s&box vmats (water shaders, etc)." );

			root.Add( syncBox );
			root.Add( syncBtnRow );
			root.AddSeparator();

			// ── Materials Section ───────────────────────────────────────
			var matHeader = Layout.Row();
			var matTitle = new Label( "Generated Materials" );
			matTitle.SetStyles( "font-weight: bold; font-size: 13px;" );
			matHeader.Add( matTitle );
			matHeader.AddStretchCell();

			var openFolderBtn = new Button( "", "folder_open" );
			openFolderBtn.ToolTip = "Open materials folder";
			openFolderBtn.FixedWidth = 26;
			openFolderBtn.FixedHeight = 26;
			openFolderBtn.Clicked += OpenMaterialsFolder;
			matHeader.Add( openFolderBtn );

			var refreshBtn = new Button( "", "refresh" );
			refreshBtn.ToolTip = "Refresh list";
			refreshBtn.FixedWidth = 26;
			refreshBtn.FixedHeight = 26;
			refreshBtn.Clicked += RefreshMaterialsList;
			matHeader.Add( refreshBtn );
			root.Add( matHeader );

			var matScroll = new ScrollArea( null );
			matScroll.MaximumHeight = 150;
			_materialsCanvas = new Widget();
			_materialsCanvas.Layout = Layout.Column();
			matScroll.Canvas = _materialsCanvas;
			root.Add( matScroll );

			RefreshMaterialsList();
			root.AddSeparator();

			// ── Log Header ──────────────────────────────────────────────
			var logHeader = Layout.Row();
			var logTitle = new Label( "Activity Log" );
			logTitle.SetStyles( "font-weight: bold; font-size: 13px;" );
			logHeader.Add( logTitle );
			logHeader.AddStretchCell();

			var clearBtn = new Button( "", "delete_sweep" );
			clearBtn.ToolTip = "Clear Log";
			clearBtn.FixedWidth = 26;
			clearBtn.FixedHeight = 26;
			clearBtn.Clicked += () => { _logEntries.Clear(); _logCanvas.DestroyChildren(); };
			logHeader.Add( clearBtn );
			root.Add( logHeader );

			// ── Log Area ────────────────────────────────────────────────
			var scroll = new ScrollArea( null );
			scroll.MinimumHeight = 250;
			_logCanvas = new Widget();
			_logCanvas.Layout = Layout.Column();
			scroll.Canvas = _logCanvas;

			foreach ( var entry in _logEntries )
				AddLogLabel( entry );

			root.Add( scroll, 1 );
			Layout = root;
		}

		private void AddLogLabel( string text )
		{
			var lbl = new Label( text );
			lbl.WordWrap = true;

			string color = "#e5e7eb";
			string weight = "normal";

			if ( text.Contains( "[ERROR]" ) )
			{
				color = "#f87171";
				weight = "bold";
			}
			else if ( text.Contains( "Created" ) || text.Contains( "Sync" ) || text.Contains( "Started" ) || text.Contains( "Restored" ) )
			{
				color = "#4ade80";
			}
			else if ( text.Contains( "Deleted" ) || text.Contains( "Stopped" ) )
			{
				color = "#9ca3af";
			}
			else if ( text.Contains( "mesh" ) || text.Contains( "Model" ) || text.Contains( "Chunked" ) )
			{
				color = "#60a5fa";
			}
			else if ( text.Contains( "light" ) || text.Contains( "Light" ) )
			{
				color = "#fbbf24";
			}

			lbl.SetStyles( $"font-family: monospace; font-size: 11px; padding: 2px; color: {color}; font-weight: {weight};" );
			_logCanvas.Layout.Add( lbl );
		}

		private string FindBridgeMaterialsDir()
		{
			try
			{
				var docsDir = System.IO.Path.Combine(
					System.Environment.GetFolderPath( System.Environment.SpecialFolder.MyDocuments ),
					"s&box projects" );

				if ( System.IO.Directory.Exists( docsDir ) )
				{
					foreach ( var projDir in System.IO.Directory.GetDirectories( docsDir ) )
					{
						var candidate = System.IO.Path.Combine( projDir, "Assets", "materials", "blender_bridge" );
						if ( System.IO.Directory.Exists( candidate ) )
							return candidate;
					}
				}
			}
			catch { }
			return null;
		}

		private void RefreshMaterialsList()
		{
			if ( _materialsCanvas == null ) return;
			_materialsCanvas.DestroyChildren();

			var dir = FindBridgeMaterialsDir();
			if ( dir == null || !System.IO.Directory.Exists( dir ) )
			{
				var lbl = new Label( "No materials generated yet" );
				lbl.SetStyles( "font-size: 11px; color: #888; padding: 4px;" );
				_materialsCanvas.Layout.Add( lbl );
				return;
			}

			var vmats = System.IO.Directory.GetFiles( dir, "*.vmat" );
			if ( vmats.Length == 0 )
			{
				var lbl = new Label( "No materials generated yet" );
				lbl.SetStyles( "font-size: 11px; color: #888; padding: 4px;" );
				_materialsCanvas.Layout.Add( lbl );
				return;
			}

			foreach ( var vmat in vmats.OrderBy( f => f ) )
			{
				var fileName = System.IO.Path.GetFileNameWithoutExtension( vmat );
				var filePath = vmat;

				var row = Layout.Row();
				row.Spacing = 4;

				var icon = new Label( "  " );
				icon.SetStyles( "color: #60a5fa; font-size: 11px;" );
				row.Add( icon );

				var nameLbl = new Label( fileName );
				nameLbl.SetStyles( "font-family: monospace; font-size: 11px; color: #e5e7eb;" );
				row.Add( nameLbl );

				row.AddStretchCell();

				try
				{
					var info = new System.IO.FileInfo( filePath );
					var sizeLbl = new Label( $"{info.Length / 1024f:F1}kb" );
					sizeLbl.SetStyles( "font-size: 10px; color: #666; padding-right: 4px;" );
					row.Add( sizeLbl );
				}
				catch { }

				var deleteBtn = new Button( "", "delete" );
				deleteBtn.ToolTip = $"Delete {fileName}";
				deleteBtn.FixedWidth = 22;
				deleteBtn.FixedHeight = 22;
				deleteBtn.Clicked += () =>
				{
					try
					{
						foreach ( var f in System.IO.Directory.GetFiles( dir, $"{fileName}*" ) )
							System.IO.File.Delete( f );
					}
					catch { }
					RefreshMaterialsList();
				};
				row.Add( deleteBtn );

				var container = new Widget();
				container.Layout = row;
				container.SetStyles( "padding: 1px 0;" );
				_materialsCanvas.Layout.Add( container );
			}

			// Delete All button
			var deleteAllRow = Layout.Row();
			deleteAllRow.AddStretchCell();
			var deleteAllBtn = new Button( "Delete All", "delete_sweep" );
			deleteAllBtn.ToolTip = "Delete all generated bridge materials";
			deleteAllBtn.Clicked += () =>
			{
				try
				{
					foreach ( var f in System.IO.Directory.GetFiles( dir ) )
						System.IO.File.Delete( f );
				}
				catch { }
				RefreshMaterialsList();
			};
			deleteAllRow.Add( deleteAllBtn );

			var allContainer = new Widget();
			allContainer.Layout = deleteAllRow;
			_materialsCanvas.Layout.Add( allContainer );
		}

		private void OpenMaterialsFolder()
		{
			var dir = FindBridgeMaterialsDir();
			if ( dir != null && System.IO.Directory.Exists( dir ) )
				System.Diagnostics.Process.Start( "explorer", $"\"{dir}\"" );
		}

		private void AddLockButton( Layout row, string label, string icon, BridgeLockFlags flag, string tooltip )
		{
			var btn = new Button( label, icon );
			btn.ToolTip = tooltip;
			btn.Clicked += () =>
			{
				var session = SceneEditorSession.Active;
				if ( session == null ) return;
				int set = 0, cleared = 0;
				foreach ( var sel in session.Selection )
				{
					if ( sel is not GameObject go ) continue;
					var next = BridgeLockPolicy.ToggleExplicit( go, flag );
					if ( next.HasFlag( flag ) ) set++; else cleared++;
				}
				if ( set > 0 )     BlenderBridgeServer.LogInfo( $"Set {flag} on {set} object(s)" );
				if ( cleared > 0 ) BlenderBridgeServer.LogInfo( $"Cleared {flag} on {cleared} object(s)" );
				if ( set == 0 && cleared == 0 ) BlenderBridgeServer.LogInfo( "No objects selected" );
				RefreshLockButtonStates();
			};
			row.Add( btn );
			_lockButtons.Add( (btn, flag, label) );
		}

		/// <summary>
		/// Update each lock button's label to reflect whether the flag is set on
		/// the current selection. Three states: all-on -> "Label [ON]",
		/// none-on -> "Label", mixed -> "Label [~]". Tooltip stays static.
		///
		/// Called on every click and from the main OnPaint above, so selection
		/// changes surface the right state without explicit event subscription.
		/// </summary>
		private void RefreshLockButtonStates()
		{
			var session = SceneEditorSession.Active;
			var selected = session?.Selection?.OfType<GameObject>().ToList();

			foreach ( var (btn, flag, baseLabel) in _lockButtons )
			{
				if ( selected == null || selected.Count == 0 )
				{
					btn.Text = baseLabel;
					continue;
				}

				int onCount = selected.Count( g => BridgeLockPolicy.GetFlags( g ).HasFlag( flag ) );
				if ( onCount == selected.Count )
					btn.Text = baseLabel + " [ON]";
				else if ( onCount == 0 )
					btn.Text = baseLabel;
				else
					btn.Text = baseLabel + " [~]";
			}
		}

		private void ToggleBridge()
		{
			if ( BlenderBridgeServer.IsRunning )
				BlenderBridgeServer.StopServer();
			else
				BlenderBridgeServer.StartServer();
		}
	}
}
