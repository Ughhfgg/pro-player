import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const String kDevName = 'Kira.art2003';
const String kInstaUrl = 'https://instagram.com/Kira.art2003';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const App());
}

Future<void> openInstagram() async {
  await launchUrl(Uri.parse(kInstaUrl), mode: LaunchMode.externalApplication);
}

// ---------------- Model ----------------
class Item {
  final String name, url;
  final bool local;
  Item(this.name, this.url, this.local);
  Map<String, dynamic> toJson() => {'n': name, 'u': url, 'l': local};
  factory Item.fromJson(Map<String, dynamic> j) =>
      Item(j['n'], j['u'], j['l'] ?? false);
}

// M3U / M3U8 parser
List<Item> parseM3u(String text) {
  final out = <Item>[];
  String? name;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final i = line.lastIndexOf(',');
      name = i >= 0 ? line.substring(i + 1).trim() : null;
    } else if (!line.startsWith('#')) {
      out.add(Item(name?.isNotEmpty == true ? name! : line, line, false));
      name = null;
    }
  }
  return out;
}

// ---------------- Instagram icon ----------------
class InstaIcon extends StatelessWidget {
  final double size;
  final Color color;
  const InstaIcon({super.key, this.size = 22, this.color = Colors.pinkAccent});

  @override
  Widget build(BuildContext context) {
    final w = size * 0.1;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: color, width: w),
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
        ),
        Center(
          child: Container(
            width: size * 0.45,
            height: size * 0.45,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: w)),
          ),
        ),
        Positioned(
          top: size * 0.17,
          right: size * 0.17,
          child: Container(
              width: size * 0.1,
              height: size * 0.1,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ),
      ]),
    );
  }
}

// ---------------- App ----------------
class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pro Player',
        theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.deepPurple),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Item> items = [];
  String query = '';
  int tab = 0; // 0 All, 1 Device, 2 Links

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('items');
    if (s != null) {
      items = (jsonDecode(s) as List).map((e) => Item.fromJson(e)).toList();
      setState(() {});
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('items', jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  void _add(List<Item> n) {
    setState(() => items.addAll(n));
    _save();
  }

  List<Item> get filtered => items.where((e) {
        if (tab == 1 && !e.local) return false;
        if (tab == 2 && e.local) return false;
        return e.name.toLowerCase().contains(query.toLowerCase());
      }).toList();

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickLocal() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.video, allowMultiple: true);
    if (r == null) return;
    _add(r.files
        .where((f) => f.path != null)
        .map((f) => Item(f.name, f.path!, true))
        .toList());
  }

  Future<void> _addUrl() async {
    final n = TextEditingController(), u = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add link'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'Name')),
          TextField(
              controller: u,
              decoration: const InputDecoration(labelText: 'URL (http, rtmp, rtsp, udp...)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && u.text.trim().isNotEmpty) {
      final url = u.text.trim();
      _add([Item(n.text.trim().isEmpty ? url : n.text.trim(), url, false)]);
    }
  }

  Future<void> _importM3u({required bool fromUrl}) async {
    try {
      String text;
      if (fromUrl) {
        final c = TextEditingController();
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('M3U playlist URL'),
            content: TextField(controller: c),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Import')),
            ],
          ),
        );
        if (ok != true || c.text.trim().isEmpty) return;
        _snack('Loading...');
        final res = await http.get(Uri.parse(c.text.trim()),
            headers: {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'});
        text = utf8.decode(res.bodyBytes, allowMalformed: true);
      } else {
        final r = await FilePicker.platform.pickFiles(type: FileType.any);
        if (r?.files.single.path == null) return;
        text = await File(r!.files.single.path!).readAsString();
      }
      final list = parseM3u(text);
      _add(list);
      _snack('${list.length} items added');
    } catch (e) {
      _snack('Import failed: $e');
    }
  }

  void _menu() => showModalBottomSheet(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.video_file),
                title: const Text('Video from device'),
                onTap: () { Navigator.pop(c); _pickLocal(); }),
            ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Add link'),
                onTap: () { Navigator.pop(c); _addUrl(); }),
            ListTile(
                leading: const Icon(Icons.cloud_download),
                title: const Text('Import IPTV playlist from URL'),
                onTap: () { Navigator.pop(c); _importM3u(fromUrl: true); }),
            ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Import M3U file from device'),
                onTap: () { Navigator.pop(c); _importM3u(fromUrl: false); }),
          ]),
        ),
      );

  void _about() => showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Pro Player'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Professional video player with IPTV support.'),
            const SizedBox(height: 16),
            const Text('Developer'),
            const SizedBox(height: 8),
            InkWell(
              onTap: openInstagram,
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                InstaIcon(size: 24),
                SizedBox(width: 8),
                Text(kDevName,
                    style: TextStyle(
                        color: Colors.pinkAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ]),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
          ],
        ),
      );

  Widget _footer() => InkWell(
        onTap: openInstagram,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
            Text('Developed by ', style: TextStyle(color: Colors.white60)),
            InstaIcon(size: 18),
            SizedBox(width: 6),
            Text(kDevName,
                style: TextStyle(
                    color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pro Player'),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _about),
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () { setState(() => items.clear()); _save(); },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Your list is empty. Tap + to add.'))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (c, i) {
                    final it = list[i];
                    return ListTile(
                      leading: Icon(it.local ? Icons.smartphone : Icons.live_tv),
                      title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(it.local ? 'Device' : it.url,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () { setState(() => items.remove(it)); _save(); },
                      ),
                      onTap: () => Navigator.push(
                        c,
                        MaterialPageRoute(
                            builder: (_) => PlayerPage(
                                list: list.length > 300 ? [it] : list,
                                index: list.length > 300 ? 0 : i)),
                      ),
                    );
                  },
                ),
        ),
        _footer(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.all_inclusive), label: 'All'),
          NavigationDestination(icon: Icon(Icons.smartphone), label: 'Device'),
          NavigationDestination(icon: Icon(Icons.live_tv), label: 'Links'),
        ],
      ),
      floatingActionButton:
          FloatingActionButton(onPressed: _menu, child: const Icon(Icons.add)),
    );
  }
}

// ---------------- Player ----------------
class PlayerPage extends StatefulWidget {
  final List<Item> list;
  final int index;
  const PlayerPage({super.key, required this.list, required this.index});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player player = Player(
      configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024));
  late final VideoController controller = VideoController(player);

  @override
  void initState() {
    super.initState();
    player.open(
      Playlist(
        widget.list
            .map((e) => Media(e.url,
                httpHeaders: e.local
                    ? null
                    : {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'}))
            .toList(),
        index: widget.index,
      ),
    );
    player.stream.error.listen((e) {
      if (mounted && e.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Playback error: $e')));
      }
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(widget.list[widget.index].name,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: SafeArea(
          child: Center(child: Video(controller: controller)),
        ),
      );
}
