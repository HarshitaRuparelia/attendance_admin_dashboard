import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'admin_dashboard.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(AdminApp());
}

class AdminApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin Dashboard',
      theme: ThemeData(primarySwatch: Colors.orange),
      home: AdminDashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}
