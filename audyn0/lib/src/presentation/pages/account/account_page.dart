import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../services/music_seeder_service.dart';
import '../../../../../utils/CryptoHelper.dart';
import '../../../data/services/LibtorrentService.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  final _libtorrent = LibtorrentService();
  final _seeder = MusicSeederService();

  List<Map<String, dynamic>> _localTorrents = [];
  List<Map<String, dynamic>> _seededTorrents = [];
  Map<String, Map<String, dynamic>> _metaCache = {};

  SupabaseClient get _sb => Supabase.instance.client;

  /* ───────────────── AUTH HELPERS ───────────────── */

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await _sb.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (res.user == null) {
        _error = 'Failed to sign in';
      } else {
        await _loadUserTorrents(res.user!.id);
        await _scanLocalTorrents();
      }
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Unknown error: $e';
    }
    setState(() {
      _busy = false;
    });
  }

  Future<void> _signUp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await _sb.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (res.user == null) {
        _error = 'Failed to sign up';
      }
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Unknown error: $e';
    }
    setState(() {
      _busy = false;
    });
  }

  Future<void> _signOut() async {
    await _sb.auth.signOut();
    setState(() {
      _localTorrents.clear();
      _seededTorrents.clear();
      _metaCache.clear();
    });
  }

  /* ──────────────── LOCAL TORRENTS SCAN ──────────────── */

  Future<void> _scanLocalTorrents() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _seeder.init();
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'vault'));
      if (!await dir.exists()) {
        setState(() {
          _localTorrents = [];
          _busy = false;
        });
        return;
      }

      final files = <File>[];
      await for (final f in dir.list(recursive: true)) {
        if (f is File && f.path.endsWith('.audyn.torrent')) {
          files.add(f);
        }
      }

      final List<Map<String, dynamic>> enriched = [];
      for (final file in files) {
        final name = p.basenameWithoutExtension(file.path.replaceAll('.audyn', ''));
        // Load metadata cache or fetch
        if (!_metaCache.containsKey(name)) {
          final m = await _seeder.getMetadataForName(name);
          _metaCache[name] = {
            'title': (m?['title'] ?? name).toString(),
            'artist': (m?['artist'] ?? 'Unknown Artist').toString(),
            'album': (m?['album'] ?? 'Unknown').toString(),
            'art': m?['albumArt'],
            'file_path': file.path,
          };
        }
        enriched.add(_metaCache[name]!);
      }

      setState(() {
        _localTorrents = enriched;
        _busy = false;
      });
    } catch (e, st) {
      debugPrint('[AccountPage] _scanLocalTorrents error: $e\n$st');
      setState(() {
        _error = 'Failed to scan local torrents';
        _busy = false;
      });
    }
  }

  /* ──────────────── LOAD SEEDED TORRENTS FROM SUPABASE ──────────────── */

  Future<void> _loadUserTorrents(String userId) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final List<dynamic> data = await _sb
          .from('seeder_peers')
          .select('info_hash')
          .eq('user_id', userId);

      final List<Map<String, dynamic>> torrents =
      data.cast<Map<String, dynamic>>();

      setState(() {
        _seededTorrents = torrents;
        _busy = false;
      });
    } catch (e, st) {
      debugPrint('[AccountPage] _loadUserTorrents error: $e\n$st');
      setState(() {
        _error = 'Failed to load seeded torrents';
        _busy = false;
      });
    }
  }


  /* ──────────────── UI ──────────────── */

  @override
  void initState() {
    super.initState();
    final user = _sb.auth.currentUser;
    if (user != null) {
      _loadUserTorrents(user.id);
      _scanLocalTorrents();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _sb.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: user == null ? _buildLogin() : _buildProfile(user),
      ),
    );
  }

  Widget _buildLogin() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      TextField(
        controller: _emailCtrl,
        decoration: const InputDecoration(labelText: 'E‑mail'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passCtrl,
        decoration: const InputDecoration(labelText: 'Password'),
        obscureText: true,
      ),
      const SizedBox(height: 24),
      if (_error != null) ...[
        Text(_error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
      ],
      _busy
          ? const CircularProgressIndicator()
          : Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton(onPressed: _signIn, child: const Text('Sign in')),
          OutlinedButton(onPressed: _signUp, child: const Text('Sign up')),
        ],
      ),
    ],
  );

  Widget _buildProfile(User user) {
    final th = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Logged in as', style: th.textTheme.labelLarge),
        Text(user.email ?? '—'),
        const SizedBox(height: 24),

        // Local Torrents
        Text('Local torrents', style: th.textTheme.titleMedium),
        const SizedBox(height: 8),
        _busy
            ? const Center(child: CircularProgressIndicator())
            : _localTorrents.isEmpty
            ? const Center(child: Text('No local torrents found'))
            : Expanded(
          child: ListView.separated(
            itemCount: _localTorrents.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = _localTorrents[i];
              return ListTile(
                leading: t['art'] != null
                    ? Image.memory(t['art'], width: 50, height: 50, fit: BoxFit.cover)
                    : const Icon(Icons.music_note, size: 32, color: Colors.white38),
                title: Text(t['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t['artist'] ?? 'Unknown Artist', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  onPressed: () => _addLocalTorrent(t),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Seeded torrents from Supabase
        Text('Your seeded torrents', style: th.textTheme.titleMedium),
        const SizedBox(height: 8),
        _seededTorrents.isEmpty
            ? const Text('No torrents seeded yet')
            : Expanded(
          child: ListView.separated(
            itemCount: _seededTorrents.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final hash = _seededTorrents[i]['info_hash'] as String;
              return ListTile(
                title: Text(hash, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteSeededTorrent(user.id, hash),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        Center(
          child: TextButton(
            onPressed: () async {
              await _signOut();
            },
            child: const Text('Logout'),
          ),
        )
      ],
    );
  }

  Future<void> _addLocalTorrent(Map<String, dynamic> t) async {
    final encPath = t['file_path'] as String?;
    if (encPath == null) return;

    try {
      final bytes = await File(encPath).readAsBytes();
      final plain = CryptoHelper.decryptBytes(bytes);
      if (plain == null || plain.isEmpty) throw 'Decrypt failed';

      final dir = await getApplicationDocumentsDirectory();
      final ok = await _libtorrent.addTorrentFromBytes(plain, dir.path, seedMode: false);
      if (!ok) throw 'Failed to add torrent to session';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${t['title']}" to torrent session.')),
        );
      }
    } catch (e, st) {
      debugPrint('[AccountPage] _addLocalTorrent error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding torrent: $e')),
        );
      }
    }
  }

  Future<void> _deleteSeededTorrent(String userId, String infoHash) async {
    try {
      final res = await _sb
          .from('seeder_peers')
          .delete()
          .match({'user_id': userId, 'info_hash': infoHash});

      if (res.error != null) {
        throw res.error!;
      }

      setState(() {
        _seededTorrents.removeWhere((t) => t['info_hash'] == infoHash);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Torrent deleted successfully.')),
        );
      }
    } catch (e, st) {
      debugPrint('[AccountPage] _deleteSeededTorrent error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting torrent: $e')),
        );
      }
    }
  }


}
