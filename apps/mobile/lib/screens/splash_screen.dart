import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import '../core/api_client.dart';
import '../core/post_login_route.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _controller.forward();

    Timer(const Duration(seconds: 6), () async {
      if (!mounted) return;

      /// A saved session is restored through the same resolver used after
      /// login: an active captain trip / client order comes back to the foreground,
      /// a fresh captain still sees the documents wizard, and signed-out users
      /// fall through to the welcome pages at '/'.
      final session = ref.read(sessionProvider);
      if (session != null) {
        // The resolver always navigates (including when lookups fail).
        await goToRelaunchRoute(context, ref, session);
        return;
      }
      context.go('/');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF03131E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/waslny_splash_bg.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF03131E).withOpacity(0.25),
                  Colors.transparent,
                  const Color(0xFF03131E).withOpacity(0.75),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: const Color(0xFF03131E).withOpacity(0.55),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF00D875).withOpacity(0.7),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Color(0xFF00D875),
                          size: 60,
                        ),
                      ),

                      const SizedBox(height: 14),

                      const Text(
                        'Waslny',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),

                      const SizedBox(height: 2),

                      const Text(
                        'Orders',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF00D875),
                          letterSpacing: 2,
                        ),
                      ),

                      const SizedBox(height: 35),

                      const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF00D875),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const Positioned(
            left: 0,
            right: 0,
            bottom: 25,
            child: SafeArea(
              child: Text(
                'توصيل طلباتك بسهولة وأمان',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}