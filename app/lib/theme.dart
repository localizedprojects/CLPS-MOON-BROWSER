import 'package:flutter/material.dart';

/// Lunar Horizon design tokens: calm deep navy. Depth comes from tone (darker
/// page, lighter cards, lighter still for raised parts), not from hairlines or
/// shadows. Colour carries meaning only (Sun amber, Earth blue, both teal);
/// UI chrome and selection are neutral navy. Mirrors charts/src/theme.ts and
/// charts/src/styles.css.
/// Below this height (a phone in landscape) the bottom bar is slim (icons
/// only, 48 dp) and the compare tray slimmer, so answers stay above the fold.
const shortScreenMaxHeight = 500.0;

class PH {
  // navy surface layers (darkest -> lightest)
  static const bg = Color(0xFF060B16);
  static const sunken = Color(0xFF08101F);
  static const panel = Color(0xFF0C1528);
  static const panelHi = Color(0xFF12203A);
  static const selected = Color(0xFF1C3358);

  /// Secondary (tonal) buttons and chips: the same neutral navy as a selection.
  static const tonal = selected;
  // hairlines (tables, segmented buttons, legacy widgets only)
  static const line = Color(0xFF1E3050);
  static const lineStrong = Color(0xFF2C4470);
  static const grid = lineStrong;

  /// The ridge in the brand mark (tools/make_icons.py RIDGE); brand only.
  static const brandRidge = Color(0xFF1F3254);
  // text
  static const text = Color(0xFFE6EEF9);
  static const muted = Color(0xFF8DA1C3);
  // interaction accent (focus, sliders, links, the primary button) - distinct in lightness from Earth blue
  static const ice = Color(0xFFA9CCFF);
  // meaning
  static const sun = Color(0xFFFFB000);
  static const earth = Color(0xFF3D8BFD);
  static const both = Color(0xFF2EC4B6);
  static const warn = Color(0xFFFF6B6B);

  static const sans = 'IBM Plex Sans';
  static const mono = 'IBM Plex Mono';

  /// Small parts: inputs, tooltips, legacy widgets.
  static const radius = 6.0;

  /// Blocks inside a card (images, insets, thumbnails).
  static const radiusInner = 12.0;
  static const radiusCard = 16.0;
  static const radiusSheet = 24.0;

  /// Bottom sheets and dialogs never grow wider than this.
  static const sheetMaxWidth = 560.0;

  /// The one motion in the app: a 250 ms fade (see [motionDuration]).
  static const fade = Duration(milliseconds: 250);

  /// Canvas text (map labels) follows the user's text size up to this factor.
  static const maxCanvasTextScale = 2.0;
}

/// True when the user's text size is well above the default (Android 130 %
/// and up, or a large browser font): layouts then give text its own row.
bool largeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(16) > 16 * 1.3;

/// [PH.fade], or no motion at all when the platform asks for it.
Duration motionDuration(BuildContext context) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : PH.fade;

/// Type scale (IBM Plex Sans): 28 / 20 / 17 / 16 / 13. Nothing smaller than 13
/// in new screens. Colours are the default text colour; use copyWith for muted.
class PHText {
  static const headline = TextStyle(fontFamily: PH.sans, fontSize: 28, fontWeight: FontWeight.w700, height: 1.2, color: PH.text);
  static const title = TextStyle(fontFamily: PH.sans, fontSize: 20, fontWeight: FontWeight.w600, height: 1.3, color: PH.text);
  static const subtitle = TextStyle(fontFamily: PH.sans, fontSize: 17, fontWeight: FontWeight.w600, height: 1.35, color: PH.text);
  static const body = TextStyle(fontFamily: PH.sans, fontSize: 16, fontWeight: FontWeight.w400, height: 1.45, color: PH.text);
  static const small = TextStyle(fontFamily: PH.sans, fontSize: 13, fontWeight: FontWeight.w400, height: 1.4, color: PH.text);
}

/// Section label for the older widgets (new screens use [PHText]). Once an
/// uppercase "console" label; now sentence case, 13 px, muted.
class MicroLabel extends StatelessWidget {
  final String text;
  final Color color;
  const MicroLabel(this.text, {super.key, this.color = PH.muted});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(fontFamily: PH.sans, fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      );
}

/// Tabular monospace numerics for coordinates, UTC times and the exact
/// numbers shown to planners ("Show exact numbers").
TextStyle numStyle({double size = 14, FontWeight weight = FontWeight.w500, Color color = PH.text}) => TextStyle(
    fontFamily: PH.mono, fontSize: size, fontWeight: weight, color: color, fontFeatures: const [FontFeature.tabularFigures()]);

/// Big friendly numbers ("80%", "13.0 days"): Plex Sans with tabular figures,
/// so values line up and do not jitter while they change.
TextStyle statStyle({double size = 28, FontWeight weight = FontWeight.w600, Color color = PH.text}) => TextStyle(
    fontFamily: PH.sans,
    fontSize: size,
    fontWeight: weight,
    height: 1.1,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()]);

/// Hairline that turns into the 2 px ice focus ring (segmented / outlined buttons).
WidgetStateProperty<BorderSide?> _side({double width = 1, Color color = PH.line, Color? selected}) =>
    WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.focused)) return const BorderSide(color: PH.ice, width: 2);
      if (selected != null && s.contains(WidgetState.selected)) return BorderSide(color: selected, width: width);
      return BorderSide(color: color, width: width);
    });

/// Borderless until focused, then a 2 px ring. Drawn just outside the shape so
/// it stays visible on the ice primary button as well as on tonal ones.
WidgetStateProperty<BorderSide?> _focusRing({Color color = PH.ice, bool outside = false}) =>
    WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused)
        ? BorderSide(color: color, width: 2, strokeAlign: outside ? BorderSide.strokeAlignOutside : BorderSide.strokeAlignInside)
        : null);

const _buttonText = TextStyle(fontFamily: PH.sans, fontSize: 16, fontWeight: FontWeight.w600, height: 1.2);

/// 250 ms cross-fade between pages; none when animations are disabled.
class _FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadePageTransitionsBuilder();

  @override
  Duration get transitionDuration => PH.fade;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child);
  }
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: PH.ice,
    onPrimary: PH.bg,
    secondary: PH.selected,
    onSecondary: PH.text,
    secondaryContainer: PH.tonal,
    onSecondaryContainer: PH.text,
    tertiary: PH.earth,
    surface: PH.panel,
    onSurface: PH.text,
    onSurfaceVariant: PH.muted,
    surfaceContainerHighest: PH.panelHi,
    surfaceContainerHigh: PH.panelHi,
    surfaceContainer: PH.panel,
    surfaceContainerLow: PH.panel,
    surfaceContainerLowest: PH.sunken,
    outline: PH.lineStrong,
    outlineVariant: PH.line,
    error: PH.warn,
  );
  // standard density and padded tap targets everywhere: the adaptive defaults
  // are compact and shrink-wrapped on desktop (and so in desktop browsers),
  // which takes buttons to 40 px and chips to about 30 px (< 48 dp)
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: PH.sans,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  const pill = StadiumBorder();
  final fades = PageTransitionsTheme(builders: {
    for (final p in TargetPlatform.values) p: const _FadePageTransitionsBuilder(),
  });
  return base.copyWith(
    scaffoldBackgroundColor: PH.bg,
    canvasColor: PH.panel,
    focusColor: PH.ice.withValues(alpha: 0.22),
    hoverColor: Colors.white.withValues(alpha: 0.04),
    splashFactory: InkRipple.splashFactory,
    dividerColor: PH.line,
    pageTransitionsTheme: fades,
    textTheme: base.textTheme.apply(bodyColor: PH.text, displayColor: PH.text, fontFamily: PH.sans).copyWith(
          headlineMedium: PHText.headline,
          titleLarge: PHText.title,
          titleMedium: PHText.subtitle,
          bodyLarge: PHText.body,
          bodyMedium: PHText.body,
          bodySmall: PHText.small.copyWith(color: PH.muted),
          labelLarge: _buttonText,
          labelMedium: PHText.small.copyWith(fontWeight: FontWeight.w500),
          labelSmall: PHText.small.copyWith(fontWeight: FontWeight.w500),
        ),
    appBarTheme: AppBarTheme(
      // the bar takes the card tone only once content scrolls under it
      backgroundColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.scrolledUnder) ? PH.panel : PH.bg),
      surfaceTintColor: Colors.transparent,
      foregroundColor: PH.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: PHText.title,
    ),
    cardTheme: CardThemeData(
      color: PH.panel,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.all(6),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusCard)),
    ),
    dividerTheme: const DividerThemeData(color: PH.line, thickness: 1, space: 1),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(pill),
        side: _side(),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? PH.selected : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? PH.text : PH.muted),
        // selected segments are also heavier, not only lighter
        textStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: PH.sans,
            fontSize: 14,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500)),
        overlayColor: WidgetStatePropertyAll(PH.ice.withValues(alpha: 0.08)),
      ),
    ),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return Colors.transparent;
        return s.contains(WidgetState.selected) ? PH.selected : PH.panelHi;
      }),
      side: WidgetStateBorderSide.resolveWith(
          (s) => s.contains(WidgetState.focused) ? const BorderSide(color: PH.ice, width: 2) : BorderSide.none),
      shape: pill,
      labelStyle: const TextStyle(fontFamily: PH.sans, fontSize: 14, fontWeight: FontWeight.w500, color: PH.text),
      secondaryLabelStyle: const TextStyle(fontFamily: PH.sans, fontSize: 14, fontWeight: FontWeight.w600, color: PH.text),
      checkmarkColor: PH.ice,
      iconTheme: const IconThemeData(color: PH.muted, size: 18),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      showCheckmark: true,
      elevation: 0,
      pressElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      // colours come from the scheme: FilledButton = ice on dark text (primary),
      // FilledButton.tonal = #1C3358 (secondaryContainer)
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(pill),
        side: _focusRing(color: PH.text, outside: true),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22)),
        textStyle: const WidgetStatePropertyAll(_buttonText),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(pill),
        side: _side(color: PH.lineStrong),
        foregroundColor: const WidgetStatePropertyAll(PH.text),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
        textStyle: const WidgetStatePropertyAll(_buttonText),
        overlayColor: WidgetStatePropertyAll(PH.ice.withValues(alpha: 0.08)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(pill),
        foregroundColor: const WidgetStatePropertyAll(PH.ice),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
        side: _focusRing(),
        textStyle: const WidgetStatePropertyAll(_buttonText),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(PH.text),
        shape: const WidgetStatePropertyAll(CircleBorder()),
        side: _focusRing(),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 80,
      backgroundColor: PH.panel,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      indicatorColor: PH.selected,
      indicatorShape: pill,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((s) {
        final sel = s.contains(WidgetState.selected);
        return TextStyle(
            fontFamily: PH.sans, fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w500, color: sel ? PH.text : PH.muted);
      }),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? PH.text : PH.muted)),
      // the focused destination's indicator fills with ice (keyboard focus)
      overlayColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.focused)) return PH.ice.withValues(alpha: 0.28);
        if (s.contains(WidgetState.pressed)) return PH.ice.withValues(alpha: 0.12);
        if (s.contains(WidgetState.hovered)) return Colors.white.withValues(alpha: 0.05);
        return null;
      }),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      // labelType is left to the shell: an extended rail must use none
      backgroundColor: PH.bg,
      elevation: 0,
      useIndicator: true,
      indicatorColor: PH.selected,
      indicatorShape: pill,
      minWidth: 88,
      minExtendedWidth: 232,
      selectedLabelTextStyle: TextStyle(fontFamily: PH.sans, fontSize: 13, fontWeight: FontWeight.w600, color: PH.text),
      unselectedLabelTextStyle: TextStyle(fontFamily: PH.sans, fontSize: 13, fontWeight: FontWeight.w500, color: PH.muted),
      selectedIconTheme: IconThemeData(size: 24, color: PH.text),
      unselectedIconTheme: IconThemeData(size: 24, color: PH.muted),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PH.panel,
      modalBackgroundColor: PH.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: Color(0x99000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(PH.radiusSheet))),
      clipBehavior: Clip.antiAlias,
      showDragHandle: true,
      dragHandleColor: PH.lineStrong,
      dragHandleSize: Size(36, 4),
      constraints: BoxConstraints(maxWidth: PH.sheetMaxWidth),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: PH.muted,
      textColor: PH.text,
      minTileHeight: 56,
      titleTextStyle: TextStyle(fontFamily: PH.sans, fontSize: 16, fontWeight: FontWeight.w500, color: PH.text),
      subtitleTextStyle: TextStyle(fontFamily: PH.sans, fontSize: 13, height: 1.4, color: PH.muted),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(PH.radiusInner))),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 4,
      activeTrackColor: PH.ice,
      inactiveTrackColor: PH.selected,
      thumbColor: PH.text,
      overlayColor: PH.ice.withValues(alpha: 0.16),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      valueIndicatorColor: PH.panelHi,
      valueIndicatorTextStyle: statStyle(size: 13, weight: FontWeight.w500),
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? PH.bg : PH.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? PH.ice : PH.panelHi),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused) ? PH.text : PH.lineStrong),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: const WidgetStatePropertyAll(PH.panelHi),
      headingTextStyle: const TextStyle(fontFamily: PH.sans, fontSize: 13, fontWeight: FontWeight.w600, color: PH.muted),
      dataTextStyle: numStyle(size: 13, weight: FontWeight.w400),
      dataRowMinHeight: 48,
      dataRowMaxHeight: 52,
      dividerThickness: 1,
      headingRowHeight: 44,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: PH.selected, borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: PH.sans, fontSize: 13, color: PH.text, height: 1.4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      waitDuration: const Duration(milliseconds: 350),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: PH.panelHi,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusInner)),
      textStyle: PHText.body,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(PH.panelHi),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusInner))),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PH.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titleTextStyle: PHText.title,
      contentTextStyle: PHText.body,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusSheet)),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: PH.panel,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: PH.panelHi,
      rangeSelectionBackgroundColor: PH.selected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusSheet)),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
        iconColor: PH.muted, collapsedIconColor: PH.muted, shape: Border(), collapsedShape: Border()),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: PH.ice, linearTrackColor: PH.selected),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(PH.lineStrong.withValues(alpha: 0.9)),
      radius: const Radius.circular(4),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PH.selected,
      contentTextStyle: PHText.body,
      actionTextColor: PH.ice,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusInner)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PH.sunken,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(PH.radiusInner), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PH.radiusInner), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PH.radiusInner), borderSide: const BorderSide(color: PH.ice, width: 2)),
      labelStyle: const TextStyle(color: PH.muted),
      hintStyle: const TextStyle(color: PH.muted),
      // not dense: every text field stays at least 48 dp tall (tap target)
      constraints: const BoxConstraints(minHeight: 48),
    ),
  );
}

/// "Working…" of unknown length: a spinner, or a still hourglass when the
/// platform asks for no animations (reduced motion).
class BusyIndicator extends StatelessWidget {
  final double size, strokeWidth;
  const BusyIndicator({super.key, this.size = 28, this.strokeWidth = 2.5});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: MediaQuery.disableAnimationsOf(context)
            ? Icon(Icons.hourglass_empty, size: size, color: PH.muted)
            : CircularProgressIndicator(strokeWidth: strokeWidth),
      );
}

/// The app's mark: a lunar horizon arc with the Sun (amber) and Earth (blue).
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 28});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Lunar Horizon logo',
        child: RepaintBoundary(child: CustomPaint(size: Size(size, size), painter: const BrandMarkPainter())),
      );
}

/// The launcher icon (tools/make_icons.py `rounded()`), drawn live: a navy
/// rounded square, the low Sun half hidden behind a crater-rim ridge (filled
/// [PH.brandRidge] with a light rim line) and a small Earth upper right. Keep
/// the geometry in step with make_icons.py (`art()` and `RIDGE_PTS`).
/// The logo. The start-up animation (screens/intro.dart) draws it part way:
/// [ridge] how far the crater-rim ridge has been drawn from the left, [sun]
/// how far the Sun has risen behind it, [earth] Earth's scale (it pops in);
/// all 1 for the finished mark.
class BrandMarkPainter extends CustomPainter {
  final double ridge, sun, earth;
  const BrandMarkPainter({this.ridge = 1, this.sun = 1, this.earth = 1});

  /// Ridge vertices: x across the whole square, y inside the art box.
  static const _ridge = [
    (0.0, 0.70), (0.14, 0.63), (0.27, 0.655), (0.40, 0.575), (0.53, 0.615), //
    (0.66, 0.55), (0.80, 0.615), (0.92, 0.585), (1.0, 0.60),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final square = RRect.fromRectAndRadius(Offset.zero & Size(s, s), Radius.circular(s * 0.2));
    canvas.save();
    canvas.clipRRect(square);
    canvas.drawRect(Offset.zero & Size(s, s), Paint()..color = PH.panel);
    // the art box of make_icons.rounded(): x0 = 0.06 s, y0 = 0.04 s, w = 0.88 s
    final x0 = 0.06 * s, y0 = 0.04 * s, w = 0.88 * s;
    if (sun > 0) {
      // rises from below the ridge
      final rise = (1 - sun) * 0.42 * w;
      canvas.drawCircle(Offset(x0 + 0.34 * w, y0 + 0.585 * w + rise), 0.15 * w, Paint()..color = PH.sun);
    }
    if (earth > 0) {
      canvas.drawCircle(Offset(x0 + 0.74 * w, y0 + 0.27 * w), 0.085 * w * earth, Paint()..color = PH.earth);
    }
    final rim = Path()..moveTo(0, y0 + _ridge.first.$2 * w);
    for (final (fx, fy) in _ridge.skip(1)) {
      rim.lineTo(fx * s, y0 + fy * w);
    }
    final ground = Path.from(rim)
      ..lineTo(s, s)
      ..lineTo(0, s)
      ..close();
    canvas.save();
    if (ridge < 1) canvas.clipRect(Rect.fromLTWH(0, 0, s * ridge, s)); // drawn from the left
    canvas.drawPath(ground, Paint()..color = PH.brandRidge);
    canvas.drawPath(
        rim,
        Paint()
          ..color = PH.text
          ..style = PaintingStyle.stroke
          ..strokeWidth = (0.022 * w).clamp(1.0, double.infinity)
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    canvas.restore();
    canvas.restore();
    canvas.drawRRect(
        square.deflate(0.006 * s),
        Paint()
          ..color = PH.lineStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = (0.012 * s).clamp(0.75, double.infinity));
  }

  @override
  bool shouldRepaint(covariant BrandMarkPainter old) => old.ridge != ridge || old.sun != sun || old.earth != earth;
}

/// Marks any approximation in the UI (CLAUDE.md: no approximation unlabelled).
/// A quiet inset: darker tone and an info icon, no coloured bar (amber means
/// the Sun, so it is not used for chrome).
/// An approximation note (every approximation is labelled). It shows its
/// first sentence with "More" and opens to the whole text on a tap (user
/// request 2026-10-14: less text on screen); screen readers always get the
/// whole text.
class FidelityBadge extends StatefulWidget {
  final String text;

  /// Open from the start (short notes are always shown whole).
  final bool expanded;
  const FidelityBadge({super.key, required this.text, this.expanded = false});

  static const customHorizon = 'Approximate horizon: computed on this device from the LOLA 400 m DEM. Typical error vs the '
      '80 m preset masks is 0.5–1.4° (up to ~6° on sharp rims). Use for exploration, not final decisions.';

  /// [customHorizon] in a line, for lists.
  static const customHorizonShort = 'Approximate horizon (400 m DEM, computed on this device)';
  /// The first sentence of [text] (cut near 110 characters if it is longer).
  static String summaryOf(String text) {
    final t = text.trim();
    final m = RegExp(r'^(.+?[.!?])(\s|$)').firstMatch(t);
    var s = m?.group(1) ?? t;
    if (s.length > 110) {
      final cut = s.lastIndexOf(' ', 104);
      s = '${s.substring(0, cut > 40 ? cut : 104)}…';
    }
    return s;
  }

  @override
  State<FidelityBadge> createState() => _FidelityBadgeState();
}

class _FidelityBadgeState extends State<FidelityBadge> {
  late bool _open = widget.expanded;

  @override
  Widget build(BuildContext context) {
    final full = widget.text;
    final short = FidelityBadge.summaryOf(full);
    final more = short.length < full.trim().length - 1;
    final style = PHText.small.copyWith(color: PH.muted);
    final body = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(color: PH.sunken, borderRadius: BorderRadius.circular(PH.radiusInner)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline, size: 18, color: PH.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: _open || !more ? full : short),
            if (more) TextSpan(text: _open ? '  Less' : '  More', style: const TextStyle(color: PH.ice, fontWeight: FontWeight.w600)),
          ])),
        ),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        label: 'Approximation: $full',
        excludeSemantics: true,
        button: more,
        onTap: more ? () => setState(() => _open = !_open) : null,
        child: DefaultTextStyle.merge(
          style: style,
          child: more
              ? Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(PH.radiusInner),
                    onTap: () => setState(() => _open = !_open),
                    child: body,
                  ),
                )
              : body,
        ),
      ),
    );
  }
}
