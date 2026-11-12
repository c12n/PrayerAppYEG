// Responsive layout layer (v3.0.0, Chromebook + foldables pass).
//
// One shared vocabulary for every adaptive decision in the app:
// Material 3 window size classes (compact / medium / expanded)
// plus fold awareness read from MediaQuery.displayFeatures.
//
//  - compact  (< 600dp): phones and folded-closed foldables. This
//    is exactly the layout set the app has always shipped; nothing
//    in this pass changes a single pixel there.
//  - medium   (600-839dp): two-pane arrangements (foldables open
//    in portrait, small tablets, phone landscape).
//  - expanded (>= 840dp): Chromebooks, tablets, foldables open in
//    landscape — the full two-pane / two-column / grid layouts.
//
// Foldables: a vertical hinge or fold (book mode) splits two-pane
// rows so neither pane runs under the hinge; a horizontal hinge
// in the half-opened posture (tabletop) splits the Quran Now
// Playing screen at the fold. On devices that report no display
// features every helper here returns null and the layouts fall
// back to their plain forms.

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

enum WindowSizeClass { compact, medium, expanded }

extension WindowSizeClassX on WindowSizeClass {
  bool get isCompact => this == WindowSizeClass.compact;
  bool get isMedium => this == WindowSizeClass.medium;
  bool get isExpanded => this == WindowSizeClass.expanded;
  bool get isAtLeastMedium => this != WindowSizeClass.compact;
}

/// Material 3 breakpoints: compact < 600, medium 600-839,
/// expanded >= 840 logical pixels of window width.
WindowSizeClass windowSizeClassForWidth(double width) {
  if (width < 600) return WindowSizeClass.compact;
  if (width < 840) return WindowSizeClass.medium;
  return WindowSizeClass.expanded;
}

WindowSizeClass windowSizeClassOf(BuildContext context) =>
    windowSizeClassForWidth(MediaQuery.sizeOf(context).width);

/// The first hinge or fold whose bounds split a window of
/// [width] vertically into two usable regions (a foldable held
/// in book mode). Null on every non-folding device, and when the
/// feature does not actually divide the window.
ui.DisplayFeature? verticalHinge(BuildContext context, double width) {
  for (final feature in MediaQuery.of(context).displayFeatures) {
    if (feature.type != ui.DisplayFeatureType.hinge &&
        feature.type != ui.DisplayFeatureType.fold) {
      continue;
    }
    final bounds = feature.bounds;
    if (bounds.width >= bounds.height) continue; // horizontal
    if (bounds.left <= 0 || bounds.right >= width) continue;
    return feature;
  }
  return null;
}

/// The first hinge or fold splitting the window horizontally
/// while the device reports the half-opened posture — a foldable
/// standing in tabletop mode. Null everywhere else, including a
/// foldable lying fully flat (postureFlat), so the tabletop
/// layout appears only while the posture is actually reported.
ui.DisplayFeature? tabletopHinge(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  for (final feature in MediaQuery.of(context).displayFeatures) {
    if (feature.type != ui.DisplayFeatureType.hinge &&
        feature.type != ui.DisplayFeatureType.fold) {
      continue;
    }
    if (feature.state != ui.DisplayFeatureState.postureHalfOpened) {
      continue;
    }
    final bounds = feature.bounds;
    if (bounds.height >= bounds.width) continue; // vertical
    if (bounds.top <= 0 || bounds.bottom >= size.height) continue;
    return feature;
  }
  return null;
}

/// Pane widths for a two-pane row inside a content region that
/// starts at [startInset] and ends [endInset] short of the
/// window's right edge, split so neither pane sits under a
/// vertical hinge: [firstWidth] for the first logical pane, then
/// a gap exactly as wide as the hinge, then the second pane takes
/// what remains. "First" follows reading direction — in RTL the
/// first pane is the physical right one, and the widths account
/// for that. Returns null when there is no usable hinge split
/// (either region would be narrower than 160dp), in which case
/// the caller keeps its plain flex row.
({double firstWidth, double gapWidth})? hingeSplit(
  BuildContext context,
  double width, {
  double startInset = 0,
  double endInset = 0,
}) {
  final feature = verticalHinge(context, width);
  if (feature == null) return null;
  final bounds = feature.bounds;
  final physicalLeft = bounds.left - startInset;
  final physicalRight = width - endInset - bounds.right;
  if (physicalLeft < 160 || physicalRight < 160) return null;
  final rtl = Directionality.of(context) == TextDirection.rtl;
  return (
    firstWidth: rtl ? physicalRight : physicalLeft,
    gapWidth: bounds.width,
  );
}
