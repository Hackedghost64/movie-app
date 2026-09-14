import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/tv_focusable.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'continue_watching_screen.dart';
import 'watchlist_screen.dart';
import 'downloads_screen.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _currentIndex = 0;
  DateTime? _lastBackPressTime;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    ContinueWatchingScreen(),
    WatchlistScreen(),
    DownloadsScreen(),
  ];

  void _onNavTapped(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        // If not on Home tab, return to Home first
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }

        // On Home tab: double back press protection to prevent accidental exit
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Press back again to exit',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color(0xFF1E1E1E),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE50914), width: 1),
              ),
              margin: const EdgeInsets.only(bottom: 24, left: 100, right: 32),
            ),
          );
          return;
        }

        // Double back pressed within 2s -> exit cleanly
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: Row(
          children: [
            // ── Left Navigation Rail ─────────────────────────────────────────
            _buildLeftNavRail(),

            // ── Main Content Area ────────────────────────────────────────────
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftNavRail() {
    return Container(
      width: 80,
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(
          right: BorderSide(color: Colors.white10, width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Logo Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE50914),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'MBX',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Navigation Destinations
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _TvRailItem(
                      icon: Icons.home_rounded,
                      label: 'Home',
                      isSelected: _currentIndex == 0,
                      onTap: () => _onNavTapped(0),
                    ),
                    const SizedBox(height: 12),
                    _TvRailItem(
                      icon: Icons.search_rounded,
                      label: 'Search',
                      isSelected: _currentIndex == 1,
                      onTap: () => _onNavTapped(1),
                    ),
                    const SizedBox(height: 12),
                    _TvRailItem(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'Continue',
                      isSelected: _currentIndex == 2,
                      onTap: () => _onNavTapped(2),
                    ),
                    const SizedBox(height: 12),
                    _TvRailItem(
                      icon: Icons.bookmark_outline_rounded,
                      label: 'My List',
                      isSelected: _currentIndex == 3,
                      onTap: () => _onNavTapped(3),
                    ),
                    const SizedBox(height: 12),
                    _TvRailItem(
                      icon: Icons.download_rounded,
                      label: 'Downloads',
                      isSelected: _currentIndex == 4,
                      onTap: () => _onNavTapped(4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvRailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TvRailItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TvFocusable(
        onTap: onTap,
        borderRadius: 10,
        scaleFactor: 1.06,
        autoScroll: false,
        focusedBackgroundColor: const Color(0x33E50914),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.5), width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFFE50914) : Colors.white70,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFFE50914) : Colors.white70,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
