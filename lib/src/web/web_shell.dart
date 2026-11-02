import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'web_routes.dart';
import 'web_theme.dart';

/// Satu item navigasi pada sidebar web.
class WebNavItem {
  const WebNavItem({
    required this.label,
    required this.icon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final String path;
}

/// Item sidebar untuk setiap peran.
///
/// Daftar ini satu-satunya sumber navigasi web; rute yang belum dibangun tetap
/// ditampilkan dan membuka halaman "Segera hadir" (bukan tautan mati).
List<WebNavItem> webNavItemsFor(UserRole role) => switch (role) {
      UserRole.patient => const <WebNavItem>[
          WebNavItem(
            label: 'Beranda',
            icon: Icons.dashboard_outlined,
            path: WebRoutes.home,
          ),
          WebNavItem(
            label: 'Asesmen',
            icon: Icons.fact_check_outlined,
            path: WebRoutes.assessment,
          ),
          WebNavItem(
            label: 'Terapi',
            icon: Icons.self_improvement_rounded,
            path: WebRoutes.therapy,
          ),
          WebNavItem(
            label: 'Profesional',
            icon: Icons.medical_services_outlined,
            path: WebRoutes.professional,
          ),
          WebNavItem(
            label: 'Jadwal',
            icon: Icons.event_available_outlined,
            path: WebRoutes.schedule,
          ),
          WebNavItem(
            label: 'Pengaturan',
            icon: Icons.settings_outlined,
            path: WebRoutes.settings,
          ),
        ],
      UserRole.professional => const <WebNavItem>[
          WebNavItem(
            label: 'Beranda',
            icon: Icons.dashboard_outlined,
            path: WebRoutes.professional,
          ),
          WebNavItem(
            label: 'Jadwal',
            icon: Icons.event_available_outlined,
            path: WebRoutes.schedule,
          ),
          WebNavItem(
            label: 'Pasien',
            icon: Icons.groups_outlined,
            path: WebRoutes.patients,
          ),
          WebNavItem(
            label: 'Pengaturan',
            icon: Icons.settings_outlined,
            path: WebRoutes.settings,
          ),
        ],
      UserRole.admin => const <WebNavItem>[
          WebNavItem(
            label: 'Ringkasan',
            icon: Icons.dashboard_outlined,
            path: WebRoutes.admin,
          ),
          WebNavItem(
            label: 'Pembayaran',
            icon: Icons.receipt_long_outlined,
            path: WebRoutes.adminPayments,
          ),
          WebNavItem(
            label: 'Harga & Paket',
            icon: Icons.sell_outlined,
            path: WebRoutes.adminPricing,
          ),
          WebNavItem(
            label: 'Pengguna',
            icon: Icons.manage_accounts_outlined,
            path: WebRoutes.adminUsers,
          ),
          WebNavItem(
            label: 'Dokter',
            icon: Icons.medical_services_outlined,
            path: WebRoutes.adminDoctors,
          ),
        ],
    };

/// Kerangka aplikasi web: sidebar + topbar + area konten.
///
/// Desktop (>= [WebBreakpoints.desktop]): sidebar selalu terlihat.
/// Jendela sempit: sidebar menjadi drawer, topbar menampilkan tombol menu.
class WebShell extends StatelessWidget {
  const WebShell({
    super.key,
    required this.role,
    required this.displayName,
    required this.currentPath,
    required this.onNavigate,
    required this.onLogout,
    required this.child,
  });

  final UserRole role;
  final String displayName;
  final String currentPath;
  final ValueChanged<String> onNavigate;
  final VoidCallback onLogout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isDesktop = constraints.maxWidth >= WebBreakpoints.desktop;
        final sidebar = _WebSidebar(
          role: role,
          displayName: displayName,
          currentPath: currentPath,
          onNavigate: onNavigate,
        );

        if (isDesktop) {
          return Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(width: WebBreakpoints.sidebarWidth, child: sidebar),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _WebContentArea(
                    role: role,
                    displayName: displayName,
                    title: WebRoutes.titleFor(currentPath),
                    onLogout: onLogout,
                    child: child,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          drawer: Drawer(
            width: 272,
            backgroundColor: Colors.white,
            child: SafeArea(child: sidebar),
          ),
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: MalvaColors.ink,
            elevation: 0,
            titleSpacing: 0,
            leading: Builder(
              builder: (BuildContext context) => IconButton(
                tooltip: 'Menu',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: Text(
              WebRoutes.titleFor(currentPath),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: MalvaColors.ink,
              ),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Keluar',
                icon: const Icon(Icons.logout_rounded),
                onPressed: onLogout,
              ),
              const SizedBox(width: 4),
            ],
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1),
            ),
          ),
          body: _WebContentArea(
            role: role,
            displayName: displayName,
            title: WebRoutes.titleFor(currentPath),
            onLogout: onLogout,
            showTopbar: false,
            child: child,
          ),
        );
      },
    );
  }
}

/// Area konten: topbar (desktop) + isi yang di-scroll dan dibatasi lebarnya.
class _WebContentArea extends StatelessWidget {
  const _WebContentArea({
    required this.role,
    required this.displayName,
    required this.title,
    required this.onLogout,
    required this.child,
    this.showTopbar = true,
  });

  final UserRole role;
  final String displayName;
  final String title;
  final VoidCallback onLogout;
  final Widget child;
  final bool showTopbar;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.sizeOf(context).width >= 600
        ? WebSpacing.gutterDesktop
        : WebSpacing.gutterCompact;
    return Column(
      children: <Widget>[
        if (showTopbar) ...<Widget>[
          _WebTopbar(
            title: title,
            role: role,
            displayName: displayName,
            onLogout: onLogout,
          ),
          const Divider(height: 1),
        ],
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                padding, WebSpacing.section, padding, WebSpacing.section + 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: WebBreakpoints.contentMaxWidth,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Topbar desktop: judul halaman, identitas pengguna, tombol keluar.
class _WebTopbar extends StatelessWidget {
  const _WebTopbar({
    required this.title,
    required this.role,
    required this.displayName,
    required this.onLogout,
  });

  final String title;
  final UserRole role;
  final String displayName;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final name = displayName.trim().isEmpty ? 'Pengguna' : displayName.trim();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: MalvaColors.ink,
              ),
            ),
          ),
          _RoleChip(role: role),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: MalvaColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            key: const Key('web-logout'),
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, size: 17),
            label: const Text('Keluar'),
          ),
        ],
      ),
    );
  }
}

/// Chip kecil berisi peran pengguna.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      UserRole.patient => MalvaColors.seed,
      UserRole.professional => MalvaColors.mint,
      UserRole.admin => MalvaColors.amber,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color == MalvaColors.amber ? const Color(0xFF8A5A00) : color,
        ),
      ),
    );
  }
}

/// Sidebar navigasi per peran.
class _WebSidebar extends StatelessWidget {
  const _WebSidebar({
    required this.role,
    required this.displayName,
    required this.currentPath,
    required this.onNavigate,
  });

  final UserRole role;
  final String displayName;
  final String currentPath;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final items = webNavItemsFor(role);
    final name = displayName.trim().isEmpty ? 'Pengguna' : displayName.trim();
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[MalvaColors.plum, MalvaColors.orchid],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.spa_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Malva',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: MalvaColors.plum,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              children: items
                  .map(
                    (WebNavItem item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _WebNavTile(
                        item: item,
                        selected: item.path == currentPath,
                        onTap: () => onNavigate(item.path),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: MalvaColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  role.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8B8194),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu baris navigasi sidebar dengan status terpilih + hover.
class _WebNavTile extends StatefulWidget {
  const _WebNavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final WebNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_WebNavTile> createState() => _WebNavTileState();
}

class _WebNavTileState extends State<_WebNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final background = selected
        ? MalvaColors.seed.withValues(alpha: 0.1)
        : (_hovered ? const Color(0xFFF6F1F9) : Colors.transparent);
    final foreground = selected ? MalvaColors.plum : const Color(0xFF5A5260);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: <Widget>[
                Icon(widget.item.icon, size: 19, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
