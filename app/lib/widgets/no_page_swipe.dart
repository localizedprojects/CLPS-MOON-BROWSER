/// Keeps a drag that starts on [child] from turning the page of the Site
/// PageView around it: while a finger is down on it, the pages are locked
/// ([PageSwipeLock]). There is no sideways drag claimed here, so a slider or
/// a chart inside still gets its drags, and a drag that wobbles sideways at
/// the start still scrolls the page up and down.
library;

import 'package:flutter/widgets.dart';

/// How many fingers are down on a [NoPageSwipe]; while above zero the
/// PageView that owns it does not turn.
class SwipeLock extends ValueNotifier<int> {
  SwipeLock() : super(0);
  bool _gone = false;

  /// Lets go of [n] fingers; nothing once disposed (a page that went away
  /// with a finger still down).
  void release(int n) {
    if (!_gone) value -= n;
  }

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }
}

/// Hands a [SwipeLock] to the [NoPageSwipe]s below.
class PageSwipeLock extends InheritedNotifier<SwipeLock> {
  const PageSwipeLock({super.key, required SwipeLock super.notifier, required super.child});

  /// The nearest lock, or null outside a PageView that has one. Does not
  /// rebuild the caller when it changes.
  static SwipeLock? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<PageSwipeLock>()?.notifier;
}

class NoPageSwipe extends StatefulWidget {
  final Widget child;
  const NoPageSwipe({super.key, required this.child});
  @override
  State<NoPageSwipe> createState() => _NoPageSwipeState();
}

class _NoPageSwipeState extends State<NoPageSwipe> {
  /// The fingers down here, and the lock they hold.
  final Set<int> _down = {};
  SwipeLock? _lock;

  void _press(PointerDownEvent e) {
    final lock = _lock = PageSwipeLock.maybeOf(context);
    if (lock != null && _down.add(e.pointer)) lock.value++;
  }

  void _release(PointerEvent e) {
    if (_down.remove(e.pointer)) _lock?.release(1);
  }

  @override
  void dispose() {
    // a finger still down when this goes away lets go of the lock too
    final lock = _lock;
    if (lock != null && _down.isNotEmpty) {
      final n = _down.length;
      // not during the build that removed this
      WidgetsBinding.instance.addPostFrameCallback((_) => lock.release(n));
    }
    _down.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    // its whole box, margins too, so a drag just beside the slider does
    // not turn the page either
    behavior: HitTestBehavior.translucent,
    onPointerDown: _press,
    onPointerUp: _release,
    onPointerCancel: _release,
    child: widget.child,
  );
}
