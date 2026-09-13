import 'package:flutter/material.dart';
import 'home_screen.dart';
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

  final List<Widget> _screens = const [
    HomeScreen(),
    ContinueWatchingScreen(),
    WatchlistScreen(),
    DownloadsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF141414),
        selectedItemColor: const Color(0xFFE50914),
        unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle_outline), label: 'Continue'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark_border), label: 'My List'),
          BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Downloads'),
        ],
      ),
    );
  }
}
