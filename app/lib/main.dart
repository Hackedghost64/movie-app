import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/moviebox_api.dart';
import 'services/storage_service.dart';
import 'services/content_filter_service.dart';
import 'services/tv_mode_service.dart';
import 'services/local_stream_relay.dart';
import 'screens/main_nav_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LocalStreamRelay.instance.start();
  } catch (e) {
    debugPrint("Failed to initialize LocalStreamRelay: $e");
  }
  try {
    await MovieBoxApi.instance.init();
  } catch (e) {
    debugPrint("Failed to initialize MovieBoxApi: $e");
  }
  try {
    await StorageService.instance.init();
  } catch (e) {
    debugPrint("Failed to initialize StorageService: $e");
  }
  try {
    await ContentFilterService.instance.init();
  } catch (e) {
    debugPrint("Failed to initialize ContentFilterService: $e");
  }
  try {
    await TvModeService.instance.init();
  } catch (e) {
    debugPrint("Failed to initialize TvModeService: $e");
  }
  runApp(const MBXApp());
}

class MBXApp extends StatelessWidget {
  const MBXApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MBX Stream',
      debugShowCheckedModeBanner: false,
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.space): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
      },
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090A0E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          onPrimary: Colors.white,
          secondary: Color(0xFFFF2A36),
          surface: Color(0xFF141622),
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF090A0E),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF141622),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: const MainNavScreen(),
    );
  }
}
