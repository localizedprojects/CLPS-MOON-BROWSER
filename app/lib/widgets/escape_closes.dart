import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

/// Escape closes the route this is in, as it closes the app's sheets and
/// dialogs. For full-screen pages (a [PageRoute]), which Flutter closes only
/// with their Back button or the system's back (1.13.4 review, a11y).
///
/// Escape asks the route to pop ([Navigator.maybePop]), as the system's back
/// does: a page with a navigator of its own (the licence page's texts on a
/// phone) first goes back one page there.
///
/// Put it round the page's content, in the route's builder. It takes the
/// keyboard focus when the page opens, so Escape works before the first Tab,
/// and is no Tab stop and no semantics node of its own.
class EscapeCloses extends StatelessWidget {
  final Widget child;
  const EscapeCloses({super.key, required this.child});

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context)},
        child: Focus(autofocus: true, skipTraversal: true, includeSemantics: false, child: child),
      );
}
