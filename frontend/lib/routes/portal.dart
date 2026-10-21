import 'package:flutter/widgets.dart';
import 'package:cacao/models/models.dart';
import 'package:cacao/screens/admin/admin_dashboard.dart';
import 'package:cacao/screens/buyer/buyer_dashboard.dart';
import 'package:cacao/screens/extension_worker/extension_worker_dashboard.dart';
import 'package:cacao/screens/farmer/farmer_dashboard.dart';
import 'package:cacao/screens/staff/staff_dashboard.dart';

/// Picks the dashboard that matches the signed-in role (Activity 2, Part A:
/// role-based routing). Each of the five documented actors gets its own
/// portal, and the backend enforces the same split.
Widget buildPortal(AppUser user) => switch (user.role) {
  'Admin' => AdminDashboard(user: user),
  'Staff' => StaffDashboard(user: user),
  'Buyer' => BuyerDashboard(user: user),
  'Extension Worker' => ExtensionWorkerDashboard(user: user),
  _ => FarmerDashboard(user: user),
};
