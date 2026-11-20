extends Control

@onready var main = get_parent().get_parent()
@onready var cubes = $SubViewportContainer/SubViewport/World/TrackSelectionCubes
@onready var labels = $TrackLabels
@onready var world_view = $SubViewportContainer/SubViewport/World

#number of tracks displayed on each page
var tracks_per_page = 8
var current_page = 0
var selected_track = 0

#stores the original horizontal positions of the track labels
var label_positions = {}

#colors used to generate the cube gradient
var cube_colors = [
	Color("0000ff"),
	Color("00ffff"),
	Color("00ff00"),
	Color("ffff00"),
	Color("ff8000"),
	Color("ff0000"),
	Color("8000ff")
]


func _ready():
	world_view.visible = visible
	visibility_changed.connect(_on_visibility_changed)
	
	randomize()
	
	for i in range(tracks_per_page):
		var label = labels.get_node("Label" + str(i + 1))
		label_positions[i] = label.position.x
		
	randomize_cube_gradient()
	update_tracks()


#generates a gradient using two randomly selected colors
func randomize_cube_gradient():
	var first_index = randi_range(0, cube_colors.size() - 1)
	var second_index = randi_range(0, cube_colors.size() - 2)
	
	if second_index >= first_index:
		second_index += 1
		
	var first_color = cube_colors[first_index]
	var last_color = cube_colors[second_index]
	
	for i in range(tracks_per_page):
		var cube = cubes.get_node("Cube" + str(i + 1))
		var blend = float(i) / float(tracks_per_page - 1)
		var color = first_color.lerp(last_color, blend)
		
		var cube_material = cube.get_active_material(0)
		
		if cube_material is StandardMaterial3D:
			cube_material = cube_material.duplicate()
		else:
			cube_material = StandardMaterial3D.new()
			
		cube_material.albedo_color = color
		cube_material.emission_enabled = true
		cube_material.emission = color * 0.25
		
		cube.material_override = cube_material


#handles navigation and confirmation of the selected track
func _process(_delta):
	if not visible:
		return
		
	if Input.is_action_just_pressed("left"):
		move_selection(-1)
	if Input.is_action_just_pressed("right"):
		move_selection(1)
	if Input.is_action_just_pressed("up"):
		move_selection(-4)
	if Input.is_action_just_pressed("down"):
		move_selection(4)
	if Input.is_action_just_pressed("confirm"):
		confirm_track()
	if Input.is_action_just_pressed("back"):
		go_back()


#changes the selected track and switches pages when necessary
func move_selection(direction):
	var total_tracks = main.playlist.size()
	var new_track = selected_track + direction
	
	if new_track < 0 or new_track >= total_tracks:
		return
		
	selected_track = new_track
	current_page = selected_track / tracks_per_page
	
	update_tracks()


#updates track numbers, cube visibility and the selection indicator
func update_tracks():
	var total_tracks = main.playlist.size()
	var start_track = current_page * tracks_per_page
	
	for i in range(tracks_per_page):
		var cube = cubes.get_node("Cube" + str(i + 1))
		var label = labels.get_node("Label" + str(i + 1))
		
		var track_number = start_track + i
		var available = track_number < total_tracks
		
		cube.visible = available
		label.visible = available
		
		if available:
			label.text = str(track_number + 1)
			label.position.x = label_positions[i] - (16 if track_number + 1 >= 10 else 0)
			
		var light = cube.get_node("Light")
		light.visible = available and track_number == selected_track


#starts playback of the selected track
func confirm_track():
	if selected_track >= main.playlist.size():
		return
		
	get_parent().get_node("MusicPlayer").start_track(selected_track)


#returns to the music selection screen
func go_back():
	get_parent().get_node("MusicSelection").visible = true
	visible = false


#keeps the 3d viewport synchronized with the screen visibility
func _on_visibility_changed():
	world_view.visible = visible
