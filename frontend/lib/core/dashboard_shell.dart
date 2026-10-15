import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';
import 'state.dart';
import 'theme.dart';

class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

/// Shared sidebar + topbar layout for the farmer, staff and admin portals.
class DashboardShell extends ConsumerStatefulWidget {
  final String brandSubtitle; // e.g. FERMENTATION INTELLIGENCE
  final String sectionLabel; // e.g. WORKSPACE
  final String breadcrumb;
  final String footerText;
  final List<NavItem> items;
  final List<String> titles;
  final Widget sidebarCard;
  final IconData userIcon;
  final String userName;
  final String userRole;
  final Widget Function(BuildContext context, int index, void Function(int) goTo) pageBuilder;

  const DashboardShell({
    super.key,
    required this.brandSubtitle,
    required this.sectionLabel,
    required this.breadcrumb,
    required this.footerText,
    required this.items,
    required this.titles,
    required this.sidebarCard,
    required this.userIcon,
    required this.userName,
    required this.userRole,
    required this.pageBuilder,
  });

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  int _index = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _goTo(int i) {
    setState(() => _index = i);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) Navigator.of(context).pop();
  }

  Future<void> _signOut() async {
    ref.read(authProvider.notifier).signOut();
    await CacaoApi.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget _sidebar() {
    return Container(
      width: 270,
      color: AppColors.forest,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Row(children: [
                Image.asset('assets/images/cacaograde-logo-transparent.png', width: 36, height: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                        children: [
                          TextSpan(text: 'Cacao'),
                          TextSpan(text: 'GradeAI', style: TextStyle(color: AppColors.dashGold)),
                        ],
                      ),
                    ),
                    Text(widget.brandSubtitle,
                        style: const TextStyle(fontSize: 8.5, letterSpacing: 1, color: Colors.white54)),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
              child: Text(widget.sectionLabel,
                  style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: Colors.white38, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (var i = 0; i < widget.items.length; i++)
                    _NavTile(
                      item: widget.items[i],
                      active: i == _index,
                      onTap: () => _goTo(i),
                    ),
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: widget.sidebarCard),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _NavTile(
                item: const NavItem(Icons.home_outlined, 'Back to Home'),
                active: false,
                onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _NavTile(
                item: const NavItem(Icons.logout, 'Log out'),
                active: false,
                onTap: _signOut,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
              child: Text(widget.footerText, style: const TextStyle(fontSize: 9, letterSpacing: 1, color: Colors.white30)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 960;
    final dark = Pal.of(context).dark;
    final p = Pal.of(context);

    final main = Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage('assets/images/cacao-landing-bg.png'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Color.fromRGBO(8, 15, 10, dark ? .74 : .38),
            BlendMode.srcOver,
          ),
        ),
      ),
      child: Column(
        children: [
          // Topbar
          Container(
            height: 76,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: p.card.withOpacity(.94),
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(children: [
              if (!wide)
                IconButton(
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  icon: Icon(Icons.menu, color: p.text),
                ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.breadcrumb, style: TextStyle(fontSize: 11, color: p.muted)),
                    Text(widget.titles[_index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
                  ],
                ),
              ),
              IconButton(
                tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
                onPressed: () => ref.read(themeProvider.notifier).toggle(),
                icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: p.text),
              ),
              const SizedBox(width: 6),
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.forest,
                child: Icon(widget.userIcon, size: 18, color: Colors.white),
              ),
              if (MediaQuery.of(context).size.width >= 600) ...[
                const SizedBox(width: 10),
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.userName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.text)),
                  Text(widget.userRole, style: TextStyle(fontSize: 11, color: p.muted)),
                ]),
              ],
            ]),
          ),
          // Page content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KeyedSubtree(key: ValueKey(_index), child: widget.pageBuilder(context, _index, _goTo)),
                      const SizedBox(height: 30),
                      const Text('CacaoGradeAI · Fermentation Classification & Quality Assessment',
                          style: TextStyle(fontSize: 11, color: Colors.white60)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: wide ? null : Drawer(width: 270, child: _sidebar()),
      // Activity 2, Part A - the client is described as having "bottom
      // navigation and role-based routing". The sidebar already routes by role
      // on wide layouts; below 960px the bottom bar is how a phone moves
      // between the same destinations.
      bottomNavigationBar: wide ? null : _bottomNav(p),
      body: wide ? Row(children: [_sidebar(), Expanded(child: main)]) : main,
    );
  }

  /// Bottom bar shown on phone-width layouts.
  ///
  /// It mirrors the sidebar exactly (same [NavItem]s, same index), so a role
  /// never gains or loses a destination by rotating the device. Past five
  /// destinations the labels stop fitting, so they collapse to the selected
  /// one instead of ellipsising into mush.
  Widget _bottomNav(Pal p) {
    final crowded = widget.items.length > 5;

    return Container(
      decoration: BoxDecoration(
        color: p.card.withOpacity(.98),
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _index.clamp(0, widget.items.length - 1),
          onDestinationSelected: _goTo,
          backgroundColor: Colors.transparent,
          height: crowded ? 62 : 68,
          labelBehavior: crowded
              ? NavigationDestinationLabelBehavior.onlyShowSelected
              : NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final item in widget.items)
              NavigationDestination(
                icon: Icon(item.icon, size: 22),
                selectedIcon: Icon(item.icon, size: 22),
                label: item.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final NavItem item;
  final bool active;
  final VoidCallback onTap;
  const _NavTile({required this.item, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? Colors.white.withOpacity(.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(item.icon, size: 20, color: active ? AppColors.dashGold : Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Text(item.label,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active ? Colors.white : Colors.white70)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Small translucent info card shown above "Back to Home" in each sidebar.
class SidebarInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const SidebarInfoCard({super.key, required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.08), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.dashGold, size: 20),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
        const SizedBox(height: 3),
        Text(body, style: const TextStyle(color: Colors.white60, fontSize: 11, height: 1.5)),
      ]),
    );
  }
}
