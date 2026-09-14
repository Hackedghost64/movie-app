import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A 10-foot UI TV Focusable widget designed specifically for Android TV D-pad navigation.
///
/// Features:
/// 1. Spatial focus management with explicit FocusNode and autofocus support.
/// 2. Clear visual feedback: smooth scale animation, bright red border, and glowing shadow.
/// 3. Auto-scroll: ensures focused items stay centered in viewports when navigating lists/grids.
/// 4. TV D-pad action mapping: handles KEYCODE_DPAD_CENTER, ENTER, NUMPAD_ENTER, SPACE, GAMEPAD_A.
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;
  final bool autofocus;
  final FocusNode? focusNode;
  final double scaleFactor;
  final Color focusBorderColor;
  final double borderWidth;
  final bool autoScroll;
  final double scrollAlignment;
  final Color? focusedBackgroundColor;
  final ValueChanged<bool>? onFocusChange;

  const TvFocusable({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = 8,
    this.autofocus = false,
    this.focusNode,
    this.scaleFactor = 1.08,
    this.focusBorderColor = const Color(0xFFE50914),
    this.borderWidth = 3.5,
    this.autoScroll = true,
    this.scrollAlignment = 0.5,
    this.focusedBackgroundColor,
    this.onFocusChange,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late FocusNode _effectiveFocusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode = widget.focusNode ?? FocusNode();
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _effectiveFocusNode = widget.focusNode ?? FocusNode();
      _effectiveFocusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _effectiveFocusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _effectiveFocusNode.hasFocus;
    if (_isFocused != focused) {
      if (mounted) {
        setState(() => _isFocused = focused);
      }
      widget.onFocusChange?.call(focused);
      if (focused && widget.autoScroll && mounted) {
        Scrollable.ensureVisible(
          context,
          alignment: widget.scrollAlignment,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.gameButtonA) {
        widget.onTap();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          transform: _isFocused
              ? Matrix4.diagonal3Values(widget.scaleFactor, widget.scaleFactor, 1.0)
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            color: _isFocused && widget.focusedBackgroundColor != null
                ? widget.focusedBackgroundColor
                : Colors.transparent,
            border: _isFocused
                ? Border.all(color: widget.focusBorderColor, width: widget.borderWidth)
                : Border.all(color: Colors.transparent, width: widget.borderWidth),
            boxShadow: _isFocused
                ? [
                    const BoxShadow(color: Color(0xCC000000), blurRadius: 14, spreadRadius: 3),
                    BoxShadow(
                      color: widget.focusBorderColor.withValues(alpha: 0.65),
                      blurRadius: 18,
                      spreadRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
