from pathlib import Path

path = Path('lib/features/chats/main_navigation_shell.dart')
text = path.read_text(encoding='utf-8')

if "import '../profile/profile_screen.dart';" not in text:
    text = text.replace(
        "import '../calls/calls_screen.dart';\n",
        "import '../calls/calls_screen.dart';\nimport '../profile/profile_screen.dart';\n",
        1,
    )
if "import 'root_navigation_policy.dart';" not in text:
    text = text.replace(
        "import 'linked_devices_qr_screen.dart';\n",
        "import 'linked_devices_qr_screen.dart';\nimport 'root_navigation_policy.dart';\n",
        1,
    )

old = """          _NavDestinationItem(
            id: 'settings',
            label: 'Settings',
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings_rounded,
            builder: (ctx) => SettingsRootScreen(
              preferencesController: preferencesController,
              themeController: themeController,
              dataStore: dataStore,
              notificationService: notificationService,
            ),
          ),
"""
new = """          _NavDestinationItem(
            id: 'profile',
            label: 'Profile',
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            builder: (ctx) => ProfileScreen(
              preferencesController: preferencesController,
              themeController: themeController,
              dataStore: dataStore,
              notificationService: notificationService,
            ),
          ),
"""
if "id: 'profile'" not in text:
    if old not in text:
        raise SystemExit('Phase 5 root Settings destination marker missing')
    text = text.replace(old, new, 1)

manual_partition = """        // Apply max 4 direct navigation items rule:
        // <= 4: Display all directly
        // > 4: Display first 3 + More as 4th item
        final bool hasOverflow = allDestinations.length > 4;
        final List<_NavDestinationItem> primaryDestinations = hasOverflow
            ? allDestinations.take(3).toList()
            : allDestinations;
        final List<_NavDestinationItem> overflowDestinations = hasOverflow
            ? allDestinations.skip(3).toList()
            : const <_NavDestinationItem>[];
"""
policy_partition = """        // Max four bottom items: direct destinations when <= 4, otherwise
        // the first three destinations plus a deterministic More destination.
        final navPlan = RootNavigationPlan.forDestinationCount(
          allDestinations.length,
        );
        final hasOverflow = navPlan.hasOverflow;
        final primaryDestinations = navPlan.primaryIndices
            .map((index) => allDestinations[index])
            .toList(growable: false);
        final overflowDestinations = navPlan.overflowIndices
            .map((index) => allDestinations[index])
            .toList(growable: false);
"""
if 'RootNavigationPlan.forDestinationCount(' not in text:
    if manual_partition not in text:
        raise SystemExit('Phase 5 manual root-nav partition marker missing')
    text = text.replace(manual_partition, policy_partition, 1)

old = """        final int bottomNavSelectedIndex = hasOverflow
            ? (effectiveIndex < 3 ? effectiveIndex : 3)
            : effectiveIndex;
"""
new = """        final bottomNavSelectedIndex = navPlan.selectedBottomIndex(
          effectiveIndex,
        );
"""
if 'navPlan.selectedBottomIndex(' not in text:
    if old not in text:
        raise SystemExit('Phase 5 bottom selection marker missing')
    text = text.replace(old, new, 1)

old = """                  if (hasOverflow && idx == 3) {
                    _showMoreMenu(
                      context,
                      theme: theme,
                      overflowDestinations: overflowDestinations,
                      onSelect: (overflowIdx) {
                        final realIndex = 3 + overflowIdx;
                        _selectRootDestination(realIndex);
                      },
                    );
                  } else {
                    _selectRootDestination(idx);
                  }
"""
new = """                  if (hasOverflow && idx == navPlan.moreBottomIndex) {
                    _showMoreMenu(
                      context,
                      theme: theme,
                      overflowDestinations: overflowDestinations,
                      onSelect: (overflowIdx) {
                        _selectRootDestination(
                          navPlan.destinationForOverflowTap(overflowIdx),
                        );
                      },
                    );
                  } else {
                    _selectRootDestination(
                      navPlan.destinationForPrimaryTap(idx),
                    );
                  }
"""
if 'navPlan.destinationForOverflowTap(' not in text:
    if old not in text:
        raise SystemExit('Phase 5 More navigation marker missing')
    text = text.replace(old, new, 1)

old = """              Expanded(
                child: IndexedStack(index: selectedIndex, children: screens),
              ),
"""
new = """              Expanded(
                child: Builder(
                  builder: (tabContext) => PageView(
                    controller: _pageController,
                    physics: const PageScrollPhysics(),
                    onPageChanged: (index) {
                      final tabController = DefaultTabController.of(tabContext);
                      if (tabController.index != index) {
                        tabController.animateTo(index);
                      }
                      if (_currentIndex != index && mounted) {
                        setState(() => _currentIndex = index);
                      }
                    },
                    children: screens,
                  ),
                ),
              ),
"""
if 'DefaultTabController.of(tabContext)' not in text:
    if old not in text:
        raise SystemExit('Phase 5 top-tab IndexedStack marker missing')
    text = text.replace(old, new, 1)

# Settings is intentionally reachable through Profile, not as a root item.
if 'SettingsRootScreen(' not in text:
    text = text.replace("import '../settings/settings_root_screen.dart';\n", '')

required = [
    "import '../profile/profile_screen.dart';",
    "import 'root_navigation_policy.dart';",
    "id: 'profile'",
    "label: 'Profile'",
    'builder: (ctx) => ProfileScreen(',
    'RootNavigationPlan.forDestinationCount(',
    'navPlan.selectedBottomIndex(',
    'navPlan.destinationForOverflowTap(',
    'DefaultTabController.of(tabContext)',
]
for marker in required:
    if marker not in text:
        raise SystemExit(f'Phase 5 navigation marker missing: {marker}')
if "id: 'settings'" in text:
    raise SystemExit('Root Settings destination is still present')

path.write_text(text, encoding='utf-8')
