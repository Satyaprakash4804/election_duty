import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../core/constants.dart';

// ─────────────────────────────────────────────
//  COLOR PALETTE
// ─────────────────────────────────────────────
const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kAccent  = Color(0xFFB8860B);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);
const kGold    = Color(0xFFFFD700);

// ─────────────────────────────────────────────
//  THEME
// ─────────────────────────────────────────────
final ThemeData electionTheme = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: kBg,
  fontFamily: 'Roboto',
  colorScheme: ColorScheme.light(
    primary:     kPrimary,
    secondary:   kAccent,
    surface:     kSurface,
    error:       kError,
    onPrimary:   Colors.white,
    onSecondary: Colors.white,
    onSurface:   kDark,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kDark,
    foregroundColor: Colors.white,
    centerTitle: true,
    elevation: 3,
    shadowColor: Color(0x44000000),
    titleTextStyle: TextStyle(
      color: Colors.white,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      elevation: 4,
      shadowColor: const Color(0x558B6914),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kBorder, width: 1.2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kPrimary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kError, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kError, width: 2),
    ),
    labelStyle: const TextStyle(color: kSubtle, fontWeight: FontWeight.w500),
    prefixIconColor: kPrimary,
  ),
  cardTheme: CardThemeData(
    color: kSurface,
    elevation: 4,
    shadowColor: const Color(0x308B6914),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: kBorder, width: 0.8),
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: kDark,
    selectedItemColor: kBorder,
    unselectedItemColor: Color(0xFF9E8E6E),
    selectedIconTheme: IconThemeData(size: 26),
    showUnselectedLabels: true,
    type: BottomNavigationBarType.fixed,
  ),
);

// ─────────────────────────────────────────────
//  BACKGROUND PAINTERS
// ─────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = kBorder.withOpacity(0.15)
      ..strokeWidth = 0.6;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final diagPaint = Paint()
      ..color = kBorder.withOpacity(0.07)
      ..strokeWidth = 60;
    canvas.drawLine(
      Offset(size.width * 0.55, 0),
      Offset(size.width * 1.2, size.height),
      diagPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _SplashBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.topCenter,
        radius: 1.2,
        colors: [
          kPrimary.withOpacity(0.18),
          kDark.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final dotPaint = Paint()
      ..color = kBorder.withOpacity(0.08)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const spacing = 28.0;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────
//  ANIMATED PROGRESS BAR
// ─────────────────────────────────────────────
class _SplashProgressBar extends StatelessWidget {
  final Animation<double> animation;
  const _SplashProgressBar({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final progress = (animation.value / 0.78).clamp(0.0, 1.0);
        return Container(
          width: 200,
          height: 4,
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPrimary, kGold]),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(color: kGold.withOpacity(0.5), blurRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  SHARED SPLASH BODY
//  Reused by both OfficerSplashPage & PostLoginSplashPage
// ─────────────────────────────────────────────
class _SplashBody extends StatelessWidget {
  final AnimationController ctrl;
  final Animation<double>   fadeIn;
  final Animation<double>   fadeOut;
  final Animation<double>   photoScale;
  final Animation<Offset>   photoSlide;
  final Animation<Offset>   textSlide;
  final Animation<double>   shimmer;
  final String              statusLabel;

  const _SplashBody({
    required this.ctrl,
    required this.fadeIn,
    required this.fadeOut,
    required this.photoScale,
    required this.photoSlide,
    required this.textSlide,
    required this.shimmer,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final opacity =
            ctrl.value < 0.78 ? fadeIn.value : fadeOut.value;

        return Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _SplashBgPainter())),

            // Gold top strip
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 6,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [kPrimary, kGold, kPrimary]),
                ),
              ),
            ),
            // Gold bottom strip
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                height: 6,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [kPrimary, kGold, kPrimary]),
                ),
              ),
            ),

            Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ── Department header ──
                        SlideTransition(
                          position: textSlide,
                          child: FadeTransition(
                            opacity: fadeIn,
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    _goldLine(),
                                    const SizedBox(width: 12),
                                    Container(
                                      width: 54, height: 54,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: kDark,
                                        border: Border.all(
                                            color: kGold, width: 2),
                                      ),
                                      child: ClipOval(
                                        child: Image.asset(
                                          'assets/images/logo.png',
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    _goldLine(),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'उत्तर प्रदेश पुलिस',
                                  style: TextStyle(
                                    color: kGold,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'UTTAR PRADESH POLICE',
                                  style: TextStyle(
                                    color: kBorder,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 3.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── Officer photo ──
                        SlideTransition(
                          position: photoSlide,
                          child: ScaleTransition(
                            scale: photoScale,
                            child: FadeTransition(
                              opacity: fadeIn,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Outer glow ring
                                  Container(
                                    width: 192, height: 192,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: kGold.withOpacity(0.25),
                                          width: 12),
                                    ),
                                  ),
                                  // Mid ring
                                  Container(
                                    width: 172, height: 172,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: kGold.withOpacity(0.5),
                                          width: 2),
                                    ),
                                  ),
                                  // Photo
                                  Container(
                                    width: 160, height: 160,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: kGold, width: 3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: kGold.withOpacity(0.3),
                                          blurRadius: 20,
                                          spreadRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: Image.asset(
                                        'assets/images/officer_suraj.jpg',
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Container(
                                          color: kSurface,
                                          child: const Icon(Icons.person,
                                              size: 80, color: kSubtle),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Shimmer sweep
                                  ClipOval(
                                    child: SizedBox(
                                      width: 160, height: 160,
                                      child: AnimatedBuilder(
                                        animation: shimmer,
                                        builder: (_, __) =>
                                            Transform.translate(
                                          offset: Offset(
                                              shimmer.value * 160, 0),
                                          child: Container(
                                            width: 60,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.white
                                                      .withOpacity(0),
                                                  Colors.white
                                                      .withOpacity(0.18),
                                                  Colors.white
                                                      .withOpacity(0),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Officer details ──
                        SlideTransition(
                          position: textSlide,
                          child: FadeTransition(
                            opacity: fadeIn,
                            child: Column(
                              children: [
                                const Text(
                                  'SURAJ KUMAR RAI',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 5),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [
                                      kPrimary,
                                      kAccent,
                                      kPrimary
                                    ]),
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: kGold.withOpacity(0.3),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: const Text(
                                    'I.P.S.',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 3.0,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    _goldLine(width: 30),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 5, height: 5,
                                      decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: kGold),
                                    ),
                                    const SizedBox(width: 8),
                                    _goldLine(width: 30),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _detailRow(
                                  icon:  Icons.workspace_premium_outlined,
                                  label: 'Designation',
                                  value: 'Superintendent of Police',
                                ),
                                const SizedBox(height: 8),
                                _detailRow(
                                  icon:  Icons.location_on_outlined,
                                  label: 'District',
                                  value: 'Baghpat, Uttar Pradesh',
                                ),
                                const SizedBox(height: 8),
                                _detailRow(
                                  icon:  Icons.account_balance_outlined,
                                  label: 'Department',
                                  value: 'UP Police — Election Cell',
                                ),
                                const SizedBox(height: 20),
                                _SplashProgressBar(animation: ctrl),
                                const SizedBox(height: 10),
                                Text(
                                  statusLabel,
                                  style: const TextStyle(
                                    color: kSubtle,
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _goldLine({double width = 50}) => Container(
        width: width, height: 1,
        color: kGold.withOpacity(0.6),
      );

  Widget _detailRow({
    required IconData icon,
    required String   label,
    required String   value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kGold, size: 15),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(
                color: kSubtle,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  SHARED ANIMATION SETUP MIXIN
// ─────────────────────────────────────────────
mixin _SplashAnimMixin<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController splashCtrl;
  late final Animation<double>   splashFadeIn;
  late final Animation<double>   splashFadeOut;
  late final Animation<double>   splashPhotoScale;
  late final Animation<Offset>   splashPhotoSlide;
  late final Animation<Offset>   splashTextSlide;
  late final Animation<double>   splashShimmer;

  void initSplashAnims() {
    splashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    splashFadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: splashCtrl,
          curve: const Interval(0.0, 0.2, curve: Curves.easeOut)),
    );
    splashFadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
          parent: splashCtrl,
          curve: const Interval(0.78, 1.0, curve: Curves.easeIn)),
    );
    splashPhotoScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
          parent: splashCtrl,
          curve: const Interval(0.0, 0.25, curve: Curves.easeOutBack)),
    );
    splashPhotoSlide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end:   Offset.zero,
    ).animate(CurvedAnimation(
        parent: splashCtrl,
        curve: const Interval(0.0, 0.22, curve: Curves.easeOut)));
    splashTextSlide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end:   Offset.zero,
    ).animate(CurvedAnimation(
        parent: splashCtrl,
        curve: const Interval(0.1, 0.3, curve: Curves.easeOut)));
    splashShimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(
          parent: splashCtrl,
          curve: const Interval(0.0, 0.5, curve: Curves.easeInOut)),
    );
  }

  void disposeSplashAnims() => splashCtrl.dispose();

  _SplashBody buildSplashBody(String statusLabel) => _SplashBody(
        ctrl:        splashCtrl,
        fadeIn:      splashFadeIn,
        fadeOut:     splashFadeOut,
        photoScale:  splashPhotoScale,
        photoSlide:  splashPhotoSlide,
        textSlide:   splashTextSlide,
        shimmer:     splashShimmer,
        statusLabel: statusLabel,
      );
}

// ═════════════════════════════════════════════
//  1.  OFFICER SPLASH PAGE
//      Shown on cold-start → navigates to '/' (AuthCheck)
// ═════════════════════════════════════════════
class OfficerSplashPage extends StatefulWidget {
  const OfficerSplashPage({super.key});

  @override
  State<OfficerSplashPage> createState() => _OfficerSplashPageState();
}

class _OfficerSplashPageState extends State<OfficerSplashPage>
    with SingleTickerProviderStateMixin, _SplashAnimMixin {
  @override
  void initState() {
    super.initState();
    initSplashAnims();
    splashCtrl.forward().then((_) {
      if (mounted) {
        // AuthCheck will decide: show dashboard (already logged in)
        // or show LoginPage (not logged in)
        Navigator.of(context).pushReplacementNamed('/');
      }
    });
  }

  @override
  void dispose() {
    disposeSplashAnims();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      body: buildSplashBody(
          'Loading Election Duty Management System…'),
    );
  }
}

// ═════════════════════════════════════════════
//  2.  POST-LOGIN SPLASH PAGE
//      Shown after successful login credentials check,
//      BEFORE navigating to the role dashboard.
//      Receives the destination route from LoginPage.
// ═════════════════════════════════════════════
class PostLoginSplashPage extends StatefulWidget {
  final String destination; // e.g. '/admin', '/master', '/staff'

  const PostLoginSplashPage({super.key, required this.destination});

  @override
  State<PostLoginSplashPage> createState() => _PostLoginSplashPageState();
}

class _PostLoginSplashPageState extends State<PostLoginSplashPage>
    with SingleTickerProviderStateMixin, _SplashAnimMixin {
  @override
  void initState() {
    super.initState();
    initSplashAnims();
    splashCtrl.forward().then((_) {
      if (mounted) {
        // Replace this splash with the role-specific dashboard
        Navigator.of(context).pushReplacementNamed(widget.destination);
      }
    });
  }

  @override
  void dispose() {
    disposeSplashAnims();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      body: buildSplashBody('Welcome! Redirecting to your dashboard…'),
    );
  }
}

// ─────────────────────────────────────────────
//  EMBLEM  (used on LoginPage)
// ─────────────────────────────────────────────
class _ElectionEmblem extends StatelessWidget {
  const _ElectionEmblem();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kDark,
            border: Border.all(color: kBorder, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withOpacity(0.35),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset('assets/images/logo.png',
                fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'उत्तर प्रदेश निर्वाचन कक्ष',
          style: TextStyle(
            color: kDark, fontSize: 15,
            fontWeight: FontWeight.w800, letterSpacing: 0.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        const Text(
          'Uttar Pradesh Election Cell',
          style: TextStyle(
            color: kSubtle, fontSize: 12,
            fontWeight: FontWeight.w500, letterSpacing: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 1, color: kBorder),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: kBorder),
              ),
            ),
            Container(width: 40, height: 1, color: kBorder),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
//  LOGIN PAGE
// ═════════════════════════════════════════════
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _idController   = TextEditingController();
  final _passController = TextEditingController();
  final _formKey        = GlobalKey<FormState>();

  bool    _obscure   = true;
  bool    _loading   = false;
  String? _errorText;

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end:   Offset.zero,
    ).animate(CurvedAnimation(
        parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _idController.dispose();
    _passController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  LOGIN
  //  On success → show PostLoginSplashPage(destination)
  //  On failure → show inline error message
  // ─────────────────────────────────────────────
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading   = true;
      _errorText = null;
    });

    try {
      final response = await AuthService.login(
        _idController.text.trim(),
        _passController.text,
      );

      final String rawRole =
          (response['data']?['user']?['role'] as String? ?? '')
              .toUpperCase()
              .trim();

      if (!mounted) return;

      // Determine destination route from role
      String? destination;
      switch (rawRole) {
        case 'MASTER':
          destination = '/master';
          break;
        case 'SUPER_ADMIN':
          destination = '/super';
          break;
        case 'ADMIN':
          destination = '/admin';
          break;
        case 'STAFF':
          destination = '/staff';
          break;
        default:
          setState(() {
            _errorText =
                'Access denied. Unrecognised account role: "$rawRole".\n'
                'Please contact your system administrator.';
          });
      }

      // ✅ Valid credentials → show officer splash THEN go to dashboard
      if (destination != null && mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, __, ___) =>
                PostLoginSplashPage(destination: destination!),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        if (msg.contains('401') ||
            msg.contains('Invalid') ||
            msg.contains('credentials') ||
            msg.contains('Unauthorized')) {
          _errorText = 'Invalid User ID or Password. Please try again.';
        } else if (msg.contains('SocketException') ||
            msg.contains('Connection refused') ||
            msg.contains('Failed host lookup')) {
          _errorText =
              'Cannot reach server. Check your network or server IP in constants.dart.';
        } else if (msg.contains('TimeoutException') ||
            msg.contains('timed out')) {
          _errorText =
              'Server is not responding. Please try again shortly.';
        } else if (msg.contains('500') || msg.contains('Internal')) {
          _errorText = 'Server error. Please contact the developer.';
        } else {
          _errorText =
              'Login failed. Please try again or contact support.';
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),

          Positioned(
            top: -80, right: -60,
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kAccent.withOpacity(0.07)),
            ),
          ),
          Positioned(
            bottom: -100, left: -80,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kPrimary.withOpacity(0.05)),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 20),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 440),
                      child: Column(
                        children: [
                          // Top banner
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 9, horizontal: 16),
                            decoration: const BoxDecoration(
                              color: kDark,
                              borderRadius: BorderRadius.only(
                                topLeft:  Radius.circular(16),
                                topRight: Radius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'ELECTION DUTY MANAGEMENT SYSTEM',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: kBorder,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ),

                          // Login card
                          Container(
                            decoration: BoxDecoration(
                              color: kBg,
                              border: Border.all(
                                  color: kBorder, width: 1.2),
                              borderRadius: const BorderRadius.only(
                                bottomLeft:  Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: kPrimary.withOpacity(0.14),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.fromLTRB(
                                28, 28, 28, 32),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  const _ElectionEmblem(),
                                  const SizedBox(height: 28),

                                  // User ID
                                  TextFormField(
                                    controller: _idController,
                                    keyboardType: TextInputType.text,
                                    textInputAction:
                                        TextInputAction.next,
                                    autocorrect: false,
                                    decoration: const InputDecoration(
                                      labelText: 'User ID / PNO',
                                      prefixIcon: Icon(
                                          Icons.badge_outlined),
                                    ),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                            ? 'Please enter your User ID or PNO'
                                            : null,
                                  ),

                                  const SizedBox(height: 14),

                                  // Password
                                  TextFormField(
                                    controller: _passController,
                                    obscureText: _obscure,
                                    textInputAction:
                                        TextInputAction.done,
                                    onFieldSubmitted: (_) =>
                                        _loading ? null : _login(),
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: const Icon(
                                          Icons.lock_outline),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscure
                                              ? Icons
                                                  .visibility_off_outlined
                                              : Icons
                                                  .visibility_outlined,
                                          color: kSubtle,
                                          size: 20,
                                        ),
                                        onPressed: () => setState(
                                            () => _obscure = !_obscure),
                                      ),
                                    ),
                                    validator: (v) =>
                                        (v == null || v.isEmpty)
                                            ? 'Please enter your password'
                                            : null,
                                  ),

                                  // Error banner
                                  AnimatedSize(
                                    duration: const Duration(
                                        milliseconds: 280),
                                    curve: Curves.easeOut,
                                    child: _errorText != null
                                        ? Padding(
                                            padding:
                                                const EdgeInsets.only(
                                                    top: 12),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.all(
                                                      11),
                                              decoration: BoxDecoration(
                                                color: kError
                                                    .withOpacity(0.07),
                                                borderRadius:
                                                    BorderRadius
                                                        .circular(9),
                                                border: Border.all(
                                                    color: kError
                                                        .withOpacity(
                                                            0.3)),
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .start,
                                                children: [
                                                  const Padding(
                                                    padding: EdgeInsets
                                                        .only(top: 1),
                                                    child: Icon(
                                                        Icons
                                                            .error_outline,
                                                        color: kError,
                                                        size: 17),
                                                  ),
                                                  const SizedBox(
                                                      width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      _errorText!,
                                                      style: const TextStyle(
                                                          color: kError,
                                                          fontSize: 12,
                                                          height: 1.45),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),

                                  const SizedBox(height: 24),

                                  // LOGIN BUTTON
                                  SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed:
                                          _loading ? null : _login,
                                      child: _loading
                                          ? const SizedBox(
                                              width: 22, height: 22,
                                              child:
                                                  CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .center,
                                              children: [
                                                Icon(
                                                    Icons.login_rounded,
                                                    size: 20),
                                                SizedBox(width: 10),
                                                Text('LOGIN'),
                                              ],
                                            ),
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  const Divider(color: kBorder),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Secure System — Authorised Personnel Only\n'
                                    'UP Police Election Cell © 2026',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: kSubtle,
                                      fontSize: 11,
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}