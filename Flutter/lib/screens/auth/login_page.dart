import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../core/constants.dart';

// ─────────────────────────────────────────────
//  COLOR PALETTE  (light beige → brownish-gold)
// ─────────────────────────────────────────────
const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kAccent  = Color(0xFFB8860B);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);

// ─────────────────────────────────────────────
//  THEME  (import in main.dart → theme: electionTheme)
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
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    labelStyle:
        const TextStyle(color: kSubtle, fontWeight: FontWeight.w500),
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
//  BACKGROUND PAINTER
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

    // Diagonal accent stripe
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

// ─────────────────────────────────────────────
//  EMBLEM
// ─────────────────────────────────────────────
class _ElectionEmblem extends StatelessWidget {
  const _ElectionEmblem();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
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
          child: const Icon(
            Icons.how_to_vote_rounded,
            color: kBorder,
            size: 38,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'उत्तर प्रदेश निर्वाचन कक्ष',
          style: TextStyle(
            color: kDark,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        const Text(
          'Uttar Pradesh Election Cell',
          style: TextStyle(
            color: kSubtle,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
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
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: kBorder,
                ),
              ),
            ),
            Container(width: 40, height: 1, color: kBorder),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  LOGIN PAGE
// ─────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  // ── Controllers ──
  final _idController   = TextEditingController();
  final _passController = TextEditingController();
  final _formKey        = GlobalKey<FormState>();

  // ── State ──
  bool    _obscure   = true;
  bool    _loading   = false;
  String? _errorText;

  // ── Animations ──
  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(
        parent: _animCtrl, curve: Curves.easeOut);
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
  //  LOGIN  —  real AuthService → Flask /api/login
  // ─────────────────────────────────────────────
  Future<void> _login() async {
    // Step 1: validate fields
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading   = true;
      _errorText = null;
    });

    try {
      // Step 2: POST to /api/login via AuthService
      //         AuthService saves JWT token to SharedPreferences
      //         and returns full response map
      final response = await AuthService.login(
        _idController.text.trim(),
        _passController.text,
      );

      // Step 3: Read role from user object
      //   Expected backend response:
      //   {
      //     "token": "eyJ...",
      //     "user":  { "id": 1, "name": "...", "role": "MASTER" }
      //   }
      //   Role values from AppConstants:
      //   roleMaster = "MASTER"  | roleSuperAdmin = "SUPER_ADMIN"
      //   roleAdmin  = "ADMIN"   | roleUser       = "STAFF"
      final String rawRole =
          (response['data']?['user']?['role'] as String? ?? '').toUpperCase().trim();
            
      if (!mounted) return;

      // Step 4: Navigate by role — no manual hardcoding needed
      switch (rawRole) {
        case 'MASTER':
          Navigator.pushReplacementNamed(context, '/master');
          break;
        case 'SUPER_ADMIN':
          Navigator.pushReplacementNamed(context, '/super');
          break;
        case 'ADMIN':
          Navigator.pushReplacementNamed(context, '/admin');
          break;
        case 'STAFF':
          // Staff goes to their own duty view page
          Navigator.pushReplacementNamed(context, '/staff');
          break;
        default:
          setState(() {
            _errorText =
                'Access denied. Unrecognised account role: "$rawRole".\n'
                'Please contact your system administrator.';
          });
      }
    } catch (e) {
      if (!mounted) return;

      // Step 5: Friendly error mapping
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
          _errorText =
              'Server error. Please contact the developer.';
        } else {
          // Show raw error only in debug mode — in production show generic
          _errorText =
              'Login failed. Please try again or contact support.';
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [

          // ── Background grid ──
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),

          // ── Decorative orbs ──
          Positioned(
            top: -80, right: -60,
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kAccent.withOpacity(0.07),
              ),
            ),
          ),
          Positioned(
            bottom: -100, left: -80,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kPrimary.withOpacity(0.05),
              ),
            ),
          ),

          // ── Main content ──
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
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        children: [

                          // ── Top banner strip ──
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

                          // ── Login card ──
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

                                  // Emblem
                                  const _ElectionEmblem(),
                                  const SizedBox(height: 28),

                                  // ── User ID / PNO ──
                                  TextFormField(
                                    controller: _idController,
                                    keyboardType: TextInputType.text,
                                    textInputAction: TextInputAction.next,
                                    autocorrect: false,
                                    decoration: const InputDecoration(
                                      labelText: 'User ID / PNO',
                                      prefixIcon:
                                          Icon(Icons.badge_outlined),
                                    ),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                            ? 'Please enter your User ID or PNO'
                                            : null,
                                  ),

                                  const SizedBox(height: 14),

                                  // ── Password ──
                                  TextFormField(
                                    controller: _passController,
                                    obscureText: _obscure,
                                    textInputAction: TextInputAction.done,
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
                                              : Icons.visibility_outlined,
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

                                  // ── Error banner (animated) ──
                                  AnimatedSize(
                                    duration:
                                        const Duration(milliseconds: 280),
                                    curve: Curves.easeOut,
                                    child: _errorText != null
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                                top: 12),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.all(11),
                                              decoration: BoxDecoration(
                                                color: kError
                                                    .withOpacity(0.07),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        9),
                                                border: Border.all(
                                                    color: kError
                                                        .withOpacity(0.3)),
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
                                                        Icons.error_outline,
                                                        color: kError,
                                                        size: 17),
                                                  ),
                                                  const SizedBox(width: 8),
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

                                  // ── LOGIN BUTTON ──
                                  SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed:
                                          _loading ? null : _login,
                                      child: _loading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child:
                                                  CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.login_rounded,
                                                    size: 20),
                                                SizedBox(width: 10),
                                                Text('LOGIN'),
                                              ],
                                            ),
                                    ),
                                  ),

                                  const SizedBox(height: 18),

                                  // ── Server URL indicator ──
                                  Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            // Green dot = server URL set
                                            color: Color(0xFF4CAF50),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          AppConstants.baseUrl,
                                          style: const TextStyle(
                                            color: kSubtle,
                                            fontSize: 10,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  // ── Footer ──
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