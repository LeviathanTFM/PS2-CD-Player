extends Control

#references to the audio file dialog and interface label
@onready var audio_dialog: FileDialog = $AudioFileDialog
@onready var music_label: Label = $MusicLabel

#handles communication with the external CDReader.exe process
var cd_connection = StreamPeerTCP.new()
var cd_pid = -1
var cd_buffer = ""
var cd_waiting = false
var cd_action = ""
var detect_timer = 0.0
var reconnect_timer = 0.0
var cd_response = {}
var connection_started = false
var shutting_down = false
var web_file_callback


func _ready():
	#browser builds use a JavaScript file picker instead of the desktop file dialog
	if OS.has_feature("web"):
		music_label.text = "Press M to select\naudio files from PC\n\nCD playback not\nsupported in browser"
		
		web_file_callback = JavaScriptBridge.create_callback(_on_web_files_selected)
		JavaScriptBridge.get_interface("window").godot_file_callback = web_file_callback
		return
		
	#configure the desktop file dialog to accept supported audio formats
	audio_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	audio_dialog.access = FileDialog.ACCESS_FILESYSTEM
	audio_dialog.use_native_dialog = true
	audio_dialog.filters = [
		"*.mp3 ; MP3 Audio",
		"*.wav ; WAV Audio",
		"*.ogg ; OGG Audio"
	]
	
	audio_dialog.files_selected.connect(_on_files_selected)
	
	start_cd_reader()


#connects to an existing CDReader server or starts the executable if necessary
func start_cd_reader():
	var connection_test = StreamPeerTCP.new()
	connection_test.connect_to_host("127.0.0.1", 47631)
	
	var attempts = 0
	
	#wait briefly for an already running CDReader server
	while attempts < 20:
		await get_tree().create_timer(0.1).timeout
		connection_test.poll()
		
		if connection_test.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			cd_connection = connection_test
			connection_started = true
			print("Connected to existing CD Reader.")
			return
			
		attempts += 1
		
	#look for CDReader.exe beside the game or inside the project tools folder
	var executable = OS.get_executable_path().get_base_dir().path_join("CDReader.exe")
	
	if not FileAccess.file_exists(executable):
		executable = ProjectSettings.globalize_path("res://tools/CDReader.exe")
		
	if not FileAccess.file_exists(executable):
		push_error("CDReader.exe not found beside the game or in res://tools/")
		return
		
	cd_pid = OS.create_process(executable, [], false)
	
	if cd_pid == -1:
		push_error("Unable to start CDReader.exe")
		return
		
	print("Started CDReader.exe: ", executable)
	print("Waiting for server...")
	connect_to_cd_server()


#opens a TCP connection to the local CDReader server
func connect_to_cd_server():
	cd_connection = StreamPeerTCP.new()
	cd_connection.connect_to_host("127.0.0.1", 47631)
	connection_started = true


func _process(delta):
	#skip CD communication in browser builds or during shutdown
	if shutting_down or OS.has_feature("web"):
		return
		
	cd_connection.poll()
	
	var status = cd_connection.get_status()
	
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if reconnect_timer > 0.0:
			print("Connected to CD Reader server.")
			
		reconnect_timer = 0.0
		
		read_cd_response()
		
		#periodically check for an inserted audio CD while the selection screen is visible
		if visible and not cd_waiting:
			detect_timer -= delta
			
			if detect_timer <= 0.0:
				detect_timer = 2.0
				send_cd_command({"action": "detect"})
				
	elif status == StreamPeerTCP.STATUS_CONNECTING:
		return
		
	elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		#attempt to reconnect if the CDReader server disconnects
		reconnect_timer -= delta
		
		if reconnect_timer <= 0.0:
			reconnect_timer = 2.0
			print("CD Reader disconnected. Reconnecting...")
			connect_to_cd_server()


#sends a JSON command to CDReader.exe through the TCP connection
func send_cd_command(data: Dictionary):
	if shutting_down:
		return
		
	if cd_connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		print("Cannot send command: not connected.")
		return
		
	cd_action = data.get("action", "")
	cd_waiting = true
	
	var json = JSON.stringify(data) + "\n"
	print("SENT TO CD READER: ", json)
	
	var error = cd_connection.put_data(json.to_utf8_buffer())
	
	if error != OK:
		cd_waiting = false
		push_error("Failed to send CD command: " + str(error))


#reads incoming data and separates complete JSON responses using newline characters
func read_cd_response():
	var available = cd_connection.get_available_bytes()
	
	if available <= 0:
		return
		
	var result = cd_connection.get_data(available)
	
	if result[0] != OK:
		push_error("Failed to read CD Reader response.")
		return
		
	cd_buffer += result[1].get_string_from_utf8()
	
	#process each complete response in the received data buffer
	while cd_buffer.contains("\n"):
		var newline_position = cd_buffer.find("\n")
		var line = cd_buffer.substr(0, newline_position)
		cd_buffer = cd_buffer.substr(newline_position + 1)
		
		if line.strip_edges().is_empty():
			continue
			
		var response = JSON.parse_string(line)
		cd_waiting = false
		
		print("CD RESPONSE: ", response)
		
		if not response is Dictionary:
			push_error("Invalid response from CD Reader: " + line)
			continue
			
		cd_response = response
		
		if response.has("error"):
			push_error("CD Reader [" + cd_action + "]: " + str(response["error"]))
			continue
			
		#handle audio CD detection separately from other CD commands
		if cd_action == "detect":
			handle_cd_detection(response)


#converts detected CD tracks into playlist entries
func handle_cd_detection(data: Dictionary):
	print("CD DETECTION: ", data)
	
	if not data.get("inserted", false):
		return
		
	var tracks = data.get("tracks", [])
	
	if not tracks is Array or tracks.is_empty():
		print("CD detected, but no audio tracks were returned.")
		return
		
	var main = get_parent().get_parent()
	main.playlist.clear()
	
	#store each CD track's number and duration in the shared playlist
	for track in tracks:
		main.playlist.append({
			"number": int(track["number"]),
			"duration": float(track["duration"]),
			"source": "cd"
		})
		
	if main.playlist.is_empty():
		return
		
	print("Audio CD detected!")
	print("Number of tracks: ", main.playlist.size())
	
	#reset track selection and open the track selection screen
	var track_selection = get_parent().get_node("TrackSelection")
	track_selection.selected_track = 0
	track_selection.current_page = 0
	track_selection.update_tracks()
	track_selection.get_node("CDLabel").text = "CD Audio"
	
	get_parent().get_node("MusicPlayer").visible = false
	track_selection.visible = true
	visible = false


#opens the appropriate audio file picker when M is pressed
func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M and not visible:
			return
			
		if event.keycode == KEY_M and visible:
			if OS.has_feature("web"):
				open_web_file_dialog()
			elif not audio_dialog.visible:
				audio_dialog.popup_centered()


#creates a browser file picker using JavaScript
func open_web_file_dialog():
	JavaScriptBridge.eval("""
	(() => {
		const input = document.createElement('input');
		input.type = 'file';
		input.accept = '.mp3,.wav,.ogg,audio/mpeg,audio/wav,audio/ogg';
		input.multiple = true;
		
		input.onchange = async () => {
			const files = Array.from(input.files);
			
			const results = await Promise.all(files.map(file => {
				return new Promise(resolve => {
					const reader = new FileReader();
					reader.onload = () => resolve({
						name: file.name,
						data: reader.result
					});
					reader.readAsDataURL(file);
				});
			}));
			
			window.godot_file_callback(JSON.stringify(results));
		};
		
		input.click();
	})();
	""")


#receives browser-selected files and converts their data into Godot audio streams
func _on_web_files_selected(args):
	if args.is_empty():
		return
		
	var files = JSON.parse_string(str(args[0]))
	
	if not files is Array:
		push_error("Invalid browser file selection.")
		return
		
	var main = get_parent().get_parent()
	main.playlist.clear()
	
	#decode each selected file and load it according to its extension
	for file in files:
		var filename = str(file["name"])
		var data_url = str(file["data"])
		var base64_data = data_url.get_slice(",", 1)
		var buffer = Marshalls.base64_to_raw(base64_data)
		
		var extension = filename.get_extension().to_lower()
		var stream: AudioStream
		
		match extension:
			"mp3":
				stream = AudioStreamMP3.load_from_buffer(buffer)
			"wav":
				stream = AudioStreamWAV.load_from_buffer(buffer)
			"ogg":
				stream = AudioStreamOggVorbis.load_from_buffer(buffer)
			_:
				continue
				
		if stream == null:
			push_error("Unable to load: " + filename)
			continue
			
		main.playlist.append({
			"number": main.playlist.size() + 1,
			"stream": stream,
			"source": "file"
		})
		
	finish_file_loading()


#loads audio files selected through the desktop file dialog
func _on_files_selected(paths: PackedStringArray):
	var main = get_parent().get_parent()
	main.playlist.clear()
	
	#load each supported file into the shared playlist
	for path in paths:
		var extension = path.get_extension().to_lower()
		var stream: AudioStream
		
		match extension:
			"mp3":
				stream = AudioStreamMP3.load_from_file(path)
			"wav":
				stream = AudioStreamWAV.load_from_file(path)
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(path)
			_:
				continue
				
		if stream == null:
			push_error("Unable to load: " + path)
			continue
			
		main.playlist.append({
			"number": main.playlist.size() + 1,
			"stream": stream,
			"source": "file"
		})
		
	finish_file_loading()


#opens the track selection screen after audio files have been loaded
func finish_file_loading():
	var main = get_parent().get_parent()
	
	if main.playlist.is_empty():
		push_error("No valid audio files selected.")
		return
		
	print("Album loaded!")
	print("Number of tracks: ", main.playlist.size())
	
	#reset track selection and identify the loaded playlist as file audio
	var track_selection = get_parent().get_node("TrackSelection")
	track_selection.selected_track = 0
	track_selection.current_page = 0
	track_selection.update_tracks()
	track_selection.get_node("CDLabel").text = "File Audio"
	
	get_parent().get_node("MusicPlayer").visible = false
	track_selection.visible = true
	visible = false


#sends a shutdown command and closes CDReader.exe when the project exits
func shutdown_cd_reader():
	if shutting_down or OS.has_feature("web"):
		return
		
	shutting_down = true
	
	if cd_connection.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var command = JSON.stringify({"action": "shutdown"}) + "\n"
		cd_connection.put_data(command.to_utf8_buffer())
		OS.delay_msec(150)
		
	#forcefully terminate the process to prevent CDReader.exe from remaining open
	OS.execute(
		"C:/Windows/System32/taskkill.exe",
		["/F", "/T", "/IM", "CDReader.exe"]
	)
	
	cd_pid = -1


#close the CD reader when the game window receives a close request
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown_cd_reader()


#ensure the CD reader is closed when this node is removed
func _exit_tree():
	shutdown_cd_reader()


#returns the latest CD response and clears it from storage
func get_cd_response():
	var response = cd_response
	cd_response = {}
	return response
