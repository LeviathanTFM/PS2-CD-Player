extends Control

#references to the shared playlist, audio player and interface elements
@onready var main = get_parent().get_parent()
@onready var audio_player = main.get_node("AudioPlayer")
@onready var music_selection = get_parent().get_node("MusicSelection")
@onready var spinning_cube = $SubViewportContainer/SubViewport/World/SpinningCube/Cube
@onready var track_label = $TrackLabel
@onready var duration_label = $DurationLabel
@onready var playback_buttons = $PlaybackButtons
@onready var world_view = $SubViewportContainer/SubViewport/World

#playback controls are stored in navigation order, from Previous to Stop
#selected_control determines which button is currently highlighted
var controls = [
	"PreviousButton",
	"RewindButton",
	"FastForwardButton",
	"NextButton",
	"PlayButton",
	"PauseButton",
	"StopButton"
]

var selected_control = 4
var current_track = 0

#stores the spinning cube's original rotation and controls its randomized spinning animation
var initial_rotation = Vector3.ZERO
var rotation_direction = Vector3.ZERO
var rotation_speed = Vector3.ZERO
var rotation_timer = 0.0
var fade_time = 0.0

#controls how quickly tracks are skipped while holding Rewind or Fast Forward
#seek_interval determines how frequently another seek command is performed
var seek_speed = 30.0
var seek_interval = 0.2
var seek_timer = 0.0
var original_volume = 0.0
var seeking = false
var audio_paused = false

#stores the spinning cube's material and handles its animated color gradient
var cube_material: StandardMaterial3D
var cube_color_time = 0.0
var cube_color_speed = 0.4

var cube_colors = [
	Color("0000ff"),
	Color("00ffff"),
	Color("00ff00"),
	Color("ffff00"),
	Color("ff8000"),
	Color("ff0000"),
	Color("8000ff")
]

#CD playback state and command management
#CD commands are sent to CDReader.exe through music_selection.gd
#only one command can be processed at a time, additional commands are queued
var cd_pending_action = ""
var cd_queued_command = {}
var cd_status_timer = 0.0
var cd_position = 0.0
var cd_playing = false
var cd_paused = false
var cd_was_playing = false
var cd_advancing = false


func _ready():
	#save the spinning cube's initial appearance and prepare its animated material
	initial_rotation = spinning_cube.rotation
	original_volume = audio_player.volume_db
	
	var source_material = spinning_cube.get_active_material(0)
	
	if source_material is StandardMaterial3D:
		cube_material = source_material.duplicate()
	else:
		cube_material = StandardMaterial3D.new()
		
	spinning_cube.material_override = cube_material
	cube_material.emission_enabled = true
	
	world_view.visible = visible
	visibility_changed.connect(_on_visibility_changed)
	
	randomize()
	randomize_rotation()
	
	#automatically advance to the next track when an audio file finishes
	audio_player.finished.connect(_on_track_finished)
	
	update_controls()


func _process(delta):
	#handle interface navigation and playback controls
	if not visible:
		return
		
	if Input.is_action_just_pressed("left"):
		selected_control = max(0, selected_control - 1)
		update_controls()
	if Input.is_action_just_pressed("right"):
		selected_control = min(6, selected_control + 1)
		update_controls()
	if Input.is_action_just_pressed("confirm"):
		#execute the action associated with the currently selected playback button
		activate_control()
	if Input.is_action_just_pressed("back"):
		go_back()
		
	#holding Confirm while Rewind or Fast Forward is selected enables continuous seeking
	#audio files are temporarily muted during seeking to avoid playback artifacts
	var is_seeking = (
		Input.is_action_pressed("confirm")
		and (selected_control == 1 or selected_control == 2)
	)
	
	if is_seeking:
		if not seeking:
			seeking = true
			seek_timer = 0.0
			
			if not is_cd_track():
				audio_player.volume_db = -80.0
				
		seek_timer = min(seek_timer + delta, 0.5)
		
		if seek_timer >= seek_interval:
			#prevent overlapping CD seek commands while another command is being processed
			if not is_cd_track() or can_send_cd_seek():
				var seek_amount = seek_timer * seek_speed
				seek_timer = 0.0
				
				if selected_control == 1:
					rewind_track(seek_amount)
				elif selected_control == 2:
					fast_forward_track(seek_amount)
	else:
		if seeking:
			seeking = false
			seek_timer = 0.0
			audio_player.volume_db = original_volume
			
	#CD playback requires periodic communication with CDReader.exe
	#physical CD audio is not played through Godot's AudioStreamPlayer
	if is_cd_track():
		process_cd(delta)
		check_cd_completion()
		
	#animate the spinning cube and its colors while a track is playing
	if is_currently_playing() and not seeking:
		rotation_timer -= delta
		
		if rotation_timer <= 0:
			#generate a random rotation direction, speed and duration for the cube animation
			randomize_rotation()
			
		spinning_cube.rotate_object_local(
			rotation_direction,
			rotation_speed.length() * delta
		)
		
		#gradually interpolate between predefined colors to create a continuous color cycle
		update_cube_color(delta)
		
	update_duration()
	update_button_fade(delta)


#checks whether another CD seek command can be sent
func can_send_cd_seek():
	return (
		cd_pending_action == ""
		and not music_selection.cd_waiting
		and cd_queued_command.is_empty()
	)


#interpolates between the predefined colors applied to the spinning cube
func update_cube_color(delta):
	cube_color_time += delta * cube_color_speed
	
	var color_position = fposmod(cube_color_time, cube_colors.size())
	var color_index = int(color_position)
	var next_index = (color_index + 1) % cube_colors.size()
	var blend = color_position - color_index
	
	var cube_color = cube_colors[color_index].lerp(
		cube_colors[next_index],
		blend
	)
	
	cube_material.albedo_color = cube_color
	cube_material.emission = cube_color * 0.25


#generates a random rotation direction, speed and duration for the cube
func randomize_rotation():
	rotation_direction = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()
	
	rotation_speed = Vector3(
		randf_range(0.5, 2.0),
		randf_range(0.5, 2.0),
		randf_range(0.5, 2.0)
	)
	
	rotation_timer = randf_range(1.0, 3.0)


func update_controls():
	update_button_fade(0.0)


#updates button colors, selection highlighting and playback animations
func update_button_fade(delta):
	fade_time += delta
	
	var alpha = 0.4 + (sin(fade_time * 2.0) + 1.0) * 0.3
	
	for i in range(controls.size()):
		var control = playback_buttons.get_node(controls[i])
		var color = Color("00ffff") if i == selected_control else Color.WHITE
		
		if controls[i] == "PlayButton" and is_currently_playing():
			color.a = alpha
			
		if controls[i] == "PauseButton" and is_currently_paused():
			color.a = alpha
			
		control.modulate = color


#calls the function associated with the selected playback button
func activate_control():
	match selected_control:
		0:
			previous_track()
		1:
			rewind_track(10.0)
		2:
			fast_forward_track(10.0)
		3:
			next_track()
		4:
			play_button()
		5:
			pause_track()
		6:
			stop_track()


#opens the music player and starts the selected track
func start_track(track_index):
	current_track = track_index
	visible = true
	
	get_parent().get_node("TrackSelection").visible = false
	
	play_track(current_track)


#checks whether the current playlist entry comes from a physical CD
func is_cd_track():
	if current_track < 0 or current_track >= main.playlist.size():
		return false
		
	return main.playlist[current_track].get("source", "") == "cd"


#returns the playback state of the current track
func is_currently_playing():
	if is_cd_track():
		return cd_playing and not cd_paused
		
	return audio_player.playing and not audio_paused


#returns whether the current track is paused
func is_currently_paused():
	if is_cd_track():
		return cd_paused
		
	return audio_paused


#handles the Play button for both CD tracks and audio files
func play_button():
	if is_cd_track():
		if cd_paused or cd_was_playing:
			request_cd_action({"action": "resume"})
		elif not cd_playing:
			play_track(current_track)
			
		return
		
	if audio_paused:
		audio_paused = false
		audio_player.stream_paused = false
	elif not audio_player.playing:
		play_track(current_track)


#initializes a track and starts playback using the appropriate audio system
func play_track(track_index):
	if track_index < 0 or track_index >= main.playlist.size():
		return
		
	current_track = track_index
	
	var track = main.playlist[current_track]
	
	track_label.text = "Track " + str(current_track + 1)
	
	#reset the previous track and its playback state
	audio_player.stop()
	audio_player.stream_paused = false
	audio_player.volume_db = original_volume
	audio_paused = false
	
	seeking = false
	seek_timer = 0.0
	
	cd_position = 0.0
	cd_playing = false
	cd_paused = false
	cd_was_playing = false
	cd_advancing = false
	cd_status_timer = 0.0
	
	#reset the cube animation and playback timer
	spinning_cube.rotation = initial_rotation
	cube_color_time = 0.0
	randomize_rotation()
	
	duration_label.text = "00 min. 00 sec."
	
	#physical CD tracks are played through CDReader.exe
	if track.get("source", "") == "cd":
		request_cd_action({
			"action": "play",
			"track": int(track["number"])
		})
		return
		
	#regular audio files are played through Godot's AudioStreamPlayer
	if not track.has("stream"):
		push_warning("Track has no audio stream.")
		return
		
	audio_player.stream = track["stream"]
	audio_player.play()
	
	update_duration()


#stores a CD command until it can be sent to CDReader.exe
func request_cd_action(data: Dictionary):
	cd_queued_command = data.duplicate()
	
	if cd_pending_action == "" and not music_selection.cd_waiting:
		send_queued_cd_command()


#sends the queued CD command when the communication channel is available
func send_queued_cd_command():
	if cd_queued_command.is_empty():
		return
		
	if music_selection.cd_waiting:
		return
		
	var data = cd_queued_command
	cd_queued_command = {}
	
	cd_pending_action = data.get("action", "")
	music_selection.send_cd_command(data)


#processes CD responses, queued commands and periodic status requests
func process_cd(delta):
	if cd_pending_action != "" and not music_selection.cd_waiting:
		var action = cd_pending_action
		var response = music_selection.get_cd_response()
		
		cd_pending_action = ""
		
		handle_cd_response(action, response)
		
	if not cd_queued_command.is_empty():
		if cd_pending_action == "" and not music_selection.cd_waiting:
			send_queued_cd_command()
			
		return
		
	if cd_pending_action != "" or music_selection.cd_waiting:
		return
		
	#periodically request the CD playback position and status
	cd_status_timer -= delta
	
	if cd_status_timer <= 0.0:
		cd_status_timer = 0.25
		request_cd_action({"action": "status"})


#updates the local playback state using the response received from CDReader.exe
func handle_cd_response(action: String, response: Dictionary):
	if response.has("error"):
		push_error("CD Reader: " + str(response["error"]))
		return
		
	match action:
		"play":
			cd_playing = true
			cd_paused = false
			cd_was_playing = true
			cd_position = 0.0
			cd_advancing = false
		"pause":
			cd_playing = true
			cd_paused = true
			cd_was_playing = true
		"resume":
			cd_playing = true
			cd_paused = false
			cd_was_playing = true
		"seek":
			cd_playing = true
		"stop":
			cd_playing = false
			cd_paused = false
			cd_was_playing = false
			cd_position = 0.0
		"status":
			cd_playing = (
				response.get("playing", false)
				or response.get("paused", false)
			)
			
			cd_paused = response.get("paused", false)
			cd_position = float(response.get("position", cd_position))
			
			if response.get("finished", false):
				advance_cd_track()


#checks whether the CD track has reached its end
func check_cd_completion():
	if not is_cd_track():
		return
		
	if cd_advancing or cd_paused or not cd_was_playing:
		return
		
	var duration = float(
		main.playlist[current_track].get("duration", 0.0)
	)
	
	if duration > 0.0 and cd_position >= duration - 0.5:
		advance_cd_track()


#advances to the next CD track after playback finishes
func advance_cd_track():
	if cd_advancing or cd_paused or not cd_was_playing:
		return
		
	cd_advancing = true
	cd_was_playing = false
	
	print("CD track finished. Advancing to next track.")
	
	if current_track < main.playlist.size() - 1:
		play_track(current_track + 1)
	else:
		stop_track()


#pauses playback using the appropriate system
func pause_track():
	if is_cd_track():
		if cd_playing and not cd_paused:
			request_cd_action({"action": "pause"})
			
		return
		
	if audio_player.playing and not audio_paused:
		audio_paused = true
		audio_player.stream_paused = true


#stops playback and resets the playback interface
func stop_track():
	seeking = false
	seek_timer = 0.0
	audio_player.volume_db = original_volume
	
	if is_cd_track():
		cd_was_playing = false
		cd_advancing = false
		request_cd_action({"action": "stop"})
	else:
		audio_paused = false
		audio_player.stream_paused = false
		audio_player.stop()
		
	cd_playing = false
	cd_paused = false
	cd_position = 0.0
	
	spinning_cube.rotation = initial_rotation
	duration_label.text = "00 min. 00 sec."


#starts the previous track if one is available
func previous_track():
	if current_track > 0:
		play_track(current_track - 1)


#starts the next track or stops playback at the end of the playlist
func next_track():
	if current_track < main.playlist.size() - 1:
		play_track(current_track + 1)
	else:
		stop_track()


#moves playback forward by the specified number of seconds
func fast_forward_track(amount):
	if is_cd_track():
		if not can_send_cd_seek():
			return
			
		var duration = float(main.playlist[current_track].get("duration", 0.0))
		var target_position = min(cd_position + amount, max(0.0, duration - 0.1))
		
		cd_position = target_position
		
		request_cd_action({
			"action": "seek",
			"position": target_position
		})
		
		return
		
	if audio_player.stream == null:
		return
		
	var file_target = audio_player.get_playback_position() + amount
	var length = audio_player.stream.get_length()
	
	if file_target >= length:
		if current_track < main.playlist.size() - 1:
			play_track(current_track + 1)
		else:
			stop_track()
	else:
		audio_player.seek(file_target)


#moves playback backward by the specified number of seconds
func rewind_track(amount):
	if is_cd_track():
		if not can_send_cd_seek():
			return
			
		var target_position = max(0.0, cd_position - amount)
		
		cd_position = target_position
		
		request_cd_action({
			"action": "seek",
			"position": target_position
		})
		
		return
		
	if audio_player.stream == null:
		return
		
	var file_target = max(
		0.0,
		audio_player.get_playback_position() - amount
	)
	
	audio_player.seek(file_target)


#updates the elapsed playback time shown in the interface
func update_duration():
	var elapsed = 0.0
	
	if is_cd_track():
		elapsed = cd_position
	elif audio_player.stream != null:
		elapsed = audio_player.get_playback_position()
	else:
		return
		
	duration_label.text = format_time(int(elapsed))


#converts seconds into the minutes and seconds display format
func format_time(seconds):
	var minutes = int(seconds / 60)
	var remaining = seconds % 60
	
	return "%02d min. %02d sec." % [minutes, remaining]


#automatically advances to the next track when an audio file finishes
func _on_track_finished():
	if not is_cd_track():
		if current_track < main.playlist.size() - 1:
			play_track(current_track + 1)
		else:
			stop_track()


#stops playback and returns to the track selection screen
func go_back():
	stop_track()
	
	visible = false
	get_parent().get_node("TrackSelection").visible = true


#updates the 3D viewport visibility and stops CD playback when leaving the player
func _on_visibility_changed():
	world_view.visible = visible
	
	if not visible and is_cd_track() and cd_was_playing:
		stop_track()
