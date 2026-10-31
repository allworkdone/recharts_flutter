import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter/services.dart';

import 'parity/fixture_renderer.dart';

const _fixtureDir = 'assets/parity/fixtures/';

const _parityTextStyle = TextStyle(fontFamily: 'Roboto', fontSize: 12, color: Color(0xFF000000));

void main() {
  final fixture = Uri.base.queryParameters['fixture'];
  runApp(fixture != null ? ParityApp(fixture: fixture) : const GalleryApp());
}

Future<Map<String, dynamic>> loadFixture(String name) async =>
    jsonDecode(await rootBundle.loadString('$_fixtureDir$name.json')) as Map<String, dynamic>;

/// `?fixture=<name>`: the chart alone at (0,0), exact size, white background.
/// With `anim=1` the chart is not mounted until JS calls `window.__parityStart()`
/// (after `window.__parityReady` is set), so animation time starts at mount.
class ParityApp extends StatefulWidget {
  const ParityApp({super.key, required this.fixture});
  final String fixture;

  @override
  State<ParityApp> createState() => _ParityAppState();
}

class _ParityAppState extends State<ParityApp> {
  final bool _deferred = Uri.base.queryParameters['anim'] == '1';
  late bool _mounted = !_deferred;
  late final Future<Map<String, dynamic>> _fixture = loadFixture(widget.fixture);

  @override
  void initState() {
    super.initState();
    if (!_deferred) return;
    globalContext.setProperty('__parityStart'.toJS, (() {
      if (mounted) setState(() => _mounted = true);
    }).toJS);
    _fixture.then((_) => WidgetsBinding.instance.addPostFrameCallback((_) {
          globalContext.setProperty('__parityReady'.toJS, true.toJS);
        }));
  }

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: const Color(0xFFFFFFFF),
      debugShowCheckedModeBanner: false,
      builder: (context, _) => ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: DefaultTextStyle(
          style: _parityTextStyle,
          child: FutureBuilder(
            future: _fixture,
            builder: (context, snapshot) {
              final f = snapshot.data;
              if (f == null || !_mounted) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: (f['width'] as num).toDouble(),
                  height: (f['height'] as num).toDouble(),
                  child: renderFixture(f),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Lists every fixture; tapping one shows the chart at its size.
class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'recharts_flutter',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF8884D8)),
      home: const _FixtureList(),
    );
  }
}

class _FixtureList extends StatelessWidget {
  const _FixtureList();

  Future<List<String>> _names() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest
        .listAssets()
        .where((a) => a.startsWith(_fixtureDir) && a.endsWith('.json'))
        .map((a) => a.substring(_fixtureDir.length, a.length - 5))
        .toList()
      ..sort();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('recharts_flutter fixtures')),
      body: FutureBuilder(
        future: _names(),
        builder: (context, snapshot) {
          final names = snapshot.data;
          if (names == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            children: [
              for (final n in names)
                ListTile(
                  title: Text(n),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => _FixturePage(name: n)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FixturePage extends StatelessWidget {
  const _FixturePage({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: FutureBuilder(
        future: loadFixture(name),
        builder: (context, snapshot) {
          final f = snapshot.data;
          if (f == null) return const Center(child: CircularProgressIndicator());
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f['description'] as String? ?? ''),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ColoredBox(
                    color: Colors.white,
                    child: DefaultTextStyle(
                      style: _parityTextStyle,
                      child: SizedBox(
                        width: (f['width'] as num).toDouble(),
                        height: (f['height'] as num).toDouble(),
                        child: renderFixture(f),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
