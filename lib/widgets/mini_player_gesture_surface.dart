import 'dart:async';

import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/theme/motion_tokens.dart';

class MiniPlayerGestureSurface extends StatefulWidget {
  const MiniPlayerGestureSurface({
    required this.child,
    this.onNext,
    this.onPrevious,
    this.onExpand,
    super.key,
  });

  final Widget child;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onExpand;

  @override
  State<MiniPlayerGestureSurface> createState() =>
      _MiniPlayerGestureSurfaceState();
}

class _MiniPlayerGestureSurfaceState extends State<MiniPlayerGestureSurface> {
  static const double _feedbackThreshold = 34;
  static const double _commitThreshold = 52;
  double _horizontalTravel = 0;
  double _verticalTravel = 0;
  double _offsetX = 0;
  double _offsetY = 0;
  bool _thresholdFeedbackSent = false;
  bool _dragging = false;

  void _start(DragStartDetails _) {
    setState(() {
      _horizontalTravel = 0;
      _verticalTravel = 0;
      _offsetX = 0;
      _offsetY = 0;
      _thresholdFeedbackSent = false;
      _dragging = true;
    });
  }

  void _update(DragUpdateDetails details) {
    _horizontalTravel += details.delta.dx;
    _verticalTravel += details.delta.dy.abs();
    final reachesThreshold = _horizontalTravel.abs() >= _feedbackThreshold;
    if (reachesThreshold && !_thresholdFeedbackSent) {
      _thresholdFeedbackSent = true;
      unawaited(Haptics.selection().catchError((Object _) {}));
    } else if (!reachesThreshold) {
      _thresholdFeedbackSent = false;
    }
    setState(() {
      if (_horizontalTravel.abs() >= _verticalTravel) {
        _offsetX = _horizontalTravel.clamp(-90.0, 90.0);
      } else {
        _offsetY = (_offsetY + details.delta.dy).clamp(-32.0, 32.0);
      }
    });
  }

  void _finish(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final horizontalDominant =
        _horizontalTravel.abs() >= _verticalTravel * 1.25;
    final shouldCommitSwipe =
        horizontalDominant &&
        (_horizontalTravel.abs() >= _commitThreshold ||
            velocity.dx.abs() >= 120);
    final shouldExpand =
        !horizontalDominant && (_verticalTravel >= 48 || velocity.dy <= -280);
    final next = _horizontalTravel < 0;
    _settle();
    if (shouldCommitSwipe) {
      if (next) {
        widget.onNext?.call();
      } else {
        widget.onPrevious?.call();
      }
    } else if (shouldExpand) {
      widget.onExpand?.call();
    }
  }

  void _cancel() => _settle();

  void _settle() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _offsetX = 0;
      _offsetY = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: _start,
      onPanUpdate: _update,
      onPanEnd: _finish,
      onPanCancel: _cancel,
      child: AnimatedContainer(
        duration: _dragging ? Duration.zero : motion.fast,
        curve: motion.standard,
        transform: Matrix4.translationValues(_offsetX, _offsetY, 0),
        child: widget.child,
      ),
    );
  }
}
