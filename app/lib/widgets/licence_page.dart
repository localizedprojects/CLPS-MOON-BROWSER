/// Learn › Credits › Open-source licences: Flutter's licence page, which the
/// app does not build itself, with the app's keyboard behaviour: Escape
/// closes it, and a focused package row has the 2 px ice focus ring (Material
/// shows only a faint lighter fill, about 1.6:1 against the panel; 1.13.4
/// review, a11y).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';
import '../version.dart';
import 'escape_closes.dart';

/// Opens the licence page, as [showLicensePage] does.
void showAppLicences(BuildContext context) {
  final nav = Navigator.of(context);
  final themes = InheritedTheme.capture(from: context, to: nav.context);
  nav.push(MaterialPageRoute<void>(
    builder: (_) => themes.wrap(const EscapeCloses(
      child: ListTileFocusRing(
        child: LicensePage(applicationName: 'Lunar Horizon', applicationVersion: appVersion),
      ),
    )),
  ));
}

/// Draws the 2 px ice focus ring round the [ListTile] inside [child] that has
/// the keyboard focus (focus shown for a keyboard, as on the app's buttons;
/// not after a tap). For list pages the app does not build itself, whose
/// rows show focus only as a fill.
class ListTileFocusRing extends StatefulWidget {
  final Widget child;
  const ListTileFocusRing({super.key, required this.child});

  @override
  State<ListTileFocusRing> createState() => _ListTileFocusRingState();
}

class _ListTileFocusRingState extends State<ListTileFocusRing> {
  // observes the focus inside; never takes it, never a Tab stop
  final _node = FocusNode(debugLabel: 'ListTileFocusRing', canRequestFocus: false, skipTraversal: true);
  final _ring = GlobalKey();

  /// The focused row, or null.
  RenderBox? _tile;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_update);
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_update);
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    _node.dispose();
    super.dispose();
  }

  void _modeChanged(FocusHighlightMode _) => _update();

  void _update() {
    RenderBox? tile;
    if (_node.hasFocus && FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
        if (e.widget is! ListTile) return true;
        final box = e.findRenderObject();
        if (box is RenderBox) tile = box;
        return false;
      });
    }
    if (tile != _tile && mounted) setState(() => _tile = tile);
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _node,
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        // the row moves when its list scrolls
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _ring.currentContext?.findRenderObject()?.markNeedsPaint();
            return false;
          },
          child: _Ring(key: _ring, tile: _tile, child: widget.child),
        ),
      );
}

class _Ring extends SingleChildRenderObjectWidget {
  final RenderBox? tile;
  const _Ring({super.key, required this.tile, required super.child});

  @override
  _RenderRing createRenderObject(BuildContext context) => _RenderRing(tile);

  @override
  void updateRenderObject(BuildContext context, _RenderRing renderObject) => renderObject.tile = tile;
}

class _RenderRing extends RenderProxyBox {
  _RenderRing(this._tile);

  RenderBox? _tile;
  set tile(RenderBox? t) {
    if (t == _tile) return;
    _tile = t;
    markNeedsPaint();
  }

  /// [box]'s rectangle in this box's coordinates.
  Rect _rectOf(RenderBox box) => MatrixUtils.transformRect(box.getTransformTo(this), Offset.zero & box.size);

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final t = _tile;
    if (t == null || !t.attached || !t.hasSize) return;
    // worked out here, as the list scrolls; inside the row (it is as wide as
    // the page) and cut where the list's viewport cuts the row
    final canvas = context.canvas..save();
    final RenderObject? viewport = RenderAbstractViewport.maybeOf(t);
    if (viewport is RenderBox && viewport.hasSize) canvas.clipRect(_rectOf(viewport).shift(offset));
    canvas.drawRRect(
      RRect.fromRectAndRadius(_rectOf(t).shift(offset).deflate(1), const Radius.circular(PH.radius)),
      Paint()
        ..color = PH.ice
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }
}
