import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../src/presentation/pages/account/account_page.dart';

class LoginBubble extends StatelessWidget {
  const LoginBubble({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          // Navigate to AccountPage, which handles login/profile logic
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AccountPage()),
          );
        },
        child: CircleAvatar(
          radius: 18,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Icon(
            user == null ? Icons.person : Icons.person_2,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
