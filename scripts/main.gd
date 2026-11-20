extends Node

#variable that stores your loaded music tracks
#music_selection.gd, track_selection.gd and music_player.gd all access this shared playlist
#it keeps the currently loaded album's track information accessible throughout the project.
#both for cd and file playback
var playlist: Array[Dictionary] = []

#IMPORTART INFORMATIONS
#DO NOT STOP THE PROJECT WITH THE SQUARE STOP BUTTON
#IF YOU DO SO CDReader.exe WILL REMAIN OPEN AND EVERYTHING BROKES
#IF YOU DO SO OR IF IT GIVES ANY ERRORS...
#...TO FIX:
#either run the project and close with the window X
#or run this in Command Prompt -> taskkill /F /T /IM CDReader.exe
#
#
#I'll paste here as commented the full cd_reader.py script that is basically CDReader.exe
#
#HOW TO USE IT IF YOU EVER NEED IT:
#Uncomment all the block from "import ctypes" with ctrl + K
#copy it in a .py file called cd_reader.py
#save it in a folder
#in command prompt in the same folder do:
#python -m pip install pyinstaller
#python -m PyInstaller --onefile --console --name CDReader cd_reader.py
#when it finishes, your executable will be located at:
#dist\CDReader.exe
#put it in the Godot project into res://tools/CDReader.exe
#Done!
#
#
#import ctypes
#import json
#import platform
#import socketserver
#import threading
#import time
#from ctypes import wintypes
#
#if platform.system() != "Windows":
	#raise SystemExit("This program only works on Windows.")
#
#HOST = "127.0.0.1"
#PORT = 47631
#
#winmm = ctypes.WinDLL("winmm")
#
#mci_send = winmm.mciSendStringW
#mci_send.argtypes = [
	#ctypes.c_wchar_p,
	#ctypes.c_wchar_p,
	#wintypes.UINT,
	#wintypes.HWND
#]
#mci_send.restype = wintypes.DWORD
#
#mci_error = winmm.mciGetErrorStringW
#mci_error.argtypes = [
	#wintypes.DWORD,
	#ctypes.c_wchar_p,
	#wintypes.UINT
#]
#mci_error.restype = wintypes.BOOL
#
#mci_lock = threading.Lock()
#
#device_open = False
#active_track = 0
#track_start = 0.0
#track_end = 0.0
#paused = False
#saved_position = 0.0
#playback_start_position = 0.0
#playback_started_at = None
#
#
#def mci_command(command):
	#error = mci_send(command, None, 0, None)
#
	#if error:
		#buffer = ctypes.create_unicode_buffer(256)
		#mci_error(error, buffer, 256)
		#raise RuntimeError(buffer.value)
#
#
#def mci_query(command):
	#buffer = ctypes.create_unicode_buffer(256)
	#error = mci_send(command, buffer, 256, None)
#
	#if error:
		#error_buffer = ctypes.create_unicode_buffer(256)
		#mci_error(error, error_buffer, 256)
		#raise RuntimeError(error_buffer.value)
#
	#return buffer.value.strip()
#
#
#def msf_to_seconds(value):
	#parts = [int(x) for x in value.split(":")]
	#return parts[0] * 60 + parts[1] + parts[2] / 75.0
#
#
#def seconds_to_msf(seconds):
	#frames = int(round(max(0.0, seconds) * 75))
	#minutes = frames // 4500
	#seconds_part = (frames % 4500) // 75
	#frame_part = frames % 75
#
	#return f"{minutes:02d}:{seconds_part:02d}:{frame_part:02d}"
#
#
#def open_cd():
	#global device_open
#
	#if device_open:
		#return
#
	#mci_command("open cdaudio alias ps2cd shareable")
	#device_open = True
#
	#try:
		#mci_command("set ps2cd time format msf")
	#except Exception:
		#close_cd()
		#raise
#
#
#def close_cd():
	#global device_open
#
	#if not device_open:
		#return
#
	#try:
		#mci_command("stop ps2cd")
	#except RuntimeError:
		#pass
#
	#try:
		#mci_command("close ps2cd")
	#except RuntimeError:
		#pass
#
	#device_open = False
#
#
#def get_track_info(number):
	#start = msf_to_seconds(
		#mci_query(f"status ps2cd position track {number}")
	#)
#
	#duration = msf_to_seconds(
		#mci_query(f"status ps2cd length track {number}")
	#)
#
	#return start, start + duration
#
#
#def no_cd_result():
	#return {
		#"inserted": False,
		#"tracks": []
	#}
#
#
#def detect_cd():
	#try:
		#open_cd()
#
		#count = int(mci_query("status ps2cd number of tracks"))
#
		#if count <= 0:
			#return no_cd_result()
#
		#tracks = []
#
		#for number in range(1, count + 1):
			#start, end = get_track_info(number)
#
			#tracks.append({
				#"number": number,
				#"duration": round(end - start, 2)
			#})
#
		#return {
			#"inserted": True,
			#"tracks": tracks
		#}
#
	#except RuntimeError as error:
		#message = str(error).lower()
#
		#expected_errors = [
			#"unknown problem while loading the specified device driver",
			#"no media",
			#"not ready",
			#"no disc",
			#"device not ready",
			#"cannot load",
			#"no compatible driver"
		#]
#
		#if any(text in message for text in expected_errors):
			#close_cd()
			#return no_cd_result()
#
		#return {
			#"inserted": False,
			#"tracks": [],
			#"error": str(error)
		#}
#
	#except Exception as error:
		#return {
			#"inserted": False,
			#"tracks": [],
			#"error": str(error)
		#}
#
#
#def play_from_position(position):
	#global paused, saved_position
	#global playback_start_position, playback_started_at
#
	#duration = max(0.0, track_end - track_start)
	#position = max(0.0, min(float(position), duration - 0.1))
#
	#absolute_position = track_start + position
#
	#mci_command("stop ps2cd")
	#mci_command(
		#f"play ps2cd from {seconds_to_msf(absolute_position)} "
		#f"to {seconds_to_msf(track_end)}"
	#)
#
	#paused = False
	#saved_position = position
	#playback_start_position = position
	#playback_started_at = time.monotonic()
#
	#return position
#
#
#def play_track(number):
	#global active_track, track_start, track_end
	#global paused, saved_position
#
	#open_cd()
#
	#count = int(mci_query("status ps2cd number of tracks"))
#
	#if number < 1 or number > count:
		#raise RuntimeError("Invalid track number.")
#
	#track_start, track_end = get_track_info(number)
	#active_track = number
	#saved_position = 0.0
	#paused = False
#
	#play_from_position(0.0)
#
#
#def get_current_position():
	#global saved_position
#
	#if active_track == 0:
		#return 0.0
#
	#if paused:
		#return saved_position
#
	#duration = max(0.0, track_end - track_start)
#
	#clock_position = saved_position
#
	#if playback_started_at is not None:
		#clock_position = (
			#playback_start_position
			#+ time.monotonic() - playback_started_at
		#)
#
	#try:
		#absolute_position = msf_to_seconds(
			#mci_query("status ps2cd position")
		#)
#
		#mci_position = max(0.0, absolute_position - track_start)
		#position = max(mci_position, clock_position)
#
	#except Exception:
		#position = clock_position
#
	#saved_position = min(position, duration)
#
	#return saved_position
#
#
#def seek_track(position):
	#global saved_position
#
	#if active_track == 0:
		#raise RuntimeError("No CD track is selected.")
#
	#duration = max(0.0, track_end - track_start)
	#position = max(0.0, min(float(position), duration - 0.1))
#
	#if paused:
		#saved_position = position
		#return position
#
	#return play_from_position(position)
#
#
#def get_status():
	#global saved_position
#
	#mode = mci_query("status ps2cd mode").lower()
	#duration = max(0.0, track_end - track_start)
#
	#if paused:
		#position = saved_position
		#playing = False
		#is_paused = True
	#else:
		#position = get_current_position()
		#playing = mode == "playing"
		#is_paused = False
#
	#finished = (
		#active_track != 0
		#and not paused
		#and mode == "stopped"
		#and duration > 0.0
		#and position >= duration - 1.0
	#)
#
	#return {
		#"mode": "paused" if is_paused else mode,
		#"playing": playing,
		#"paused": is_paused,
		#"position": round(position, 2),
		#"finished": finished
	#}
#
#
#def handle_request(data):
	#global active_track, track_start, track_end
	#global paused, saved_position, playback_started_at
	#global playback_start_position
#
	#action = data.get("action", "")
#
	#with mci_lock:
		#if action == "detect":
			#return detect_cd()
#
		#if action == "play":
			#play_track(int(data.get("track", 1)))
			#return {"success": True}
#
		#if action == "pause":
			#if active_track != 0 and not paused:
				#saved_position = get_current_position()
				#mci_command("stop ps2cd")
				#paused = True
				#playback_started_at = None
#
			#return {
				#"success": True,
				#"position": round(saved_position, 2)
			#}
#
		#if action == "resume":
			#if active_track != 0 and paused:
				#play_from_position(saved_position)
#
			#return {
				#"success": True,
				#"position": round(saved_position, 2)
			#}
#
		#if action == "seek":
			#position = seek_track(data.get("position", 0))
#
			#return {
				#"success": True,
				#"position": round(position, 2)
			#}
#
		#if action == "stop":
			#if device_open:
				#mci_command("stop ps2cd")
#
			#active_track = 0
			#track_start = 0.0
			#track_end = 0.0
			#paused = False
			#saved_position = 0.0
			#playback_start_position = 0.0
			#playback_started_at = None
#
			#return {"success": True}
#
		#if action == "status":
			#return get_status()
#
		#if action == "shutdown":
			#close_cd()
#
			#active_track = 0
			#track_start = 0.0
			#track_end = 0.0
			#paused = False
			#saved_position = 0.0
			#playback_start_position = 0.0
			#playback_started_at = None
#
			#return {
				#"success": True,
				#"shutdown": True
			#}
#
	#raise RuntimeError("Unknown command: " + action)
#
#
#class CDHandler(socketserver.StreamRequestHandler):
	#def handle(self):
		#while True:
			#line = self.rfile.readline()
#
			#if not line:
				#break
#
			#try:
				#data = json.loads(line.decode("utf-8"))
				#result = handle_request(data)
#
				#self.wfile.write(
					#(json.dumps(result) + "\n").encode("utf-8")
				#)
				#self.wfile.flush()
#
				#if data.get("action") == "shutdown":
					#threading.Thread(
						#target=self.server.shutdown,
						#daemon=True
					#).start()
					#break
#
			#except Exception as error:
				#response = {"error": str(error)}
#
				#self.wfile.write(
					#(json.dumps(response) + "\n").encode("utf-8")
				#)
				#self.wfile.flush()
#
#
#class CDServer(socketserver.ThreadingTCPServer):
	#allow_reuse_address = True
	#daemon_threads = True
#
#
#if __name__ == "__main__":
	#try:
		#with CDServer((HOST, PORT), CDHandler) as server:
			#print("CD Reader Server Ready", flush=True)
			#server.serve_forever()
#
	#except KeyboardInterrupt:
		#pass
#
	#finally:
		#with mci_lock:
			#close_cd()
