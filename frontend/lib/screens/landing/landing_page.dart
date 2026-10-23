import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cacao/services/api_service.dart';
import 'package:cacao/models/models.dart';
import 'package:cacao/providers/state.dart';
import 'package:cacao/theme.dart';
import 'package:cacao/widgets/widgets.dart';
import 'package:cacao/routes/app_routes.dart';
import 'package:cacao/routes/portal.dart';
import 'package:cacao/widgets/pills.dart';
import 'package:cacao/screens/auth/auth_dialog.dart';
import 'package:cacao/screens/landing/analysis_dialog.dart';
import 'package:cacao/screens/landing/developers_dialog.dart';

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
    if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
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
      showDialog(context: context, builder: (_) => const AuthDialog());
  void _openAnalysis() =>
      showDialog(context: context, builder: (_) => const AnalysisDialog());
  void _openDevs() =>
      showDialog(context: context, builder: (_) => const DevelopersDialog());

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
          LoginPill(
            onTap: () {
              beforeTap?.call();
              _openAuth();
            },
          ),
        ]
      : [
          LoginPill(
            label: 'Dashboard',
            background: AppColors.forest,
            onTap: () {
              beforeTap?.call();
              _openDashboard(session);
            },
          ),
          const SizedBox(width: 8),
          LoginPill(
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
        color: const Color(0xFF26120B).withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
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
            const Color(0xFF140906).withValues(alpha: 0.82),
            const Color(0xFF140906).withValues(alpha: 0.5),
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
              PrimaryPill(label: '✦ Analyze Cacao', onTap: _openAnalysis),
              OutlinedButton(
                onPressed: () => _scrollTo('how'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
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
      color: const Color(0xFF1D0E09).withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
                            backgroundColor: AppColors.violet.withValues(
                              alpha: 0.12,
                            ),
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
              PrimaryPill(label: 'Start Analysis →', onTap: _openAnalysis),
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
