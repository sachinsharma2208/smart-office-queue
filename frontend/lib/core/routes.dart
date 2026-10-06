import 'package:flutter/material.dart';

import '../models/department.dart';
import '../screens/admin_dashboard_screen.dart';
import '../screens/department_management_screen.dart';
import '../screens/department_selection_screen.dart';
import '../screens/generate_token_screen.dart';
import '../screens/home_screen.dart';
import '../screens/queue_screen.dart';
import '../screens/staff_dashboard_screen.dart';
import '../screens/staff_login_screen.dart';
import '../screens/token_details_screen.dart';
import '../widgets/require_auth.dart';

class Routes {
  static const home = '/';
  static const departments = '/departments';
  static const generate = '/generate';
  static const token = '/token';
  static const staffLogin = '/staff/login';
  static const staff = '/staff';
  static const queue = '/staff/queue';
  static const admin = '/admin';
  static const manage = '/admin/departments';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case departments:
        return _page(settings, const DepartmentSelectionScreen());
      case generate:
        return _page(settings, GenerateTokenScreen(department: settings.arguments as Department));
      case token:
        return _page(settings, const TokenDetailsScreen());
      case staffLogin:
        return _page(settings, const StaffLoginScreen());
      case staff:
        return _page(settings, const RequireAuth(child: StaffDashboardScreen()));
      case queue:
        return _page(settings, const RequireAuth(child: QueueScreen()));
      case admin:
        return _page(settings, const RequireAuth(adminOnly: true, child: AdminDashboardScreen()));
      case manage:
        return _page(settings, const RequireAuth(adminOnly: true, child: DepartmentManagementScreen()));
      case home:
      default:
        return _page(settings, const HomeScreen());
    }
  }

  static MaterialPageRoute<dynamic> _page(RouteSettings s, Widget child) =>
      MaterialPageRoute<dynamic>(settings: s, builder: (_) => child);
}
