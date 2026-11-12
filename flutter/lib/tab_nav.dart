// Tab navigation (v3.0.0, 1:1 with the iOS phone shell) — the
// shared controller behind the bottom tab bar. The iOS shell's
// phoneTab has four tabs in this order: Prayer, Quran, Qibla,
// Settings. In-page shortcuts (the home Quran card, the Qibla
// card, the header Settings gear) switch tabs through this
// controller instead of pushing routes, exactly like the iOS
// tab shell.

import 'package:flutter/widgets.dart';

class TabNavController extends ChangeNotifier {
  static const prayer = 0;
  static const quran = 1;
  static const qibla = 2;
  static const settings = 3;

  int index = prayer;

  void goTo(int tab) {
    if (tab == index) return;
    index = tab;
    notifyListeners();
  }
}

class TabNavScope extends InheritedWidget {
  final TabNavController controller;
  const TabNavScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static TabNavController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabNavScope>()!.controller;

  static TabNavController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabNavScope>()?.controller;

  @override
  bool updateShouldNotify(TabNavScope oldWidget) =>
      controller != oldWidget.controller;
}
