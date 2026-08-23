from pathlib import Path

path = Path('lib/features/chats/main_navigation_shell.dart')
text = path.read_text(encoding='utf-8')

if "import '../profile/profile_screen.dart';" not in text:
    text = text.replace(
        "import '../calls/calls_screen.dart';\n",
        "import '../calls/calls_screen.dart';\nimport '../profile/profile_screen.dart';\n",
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

# Settings is now intentionally reachable through Profile, not directly in the
# root navigation candidate list. Remove the stale import only when no direct
# SettingsRootScreen construction remains in this file.
if 'SettingsRootScreen(' not in text:
    text = text.replace("import '../settings/settings_root_screen.dart';\n", '')

for marker in [
    "import '../profile/profile_screen.dart';",
    "id: 'profile'",
    "label: 'Profile'",
    'builder: (ctx) => ProfileScreen(',
]:
    if marker not in text:
        raise SystemExit(f'Phase 5 profile-nav marker missing: {marker}')
if "id: 'settings'" in text:
    raise SystemExit('Root Settings destination is still present')

path.write_text(text, encoding='utf-8')
