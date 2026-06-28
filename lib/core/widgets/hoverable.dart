import 'package:flutter/widgets.dart';

/// Tiny helper that exposes hover + pressed state to a builder, with the right
/// macOS cursor. Saves every interactive widget from re-implementing a
/// MouseRegion/GestureDetector pair.
class Hoverable extends StatefulWidget {
  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.cursor = SystemMouseCursors.click,
    this.enabled = true,
  });

  final Widget Function(BuildContext context, bool hovered, bool pressed) builder;
  final VoidCallback? onTap;
  final MouseCursor cursor;
  final bool enabled;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel:
            widget.enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.enabled ? widget.onTap : null,
        child: widget.builder(context, _hovered && widget.enabled, _pressed),
      ),
    );
  }
}
