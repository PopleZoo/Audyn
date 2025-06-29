import 'package:flutter/material.dart';

import 'package:audyn/src/core/constants/assets.dart';
import 'package:audyn/src/core/router/app_router.dart';
import 'package:audyn/src/core/theme/themes.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    // after 1 seconds, navigate to home page

    Future.delayed(
      const Duration(seconds: 1),
      () {
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRouter.homeRoute);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Ink(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset(
              Assets.logo,
              width: 200,
              height: 200,
            ),
            const Text(
              'audyn',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
