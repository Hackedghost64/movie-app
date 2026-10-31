import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/tv_focusable.dart';
import '../services/tv_mode_service.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'continue_watching_screen.dart';
import 'watchlist_screen.dart';
import 'downloads_screen.dart';
import 'my_space_screen.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _currentIndex = 0;
  DateTime? _lastBackPressTime;

  final List<Widget> _tvScreens = const [
    HomeScreen(),
    SearchScreen(),
    ContinueWatchingScreen(),
    WatchlistScreen(),
    DownloadsScreen(),
  ];

  final List<Widget> _mobileScreens = const [
    HomeScreen(),
    SearchScreen(),
    MySpaceScreen(),
    DownloadsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    TvModeService.instance.addListener(_onTvModeChanged);
  }

  @override
  void dispose() {
    TvModeService.instance.removeListener(_onTvModeChanged);
    super.dispose();
  }

  void _onTvModeChanged() {
    if (mounted) setState(() {});
  }

  void _onNavTapped(int index) {
    if (_currentIndex != index) {
      HapticFeedback.selectionClick();
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTv = TvModeService.instance.isTvMode(context);
    final activeScreens = isTv ? _tvScreens : _mobileScreens;
    final maxIndex = activeScreens.length - 1;
    final safeIndex = _currentIndex.clamp(0, maxIndex);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        // If not on Home tab, return to Home first
        if (_currentIndex != 0) {
          HapticFeedback.lightImpact();
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
              margin: EdgeInsets.only(bottom: 24, left: isTv ? 100 : 24, right: 24),
            ),
          );
          return;
        }

        // Double back pressed within 2s -> exit cleanly
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090A0E),
        body: isTv
            ? Row(
                children: [
                  // ── Left Navigation Rail ─────────────────────────────────────────
                  _buildLeftNavRail(),

                  // ── Main Content Area with 10-foot Safe Margin ───────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: IndexedStack(
                        index: safeIndex,
                        children: activeScreens,
                      ),
                    ),
                  ),
                ],
              )
            : IndexedStack(
                index: safeIndex,
                children: activeScreens,
              ),
        bottomNavigationBar: isTv ? null : _buildBottomBar(safeIndex),
      ),
    );
  }

  Widget _buildBottomBar(int selectedIndex) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10121A).withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: Color(0x1FFFFFFF), width: 0.8),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomNavItem(
                index: 0,
                selectedIndex: selectedIndex,
                selectedIcon: Icons.home_rounded,
                unselectedIcon: Icons.home_outlined,
                label: 'Home',
              ),
              _buildBottomNavItem(
                index: 1,
                selectedIndex: selectedIndex,
                selectedIcon: Icons.search_rounded,
                unselectedIcon: Icons.search_outlined,
                label: 'Search',
              ),
              _buildBottomNavItem(
                index: 2,
                selectedIndex: selectedIndex,
                selectedIcon: Icons.video_library_rounded,
                unselectedIcon: Icons.video_library_outlined,
                label: 'Library',
              ),
              _buildBottomNavItem(
                index: 3,
                selectedIndex: selectedIndex,
                selectedIcon: Icons.download_rounded,
                unselectedIcon: Icons.download_outlined,
                label: 'Downloads',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required int index,
    required int selectedIndex,
    required IconData selectedIcon,
    required IconData unselectedIcon,
    required String label,
  }) {
    final isSelected = selectedIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onNavTapped(index),
        splashColor: const Color(0x33E50914),
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                  horizontal: isSelected ? 16 : 0,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0x2EE50914) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isSelected ? selectedIcon : unselectedIcon,
                  color: isSelected ? const Color(0xFFE50914) : Colors.white60,
                  size: 24,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  letterSpacing: 0.2,
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

  void _showTvModeDialog() {
    final tvService = TvModeService.instance;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.tv_rounded, color: Color(0xFFE50914)),
                  SizedBox(width: 10),
                  Text("TV & Display Mode", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: tvService.isTvHardware ? Colors.green.withValues(alpha: 0.15) : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tvService.isTvHardware ? Colors.green : Colors.white24),
                      ),
                      child: Row(
                        children: [
                          Icon(tvService.isTvHardware ? Icons.check_circle : Icons.devices,
                               color: tvService.isTvHardware ? Colors.greenAccent : Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tvService.isTvHardware ? "Android TV Device Detected" : "Standard Screen / Phone",
                              style: TextStyle(
                                color: tvService.isTvHardware ? Colors.greenAccent : Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text("UI Layout Mode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    RadioGroup<TvModePreference>(
                      groupValue: tvService.preference,
                      onChanged: (pref) async {
                        if (pref != null) {
                          await tvService.setPreference(pref);
                          setDialogState(() {});
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<TvModePreference>(
                            value: TvModePreference.auto,
                            activeColor: const Color(0xFFE50914),
                            title: const Text("Auto Detect", style: TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: const Text("Switches automatically based on hardware/screen", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                          RadioListTile<TvModePreference>(
                            value: TvModePreference.tv,
                            activeColor: const Color(0xFFE50914),
                            title: const Text("Force TV Mode (10-Foot UI)", style: TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: const Text("Enforces navigation rail and remote D-pad focus", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                          RadioListTile<TvModePreference>(
                            value: TvModePreference.mobile,
                            activeColor: const Color(0xFFE50914),
                            title: const Text("Force Mobile Mode", style: TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: const Text("Enforces bottom navigation bar", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TvFocusable(
                  onTap: () => Navigator.pop(ctx),
                  borderRadius: 8,
                  autofocus: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text("Done", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            );
          },
        );
      },
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
            // Logo & TV Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'MBX',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'TV',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
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

            // Bottom TV Settings Quick Action Button
            TvFocusable(
              onTap: _showTvModeDialog,
              borderRadius: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tv_rounded, color: Colors.white70, size: 20),
              ),
            ),
            const SizedBox(height: 12),
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
