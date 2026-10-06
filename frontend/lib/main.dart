import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/routes.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/staff_provider.dart';
import 'providers/visitor_provider.dart';
import 'repositories/auth_repository.dart';
import 'repositories/queue_repository.dart';
import 'services/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Dependency wiring: ApiClient -> repositories -> providers -> widgets.
  final api = ApiClient();
  final queueRepo = QueueRepository(api);
  final auth = AuthProvider(AuthRepository(api), api, prefs);
  await auth.restore();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<VisitorProvider>(create: (_) => VisitorProvider(queueRepo, prefs)),
        ChangeNotifierProvider<StaffProvider>(create: (_) => StaffProvider(queueRepo)),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Office Queue',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: Routes.home,
      onGenerateRoute: Routes.onGenerateRoute,
    );
  }
}
