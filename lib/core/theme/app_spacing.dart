import 'package:flutter/widgets.dart';

/// Spacing, radii and durations — a small scale so the whole app feels of a
/// piece.
class Insets {
  Insets._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double gutter = 28;
}

class Radii {
  Radii._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const Radius card = Radius.circular(lg);
  static const BorderRadius cardBR = BorderRadius.all(card);
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

class Motion {
  Motion._();
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 520);
  static const Curve curve = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuart;
}
