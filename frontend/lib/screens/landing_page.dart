import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cacao/services/api_service.dart';
import 'package:cacao/models/models.dart';
import 'package:cacao/services/pick_image.dart';
import 'package:cacao/providers/state.dart';
import 'package:cacao/theme.dart';
import 'package:cacao/widgets/widgets.dart';
import 'package:cacao/routes/app_routes.dart';
import 'package:cacao/screens/admin_dashboard.dart';
import 'package:cacao/screens/buyer_dashboard.dart';
import 'package:cacao/screens/extension_worker_dashboard.dart';
import 'package:cacao/screens/farmer_dashboard.dart';
import 'package:cacao/screens/staff_dashboard.dart';

class LandingPage extends ConsumerStatefulWidget {
  const LandingPage({super.key});

  @override
  ConsumerState<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends ConsumerState<LandingPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _keys = {'home': GlobalKey(), 'about': GlobalKey(), 'how': GlobalKey()};

  @override
  void initState() {
    super.initState();
    // Same behaviour as the web frontend's session guard: a stored session
    // goes straight to its own dashboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider);
      if (user != null && mounted) _openDashboard(user);
    });
  }

  void _scrollTo(String k) {
    if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false)
      Navigator.of(context).pop();
    final c = _keys[k]?.currentContext;
    if (c != null) {
      Scrollable.ensureVisible(
        c,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Picks the portal that matches the signed-in role.
  Widget portalFor(AppUser user) => buildPortal(user);

  void _openDashboard(AppUser user) {
    Navigator.of(context).push(AppRoutes.page(portalFor(user)));
  }

  Future<void> _logout() async {
    ref.read(authProvider.notifier).signOut();
    await CacaoApi.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openAuth() =>
      showDialog(context: context, builder: (_) => const _AuthDialog());
  void _openAnalysis() =>
      showDialog(context: context, builder: (_) => const _AnalysisDialog());
  void _openDevs() =>
      showDialog(context: context, builder: (_) => const _DevelopersDialog());

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final wide = w >= 860;
    final session = ref.watch(authProvider);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.cream,
      endDrawer: wide
          ? null
          : Drawer(
              backgroundColor: AppColors.brown900,
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _drawerLink('Home', () => _scrollTo('home')),
                    _drawerLink('About', () => _scrollTo('about')),
                    _drawerLink('How It Works', () => _scrollTo('how')),
                    _drawerLink('Developers', () {
                      Navigator.of(context).pop();
                      _openDevs();
                    }),
                    const SizedBox(height: 12),
                    ..._sessionActions(
                      session,
                      beforeTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _hero(context, w, wide),
                  _stages(context, wide),
                  _how(context),
                  _cta(context),
                  _footer(),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _navbar(wide, w, session),
          ),
        ],
      ),
    );
  }

  Widget _drawerLink(String t, VoidCallback f) => ListTile(
    title: Text(
      t,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
    onTap: f,
  );

  /// Login button when signed out; Dashboard + Log out when signed in.
  List<Widget> _sessionActions(AppUser? session, {VoidCallback? beforeTap}) =>
      session == null
      ? [
          _LoginPill(
            onTap: () {
              beforeTap?.call();
              _openAuth();
            },
          ),
        ]
      : [
          _LoginPill(
            label: 'Dashboard',
            background: AppColors.forest,
            onTap: () {
              beforeTap?.call();
              _openDashboard(session);
            },
          ),
          const SizedBox(width: 8),
          _LoginPill(
            label: 'Log out',
            background: AppColors.brown700,
            onTap: () {
              beforeTap?.call();
              _logout();
            },
          ),
        ];

  // ---------------- Navbar ----------------
  Widget _navbar(bool wide, double w, AppUser? session) {
    Widget link(String t, VoidCallback f) => TextButton(
      onPressed: f,
      style: TextButton.styleFrom(foregroundColor: const Color(0xFFF9EEE5)),
      child: Text(t, style: const TextStyle(fontSize: 14)),
    );

    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: w * .05),
      decoration: BoxDecoration(
        color: const Color(0xFF26120B).withOpacity(.92),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(.09)),
        ),
      ),
      child: Row(
        children: [
          _brand(),
          const Spacer(),
          if (wide) ...[
            link('Home', () => _scrollTo('home')),
            link('About', () => _scrollTo('about')),
            link('How It Works', () => _scrollTo('how')),
            link('Developers', _openDevs),
            const SizedBox(width: 14),
            ..._sessionActions(session),
          ] else
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
        ],
      ),
    );
  }

  Widget _brand() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/images/cacaograde-logo-transparent.png',
        width: 34,
        height: 34,
        fit: BoxFit.contain,
      ),
      const SizedBox(width: 10),
      RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          children: const [
            TextSpan(text: 'CacaoGrade '),
            TextSpan(
              text: 'AI',
              style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  // ---------------- Hero ----------------
  Widget _hero(BuildContext context, double w, bool wide) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      key: _keys['home'],
      constraints: BoxConstraints(minHeight: h < 700 ? 700 : h),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(w * .08, 130, w * .08, 50),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/hero-bg.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      foregroundDecoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFF140906).withOpacity(.82),
            const Color(0xFF140906).withOpacity(.5),
            Colors.transparent,
          ],
          stops: const [0, .32, .6],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SMART CACAO FERMENTATION',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              letterSpacing: 2.2,
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          RichText(
            text: TextSpan(
              style: GoogleFonts.playfairDisplay(
                fontSize: wide ? 68 : 40,
                height: 1.08,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              children: [
                const TextSpan(text: 'Know your cacao.\nGrade it '),
                TextSpan(
                  text: 'smarter.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: AppColors.gold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: const Text(
              'Upload a cacao bean image and let AI determine the fermentation stage, quality notes, and recommendations.',
              style: TextStyle(
                fontSize: 17,
                height: 1.6,
                color: Color(0xFFF3E6DA),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              _PrimaryPill(label: '✦ Analyze Cacao', onTap: _openAnalysis),
              OutlinedButton(
                onPressed: () => _scrollTo('how'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(.6)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Learn More →',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 70),
          Text(
            'FERMENTATION STAGES',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              letterSpacing: 2.2,
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ResponsiveGrid(
            minWidth: 230,
            children: [for (final s in _stageData) _heroStageCard(s)],
          ),
        ],
      ),
    );
  }

  Widget _heroStageCard(_Stage s) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF1D0E09).withOpacity(.55),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(.12)),
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(s.image, width: 56, height: 56, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              Text(
                s.desc,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ---------------- Stages ----------------
  Widget _sectionHead(
    String eyebrow,
    Color eyebrowColor,
    String title, [
    String? sub,
  ]) => Column(
    children: [
      Text(
        eyebrow,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          letterSpacing: 2.2,
          color: eyebrowColor,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        title,
        textAlign: TextAlign.center,
        style: GoogleFonts.playfairDisplay(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: AppColors.brown800,
        ),
      ),
      if (sub != null) ...[
        const SizedBox(height: 8),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.mutedBrown),
        ),
      ],
    ],
  );

  Widget _stages(BuildContext context, bool wide) {
    return Container(
      key: _keys['about'],
      width: double.infinity,
      color: AppColors.cream,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1150),
          child: Column(
            children: [
              _sectionHead(
                'FERMENTATION STAGES',
                AppColors.brown700,
                'Understand the bean at a glance.',
                'Four categories used by CacaoGrade AI for fermentation-stage assessment.',
              ),
              const SizedBox(height: 40),
              ResponsiveGrid(
                minWidth: 240,
                gap: 20,
                children: [
                  for (final s in _stageData)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: s.featured
                              ? AppColors.gold
                              : const Color(0xFFE6D8CF),
                          width: s.featured ? 2 : 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 150,
                            child: Image.asset(s.image, fit: BoxFit.contain),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            s.title,
                            style: GoogleFonts.dmSans(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textBrown,
                            ),
                          ),
                          Text(
                            s.desc,
                            style: const TextStyle(
                              color: AppColors.mutedBrown,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: s.dot,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- How it works ----------------
  Widget _how(BuildContext context) {
    const steps = [
      (
        '01',
        Icons.upload,
        'Upload',
        'Choose a clear photo of whole or cut-test cacao beans.',
      ),
      (
        '02',
        Icons.analytics_outlined,
        'Analyze',
        'The computer vision model evaluates visible fermentation indicators.',
      ),
      (
        '03',
        Icons.check_circle_outline,
        'Get Results',
        'Receive a stage classification, quality notes, and recommendation.',
      ),
    ];
    return Container(
      key: _keys['how'],
      width: double.infinity,
      color: AppColors.cream2,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: Column(
            children: [
              _sectionHead(
                'HOW IT WORKS',
                AppColors.violet,
                'From cacao photo to useful insight.',
              ),
              const SizedBox(height: 40),
              ResponsiveGrid(
                minWidth: 260,
                gap: 22,
                children: [
                  for (final s in steps)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Text(
                            s.$1,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 14,
                              color: AppColors.mutedBrown,
                            ),
                          ),
                          const SizedBox(height: 10),
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AppColors.violet.withOpacity(.12),
                            child: Icon(s.$2, color: AppColors.violet),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            s.$3,
                            style: GoogleFonts.dmSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textBrown,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            s.$4,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.mutedBrown,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- CTA + Footer ----------------
  Widget _cta(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.cream,
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 70),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1050),
        child: Container(
          padding: const EdgeInsets.all(34),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.brown900, AppColors.brown700],
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 20,
            spacing: 20,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'READY TO CHECK A BATCH?',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        letterSpacing: 2.2,
                        color: AppColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Turn a cacao photo into a smarter decision.',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 30,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _PrimaryPill(label: 'Start Analysis →', onTap: _openAnalysis),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _footer() => Container(
    width: double.infinity,
    color: AppColors.brown950,
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 14,
      spacing: 20,
      children: [
        _brand(),
        const Text(
          '© 2026 CacaoGrade AI — Cacao Fermentation & Quality Assessment',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
        TextButton(
          onPressed: _openDevs,
          child: const Text(
            'Meet the Developers',
            style: TextStyle(color: AppColors.gold),
          ),
        ),
      ],
    ),
  );
}

class _Stage {
  final String title, desc, image;
  final Color dot;
  final bool featured;
  const _Stage(
    this.title,
    this.desc,
    this.image,
    this.dot, {
    this.featured = false,
  });
}

const _stageData = [
  _Stage(
    'Unfermented',
    'Pale color, low aroma',
    'assets/images/unfermented-cacao.png',
    Color(0xFFCBBDB4),
  ),
  _Stage(
    'Partially Fermented',
    'Light brown, mild aroma',
    'assets/images/partially-fermented.png',
    Color(0xFFE6AD67),
  ),
  _Stage(
    'Well-Fermented',
    'Rich brown, good aroma',
    'assets/images/well-fermented.png',
    Color(0xFF67905C),
    featured: true,
  ),
  _Stage(
    'Over-Fermented',
    'Dark, cracked, weak aroma',
    'assets/images/over-fermented.png',
    Color(0xFFC5574B),
  ),
];

// ---------------- Small shared pills ----------------
class _PrimaryPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF8B5CC0), Color(0xFF6D469B)],
      ),
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF583283).withOpacity(.3),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
  );
}

class _LoginPill extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final Color background;
  const _LoginPill({
    required this.onTap,
    this.label = 'Login',
    this.background = const Color(0xFF7852A9),
  });

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: background,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: const StadiumBorder(),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _ModalFrame extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  const _ModalFrame({required this.maxWidth, required this.child});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Stack(
        children: [
          SingleChildScrollView(child: child),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------- Auth dialog ----------------

/// Picks the dashboard that matches the signed-in role - Activity 2, Part A:
/// *"bottom navigation and role-based routing"*. Each of the five documented
/// actors gets its own portal, and the backend enforces the same split.
Widget buildPortal(AppUser user) => switch (user.role) {
  'Admin' => AdminDashboard(user: user),
  'Staff' => StaffDashboard(user: user),
  'Buyer' => BuyerDashboard(user: user),
  'Extension Worker' => ExtensionWorkerDashboard(user: user),
  _ => FarmerDashboard(user: user),
};

class _AuthDialog extends ConsumerStatefulWidget {
  const _AuthDialog();

  @override
  ConsumerState<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends ConsumerState<_AuthDialog> {
  bool _login = true;
  bool _hidePw = true;
  bool _busy = false;
  String _error = '';
  String _info = '';
  bool _consent = false;

  final _lEmail = TextEditingController();
  final _lPass = TextEditingController();
  final _rName = TextEditingController();
  final _rEmail = TextEditingController();
  final _rPass = TextEditingController();
  final _rConfirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_lEmail, _lPass, _rName, _rEmail, _rPass, _rConfirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _openPortal(NavigatorState nav, AppUser user) {
    nav.pop();
    nav.push(AppRoutes.page(buildPortal(user)));
  }

  /// Pulls the full account list so the admin portal shows real users.
  Future<void> _loadAdminUsers() async {
    try {
      await refreshUsers(ref);
    } catch (_) {
      // Keep whatever we already had - the admin list is not critical here.
    }
  }

  Future<void> _doLogin() async {
    final email = _lEmail.text.trim();
    if (email.isEmpty || _lPass.text.isEmpty) {
      return setState(() => _error = 'Enter your email and password.');
    }

    setState(() {
      _busy = true;
      _error = '';
      _info = '';
    });

    try {
      final user = await CacaoApi.login(email: email, password: _lPass.text);
      if (!mounted) return;
      ref.read(authProvider.notifier).signIn(user);
      if (user.role == 'Admin') _loadAdminUsers();
      _openPortal(Navigator.of(context), user);
    } on ApiException catch (err) {
      if (mounted) setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRegister() async {
    final name = _rName.text.trim();
    final email = _rEmail.text.trim();
    if (name.isEmpty || !email.contains('@')) {
      return setState(() => _error = 'Enter your name and a valid email.');
    }
    if (_rPass.text.length < 8) {
      return setState(() => _error = 'Password must be at least 8 characters.');
    }
    if (_rPass.text != _rConfirm.text) {
      return setState(() => _error = 'Passwords do not match.');
    }
    if (!_consent) {
      return setState(
        () => _error = 'Please accept the terms and privacy notice.',
      );
    }

    setState(() {
      _busy = true;
      _error = '';
      _info = '';
    });

    try {
      await CacaoApi.register(
        fullName: name,
        email: email,
        password: _rPass.text,
      );
      if (!mounted) return;
      setState(() {
        _login = true;
        _lEmail.text = email;
        _lPass.clear();
        _rName.clear();
        _rEmail.clear();
        _rPass.clear();
        _rConfirm.clear();
        _consent = false;
        _info = 'Account created! Please log in.';
      });
    } on ApiException catch (err) {
      if (mounted) setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final eye = IconButton(
      icon: Icon(
        _hidePw ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
      ),
      onPressed: () => setState(() => _hidePw = !_hidePw),
    );

    return _ModalFrame(
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Login')),
                ButtonSegment(value: false, label: Text('Register')),
              ],
              selected: {_login},
              onSelectionChanged: (s) => setState(() {
                _login = s.first;
                _error = '';
                _info = '';
              }),
            ),
            const SizedBox(height: 20),
            Text(
              _login ? 'Welcome back.' : 'Create account.',
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.brown800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _login
                  ? 'Sign in to analyze cacao and manage your batch records.'
                  : 'Create your CacaoGrade AI account to save analysis records.',
              style: const TextStyle(color: AppColors.mutedBrown, fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (_login) ...[
              TextField(
                controller: _lEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: _dec('Email address', Icons.mail_outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lPass,
                obscureText: _hidePw,
                decoration: _dec('Password', Icons.lock_outline, suffix: eye),
              ),
            ] else ...[
              TextField(
                controller: _rName,
                decoration: _dec('Full name', Icons.person_outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: _dec('Email address', Icons.mail_outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rPass,
                obscureText: _hidePw,
                decoration: _dec(
                  'Password (min. 8 characters)',
                  Icons.lock_outline,
                  suffix: eye,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rConfirm,
                obscureText: _hidePw,
                decoration: _dec('Confirm password', Icons.lock_outline),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cream2,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.mutedBrown,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your access role (Farmer, Staff or Admin) is assigned by the administrator.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.mutedBrown,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                title: const Text(
                  'I agree to the system terms and privacy notice.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
            if (_info.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _info,
                  style: const TextStyle(color: AppColors.green, fontSize: 12),
                ),
              ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error,
                  style: const TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : (_login ? _doLogin : _doRegister),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6D469B),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _login ? 'Log In' : 'Create Account',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Analysis dialog (demo) ----------------
class _AnalysisDialog extends StatefulWidget {
  const _AnalysisDialog();

  @override
  State<_AnalysisDialog> createState() => _AnalysisDialogState();
}

class _AnalysisDialogState extends State<_AnalysisDialog> {
  Uint8List? _bytes;
  bool _loading = false;
  bool _done = false;
  String _error = '';

  Future<void> _pick() async {
    try {
      // Same helper the signed-in upload screen uses, so this demo dialog
      // applies Part C's jpg/png and 10 MB checks too.
      final picked = await pickCacaoImage(ImageSource.gallery);
      if (picked == null) return; // cancelled

      setState(() {
        _bytes = picked.bytes;
        _done = false;
        _error = '';
      });
    } on ImagePickException catch (error) {
      setState(() {
        _bytes = null;
        _done = false;
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _bytes = null;
        _done = false;
        _error = 'Could not read that image. Please try another one.';
      });
    }
  }

  Future<void> _run() async {
    if (_bytes == null)
      return setState(() => _error = 'Please choose an image first.');
    setState(() {
      _loading = true;
      _done = false;
      _error = '';
    });
    // Simulation only, same as the web version. Replace with the FastAPI classify call.
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget tick(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('✓ $t', style: const TextStyle(fontSize: 13)),
    );

    return _ModalFrame(
      maxWidth: 640,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CACAO ANALYSIS',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                letterSpacing: 2,
                color: AppColors.violet,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Analyze a cacao image',
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.brown800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Upload a clear image to simulate the CacaoGrade AI assessment.',
              style: TextStyle(color: AppColors.mutedBrown, fontSize: 13),
            ),
            const SizedBox(height: 18),
            InkWell(
              onTap: _pick,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFC9A8F0),
                    width: 1.5,
                  ),
                ),
                child: _bytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _bytes!,
                          height: 180,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Column(
                        children: [
                          const Icon(
                            Icons.upload,
                            size: 34,
                            color: AppColors.violet,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tap to choose an image',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const Text(
                            'JPG, PNG or WEBP',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.mutedBrown,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error,
                  style: const TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _run,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6D469B),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Analyze Image',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: AppColors.violet),
                      SizedBox(height: 10),
                      Text(
                        'AI is analyzing fermentation indicators...',
                        style: TextStyle(color: AppColors.mutedBrown),
                      ),
                    ],
                  ),
                ),
              ),
            if (_done)
              Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '✓ DEMO RESULT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Well-Fermented',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brown800,
                      ),
                    ),
                    const Text('Confidence: 94.8%'),
                    const Divider(height: 22),
                    const Text(
                      'Quality Assessment',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    tick('Good fermentation indicators'),
                    tick('Desirable color development'),
                    tick('Suitable for further drying and storage'),
                    const SizedBox(height: 8),
                    const Text(
                      'Recommendation',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Text(
                      'Continue proper drying and storage practices to maintain quality.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Developers dialog ----------------
class _DevelopersDialog extends StatelessWidget {
  const _DevelopersDialog();

  @override
  Widget build(BuildContext context) {
    const devs = [
      ('RS', 'Rico D. Respecia'),
      ('AC', 'Ashley C. Cuarenta'),
      ('PC', 'Princess Ivony P. Castillo'),
    ];
    return _ModalFrame(
      maxWidth: 720,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Text(
              'THE TEAM BEHIND CACAOGRADE AI',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                letterSpacing: 2,
                color: AppColors.violet,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Meet the Developers',
              style: GoogleFonts.playfairDisplay(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: AppColors.brown800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Three developers working together to bring smarter cacao assessment to the web.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.mutedBrown),
            ),
            const SizedBox(height: 22),
            ResponsiveGrid(
              minWidth: 190,
              children: [
                for (final d in devs)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.brown800,
                          child: Text(
                            d.$1,
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          d.$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const Text(
                          'Developer',
                          style: TextStyle(
                            color: AppColors.mutedBrown,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Code + Cacao = Impact',
              style: GoogleFonts.playfairDisplay(
                fontStyle: FontStyle.italic,
                color: AppColors.brown700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
