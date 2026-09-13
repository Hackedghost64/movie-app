import 'package:flutter/material.dart';
import 'services/moviebox_api.dart';
import 'services/storage_service.dart';
import 'screens/main_nav_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  runApp(const MBXApp());
}

class MBXApp extends StatelessWidget {
  const MBXApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MBX Stream',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          onPrimary: Colors.white,
          secondary: Color(0xFFB81D24),
          surface: Color(0xFF1E1E1E),
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F0F),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const MainNavScreen(),
    );
  }
}
