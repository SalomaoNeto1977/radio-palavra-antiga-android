import 'package:flutter/widgets.dart';

/// AudioService can start the shared engine without a phone Activity. Platform
/// views must wait until the phone UI is resumed. A backgrounded Activity keeps
/// its UI, but a destroyed Activity must release its platform views. Audio and
/// the shared engine live above this widget and continue across that replacement.
class ForegroundInterface extends StatefulWidget {
  const ForegroundInterface({required this.builder, super.key});

  final WidgetBuilder builder;

  @override
  State<ForegroundInterface> createState() => _ForegroundInterfaceState();
}

class _ForegroundInterfaceState extends State<ForegroundInterface>
    with WidgetsBindingObserver {
  Widget? _interface;
  int _viewGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.detached && _interface != null) {
      setState(() {
        _interface = null;
        _viewGeneration += 1;
      });
    } else if (state == AppLifecycleState.resumed && _interface == null) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_interface == null &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _interface = widget.builder(context);
    }
    if (_interface == null) return const SizedBox.expand();
    // Detached engines may receive no frame until the new Activity resumes.
    // Change the key as well, so Flutter cannot reuse the old platform-view
    // element when detach and reattach happen before the next build.
    return KeyedSubtree(
      key: ValueKey<int>(_viewGeneration),
      child: _interface!,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
