// OpenBFME. GPL-3.0.
// The iOS input bridge's click logic (GodotDevice/GodotIOSTouch.h), which has no UIKit in it: run on any host.
#include "doctest.h"
#include "GodotDevice/GodotIOSTouch.h"

TEST_CASE("iPad pointer clicks retain their button through an unlabelled drag") {
    using OpenBFMEIOSTouch::pointerButtons;
    for (unsigned long button : {1ul, 2ul, 4ul}) {
        const auto pressed = pointerButtons(button, 0, 0);
        CHECK(pressed == button);
        CHECK(pointerButtons(0, pressed, 1) == button);
        CHECK(pointerButtons(0, pressed, 2) == 0);
        CHECK(pointerButtons(button, pressed, 3) == 0);
    }
}

TEST_CASE("iPad unlabelled primary click produces a complete press and release") {
    using OpenBFMEIOSTouch::pointerButtons;
    const auto pressed = pointerButtons(0, 0, 0);
    CHECK(pressed == 1);
    CHECK(pointerButtons(0, pressed, 1) == 1);
    CHECK(pointerButtons(0, pressed, 2) == 0);
    CHECK(pointerButtons(0, pressed, 3) == 0);
    CHECK(pointerButtons(0, 0, 1) == 0);
    CHECK(pointerButtons(3, 1, 0) == 3);
    CHECK(pointerButtons(2, 3, 2) == 2);
}

TEST_CASE("iPad Control click matches macOS through modifier changes and cancellation") {
    OpenBFMEIOSTouch::PointerClick click;
    CHECK(click.update(1, 0, true) == 2);
    CHECK(click.update(1, 1, false) == 2);
    CHECK(click.update(0, 1, false) == 2);
    CHECK(click.update(0, 2, false) == 0);
    CHECK(click.update(1, 0, false) == 1);
    CHECK(click.update(1, 1, true) == 1);
    CHECK(click.update(1, 3, true) == 0);
    CHECK(click.update(0, 0, true) == 2);
    CHECK(click.update(0, 2, false) == 0);
    CHECK(click.update(2, 0, false) == 2);
    CHECK(click.update(0, 1, true) == 2);
    CHECK(click.update(0, 2, true) == 0);
}

TEST_CASE("iPad double click classification matches macOS") {
    using OpenBFMEIOSTouch::pointerDoubleClick;
    CHECK(pointerDoubleClick(1, true, 1) == false);
    CHECK(pointerDoubleClick(1, true, 2) == true);
    CHECK(pointerDoubleClick(1, false, 2) == false);
    CHECK(pointerDoubleClick(1, true, 3) == false);
    CHECK(pointerDoubleClick(2, true, 2) == false);
    CHECK(pointerDoubleClick(3, true, 2) == false);
}

TEST_CASE("a mouse button told by both UIKit and GCMouse is pressed once and released when both let go") {
    OpenBFMEIOSTouch::ButtonUnion sources;
    // a right click both report: GCMouse first, then the pointer touch
    CHECK(sources.fromGameController(2) == 2);
    CHECK(sources.fromUIKit(2) == 2);
    CHECK(sources.fromGameController(0) == 2); // the touch still holds it
    CHECK(sources.fromUIKit(0) == 0);
    // a middle press that reaches the view as no touch: GCMouse alone
    CHECK(sources.fromGameController(4) == 4);
    CHECK(sources.fromGameController(0) == 0);
    // GCMouse's left button is ignored: the left button is the pointer touch's (its place, Control-click)
    CHECK(sources.fromGameController(1) == 0);
    CHECK(sources.fromUIKit(1) == 1);
    CHECK(sources.fromGameController(3) == 3);
    CHECK(sources.fromUIKit(0) == 2);
    CHECK(sources.fromGameController(0) == 0);
}
