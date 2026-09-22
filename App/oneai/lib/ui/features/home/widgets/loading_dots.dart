import 'package:flutter/material.dart';

/// Animated loading indicator with 5 bouncing dots.
class LoadingDots extends StatelessWidget {
  const LoadingDots({super.key, this.color = Colors.blue, this.size = 10.0, this.dotCount = 5, this.spacing = 8.0});

  final Color color;
  final double size;
  final int dotCount;
  final double spacing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: size * 2,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        dotCount,
        (i) => _AnimatedDot(delay: i * 120, color: color, size: size, spacing: spacing),
      ),
    ),
  );
}

class _AnimatedDot extends StatefulWidget {
  final int delay;
  final Color color;
  final double size;
  final double spacing;
  const _AnimatedDot({required this.delay, required this.color, required this.size, required this.spacing});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _animation = Tween<double>(begin: 0.3, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(widget.delay / 1200, (widget.delay + 600) / 1200, curve: Curves.easeInOut),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder:
        (context, child) => Container(
          margin: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: widget.color.withValues(alpha: _animation.value), shape: BoxShape.circle),
        ),
  );
}
