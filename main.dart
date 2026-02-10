import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:marquee/marquee.dart';
import 'package:on_audio_query/on_audio_query.dart';

void main() {
  runApp(const ZenSeiApp());
}

class ZenSeiApp extends StatelessWidget {
  const ZenSeiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZenSei',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Colors.cyanAccent,
          thumbColor: Colors.white,
          trackHeight: 2.0,
        ),
      ),
      home: const SplashScreen(), // Starts with Splash
    );
  }
}

// --- 1. SPLASH SCREEN ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Wait 3 seconds then go to Main
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const MainScreen()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo Animation
            TweenAnimationBuilder(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(seconds: 2),
              builder: (context, double val, child) {
                return Opacity(
                  opacity: val,
                  child: const Text("Z E N S E I", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 5, color: Colors.cyanAccent)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// --- 2. MAIN PLAYER ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final OnAudioQuery _audioQuery = OnAudioQuery();
  
  // Playlist State
  List<Map<String, String>> _playlist = [];
  int _currentIndex = -1;
  LoopMode _loopMode = LoopMode.off;

  String _bgImage = "https://images.unsplash.com/photo-1494232410401-ad00d5433cfa";
  String _trackTitle = "ZEN • SEI";
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  late AnimationController _eqController;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    
    _player.positionStream.listen((p) => setState(() => _position = p));
    _player.durationStream.listen((d) => setState(() => _duration = d ?? Duration.zero));
    _player.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        _onTrackFinished();
      }
    });

    _eqController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100))..repeat(reverse: true);
  }

  Future<void> _requestPermissions() async {
    // Android 13+ needs separate media permissions
    await [Permission.storage, Permission.audio, Permission.manageExternalStorage].request();
  }

  void _onTrackFinished() {
    if (_loopMode == LoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
    } else {
      _playNext();
    }
  }

  void _playNext() {
    if (_playlist.isEmpty) return;
    int nextIndex = _currentIndex + 1;
    if (nextIndex >= _playlist.length) {
      if (_loopMode == LoopMode.all) nextIndex = 0; // Loop back to start
      else return; // Stop if no repeat
    }
    _loadTrack(nextIndex);
  }

  void _playPrevious() {
    if (_playlist.isEmpty) return;
    if (_position.inSeconds > 3) {
      _player.seek(Duration.zero); // Restart song if > 3s in
    } else {
      int prevIndex = _currentIndex - 1;
      if (prevIndex < 0) prevIndex = _playlist.length - 1;
      _loadTrack(prevIndex);
    }
  }

  void _toggleRepeat() {
    setState(() {
      if (_loopMode == LoopMode.off) {
        _loopMode = LoopMode.all;
        Fluttertoast.showToast(msg: "Repeat All");
      } else if (_loopMode == LoopMode.all) {
        _loopMode = LoopMode.one;
        Fluttertoast.showToast(msg: "Repeat One");
      } else {
        _loopMode = LoopMode.off;
        Fluttertoast.showToast(msg: "Repeat Off");
      }
    });
  }

  void _loadTrack(int index) async {
    try {
      if (index < 0 || index >= _playlist.length) return;
      _currentIndex = index;
      final track = _playlist[index];
      
      setState(() {
        _trackTitle = track['title']!;
        // Use local art if available, otherwise default aesthetic
        _bgImage = "https://images.unsplash.com/photo-1494232410401-ad00d5433cfa"; 
      });

      if (track['type'] == 'local') {
        await _player.setFilePath(track['url']!);
      } else {
        await _player.setUrl(track['url']!);
      }
      _player.play();
    } catch (e) {
      Fluttertoast.showToast(msg: "Error: $e");
    }
  }

  // Called from Library Screen
  void _setPlaylist(List<Map<String, String>> newPlaylist, int startIndex) {
    setState(() {
      _playlist = newPlaylist;
    });
    _loadTrack(startIndex);
  }

  Widget _glassBox({required Widget child, double? height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: height,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _glassButton(IconData icon, VoidCallback onPressed, {Color color = Colors.white, double size = 60}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    IconData repeatIcon = Icons.repeat;
    Color repeatColor = Colors.white;
    if (_loopMode == LoopMode.one) { repeatIcon = Icons.repeat_one; repeatColor = Colors.cyanAccent; }
    if (_loopMode == LoopMode.all) { repeatIcon = Icons.repeat; repeatColor = Colors.cyanAccent; }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(_bgImage, fit: BoxFit.cover, errorBuilder: (c,o,s) => Container(color: Colors.black)),
          Container(color: Colors.black.withOpacity(0.6)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _glassBox(
                    height: 120,
                    child: Center(
                      child: SizedBox(
                        height: 40,
                        child: Marquee(
                          text: _trackTitle.toUpperCase(),
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white),
                          blankSpace: 50.0,
                          velocity: 30.0,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _glassBox(
                    height: 400,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Slider(value: min(_position.inSeconds.toDouble(), _duration.inSeconds.toDouble()), max: _duration.inSeconds.toDouble(), onChanged: (v) => _player.seek(Duration(seconds: v.toInt()))),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _glassButton(repeatIcon, _toggleRepeat, color: repeatColor, size: 50),
                            _glassButton(Icons.skip_previous, _playPrevious, size: 50),
                            _glassButton(_isPlaying ? Icons.pause : Icons.play_arrow, () => _isPlaying ? _player.pause() : _player.play(), color: _isPlaying ? Colors.amber : Colors.white, size: 70),
                            _glassButton(Icons.skip_next, _playNext, size: 50),
                            _glassButton(Icons.queue_music, () => Navigator.push(context, MaterialPageRoute(builder: (c) => LibraryScreen(onPlaylistSelected: _setPlaylist)))),
                          ],
                        ),
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

// --- 3. HYBRID LIBRARY SCREEN ---
class LibraryScreen extends StatefulWidget {
  final Function(List<Map<String, String>>, int) onPlaylistSelected;
  const LibraryScreen({required this.onPlaylistSelected, super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Map<String, String>> _allTracks = [];
  bool _loading = true;
  final OnAudioQuery _audioQuery = OnAudioQuery();

  @override
  void initState() {
    super.initState();
    _fetchAllMusic();
  }

  Future<void> _fetchAllMusic() async {
    List<Map<String, String>> tracks = [];

    // 1. Fetch Local
    try {
      if (await Permission.storage.request().isGranted || await Permission.audio.request().isGranted) {
        List<SongModel> localSongs = await _audioQuery.querySongs(
          sortType: null,
          orderType: OrderType.ASC_OR_SMALLER,
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
        );
        for (var song in localSongs) {
          if (song.isMusic == true) {
            tracks.add({
              'title': song.title,
              'url': song.data,
              'type': 'local',
            });
          }
        }
      }
    } catch (e) { print("Local Error: $e"); }

    // 2. Fetch Drive
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('bridge_url');
      if (url != null && url.isNotEmpty) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          List<dynamic> driveData = json.decode(response.body);
          for (var item in driveData) {
            tracks.add({
              'title': item['name'].toString().replaceAll('.mp3', ''),
              'url': "https://docs.google.com/uc?export=download&id=${item['id']}",
              'type': 'drive',
            });
          }
        }
      }
    } catch (e) { print("Drive Error: $e"); }

    setState(() {
      _allTracks = tracks;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("LIBRARY", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))
                ],
              ),
            ),
            Expanded(
              child: _loading 
                ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                : ListView.builder(
                    itemCount: _allTracks.length,
                    itemBuilder: (ctx, i) {
                      final t = _allTracks[i];
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
                        child: ListTile(
                          leading: Container(
                            width: 50, height: 50,
                            decoration: BoxDecoration(color: t['type'] == 'local' ? Colors.green : Colors.blue, borderRadius: BorderRadius.circular(10)),
                            child: Icon(t['type'] == 'local' ? Icons.sd_storage : Icons.cloud, color: Colors.white),
                          ),
                          title: Text(t['title']!, style: const TextStyle(color: Colors.white)),
                          onTap: () {
                            widget.onPlaylistSelected(_allTracks, i);
                            Navigator.pop(context);
                          },
                        ),
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
