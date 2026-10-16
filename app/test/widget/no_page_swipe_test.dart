// NoPageSwipe locks the PageView around it (PageSwipeLock) while a finger is
// down on it, also with a device's small touch slop (Android: the page used
// to win the drag).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/widgets/no_page_swipe.dart';

void main() {
  Future<PageController> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pages = PageController();
    addTearDown(pages.dispose);
    final lock = SwipeLock();
    addTearDown(lock.dispose);
    // as the Site pages do: no device drags the page while a finger is down
    final devices = {...const ScrollBehavior().dragDevices};
    lock.addListener(() {
      devices.clear();
      if (lock.value == 0) devices.addAll(const ScrollBehavior().dragDevices);
    });
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        // an Android phone's touch slop (8 dp), smaller than Flutter's default
        data: const MediaQueryData(size: Size(400, 800), gestureSettings: DeviceGestureSettings(touchSlop: 8)),
        // as the Site pages wire it
        child: PageSwipeLock(
          notifier: lock,
          child: ScrollConfiguration(
            behavior: const ScrollBehavior().copyWith(dragDevices: devices),
            child: PageView(controller: pages, children: const [
              Center(child: NoPageSwipe(child: SizedBox(key: ValueKey('kept'), width: 300, height: 300))),
              SizedBox.expand(),
            ]),
          ),
        ),
      ),
    ));
    return pages;
  }

  /// A finger drag in small steps, as a real touch screen reports it.
  Future<void> dragInSteps(WidgetTester tester, Offset from, Offset by) async {
    final g = await tester.startGesture(from, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 25; i++) {
      await g.moveBy(by / 25);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a sideways drag on it never turns the page, with a small touch slop', (tester) async {
    final pages = await pump(tester);
    await dragInSteps(tester, tester.getCenter(find.byKey(const ValueKey('kept'))), const Offset(-300, 0));
    expect(pages.page, 0);
  });

  testWidgets('a sideways drag beside it still turns the page', (tester) async {
    final pages = await pump(tester);
    await dragInSteps(tester, const Offset(200, 760), const Offset(-300, 0));
    expect(pages.page, 1);
  });

  testWidgets('the lock lets go when the finger lifts', (tester) async {
    final pages = await pump(tester);
    await dragInSteps(tester, tester.getCenter(find.byKey(const ValueKey('kept'))), const Offset(-300, 0));
    await dragInSteps(tester, const Offset(200, 760), const Offset(-300, 0));
    expect(pages.page, 1);
  });
}
