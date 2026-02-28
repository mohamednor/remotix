// lib/presentation/widgets/remote_button.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RemoteButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final bool isCircle;

  const RemoteButton({
    super.key,
    required this.child,
    this.onTap,
    this.size = 56,
    this.color,
    this.isCircle = true,
  });

  @override
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  static const Color _bgColor = Color(0xFF1E1E2E);
  static const Color _shadowDark = Color(0xFF111120);
  static const Color _shadowLight = Color(0xFF2D2D44);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _controller.reverse();
    HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final Color bg = widget.color ?? _bgColor;
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: bg,
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircle ? null : BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: _shadowDark,
                offset: Offset(4, 4),
                blurRadius: 8,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: _shadowLight,
                offset: Offset(-4, -4),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}
