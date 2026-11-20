
PS2 CD Player

A recreation of the PS2 CD Player made in Godot 4.

You can play audio CDs (Windows only) or load your own MP3, WAV and OGG files.

Features:
- Physical CD playback
- Audio file playback
- Track selection
- 3D animated interface
- Browser support for audio files

Important:
Don't stop the project using the square Stop button in the Godot editor while using CD playback.

This can leave CDReader.exe running in the background.

Close the game using the window's X button instead.

If CDReader.exe gets stuck, open Command Prompt and run:

taskkill /F /T /IM CDReader.exe

Rebuilding CDReader.exe:

The Python source code for CDReader is included as comments in main.gd.

If you need to rebuild it:

1. Copy the Python code from main.gd into a file named cd_reader.py
2. Open Command Prompt in the folder containing the file
3. Install PyInstaller:

python -m pip install pyinstaller

4. Build the executable:

python -m PyInstaller --onefile --console --name CDReader cd_reader.py

5. Copy the generated dist\CDReader.exe into res://tools/CDReader.exe

Controls:
- WASD / Arrow Keys: Navigate
- Space / Enter: Select
- Backspace / Escape: Go back
- M: Load audio files

Disclaimer:

This is an unofficial fan-made project inspired by the original PlayStation 2 CD Player.

PlayStation and PlayStation 2 are trademarks of Sony Interactive Entertainment.

This project is not affiliated with or endorsed by Sony Interactive Entertainment.
