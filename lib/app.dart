import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/book.dart';
import 'models/browse_list_args.dart';
import 'providers/download_providers.dart';
import 'providers/player_providers.dart';
import 'providers/settings_providers.dart';
import 'providers/source_providers.dart';
import 'screens/about_screen.dart';
import 'screens/book_detail_screen.dart';
import 'screens/bookshelf_screen.dart';
import 'screens/category_all_screen.dart';
import 'screens/category_list_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/download_book_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sources_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_dock.dart';
import 'widgets/mini_player_bar.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

class AudiobookApp extends ConsumerStatefulWidget {
  const AudiobookApp({super.key});

  @override
  ConsumerState<AudiobookApp> createState() => _AudiobookAppState();
}

class _AudiobookAppState extends ConsumerState<AudiobookApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/shelf',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              _ShellScreen(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/shelf',
                builder: (context, state) => const BookshelfScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/discover',
                builder: (context, state) => const DiscoverScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => SearchScreen(
                  initialKeyword: state.extra is String
                      ? state.extra as String
                      : null,
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/downloads',
                builder: (context, state) => const DownloadsScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ]),
          ],
        ),
        GoRoute(
          path: '/player',
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            opaque: false,
            barrierColor: Colors.black38,
            child: const PlayerScreen(),
            transitionsBuilder: (context, animation, secondary, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              );
            },
          ),
        ),
        GoRoute(
          path: '/sources',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) => const SourcesScreen(),
        ),
        GoRoute(
          path: '/book-detail',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) {
            final extra = state.extra;
            if (extra is! Book) {
              return Scaffold(
                appBar: AppBar(title: const Text('书籍详情')),
                body: const Center(child: Text('缺少书籍信息，请返回重试')),
              );
            }
            return BookDetailScreen(book: extra);
          },
        ),
        GoRoute(
          path: '/download-book/:bookId',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) {
            final raw = state.pathParameters['bookId'] ?? '';
            return DownloadBookScreen(bookId: Uri.decodeComponent(raw));
          },
        ),
        GoRoute(
          path: '/category-all',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) => const CategoryAllScreen(),
        ),
        GoRoute(
          path: '/category',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) => CategoryListScreen(
            args: BrowseListArgs.fromExtra(state.extra),
          ),
        ),
        GoRoute(
          path: '/about',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) => const AboutScreen(),
        ),
      ],
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playerControllerProvider).restoreLastSession();
      ref.read(sourcesControllerProvider).load();
      ref.read(downloadServiceProvider).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    return MaterialApp.router(
      title: AppTheme.brandName,
      debugShowCheckedModeBanner: false,
      theme: settings.lightTheme,
      darkTheme: settings.darkTheme,
      themeMode: settings.themeMode,
      routerConfig: _router,
    );
  }
}

class _ShellScreen extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const _ShellScreen({required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSession = ref.watch(
      playerControllerProvider.select((p) => p.hasSession),
    );

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasSession) const MiniPlayerBar(),
          AppDock(
            index: navigationShell.currentIndex,
            onChanged: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
          ),
        ],
      ),
    );
  }
}
