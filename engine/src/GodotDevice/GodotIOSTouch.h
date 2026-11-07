// OpenBFME. GPL-3.0.
//
// The iOS / iPadOS input bridge (GodotIOSTouch.mm): an Apple Pencil, a mouse or trackpad and a hardware keyboard on Godot's view.
// After daisyhasacat/openbfme-godot (GodotIOSTouch.h / .mm, test_ios_pointer.cpp), with the GameController additions of the other
// iOS port (a mouse's right and middle buttons through GCMouse, missing key releases through GCKeyboard).
//
// The click logic below has no UIKit in it, so the unit tests run it on any host (engine/tests/test_ios_pointer.cpp).
#pragma once

namespace OpenBFMEIOSTouch {
// The device id of the Pencil's mouse events; ordinary fingers remain Godot screen touches.
inline constexpr int PencilDevice = 1001;
// UIKit indirect-pointer touches describe a click lifetime. A zero buttonMask
// must not erase its press or release a drag before touchesEnded. Preserve an
// explicit secondary/middle mask; infer primary only for an unlabelled press.
// phase matches hooks[]: began, moved, ended, cancelled.
inline constexpr unsigned long pointerButtons(unsigned long reported, unsigned long held, int phase) {
    if (phase == 3) return 0;
    if (reported) return reported;
    if (phase == 2) return 0;
    return phase == 0 ? 1ul : held;
}
// Match Godot macOS godot_content_view.mm mouseDown/mouseUp: Control-primary
// is secondary for the entire click, even if Control is released mid-drag.
struct PointerClick {
    unsigned long nativeButtons = 0;
    bool controlPrimary = false;
    unsigned long update(unsigned long reported, int phase, bool control) {
        const auto next = pointerButtons(reported, nativeButtons, phase);
        if ((next & 1ul) && !(nativeButtons & 1ul)) controlPrimary = control;
        nativeButtons = next;
        const auto mapped = controlPrimary && (next & 1ul) ? (next & ~1ul) | 2ul : next;
        if (!(next & 1ul)) controlPrimary = false;
        return mapped;
    }
};
// macOS marks only the second primary press as a double click, not triple
// clicks or secondary clicks (godot_content_view.mm processMouseEvent).
inline constexpr bool pointerDoubleClick(int index, bool pressed, unsigned long taps) {
    return index == 1 && pressed && taps == 2;
}
// Two sources tell a mouse's buttons: the pointer touch's UIEvent.buttonMask (UIKit) and GCMouse's right and middle buttons
// (GameController), which also report a press that reaches the view as no touch at all. Godot is told the union: a button either
// source holds is pressed once and released when both let go. update() returns the buttons Godot holds after the change; the caller
// emits a press or release for each bit that differs from the previous answer.
struct ButtonUnion {
    unsigned long uikit = 0;
    unsigned long gc = 0;
    unsigned long fromUIKit(unsigned long buttons) { uikit = buttons; return uikit | gc; }
    unsigned long fromGameController(unsigned long buttons) { gc = buttons & ~1ul; return uikit | gc; } // the left button is the touch's
};
void install();
void uninstall();
}
