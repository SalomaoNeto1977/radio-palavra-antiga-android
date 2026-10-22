import 'package:flutter/material.dart';

/// Hybrid Composition can lose a retained Flutter layer when Android restores
/// the phone surface. Recreate only the menu's paint layer after that surface
/// has resumed. The selected destination and the WebView stay owned by the shell.
class PersistentNavigationBar extends StatefulWidget {
  const PersistentNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<PersistentNavigationBar> createState() =>
      _PersistentNavigationBarState();
}

class _PersistentNavigationBarState extends State<PersistentNavigationBar>
    with WidgetsBindingObserver {
  int _paintGeneration = 0;
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshSurface();
  }

  @override
  void didChangeMetrics() => _refreshSurface();

  void _refreshSurface() {
    final WidgetsBinding binding = WidgetsBinding.instance;
    if (_refreshScheduled ||
        binding.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _refreshScheduled = true;
    binding.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted ||
          binding.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      setState(() => _paintGeneration += 1);
    });
    // A paused WebView need not produce a frame of its own. Request one even
    // when no audio state, page content or subscription value has changed.
    binding.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: ValueKey<int>(_paintGeneration),
      child: ColoredBox(
        // Paint the safe-area padding as well as the buttons.
        color: const Color(0xFFFFFBF5),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            height: 60,
            selectedIndex: widget.selectedIndex,
            onDestinationSelected: widget.onDestinationSelected,
            backgroundColor: const Color(0xFFFFFBF5),
            indicatorColor: const Color(0xFFEBC9A4),
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.radio_outlined),
                selectedIcon: Icon(Icons.radio),
                label: 'Rádio',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Música',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Conta',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_outlined),
                selectedIcon: Icon(Icons.chat),
                label: 'WhatsApp',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
