import 'package:audyn/src/presentation/pages/home/views/Downloads_view.dart';
import 'package:audyn/src/presentation/pages/home/views/Swarm_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:audyn/src/bloc/theme/theme_bloc.dart';
import 'package:audyn/src/core/constants/assets.dart';
import 'package:audyn/src/core/di/service_locator.dart';
import 'package:audyn/src/core/router/app_router.dart';
import 'package:audyn/src/core/theme/themes.dart';
import 'package:audyn/src/presentation/pages/home/views/playlists_view.dart';
import 'package:audyn/src/presentation/pages/home/views/songs_view.dart';
import 'package:audyn/src/presentation/widgets/player_bottom_app_bar.dart';


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

  final tabs = ['Songs', 'Playlists', 'Search The Swarm', 'Downloads'];

  @override
  void initState() {
    super.initState();
    checkAndRequestPermissions();
    _tabController = TabController(length: tabs.length, vsync: this);
  }

  Future<void> checkAndRequestPermissions({bool retry = false}) async {
    _hasPermission = await _audioQuery.checkAndRequest(retryRequest: retry);

    if (_hasPermission) {
      setState(() {});
    } else {
      checkAndRequestPermissions(retry: true);
    }
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
            dividerColor:
            Theme.of(context).colorScheme.onPrimary.withOpacity(0.3),
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            controller: _tabController,
            tabs: tabs.map((e) => Tab(text: e)).toList(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
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
        IconButton(
          onPressed: () {
            Navigator.of(context).pushNamed(AppRouter.searchRoute);
          },
          icon: const Icon(Icons.search_outlined),
          tooltip: 'Search',
        ),
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
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
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
