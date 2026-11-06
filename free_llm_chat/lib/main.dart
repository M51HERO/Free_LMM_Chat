import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'data/chat_repository.dart';
import 'data/secret_store.dart';
import 'state/chat_controller.dart';
import 'state/model_catalog_controller.dart';
import 'state/settings_controller.dart';
import 'ui/chat_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final settingsBox = await Hive.openBox('settings');
  final chatBox = await Hive.openBox<String>('chats');

  final settings = SettingsController(settingsBox, FlutterSecretStore());
  await settings.load();
  // Model list with prices: fetched now, after settings changes, on demand and every 10 minutes.
  final catalog = ModelCatalogController(settings)..start();
  final chats = ChatController(ChatRepository(chatBox), settings, catalog);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<ModelCatalogController>.value(value: catalog),
      ChangeNotifierProvider<ChatController>.value(value: chats),
    ],
    child: const App(),
  ));
}

ThemeData _theme(Brightness brightness, String lang) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFD97757), brightness: brightness)
      .copyWith(surface: dark ? const Color(0xFF262624) : const Color(0xFFFAF9F5));
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
  );
  final arabicFirst = lang == 'ar';
  final primary = arabicFirst
      ? GoogleFonts.notoSansArabicTextTheme(base.textTheme)
      : GoogleFonts.interTextTheme(base.textTheme);
  final fallback = (arabicFirst ? GoogleFonts.inter() : GoogleFonts.notoSansArabic()).fontFamily!;
  return base.copyWith(textTheme: primary.apply(fontFamilyFallback: [fallback]));
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Free LLM Chat',
      locale: Locale(s.lang),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: s.themeMode,
      theme: _theme(Brightness.light, s.lang),
      darkTheme: _theme(Brightness.dark, s.lang),
      home: const ChatScreen(),
    );
  }
}
