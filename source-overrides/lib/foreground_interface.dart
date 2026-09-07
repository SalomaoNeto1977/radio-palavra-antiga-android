import 'package:flutter/widgets.dart';

/// AudioService can start the shared engine without a phone Activity. Platform
/// views must wait until the phone UI is resumed; afterwards keep their identity
/// across background/foreground transitions so playback and navigation survive.
class ForegroundInterface extends StatefulWidget {
  const ForegroundInterface({required this.builder, super.key});

  final WidgetBuilder builder;

  @override
  State<ForegroundInterface> createState() => _ForegroundInterfaceState();
}

class _ForegroundInterfaceState extends State<ForegroundInterface>
    with WidgetsBindingObserver {
  Widget? _interface;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _interface == null && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_interface == null &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _interface = widget.builder(context);
    }
    return _interface ?? const SizedBox.expand();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
