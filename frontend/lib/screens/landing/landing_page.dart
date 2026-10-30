import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cacao/services/api_service.dart';
import 'package:cacao/models/models.dart';
import 'package:cacao/providers/state.dart';
import 'package:cacao/routes/app_routes.dart';
import 'package:cacao/routes/portal.dart';
import 'package:cacao/screens/auth/auth_dialog.dart';
import 'package:cacao/screens/landing/analysis_dialog.dart';
import 'package:cacao/screens/landing/developers_dialog.dart';

// ---------- palette (matches the stylesheet tokens) ----------
class _C {
  static const brown950 = Color(0xFF1D0E09);
  static const brown900 = Color(0xFF29130C);
  static const gold = Color(0xFFDCA650);
  static const goldSoft = Color(0xFFE6AD67);
  static const softText = Color(0xFFE6D8CF);
  static const dimText = Color(0xFFD9C9BE);
  static const barrier = Color(0x8C120805);
}

TextStyle _sans(
  double size, {
  Color color = Colors.white,
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
  double height = 1.5,
}) => GoogleFonts.dmSans(
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  height: height,
);

TextStyle _display(
  double size, {
  Color color = Colors.white,
  FontWeight weight = FontWeight.w700,
  bool italic = false,
  double height = 1.12,
}) => GoogleFonts.playfairDisplay(
  fontSize: size,
  color: color,
  fontWeight: weight,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  height: height,
);

// ---------- frosted glass surface ----------
Widget _glass({
  required Widget child,
  double radius = 18,
  double blur = 14,
  EdgeInsets padding = EdgeInsets.zero,
  Color color = const Color(0x12FFFFFF),
  Color border = const Color(0x26FFFFFF),
}) {
  final r = BorderRadius.circular(radius);
  return ClipRRect(
    borderRadius: r,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: r,
          border: Border.all(color: border),
        ),
        child: child,
      ),
    ),
  );
}

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

  Widget portalFor(AppUser user) => buildPortal(user);

  void _openDashboard(AppUser user) =>
      Navigator.of(context).push(AppRoutes.page(portalFor(user)));

  Future<void> _logout() async {
    ref.read(authProvider.notifier).signOut();
    await CacaoApi.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openAuth() => showDialog(
    context: context,
    barrierColor: _C.barrier,
    builder: (_) => const AuthDialog(),
  );

  void _openAnalysis() => showDialog(
    context: context,
    barrierColor: _C.barrier,
    builder: (_) => const AnalysisDialog(),
  );

  void _openDevs() => showDialog(
    context: context,
    barrierColor: _C.barrier,
    builder: (_) => const DevelopersDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final wide = w >= 950;
    final session = ref.watch(authProvider);
    final side = wide ? 40.0 : 18.0;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _C.brown950,
      endDrawer: wide ? null : _drawer(session),
      body: Stack(
        children: [
          // fixed background photo, like background-attachment: fixed
          Positioned.fill(
            child: Image.asset('assets/images/hero-bg.jpg', fit: BoxFit.cover),
          ),
          // dark layer so text stays readable
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xA61D0E09), Color(0xCC1D0E09)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _hero(w, wide, size.height),
                  _stages(wide),
                  _how(wide),
                  _cta(wide),
                  _footer(),
                ],
              ),
            ),
          ),
          // floating glass navbar
          Positioned(
            top: wide ? 14 : 10,
            left: side,
            right: side,
            child: _navbar(wide, session),
          ),
        ],
      ),
    );
  }

  // ---------------- Navbar ----------------
  Widget _navbar(bool wide, AppUser? session) {
    Widget link(String t, VoidCallback f) => TextButton(
      onPressed: f,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFF9EEE5),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(t, style: _sans(14)),
    );

    return _glass(
      radius: 20,
      blur: 18,
      padding: EdgeInsets.symmetric(horizontal: wide ? 22 : 16),
      color: const Color(0x8C1E0E09),
      border: const Color(0x1FFFFFFF),
      child: SizedBox(
        height: wide ? 72 : 62,
        child: Row(
          children: [
            _brand(),
            const Spacer(),
            if (wide) ...[
              link('Home', () => _scrollTo('home')),
              link('About', () => _scrollTo('about')),
              link('How It Works', () => _scrollTo('how')),
              link('Developers', _openDevs),
              const SizedBox(width: 10),
              if (session == null)
                _primaryBtn('Login', _openAuth, compact: true)
              else ...[
                _primaryBtn(
                  'Dashboard',
                  () => _openDashboard(session),
                  compact: true,
                ),
                const SizedBox(width: 8),
                _outlineBtn('Log out', _logout, compact: true),
              ],
            ] else
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _drawer(AppUser? session) => Drawer(
    backgroundColor: _C.brown900,
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
          const SizedBox(height: 16),
          if (session == null)
            _primaryBtn(
              'Login',
              () {
                Navigator.of(context).pop();
                _openAuth();
              },
              full: true,
            )
          else ...[
            _primaryBtn(
              'Dashboard',
              () {
                Navigator.of(context).pop();
                _openDashboard(session);
              },
              full: true,
            ),
            const SizedBox(height: 10),
            _outlineBtn(
              'Log out',
              () {
                Navigator.of(context).pop();
                _logout();
              },
              full: true,
            ),
          ],
        ],
      ),
    ),
  );

  Widget _drawerLink(String t, VoidCallback f) => ListTile(
    title: Text(t, style: _sans(15, weight: FontWeight.w600)),
    onTap: f,
  );

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
          style: _sans(18, weight: FontWeight.w600),
          children: const [
            TextSpan(text: 'CacaoGrade '),
            TextSpan(
              text: 'AI',
              style: TextStyle(
                color: Color(0xFFE7B55F),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  // ---------------- Buttons ----------------
  Widget _primaryBtn(
    String label,
    VoidCallback onTap, {
    bool compact = false,
    bool full = false,
  }) {
    final r = BorderRadius.circular(24);
    return Container(
      width: full ? double.infinity : null,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B5CC0), Color(0xFF6D469B)],
        ),
        borderRadius: r,
        boxShadow: const [
          BoxShadow(
            color: Color(0x4058327C),
            blurRadius: 25,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 20 : 24,
              vertical: compact ? 9 : 13,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: _sans(compact ? 13 : 15, weight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  Widget _outlineBtn(
    String label,
    VoidCallback onTap, {
    bool compact = false,
    bool full = false,
  }) {
    final r = BorderRadius.circular(24);
    return Container(
      width: full ? double.infinity : null,
      decoration: BoxDecoration(
        borderRadius: r,
        border: Border.all(color: const Color(0x73FFFFFF)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 18 : 22,
              vertical: compact ? 9 : 12,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: _sans(
                compact ? 13 : 14,
                weight: FontWeight.w600,
                color: const Color(0xFFF9EEE5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- Hero ----------------
  Widget _hero(double w, bool wide, double h) {
    final hPad = wide ? w * .08 : 20.0;
    final headSize = wide ? 62.0 : (w < 400 ? 34.0 : 42.0);

    return Container(
      key: _keys['home'],
      width: double.infinity,
      constraints: BoxConstraints(minHeight: h),
      padding: EdgeInsets.fromLTRB(hPad, wide ? 132 : 108, hPad, 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xD9140906), Color(0x66140906), Color(0x00140906)],
          stops: [0, .45, .85],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FERMENTATION STAGE ASSESSMENT',
                      style: _sans(
                        11,
                        color: _C.goldSoft,
                        weight: FontWeight.w700,
                        letterSpacing: 3.2,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    RichText(
                      text: TextSpan(
                        style: _display(headSize, height: 1.1),
                        children: [
                          const TextSpan(
                            text: 'Consistent grading\nfor every ',
                          ),
                          TextSpan(
                            text: 'batch.',
                            style: _display(
                              headSize,
                              color: _C.gold,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: Text(
                        'Submit a photograph of whole or cut-test beans to receive a fermentation stage classification, quality observations, and recommended next steps.',
                        style: _sans(
                          wide ? 17 : 15,
                          color: _C.softText,
                          height: 1.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 14,
                      runSpacing: 12,
                      children: [
                        _primaryBtn('Analyze a Sample', _openAnalysis),
                        _outlineBtn('View Process →', () => _scrollTo('how')),
                      ],
                    ),
                  ],
                ),
              ),
              if (wide) ...[
                const SizedBox(width: 24),
                _scanChip(),
              ],
            ],
          ),
          SizedBox(height: wide ? 70 : 40),
          _glass(
            radius: 26,
            blur: 16,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            color: const Color(0x801E0E09),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FERMENTATION STAGES',
                  style: _sans(
                    10,
                    weight: FontWeight.w700,
                    letterSpacing: 3,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _responsiveGrid(
                  minItemWidth: 230,
                  gap: 14,
                  children: [for (final s in _stageData) _heroStageCard(s)],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanChip() => Transform.rotate(
    angle: 0.09,
    child: _glass(
      radius: 13,
      blur: 10,
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      color: const Color(0xC724100A),
      border: const Color(0x4DDEA650),
      child: Text(
        'Consistent Quality\nBetter Harvests',
        style: _display(15, italic: true, height: 1.4),
      ),
    ),
  );

  Widget _heroStageCard(_Stage s) => _glass(
    radius: 16,
    blur: 8,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    color: const Color(0x0FFFFFFF),
    border: const Color(0x1FFFFFFF),
    child: Row(
      children: [
        ClipOval(
          child: Image.asset(s.image, width: 52, height: 52, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(14, weight: FontWeight.w600, height: 1.3),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: s.dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.desc,
                      style: _sans(11, color: _C.dimText, height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ---------------- Stages ----------------
  Widget _sectionHead(String eyebrow, String title, [String? sub]) {
    final narrow = MediaQuery.of(context).size.width < 650;
    return Column(
      children: [
        Text(
          eyebrow,
          style: _sans(
            11,
            color: _C.goldSoft,
            weight: FontWeight.w700,
            letterSpacing: 3.2,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: _display(narrow ? 30 : 42, height: 1.14),
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              sub,
              textAlign: TextAlign.center,
              style: _sans(narrow ? 13 : 14, color: _C.softText, height: 1.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stages(bool wide) => Container(
    key: _keys['about'],
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: wide ? 56 : 20, vertical: 90),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1250),
        child: Column(
          children: [
            _sectionHead(
              'STAGE CATEGORIES',
              'Four stages, one consistent reference.',
              'Every sample is classified into one of four fermentation stages based on visible indicators in the bean.',
            ),
            const SizedBox(height: 45),
            _responsiveGrid(
              minItemWidth: 250,
              gap: 18,
              children: [for (final s in _stageData) _stageCard(s)],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _stageCard(_Stage s) => _glass(
    radius: 18,
    padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
    child: Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(s.image, width: 112, height: 92, fit: BoxFit.cover),
        ),
        const SizedBox(height: 20),
        Text(s.title, style: _display(21, height: 1.2)),
        const SizedBox(height: 8),
        Text(
          s.desc,
          textAlign: TextAlign.center,
          style: _sans(13, color: _C.softText, height: 1.5),
        ),
        const SizedBox(height: 18),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: s.dot, shape: BoxShape.circle),
        ),
      ],
    ),
  );

  // ---------------- Process ----------------
  Widget _how(bool wide) {
    const steps = [
      _Step(
        '01',
        Icons.upload_file_outlined,
        'Upload',
        'Submit a well-lit photograph of whole or cut-test beans.',
      ),
      _Step(
        '02',
        Icons.analytics_outlined,
        'Analyze',
        'The convolutional neural network assesses visible indicators such as color, uniformity, and surface condition.',
      ),
      _Step(
        '03',
        Icons.check_circle_outline,
        'Review Results',
        'Receive a stage classification, supporting observations, and a recommended next step.',
      ),
    ];

    return Container(
      key: _keys['how'],
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: wide ? 56 : 20, vertical: 90),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              _sectionHead('PROCESS', 'From photograph to documented result.'),
              const SizedBox(height: 45),
              if (wide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _stepCard(steps[0])),
                      _connector(),
                      Expanded(child: _stepCard(steps[1])),
                      _connector(),
                      Expanded(child: _stepCard(steps[2])),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    for (final s in steps)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _stepCard(s),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connector() => SizedBox(
    width: 70,
    child: Row(
      children: [
        Expanded(
          child: Container(height: 1, color: const Color(0x99E6AD67)),
        ),
        Text('›', style: _sans(24, color: _C.goldSoft, height: 1.6)),
      ],
    ),
  );

  Widget _stepCard(_Step s) => _glass(
    radius: 18,
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.num,
          style: _sans(11, color: const Color(0xFF9B8575), letterSpacing: 2),
        ),
        const SizedBox(height: 18),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF72509A),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(s.icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 18),
        Text(s.title, style: _display(24, height: 1.15)),
        const SizedBox(height: 8),
        Text(s.desc, style: _sans(13, color: _C.softText, height: 1.6)),
      ],
    ),
  );

  // ---------------- CTA + Footer ----------------
  Widget _cta(bool wide) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: wide ? 56 : 20, vertical: 80),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1150),
        child: _glass(
          radius: 25,
          blur: 10,
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 45 : 26,
            vertical: wide ? 40 : 30,
          ),
          color: const Color(0xB824100A),
          border: const Color(0x47DEA650),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 20,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ASSESS A SAMPLE',
                      style: _sans(
                        11,
                        color: _C.goldSoft,
                        weight: FontWeight.w700,
                        letterSpacing: 3.2,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Log a fermentation assessment for this batch.',
                      style: _display(wide ? 34 : 26, height: 1.16),
                    ),
                  ],
                ),
              ),
              _primaryBtn('Start an Assessment →', _openAnalysis),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _footer() => Container(
    width: double.infinity,
    color: const Color(0xE0210F0A),
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1300),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          runSpacing: 14,
          children: [
            _brand(),
            Text(
              '© 2026 CacaoGrade AI — Fermentation Stage Classification and Quality Assessment',
              style: _sans(11, color: const Color(0xFFCBBDB4), height: 1.5),
            ),
            TextButton(
              onPressed: _openDevs,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Meet the Developers',
                style: _sans(
                  12,
                  color: const Color(0xFFE5AF5E),
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ---------------- Grid helper ----------------
  Widget _responsiveGrid({
    required double minItemWidth,
    required List<Widget> children,
    double gap = 14,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final avail = c.maxWidth.isFinite
            ? c.maxWidth
            : MediaQuery.of(context).size.width;
        var cols = ((avail + gap) / (minItemWidth + gap)).floor();
        if (cols < 1) cols = 1;
        if (cols > children.length) cols = children.length;
        final itemW = (avail - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final ch in children) SizedBox(width: itemW, child: ch),
          ],
        );
      },
    );
  }
}

class _Stage {
  final String title, desc, image;
  final Color dot;
  const _Stage(this.title, this.desc, this.image, this.dot);
}

class _Step {
  final String num, title, desc;
  final IconData icon;
  const _Step(this.num, this.icon, this.title, this.desc);
}

const _stageData = [
  _Stage(
    'Unfermented',
    'Pale, no aroma development',
    'assets/images/unfermented-cacao.png',
    Color(0xFFCBBDB4),
  ),
  _Stage(
    'Partially Fermented',
    'Light brown, aroma still developing',
    'assets/images/partially-fermented.png',
    Color(0xFFE6AD67),
  ),
  _Stage(
    'Well-Fermented',
    'Uniform brown, aroma fully developed',
    'assets/images/well-fermented.png',
    Color(0xFF67905C),
  ),
  _Stage(
    'Over-Fermented',
    'Dark and cracked, aroma diminished',
    'assets/images/over-fermented.png',
    Color(0xFFC5574B),
  ),
];