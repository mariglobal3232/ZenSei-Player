import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';

void main() {
  runApp(const ZenSeiApp());
}

class ZenSeiApp extends StatelessWidget {
  const ZenSeiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZenSei',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000), // OLED Black
        sliderTheme: const SliderThemeData(
          activeTrackColor: Colors.cyanAccent,
          thumbColor: Colors.white,
          overlayColor: Color(0x2918FFFF),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AudioPlayer _player = AudioPlayer();
  String _bgImage = "https://images.unsplash.com/photo-1494232410401-ad00d5433cfa";
  String _trackTitle = "ZEN • SEI";
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _player.positionStream.listen((p) => setState(() => _position = p));
    _player.durationStream.listen((d) => setState(() => _duration = d ?? Duration.zero));
    _player.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
  }

  // --- UI COMPONENTS ---

  Widget _glassBox({required Widget child, double height = 100}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: height,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _glassButton(IconData icon, VoidCallback onPressed, {Color color = Colors.white}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  // --- LOGIC ---

  void _playTrack(String url, String title, String art) async {
    try {
      setState(() {
        _trackTitle = title;
        _bgImage = art;
      });
      await _player.setUrl(url);
      _player.play();
    } catch (e) {
      Fluttertoast.showToast(msg: "Error playing track");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dynamic Background
          Image.network(_bgImage, fit: BoxFit.cover, 
            errorBuilder: (c, o, s) => Container(color: Colors.black)),
          Container(color: Colors.black.withOpacity(0.5)), // Dark Overlay

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                children: [
                  // Marquee
                  _glassBox(
                    height: 100,
                    child: Center(
                      child: Text(_trackTitle, 
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const Spacer(),
                  
                  // Controls Panel
                  _glassBox(
                    height: 400,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Seeker
                        Slider(
                          value: _position.inSeconds.toDouble(),
                          max: _duration.inSeconds.toDouble(),
                          onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
                        ),
                        
                        // Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _glassButton(Icons.settings, () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsScreen()))),
                            _glassButton(_isPlaying ? Icons.pause : Icons.play_arrow, 
                                () => _isPlaying ? _player.pause() : _player.play(), 
                                color: _isPlaying ? Colors.amber : Colors.white),
                            _glassButton(Icons.library_music, () => Navigator.push(context, MaterialPageRoute(builder: (c) => LibraryScreen(onPlay: _playTrack)))),
                          ],
                        ),
                        
                        // EQ Visualizer (Animated Bars)
                        SizedBox(
                          height: 50,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(10, (index) => 
                              AnimatedContainer(
                                duration: Duration(milliseconds: 300 + (index * 50)),
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                width: 8,
                                height: _isPlaying ? (20 + (index % 3 * 10)).toDouble() : 5,
                                decoration: BoxDecoration(
                                  color: Colors.cyanAccent.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              )
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- SETTINGS SCREEN ---

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      _controller.text = prefs.getString('bridge_url') ?? '';
    });
  }

  void _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bridge_url', _controller.text);
    Fluttertoast.showToast(msg: "URL Saved!");
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Setup Page
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("SETTINGS", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 20),
                  
                  // Setup Guide
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15)),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("SETUP INSTRUCTIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.cyanAccent)),
                        SizedBox(height: 10),
                        Text("1. Create 'ZenSei_Music' folder in Drive.\n2. Create a Google Apps Script.\n3. Paste the code below.\n4. Deploy as Web App (Anyone).\n5. Paste URL below."),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Code Box
                  Container(
                    padding: const EdgeInsets.all(10),
                    color: Colors.black54,
                    child: const SelectableText(
                      "function doGet() {\n  var f = DriveApp.getFoldersByName('ZenSei_Music').next();\n  var files = f.getFiles();\n  var list = [];\n  while (files.hasNext()) {\n    var file = files.next();\n    list.push({id: file.getId(), name: file.getName()});\n  }\n  return ContentService.createTextOutput(JSON.stringify(list)).setMimeType(ContentService.MimeType.JSON);\n}",
                      style: TextStyle(fontFamily: 'monospace', color: Colors.greenAccent),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Input
                  TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: "Paste Bridge URL...",
                      hintStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Buttons
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, padding: const EdgeInsets.all(15)),
                    child: const Text("SAVE CONNECTION", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, padding: const EdgeInsets.all(15)),
                    child: const Text("BACK"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- LIBRARY SCREEN ---

class LibraryScreen extends StatefulWidget {
  final Function(String, String, String) onPlay;
  const LibraryScreen({required this.onPlay, super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<dynamic> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchTracks();
  }

  Future<void> _fetchTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('bridge_url');
      if (url == null || url.isEmpty) throw Exception("No URL");

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        setState(() {
          _tracks = json.decode(response.body);
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
      Fluttertoast.showToast(msg: "Failed to sync. Check URL.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("LIBRARY", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            
            // List
            Expanded(
              child: _loading 
                ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                : ListView.builder(
                    itemCount: _tracks.length,
                    itemBuilder: (ctx, i) {
                      final t = _tracks[i];
                      // Simple Album Art Logic
                      final art = "https://images.unsplash.com/photo-1494232410401-ad00d5433cfa";
                      final streamUrl = "https://docs.google.com/uc?export=download&id=${t['id']}";
                      
                      return ListTile(
                        leading: Container(
                          width: 50, height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            image: DecorationImage(image: NetworkImage(art), fit: BoxFit.cover),
                          ),
                        ),
                        title: Text(t['name'], style: const TextStyle(color: Colors.white)),
                        onTap: () {
                          widget.onPlay(streamUrl, t['name'], art);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

