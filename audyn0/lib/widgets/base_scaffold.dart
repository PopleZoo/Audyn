// lib/src/widgets/base_scaffold.dart

import 'package:flutter/material.dart';
import 'login_bubble.dart';

class BaseScaffold extends StatelessWidget {
  final Widget body;
  final String title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const BaseScaffold({
    super.key,
    required this.body,
    required this.title,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(title),
        actions: [
          if (actions != null) ...actions!,
          const LoginBubble(), // Always at the end (right corner)
        ],
      ),
      drawer: const Drawer(
        child: Center(child: Text("Your Navigation Drawer")),
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
