import 'dart:async';

import 'package:audyn/src/presentation/pages/home/views/Downloads_view.dart';
import 'package:audyn/src/presentation/pages/home/views/Swarm_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, OAuthProvider;
import 'package:flutter_appauth/flutter_appauth.dart';

import 'package:audyn/src/bloc/theme/theme_bloc.dart';
import 'package:audyn/src/core/constants/assets.dart';
import 'package:audyn/src/core/di/service_locator.dart';
import 'package:audyn/src/core/router/app_router.dart';
import 'package:audyn/src/core/theme/themes.dart';
import 'package:audyn/src/presentation/pages/home/views/playlists_view.dart';
import 'package:audyn/src/presentation/pages/home/views/songs_view.dart';
import 'package:audyn/src/presentation/widgets/player_bottom_app_bar.dart';

final FlutterAppAuth appAuth = FlutterAppAuth();

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final OnAudioQuery _audioQuery = sl<OnAudioQuery>();
  late TabController _tabController;
  bool _hasPermission = false;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  late final StreamSubscription<AuthState> _authSub;

  final tabs = ['Songs', 'Playlists', 'Swarm', 'Downloads'];

  @override
  void initState() {
    super.initState();
    checkAndRequestPermissions();
    _tabController = TabController(length: tabs.length, vsync: this);

    // Listen for auth state changes and update UI accordingly
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      debugPrint('Auth event: $event');
      setState(() {
        // Rebuild UI on sign in or sign out
      });
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> checkAndRequestPermissions({bool retry = false}) async {
    _hasPermission = await _audioQuery.checkAndRequest(retryRequest: retry);

    if (_hasPermission) {
      setState(() {});
    } else {
      checkAndRequestPermissions(retry: true);
    }
  }

  Widget _buildLoginBubble() {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return TextButton(
        onPressed: () async {
          final success = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
          if (success == true) {
            setState(() {});
          }
        },
        child: const Icon(Icons.person, color: Colors.white),
      );
    } else {
      return PopupMenuButton<String>(
        tooltip: 'Account',
        icon: CircleAvatar(
          backgroundColor: Colors.blueGrey,
          backgroundImage: user.userMetadata?['avatar_url'] != null
              ? NetworkImage(user.userMetadata!['avatar_url'])
              : null,
          child: user.userMetadata?['avatar_url'] == null
              ? Text(
            (user.email ?? "?").substring(0, 1).toUpperCase(),
            style: const TextStyle(color: Colors.white),
          )
              : null,
        ),
        onSelected: (value) async {
          switch (value) {
            case 'logout':
              await Supabase.instance.client.auth.signOut();
              setState(() {});
              break;
            case 'removeSeeder':
              await _removeSelfAsSeeder();
              break;
            case 'takeDownTorrents':
              await _takeDownOwnTorrents();
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'removeSeeder',
            child: Text('Remove Self as Seeder'),
          ),
          const PopupMenuItem(
            value: 'takeDownTorrents',
            child: Text('Take Down Own Torrents'),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'logout',
            child: Text('Logout (${user.email ?? "user"})'),
          ),
        ],
      );
    }
  }

  Future<void> _removeSelfAsSeeder() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("You have been removed as a seeder.")),
    );
  }

  Future<void> _takeDownOwnTorrents() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Your torrents have been taken down.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, state) {
        return Scaffold(
          key: scaffoldKey,
          bottomNavigationBar: const PlayerBottomAppBar(),
          extendBody: true,
          backgroundColor: Theme.of(context).colorScheme.background,
          drawer: _buildDrawer(context),
          appBar: _buildAppBar(),
          body: _buildBody(context),
        );
      },
    );
  }

  Ink _buildBody(BuildContext context) {
    return Ink(
      child: _hasPermission
          ? Column(
        children: [
          TabBar(
            dividerColor: Theme.of(context)
                .colorScheme
                .onPrimary
                .withOpacity(0.3),
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            controller: _tabController,
            tabs: tabs.map((e) => Tab(text: e)).toList(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                SongsView(),
                PlaylistsView(),
                SwarmView(),
                DownloadsView(),
              ],
            ),
          ),
        ],
      )
          : Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Center(child: Text('No permission to access library')),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () async {
              await Permission.storage.request();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Themes.getTheme().primaryColor,
      leading: IconButton(
        icon: SvgPicture.asset(
          Assets.menuSvg,
          width: 32,
          height: 32,
          colorFilter: ColorFilter.mode(
            Theme.of(context).textTheme.bodyMedium!.color!,
            BlendMode.srcIn,
          ),
        ),
        tooltip: 'Menu',
        onPressed: () => scaffoldKey.currentState?.openDrawer(),
      ),
      actions: [
        _buildLoginBubble(),
      ],
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          BlocBuilder<ThemeBloc, ThemeState>(
            builder: (context, state) {
              return Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(top: 48, bottom: 16),
                decoration: BoxDecoration(
                  color: Themes.getTheme().primaryColor,
                ),
                child: Row(
                  children: [
                    Hero(
                      tag: 'logo',
                      child: Image.asset(Assets.logo, height: 64, width: 64),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'audyn',
                      style:
                      TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          ),
          Divider(
            color: Colors.grey.withOpacity(0.1),
            indent: 16,
            endIndent: 16,
          ),
          ListTile(
            leading: const Icon(Icons.color_lens_outlined),
            title: const Text('Themes'),
            onTap: () {
              Navigator.of(context).pushNamed(AppRouter.themesRoute);
            },
          ),
          ListTile(
            leading: SvgPicture.asset(
              Assets.settingsSvg,
              colorFilter: ColorFilter.mode(
                Theme.of(context).textTheme.bodyMedium!.color!,
                BlendMode.srcIn,
              ),
            ),
            title: const Text('Settings'),
            onTap: () {
              Navigator.of(context).pushNamed(AppRouter.settingsRoute);
            },
          ),
        ],
      ),
    );
  }
}


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _loginWithEmail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (res.user != null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = 'Login failed: User not found or wrong password.';
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signUpWithEmail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (res.user != null) {
        setState(() {
          _error = 'Sign up successful. Please check your email to confirm.';
        });
      } else {
        setState(() {
          _error = 'Sign up failed.';
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login / Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              autofillHints: const [AutofillHints.password],
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              Column(
                children: [
                  ElevatedButton(
                    onPressed: _loginWithEmail,
                    child: const Text('Login with Email'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _signUpWithEmail,
                    child: const Text('Sign Up with Email'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
