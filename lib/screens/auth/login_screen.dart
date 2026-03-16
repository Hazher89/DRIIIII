import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_strings.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _controller;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    try {
      // Supabase Google Login for Web
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'http://localhost:8080', // In production, this must match your Supabase config
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Innlogging feilet: $e'),
            backgroundColor: DriftProTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background with animated mesh-like gradient effect
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark 
                    ? [const Color(0xFF03080F), const Color(0xFF0A192F), const Color(0xFF112240)]
                    : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9), const Color(0xFFA5D6A7)],
                ),
              ),
            ),
          ),
          
          // Decorative Orbs
          Positioned(
            top: -100,
            right: -50,
            child: _buildOrb(300, DriftProTheme.primaryGreen.withOpacity(0.15)),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: _buildOrb(400, Colors.blue.withOpacity(0.1)),
          ),

          // Main Content
          Center(
            child: FadeTransition(
              opacity: _fadeIn,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Glass Logo Container
                    _buildGlassContainer(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Icon(
                          Icons.dashboard_customize_rounded,
                          size: 64,
                          color: isDark ? Colors.white : DriftProTheme.primaryGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    Text(
                      'DriftPro',
                      style: DriftProTheme.headingLg.copyWith(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                        color: isDark ? Colors.white : Colors.grey[900],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Fremtidens ERP & HMS Platform'.toUpperCase(),
                      style: DriftProTheme.labelSm.copyWith(
                        letterSpacing: 3,
                        color: DriftProTheme.primaryGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 64),

                    // Advanced Login Card
                    _buildGlassContainer(
                      width: 450,
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Logg Inn',
                            style: DriftProTheme.headingMd.copyWith(
                              fontSize: 28,
                              color: isDark ? Colors.white : Colors.grey[900],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Bli med i systemet som driver de mest effektive avdelingene.',
                            style: DriftProTheme.bodyMd.copyWith(
                              color: isDark ? Colors.white70 : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 48),

                          // Advanced Google Button
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isLoading ? null : _signInWithGoogle,
                              borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white : Colors.grey[900],
                                  borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: _isLoading
                                    ? const Center(
                                        child: SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(DriftProTheme.primaryGreen),
                                          ),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.network(
                                            'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1024px-Google_%22G%22_logo.svg.png',
                                            height: 22,
                                          ),
                                          const SizedBox(width: 16),
                                          Text(
                                            'Fortsett med Google',
                                            style: TextStyle(
                                              color: isDark ? Colors.black : Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          Center(
                            child: Text(
                              'Sikker innlogging med Supabase Auth',
                              style: DriftProTheme.caption.copyWith(
                                color: isDark ? Colors.white38 : Colors.grey[500],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 80),
                    
                    // Simple Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildFooterLink('Personvern'),
                        _buildFooterDot(),
                        _buildFooterLink('Vilkår'),
                        _buildFooterDot(),
                        _buildFooterLink('Støtte'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }

  Widget _buildGlassContainer({
    required Widget child,
    double? width,
    EdgeInsets? padding,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(DriftProTheme.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: width,
          padding: padding,
          decoration: BoxDecoration(
            color: isDark 
              ? Colors.white.withOpacity(0.04)
              : Colors.black.withOpacity(0.02),
            borderRadius: BorderRadius.circular(DriftProTheme.radiusXl),
            border: Border.all(
              color: isDark 
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.05),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildFooterLink(String text) {
    return Text(
      text,
      style: DriftProTheme.caption.copyWith(
        color: Colors.grey[500],
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildFooterDot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[400],
        ),
      ),
    );
  }
}
