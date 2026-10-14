/// Shared frame for the app's bottom sheets: 560 dp wide at most, radius 24
/// (from the theme), a title row with a 48 dp close button, no animation
/// under reduced motion. Sheets are routes, so Android and browser Back close
/// them before anything else.
library;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Opens [builder] as a modal bottom sheet in the app's style.
Future<T?> showPhSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: PH.sheetMaxWidth),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(PH.radiusSheet))),
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null,
      builder: builder,
    );

/// The sheet's title (20/600) with an optional one-line explanation and a
/// close button, so the sheet can be dismissed without a drag or Back.
class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SheetHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(title, style: PHText.title)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(subtitle!, style: PHText.small.copyWith(color: PH.muted)),
                ),
            ]),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ]);
}

/// A section heading inside a sheet (17/600, sentence case).
class SheetSection extends StatelessWidget {
  final String text;
  const SheetSection(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Semantics(header: true, child: Text(text, style: PHText.subtitle)),
      );
}
