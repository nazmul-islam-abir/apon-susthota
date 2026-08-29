/// Apon Susthota — shared app shell.
///
/// This widget is mounted *once* by `HomeShell` and wraps every bottom-nav
/// tab. It owns:
///   • the brand top bar (drawer hamburger on the **left**, "আপন সুস্থতা"
///     wordmark on the **right** — matches the reference design)
///   • the side drawer that slides in left-to-right when the hamburger is
///     tapped (or when the user swipes from the left edge)
///
/// The drawer deliberately *does not* list the tabs that already live in the
/// bottom nav (insights, meal plan, workout, analytics, AI chat). It only
/// carries the things that are not reachable from the bottom bar: Profile,
/// Medicine, Water tracker, and Logout.
///
/// The top bar fades out while the drawer is open so the dark scrim covers
/// the whole screen (per the reference design). Tapping anywhere outside
/// the drawer panel (the scrim) closes the drawer.
///
/// All visual styling reuses tokens from `AppColors` so every screen stays
/// consistent with the rest of the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/user_profile.dart';
import '../screens/auth_screen.dart';
import '../screens/doctor_report_screen.dart';
import '../screens/medicine_screen.dart';
import '../screens/patient/patient_inbox_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/water_screen.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// App version shown at the bottom of the side drawer. Kept in sync with
/// `pubspec.yaml`. Update both if the build number changes.
const String _kAppVersion = '0.1.0';

// ─── Public API ──────────────────────────────────────────────────────────

/// Wraps a tab body with the shared brand bar + side drawer.
class AppShellScaffold extends StatelessWidget {
  /// Body of the currently-active tab (already laid out, without its own
  /// Scaffold — the shell provides the [Scaffold]).
  final Widget body;

  /// Optional persistent footer (e.g. the floating bottom navigation bar).
  /// Sits *outside* the drawer's slide area so the drawer can still cover
  /// it when opened.
  final Widget? bottomBar;

  /// Whether the floating brand top bar (hamburger + app name) is rendered
  /// at the top of the stack. Defaults to `true` so legacy callers stay
  /// backwards-compatible. Tabs that bring their own internal app-bar
  /// (Meal / Workout / Analytics / AI) pass `false` so the shell's pill
  /// doesn't double up with their header.
  final bool showTopBar;

  /// Called when the drawer reports that the user tapped Logout.
  /// `HomeShell` wires this up so the auth flow runs through the same path
  /// that every other sign-out does.
  final VoidCallback onLogoutRequested;

  const AppShellScaffold({
    super.key,
    required this.body,
    required this.onLogoutRequested,
    this.bottomBar,
    this.showTopBar = true,
  });

  @override
  Widget build(BuildContext context) {
    return _ShellHost(
      body: body,
      bottomBar: bottomBar,
      showTopBar: showTopBar,
      onLogoutRequested: onLogoutRequested,
    );
  }
}

// ─── Shell host ──────────────────────────────────────────────────────────

class _ShellHost extends StatefulWidget {
  final Widget body;
  final Widget? bottomBar;
  final bool showTopBar;
  final VoidCallback onLogoutRequested;

  const _ShellHost({
    required this.body,
    required this.bottomBar,
    required this.showTopBar,
    required this.onLogoutRequested,
  });

  @override
  State<_ShellHost> createState() => _ShellHostState();
}

class _ShellHostState extends State<_ShellHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drawerCtrl;
  late final Animation<double> _drawerAnim;
  late final Animation<Offset> _drawerSlide;
  late final Animation<double> _scrimAnim;

  bool get _isOpen =>
      _drawerCtrl.status == AnimationStatus.completed ||
      _drawerCtrl.status == AnimationStatus.forward;

  @override
  void initState() {
    super.initState();
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    // Slight curve so the drawer feels physical: fast in, slow out.
    final eased = CurvedAnimation(
      parent: _drawerCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _drawerAnim = eased;
    _drawerSlide = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(eased);
    _scrimAnim = Tween<double>(begin: 0.0, end: 0.45).animate(eased);
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    super.dispose();
  }

  void _openDrawer() {
    HapticFeedback.selectionClick();
    _drawerCtrl.forward();
  }

  void _closeDrawer() {
    HapticFeedback.selectionClick();
    _drawerCtrl.reverse();
  }

  void _handleAction(_DrawerAction action) async {
    // Close first so the drawer slide-out doesn't fight the route push.
    _closeDrawer();
    // Wait for the close animation to finish (or skip if it's already idle).
    if (_drawerCtrl.status == AnimationStatus.forward ||
        _drawerCtrl.status == AnimationStatus.completed) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    if (!mounted) return;
    switch (action) {
      case _DrawerAction.profile:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
      case _DrawerAction.medicine:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MedicineScreen()),
        );
      case _DrawerAction.water:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WaterScreen()),
        );
      case _DrawerAction.doctorReport:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DoctorReportScreen()),
        );
      case _DrawerAction.myCaretakers:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PatientInboxScreen()),
        );
      case _DrawerAction.logout:
        widget.onLogoutRequested();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Layout strategy (top → bottom):
    //   1. [_ShellTopBar] (when `showTopBar`) — sits inside a Column so it
    //      pushes the body downward instead of overlaying it. The previous
    //      `Positioned(top: 0, …)` design hid the bar behind the body on
    //      several tabs (the caretaker রোগী + ইনবক্স tabs looked cropped
    //      because the greeting strip's `padTop` lined up with the body's
    //      own top inset, so the floating bar was drawn but its content
    //      ended up under the system status bar in tight safe-areas).
    //   2. [widget.body] fills the rest of the column, but is wrapped in a
    //      Stack so the drawer + scrim can still slide over it without
    //      needing a second Scaffold.
    //
    // The Stack's first child is the IndexedStack (the tab body), painted
    // first; the floating bottom bar paints over the bottom edge; the
    // scrim + drawer sit at the very top of the stack so their tap targets
    // always win.
    return Scaffold(
      backgroundColor: AppColors.void2,
      extendBody: false,
      bottomNavigationBar: null,
      body: Stack(
        children: [
          Column(
            children: [
              if (widget.showTopBar)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: _isOpen ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: _isOpen,
                    child: _ShellTopBar(onMenuTap: _openDrawer),
                  ),
                ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _drawerAnim,
                  builder: (context, child) {
                    final t = _drawerAnim.value;
                    return Transform.translate(
                      offset: Offset(48 * t, 0),
                      child: IgnorePointer(
                        ignoring: _isOpen,
                        child: child,
                      ),
                    );
                  },
                  child: widget.body,
                ),
              ),
            ],
          ),
          // Floating bottom navigation bar — sits *above* the scrim so the
          // drawer slides over it. Hidden behind the drawer, visible when
          // closed.
          if (widget.bottomBar != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: _isOpen,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: _isOpen ? 0.0 : 1.0,
                  child: widget.bottomBar,
                ),
              ),
            ),
          // Scrim blocks touches outside the drawer — tapping it closes.
          if (_isOpen || _drawerCtrl.isAnimating)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _scrimAnim,
                builder: (context, _) {
                  return GestureDetector(
                    onTap: _closeDrawer,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      color: Colors.black.withValues(alpha: _scrimAnim.value),
                    ),
                  );
                },
              ),
            ),
          // Drawer itself — slides in from the left, sits above everything
          // so its tap targets always win over the scrim/body beneath.
          AnimatedBuilder(
            animation: _drawerSlide,
            builder: (context, _) {
              return FractionalTranslation(
                translation: _drawerSlide.value,
                child: _AponSusthotaDrawer(
                  onAction: _handleAction,
                  onDismiss: _closeDrawer,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Top bar ────────────────────────────────────────────────────────────

/// Shared top bar rendered by the shell on every tab.
///
/// Layout (left → right):
///   • Drawer hamburger — small pill in the left corner.
///   • App name "আপন সুস্থতা" — flush-right, bold Bengali + English caption.
///
/// Rendered as a **solid, fixed app-header bar** (opaque white surface,
/// 1-px hairline at the bottom) so it stays visually anchored at the top
/// while the dashboard list scrolls underneath it. No backdrop blur, no
/// floating gaps — content scrolls *under* the bar, never through it.
/// Fades out when the drawer is open.
class _ShellTopBar extends StatelessWidget {
  final VoidCallback onMenuTap;
  const _ShellTopBar({required this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // The app is always rendered in its light/cream palette, so the wordmark
    // colors are pinned here instead of being theme-switched. (Earlier we
    // branched on `MediaQuery.platformBrightnessOf(context)`, which made
    // the text disappear whenever the device reported a dark platform
    // brightness even though the page itself is light.)
    const titleColor = AppColors.newsInk;
    const accent = AppColors.brandPinkDeep;
    const captionColor = AppColors.newsMuted;
    // Matches the rest of the chrome so the bar blends with cards below
    // while still being visually distinct from the scaffold (void2).
    const surface = AppColors.newsSurface;

    return Material(
      // Solid, opaque bar — fixes the "floating / interrupts scroll"
      // issue where content could be seen through the previous
      // transparent top bar.
      color: surface,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          // Tight 12-px side + 10-px top/bottom padding so the bar is one
          // compact header unit (≈64-px tall with SafeArea status bar)
          // instead of two widgets floating inside transparent gaps.
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          // `MainAxisAlignment.spaceBetween` keeps the logo+hamburger pinned
          // to the left and the wordmark pinned to the right edge of the
          // same horizontal row.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left cluster: hamburger pill + app logo (assets/logo.png).
              // The logo visually anchors the brand identity so users
              // never have to wonder which app they're in.
              Row(
                children: [
                  Material(
                    color: Colors.white,
                    elevation: 2,
                    shadowColor: Colors.black.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: onMenuTap,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.menu_rounded,
                          color: AppColors.cyanDeep,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // App logo — loaded from assets/logo.png. We let it
                  // fill its natural box (the PNG is already 512-ish
                  // square, transparent background) and use BoxFit.contain
                  // so we never crop the mark.
                  Image.asset(
                    'assets/logo.png',
                    height: 38,
                    fit: BoxFit.contain,
                    // While the asset is being decoded on first run, fall
                    // back to a small coloured placeholder so the bar
                    // never collapses to an empty gap.
                    errorBuilder: (_, __, ___) => Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.health_and_safety_rounded,
                        size: 22,
                        color: AppColors.cyanDeep,
                      ),
                    ),
                  ),
                ],
              ),
              // App name — right-aligned per the reference design.
              // The brand wordmark is a two-tone split (e.g. "আপন" +
              // "সুস্থতা" in Bangla). We hard-code the split here using
              // the indexOf ' ' on the localized title — that's a
              // runtime read so we can't use `const` on the Column
              // (Dart requires const args).
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: () {
                  final spaceIdx = l.appTitle.indexOf(' ');
                  final first = spaceIdx > 0
                      ? l.appTitle.substring(0, spaceIdx)
                      : l.appTitle;
                  final rest = spaceIdx > 0
                      ? l.appTitle.substring(spaceIdx)
                      : '';
                  return [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          first,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            // Bangla wordmarks need positive line-height
                            // to keep conjuncts from getting clipped by
                            // the next row.
                            height: 1.15,
                          ),
                        ),
                        Text(
                          rest,
                          style: TextStyle(
                            color: accent,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Apon Susthota',
                      style: TextStyle(
                        color: captionColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ];
                }(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Drawer ──────────────────────────────────────────────────────────────

enum _DrawerAction {
  profile,
  medicine,
  water,
  doctorReport,
  myCaretakers,
  logout,
}

class _AponSusthotaDrawer extends StatefulWidget {
  final ValueChanged<_DrawerAction> onAction;

  /// Tapped when the user wants to dismiss the drawer without picking a
  /// menu item — wired to the [Icons.close_rounded] chip in the top-right
  /// of the panel.
  final VoidCallback onDismiss;

  const _AponSusthotaDrawer({
    required this.onAction,
    required this.onDismiss,
  });

  @override
  State<_AponSusthotaDrawer> createState() => _AponSusthotaDrawerState();
}

class _AponSusthotaDrawerState extends State<_AponSusthotaDrawer> {
  /// Whether the current user is a patient. Pulled async on init so we
  /// can hide the "আমার কেয়ারটেকার" tile when the signed-in user is a
  /// caretaker (caretakers don't have a "who is watching me" inbox).
  String _role = 'patient';

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    try {
      final p = await SupabaseService.fetchProfile();
      if (!mounted) return;
      setState(() {
        _role = (p?.role ?? 'patient').isEmpty ? 'patient' : p!.role;
      });
    } catch (_) {
      // Fail open: treat as patient so the tile appears. Worst case:
      // a caretaker taps it and lands on an empty inbox.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1D21) : Colors.white;
    final titleColor = isDark ? Colors.white : AppColors.newsInk;
    final subtitleColor =
        isDark ? const Color(0xFFB0B3B8) : AppColors.newsMuted;

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.84,
      child: Material(
        color: bg,
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Brand strip — small horizontal row that pairs the app
              // logo (assets/logo.png) with the Bangla wordmark. Gives
              // the drawer an obvious "this is the X app" anchor at the
              // very top so the user can never confuse it with another
              // shell.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/logo.png',
                      height: 32,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.health_and_safety_rounded,
                          size: 18,
                          color: AppColors.cyanDeep,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l.appTitle,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              // Top row: profile header (left, takes available space) +
              // close button (right edge). The close chip is small,
              // circular, and sits on the panel — it explicitly answers
              // the "where is the option to close the drawer?" question.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DrawerProfileHeader(
                        titleColor: titleColor,
                        subtitleColor: subtitleColor,
                        onViewProfile: () =>
                            widget.onAction(_DrawerAction.profile),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: widget.onDismiss,
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.close_rounded,
                              size: 22,
                              color: subtitleColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Main menu list — only items not already in the bottom nav.
              _DrawerTile(
                icon: Icons.person_rounded,
                title: 'প্রোফাইল',
                subtitle: 'আমার তথ্য ও সেটিংস',
                accent: const Color(0xFF0F766E),
                titleColor: titleColor,
                subtitleColor: subtitleColor,
                onTap: () => widget.onAction(_DrawerAction.profile),
              ),
              _DrawerTile(
                icon: Icons.medical_services_rounded,
                title: 'মেডিসিন',
                subtitle: 'ওষুধের রিমাইন্ডার ও ট্র্যাকার',
                accent: const Color(0xFF059669),
                titleColor: titleColor,
                subtitleColor: subtitleColor,
                onTap: () => widget.onAction(_DrawerAction.medicine),
              ),
              _DrawerTile(
                icon: Icons.water_drop_rounded,
                title: 'পানি',
                subtitle: 'দৈনিক লক্ষ্য ও ট্র্যাকার',
                accent: const Color(0xFF0284C7),
                titleColor: titleColor,
                subtitleColor: subtitleColor,
                onTap: () => widget.onAction(_DrawerAction.water),
              ),
              _DrawerTile(
                icon: Icons.assignment_rounded,
                title: 'ডাক্তারের রিপোর্ট',
                subtitle: '৩০ দিনের চক্র ও PDF',
                accent: const Color(0xFF7C3AED),
                titleColor: titleColor,
                subtitleColor: subtitleColor,
                onTap: () => widget.onAction(_DrawerAction.doctorReport),
              ),
              // "My Caretakers" — patient-only. Caretakers don't have
              // an "inbox of people watching me", so we hide the tile
              // for them. The profile fetch in initState populates
              // [_role]; we default to 'patient' so a slow / failed
              // fetch still shows the tile rather than silently
              // dropping a feature on a brand-new user.
              if (_role == 'patient')
                _DrawerTile(
                  icon: Icons.connect_without_contact_rounded,
                  title: l.drawerMyCaretakers,
                  subtitle: l.drawerMyCaretakersSub,
                  accent: const Color(0xFF0E7490),
                  titleColor: titleColor,
                  subtitleColor: subtitleColor,
                  onTap: () =>
                      widget.onAction(_DrawerAction.myCaretakers),
                ),
              const Spacer(),
              const _DrawerDivider(),
              _DrawerTile(
                icon: Icons.logout_rounded,
                title: 'লগআউট',
                subtitle: 'অ্যাকাউন্ট থেকে বের হোন',
                accent: const Color(0xFFB91C1C),
                titleColor: titleColor,
                subtitleColor: subtitleColor,
                onTap: () => widget.onAction(_DrawerAction.logout),
              ),
              const SizedBox(height: 12),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l.drawerAppVersion(_kAppVersion),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerProfileHeader extends StatefulWidget {
  final Color titleColor;
  final Color subtitleColor;
  final VoidCallback onViewProfile;

  const _DrawerProfileHeader({
    required this.titleColor,
    required this.subtitleColor,
    required this.onViewProfile,
  });

  @override
  State<_DrawerProfileHeader> createState() => _DrawerProfileHeaderState();
}

class _DrawerProfileHeaderState extends State<_DrawerProfileHeader> {
  late Future<_DrawerProfileData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DrawerProfileData> _load() async {
    final UserProfile? profile = await SupabaseService.fetchProfile();
    String avatarUrl = '';
    final rawPath = profile?.avatarUrl;
    if (rawPath != null && rawPath.isNotEmpty) {
      try {
        final signed = await SupabaseService.getProfilePhotoUrl(rawPath);
        if (signed.isNotEmpty) {
          avatarUrl = '$signed&_v=${profile?.photoUploadCount ?? 0}';
        }
      } catch (_) {/* keep empty avatar */}
    }
    final name = (profile?.fullName?.trim() ?? '');
    return _DrawerProfileData(name: name, avatarUrl: avatarUrl);
  }

  String _initials(String name, AppLocalizations l) {
    final raw = name.trim();
    if (raw.isEmpty) return l.drawerInitial;
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0].isNotEmpty ? parts[0][0] : '') +
          (parts[1].isNotEmpty ? parts[1][0] : '');
    }
    return raw.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return FutureBuilder<_DrawerProfileData>(
      future: _future,
      builder: (context, snap) {
        final data =
            snap.data ?? const _DrawerProfileData(name: '', avatarUrl: '');
        final display = data.name.isEmpty ? l.drawerFriend : data.name;
        final initials = _initials(display, l);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onViewProfile,
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.cyan.withValues(alpha: 0.18),
                    AppColors.mint.withValues(alpha: 0.16),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _DrawerAvatar(
                    initials: initials,
                    imageUrl: data.avatarUrl,
                    size: 48,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: widget.titleColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.drawerViewProfile,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: widget.subtitleColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: widget.subtitleColor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DrawerProfileData {
  final String name;
  final String avatarUrl;
  const _DrawerProfileData({required this.name, required this.avatarUrl});
}

class _DrawerAvatar extends StatelessWidget {
  final String initials;
  final String imageUrl;
  final double size;
  const _DrawerAvatar({
    required this.initials,
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = imageUrl.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.cyan, AppColors.cyanDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyanDeep.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.void2,
        ),
        clipBehavior: Clip.antiAlias,
        child: hasPhoto
            ? Image.network(
                imageUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) =>
                    _DrawerFallback(initials: initials),
                loadingBuilder: (ctx, child, prog) {
                  if (prog == null) return child;
                  return _DrawerFallback(initials: initials);
                },
              )
            : _DrawerFallback(initials: initials),
      ),
    );
  }
}

class _DrawerFallback extends StatelessWidget {
  final String initials;
  const _DrawerFallback({required this.initials});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8F2EB), Color(0xFFCDE8D8)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? l.drawerInitial : initials,
        style: const TextStyle(
          color: AppColors.cyanDeep,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DrawerDivider extends StatelessWidget {
  const _DrawerDivider();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: AppColors.newsDivider,
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color titleColor;
  final Color subtitleColor;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.titleColor,
    required this.subtitleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: accent, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: subtitleColor,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: subtitleColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Logout helper ───────────────────────────────────────────────────────

/// Reusable sign-out flow used by the drawer's Logout tile. Returns once
/// the navigation has settled on the auth screen so callers can `await` it
/// without racing with route teardown.
Future<void> performShellLogout(BuildContext context) async {
  try {
    await SupabaseService.signOut();
  } catch (_) {
    // Swallow — sign-out failures shouldn't trap the user in the app.
  }
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthScreen()),
    (route) => false,
  );
}
