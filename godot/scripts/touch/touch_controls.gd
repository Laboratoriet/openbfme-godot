extends Node
## Lane IOS-2 (prototype, for the owner's review): touch controls for phones and tablets.
##
## The game itself only knows the mouse (InGameHudNode and AptMenuPlayer read Godot mouse events and give them to the SAGE input), so the
## touches are translated here into the mouse events a player would make, plus two camera gestures the mouse has no single event for.
## Nothing below changes the mouse path: on a desktop without --touch this node does nothing.
##
##   one finger, tap ............ left click (select; with the touch default of Alternate Mouse Setup the left click also orders)
##   one finger, two quick taps . double click (select all of that type on screen)
##   one finger, drag ........... left drag (a selection box; in a menu, a list or slider drag)
##   one finger, hold ........... right click (deselect / cancel) with a short vibration; on a HUD button its help instead (lane IOS-21, below)
##   two fingers, drag .......... pan the camera: the ground under the fingers stays under them
##   two fingers, pinch ......... zoom (the mouse wheel's notches)
##   two fingers, twist ......... turn the camera (lane IOS-15; past an 8 degree turn, so pinches and pans do not turn it)
##   two fingers, quick tap ..... right click at their middle
##
## Active on a mobile build (OS feature "mobile") or with `-- --touch` (to try it on a desktop with a touch screen or synthetic events).
## The thresholds are in points (DisplayServer.screen_get_scale), so they are the same physical size on any screen.
##
## Lane IOS-10 (prototype, for the owner's review), the menus and the HUD for fingers:
##   tap assist ................. a tap on no button but within ASSIST_PT of one presses that button (its centre); a tap that hits a control
##                                never moves, nor one that picks a unit / building, aims a placement, a power or a command, or lands on the
##                                radar; a tap about as near two buttons (ASSIST_TIE_PT) stays where it is. AptMenuPlayer / InGameHudNode
##                                nearest_button decide (the controls the pointer could press now). Counted in stats.assisted_taps.
##   one finger, drag on a list . scrolls the list (a mouse wheel notch per row of finger travel) instead of a press-and-drag; a drag that
##                                starts on its scroll bar still drags the bar. Menus only (over a game: while a menu has the input).
## `-- --no-tap-assist` / `-- --no-list-scroll` turn either off for a comparison.
##
## Lane IOS-21 (the owner's decision, 2026-11-03: "hold shows info"), information without a hover:
##   hold on a HUD button ....... its help box at once (no tooltip delay) for as long as the finger stays, with a lighter vibration; lifting does
##                                nothing (a preview, never a press); sliding off past SLOP_PT ends it. The HUD buttons: the Palantir's (the arc,
##                                its keys, the portrait: the selection's name and help), the side command bar, the spell book, the hero bar, the
##                                radial bubbles (InGameHudNode.touch_button_at, the clicks' own hit test with the HUD size). The world, the radar
##                                and a menu over the game keep the hold's right click. The help box shows only for a held finger (set_touch_help):
##                                the pointer a tap leaves on a button opens none. A mouse in use (IOS-14) gives the desktop's hover back.
##   two taps on an ability ..... toggle its autocast (the right press of lane AUTOCAST-1), only on a button whose right press does that
##                                (touch_button_at's "autocast": an AutoAbility power or weapon of the Palantir / side bar). Its first tap waits
##                                DOUBLE_TAP_MS for a second one before it presses (else a double tap would cast the power, or start its aiming,
##                                on the way to the toggle). Every other button keeps two taps as two presses (a bubble queues two units).
##   (production cancel ........ was the hold on a bubble (its right press); now a two-finger tap whose middle is on the bubble, the one right click
##                                left on a HUD button: an open question for the owner)
##
## Lane IOS-23 (the owner's decisions, 2026-11-03), a building's placement for fingers. While a build button waits for its site (InGameHudNode
## touch_placement_at: placing, and the finger came down on the world), a finger would hide the ghost under it, so:
##   finger down ................ the pointer, and with it the ghost (PlaceEventTranslator follows the live pointer), goes GHOST_OFFSET_PT above the
##                                fingertip (clamped into the view); valid / invalid colouring as with a mouse
##   drag ....................... the ghost follows the finger at that offset (no selection box, no rotation: the left button is not held)
##   lift after a drag .......... the ghost stays there and waits for ✓ / ✕ (lane IOS-26, below). A lift whose ghost point is on the HUD offers
##                                nothing (the ghost is under the HUD) and the placement stays
##   tap ........................ lane IOS-26: the ghost goes under the tap point (no offset: no finger is left over it) and waits for ✓ / ✕
##   hold (still finger) ........ the right click: cancels the placement; once the finger has moved, holding still no longer cancels (it can rest)
##   two-finger tap ............. the right click: cancels; a second finger during the drag stops the ghost where it is (pan / zoom / twist the camera)
##   walls ...................... Begin Wall Span: the same gesture; the span's ghost segments (PlacementIcons::updateWall, the span planner's tiles) run
##                                from the hub to the ghost's point, and ✓ builds the span to it (MSG_WALL_HUB_CONSTRUCT_SPAN)
## Rotation: retail turns the ghost with a drag after the press; on touch the drag is the position, so a placement keeps its PlacementViewAngle (an
## open question for the owner: a second finger's twist, or a rotate button). A mouse (IOS-14) keeps the desktop's placement.
##
## Lane IOS-26 (the owner's decision, 2026-11-04: "still a bit hard to not place a building accidentally"; "✓ / ✕ by the ghost"): no finger places
## a building by itself. A lift or a tap leaves the ghost at its point and shows two buttons beside it (placement_confirm.gd: ✕ left, ✓ right):
##   ✓ .......................... the left click at the ghost's point (IOS-23's lift, unchanged: the press anchors, the release places, or refuses with
##                                retail's message and BadBuildingPlacementSound; then the placement and the buttons stay). While the ghost is red
##                                (get_placement's legal code, the ghost's own tint) ✓ is dimmed, and a tap on it still asks the game, whose refusal
##                                says why. Walls: a line build skips the legality test (RW 0x83E7FE), so ✓ is never dimmed for a span
##   ✕ .......................... the right click at the ghost's point: cancels the placement (as the hold does)
##   a finger on the world ...... hides the buttons and moves the ghost again by IOS-23's rules (a drag: 60 pt above the finger; a tap: under it); they
##                                come back where it stops. Anywhere on the world, not only on the ghost: one rule, the same as the first time
##   a finger on the HUD ........ ends the wait (the HUD tap goes through as before; a new build button starts its own ghost)
##   two fingers ................ the camera moves; the ghost keeps its point on the ground (the pointer follows it, InGameHudNode.world_to_pixel); the
##                                buttons hide while the fingers are down and come back beside it. A ghost whose point leaves the view (or goes under
##                                the HUD) keeps its buttons hidden until the point is back. A second finger that comes down before the first one moved
##                                puts the ghost back where it waited (the start of a pan, not a new spot)
##   a mouse (IOS-14) ........... its first motion ends the wait: the mouse has the pointer, and a mouse click places as retail's does
## A finger on ✓ / ✕ presses it (the disc shrinks); lifting on it activates it, sliding off and lifting does nothing, a second finger cancels it.
##
## Lane IOS-36, after daisyhasacat/openbfme-godot facef81b ("Deselect iOS builders after issuing construction orders", GPL-3.0): once a ✓ was
## accepted (the placement ended and InGameHudNode.touch_placement_at's "builds" count went up: the construct order or the wall span was issued),
## builders are deselected (InGameHudNode.deselect_builders: only when every selected object is a builder), so the next finger on the world is not
## another order to the builder. A refused ✓ (the placement and the buttons stay), ✕, a hold or the game cancelling it deselect nothing; a mouse's
## placement (IOS-14, not this layer) keeps retail's selection. Daisy deselects in the engine after every placement; here only the touch layer's ✓.
## deselect_builders_after_build turns it off (an option for the owner to decide, COMBINE.md Q3).
##
## Lane IOS-35 (the owner's request, 2026-11-04: the one-finger pan of daisyhasacat/openbfme-godot as an OPTION; scheme after daisyhasacat/openbfme-godot
## 607d6406 "Add finger navigation and Pencil selection for touch devices", GPL-3.0; no code copied: Daisy's lives in the engine's InGameHudNode, ours
## here): Options > Touch > "One finger drag" (game_options.gd OpenBFMETouchDrag, set_drag_mode). "select" (the default) keeps the gestures above.
## "pan", for a finger that comes down on the battlefield (the world: not the HUD, the radar, a menu over the game) with no placement waiting:
##   one finger, drag ........... moves the camera: the ground under the finger stays under it (the two-finger pan's rule, from the touch-down point).
##                                OpenBFMEInvertDragScroll is not applied: it is the right-button drag's option, and the ground under the finger is the
##                                one direction a direct drag can have (as the two-finger pan)
##   one finger, hold, then drag  a selection box (the left press where the finger came down): held still LONG_PRESS_MS the finger is armed (a short
##                                vibration), and a drag past SLOP_PT from there is the box
##   one finger, hold, lift ..... the hold's right click, at the lift (a still hold cannot fire while held: it may still become a box)
##   one finger, tap ............ unchanged (the left click: select, or with Alternate Mouse Setup's touch default the contextual order). Daisy's e732ac15
##                                ("Prefer object selection for touch taps") makes a tap on any selectable object select it; not taken: the retail left
##                                click already selects a unit or building, and keeps the contextual orders of a tap on one (garrison, enter, repair)
##   an Apple Pencil ............ a mouse's left button (lane IOS-45: the input bridge, GodotIOSTouch.mm after daisyhasacat/openbfme-godot, makes
##                                its touches left-button mouse events, device PENCIL_DEVICE, before Godot sees them): a drag is a selection box,
##                                a tap the left click, in either mode. They never reach this layer as touches
## Unchanged in either mode: a placement's ghost drag (IOS-23 / IOS-26), the menus' list scrolling (IOS-10), a drag that starts on the HUD or the radar,
## a hold on a HUD button (its help, IOS-21), the two-finger gestures. The drag threshold stays SLOP_PT (10 pt: about Daisy's 12 px at a 720 px height on
## a 1x screen, and the same physical size on every screen).
##
## Lane IOS-40 (the owner's decision, 2026-11-05: "hold kind of works, but in most cases click once to see name/info and twice to build is better"), tap to
## preview, tap again to use. Options > Touch > "Button taps" (game_options.gd OpenBFMETouchButtonTaps, set_button_taps):
##   "costs" (the touch default) a HUD button whose press costs (touch_button_at's "costs": ControlBar::pressCosts, from the button's Command: build,
##                               recruit, upgrades, revive, castles, the spell book's purchases and powers, abilities) is previewed; every other button (stop,
##                               guard, formations, stances, rally points, gates, the portrait, the hero bar, the Palantir's keys) acts at once
##   "all" ..................... every HUD button (touch_button_at's kinds) is previewed
##   "act" ..................... every button acts at once: IOS-21's taps (the autocast wait below included)
## A previewed button:
##   first tap .................. its help box (IOS-21's hold_help, the pointer on the button) and a gold ring around it (armed_ring.gd) for ARM_MS; nothing pressed
##   second tap on it ........... within ARM_MS: its press (the left click at the button), the ring flashes and goes. On an autocast ability (touch_button_at's
##                                "autocast") a second tap within DOUBLE_TAP_MS of the first is the double tap: its autocast toggles (the right press, as
##                                IOS-21), and a later one uses it. So a quick double tap toggles, "tap, read, tap" uses; no tap ever waits for a second one
##   a finger elsewhere ......... disarms as it comes down (the ring fades, the help goes); its own gesture goes on as usual (a tap on another previewed button
##                                arms that one, a tap on the world selects ...). So do a second finger, a hold (the hold is IOS-21's preview), a drag and
##                                the time out
## A mouse in use (IOS-14) acts at once (its hover is the desktop's help); the setting changes nothing for a mouse click, which never reaches _tap.
## After a use the button stays armed (its help and ring, ARM_MS from the last tap), so every further tap is one more use: tap to see a unit, then tap,
## tap, tap queues three. A quick double tap toggles autocast only from the unarmed state (after a use, quick taps are uses); the toggle disarms.
##
## Lane IOS-37 (the owner's decisions, 2026-11-05), the touch command toolbar and two touch gaps:
##   the toolbar ................ command_toolbar.gd: a strip of round buttons along the top edge (Options > Touch > "Command toolbar",
##                                OpenBFMETouchToolbar, set_toolbar). A finger that comes down on it is the toolbar's: a tap presses the button (its command,
##                                the keyboard's way), a hold shows what it does and presses nothing (IOS-21), a hold on a control group makes the group (a
##                                ring fills, then flashes), sliding off and lifting does nothing, a second finger cancels. Shown in a game with no menu over
##                                it, hidden while a mouse is in use (the keyboard has these keys) and in the menus
##   rotating a ghost ........... while ✓ / ✕ wait (IOS-26), a two-finger twist turns the building's ghost instead of the camera (InGameHudNode.
##                                set_placement_angle); the pan and the pinch still move the camera. The ghost turns with the fingers on screen: its facing's
##                                screen direction turns by the twist, read back to the ground (any camera angle and pitch). Not for a wall span (its line
##                                is its direction). The camera's own twist is back once the placement ends
##   cancelling production ...... the armed button (IOS-40) whose right press would cancel something queued (touch_button_at's "cancel": a recruit bubble with
##                                units in its queue, a reviving hero) shows a small ✕ beside its ring (armed_ring.gd); a tap on ✕ is the button's right press,
##                                retail's cancel of one (the button stays armed: tap it to queue one more, ✕ to take one off). The two-finger tap on the
##                                bubble (IOS-21) still cancels too, and is the way with "Act at once"
##
## Lane IOS-42 (the owner, 2026-11-05: "It would be nice if you could toggle on/off and check what works best"): every touch behaviour with a switch is
## a row of Options > Touch (openbfme_options_screen.gd; game_options.gd's OpenBFMETouch* keys, apply_options below). Each default is the behaviour
## described above; each is read by the gesture that uses it, so a change applies at once, in a game too:
##   OpenBFMETouchListScroll ...... "no": a drag on a menu list is the mouse's press-and-drag (IOS-10's list scrolling off; --no-list-scroll wins)
##   OpenBFMETouchTapAssist ....... "no": a tap presses only what is under it (IOS-10's tap assist off; --no-tap-assist wins)
##   OpenBFMETouchHoldButton ...... "right": a hold on a HUD button is the right click there (IOS-2's hold), not its help (IOS-21)
##   OpenBFMETouchAutocastTap ..... "no": no double tap toggles autocast; a tap on an autocast ability presses at once (no DOUBLE_TAP_MS wait), and with
##                                  "Button taps" previewing, a quick second tap uses it. The two-finger tap on it (its right press) still toggles
##   OpenBFMETouchPlacement ....... "confirm": IOS-26's ✓ / ✕. "lift": IOS-23 as it was: lifting after a drag places at the ghost (a lift with the
##                                  ghost on the HUD places nothing), a tap places under the finger. "tap": the touch layer leaves placement alone:
##                                  a tap is the left click (it places, as a mouse click does), a drag the left drag (retail's press, turn, release)
##   OpenBFMETouchGhostAbove ...... "no": the ghost goes under the finger, not GHOST_OFFSET_PT above it (IOS-23)
##   OpenBFMETouchPlaceTwist ...... "camera": while ✓ / ✕ wait a two-finger twist turns the camera, as elsewhere (not the ghost, IOS-37)
##   OpenBFMETouchDeselectBuilders  "no": an accepted placement keeps the builders selected (IOS-36). With "lift" and "tap" the placing click counts as
##                                  the ✓ (the deselect waits for the game to take it, PLACE_WATCH_MS at most)
##   OpenBFMETouchTargeting ...... "tap": a power or ability waiting for its target is used by the next tap on the map, as before IOS-43 (no aim, no
##                                  ✓ / ✕); the banner still says what it waits for and its ✕ still cancels
## Not switches (no row): the thresholds (TAP_MAX_MS, LONG_PRESS_MS, SLOP_PT, DOUBLE_TAP_MS, TWIST_START_DEG, ARM_MS), the two-finger camera gestures,
## the vibrations, an Apple Pencil's box (IOS-35) and the mouse / keyboard bridge (IOS-14, IOS-45): a number to tune or a device's own behaviour, not a choice
## between two ways to play.
##
## Lane IOS-43 (the owner, 2026-11-05: "I don't remember how they work, and after clicking it seems like you have to place them on the map. Maybe
## incorporate something similar to building placement?"), aiming a power or a hero ability with a finger, modelled on IOS-23 / IOS-26's placement.
## While a spell book power or an ability waits for its target (InGameHudNode.touch_targeting_at: kind "location" or "object"; the unit commands that
## wait too, attack move, guard, rally point, are not powers and keep the taps):
##   the banner ................. touch_targeting.gd, at the top of the safe area under the command toolbar: "Choose where: <power>" or "Choose a target:
##                                <power>", a line saying what to do, and ✕: the game's cancel (cancel_targeting: the right click's, without a click)
##   a ground power ("location"), Options > Touch > "Aim powers" Confirm first (OpenBFMETouchTargeting = confirm, the default):
##     finger down on the map ... the pointer goes GHOST_OFFSET_PT above the fingertip (the "Above the finger" switch, as a ghost): the game draws the
##                                power's radius decal there, white where it would land and red where it would not (retail's mouse cursor); a power
##                                with no decal drawn gets touch_targeting.gd's ring of its radius, gold or red. Nothing is pressed
##     drag ..................... the decal (or ring) follows at that offset
##     lift ..................... it stays; ✓ / ✕ (IOS-26's buttons) beside it. ✓ is dimmed on a red spot
##     tap ...................... the point goes under the tap (no finger is left over it); ✓ / ✕ beside it
##     ✓ ........................ the left click at the point (the cast), when the game says it would take it; on a red spot nothing is clicked: the
##                                refusal mark (a red ring and cross) and a short vibration, and the aim waits
##     ✕ ........................ the cancel (as the banner's ✕)
##     a finger on the map ...... moves the point again (✓ / ✕ hide until it stops); on the HUD: the HUD's own tap, the wait at the point ends (the
##                                banner stays while the power waits)
##     two fingers .............. the camera; the point keeps its ground point and ✓ / ✕ come back beside it
##     hold (still finger) ...... the right click: cancels, as for a placement
##   a target power ("object"): a tap (or a drag's lift, at its offset point) on a unit or building the power can have picks it: a gold sight ring
##                                around it (following it as it moves) and ✓ / ✕ beside it; ✓ clicks it (the cast), ✕ cancels. A tap on something it
##                                cannot have, or on the ground: the refusal mark and a vibration, the aim waits. While a finger drags, the sight shows
##                                on a valid target under the offset point
##   hero abilities go the same way (their GUI command); a power with no target acts at once on its button's use (after IOS-40's tap to preview)
##   "On tap" (OpenBFMETouchTargeting = tap): the next tap on the map is the mouse's click: it uses the power at once (the pre-IOS-43 behaviour)
## A mouse in use (IOS-14) hides the banner and aims with the pointer as on a desktop; its motion ends a wait at ✓ / ✕. A desktop without touch has
## none of this.
##
## Lane IOS-14, a mouse, a trackpad and a hardware keyboard (an iPad's, the simulator's with the Mac's pointer captured, the iPhone build on an
## Apple Silicon Mac). Godot's iOS layer knows no mouse: a click reaches it as a screen touch, with no hover, no right button and no wheel.
## Lane IOS-45: the extension's input bridge (engine/src/GodotDevice/GodotIOSTouch.mm, iOS builds only; the shared design of
## daisyhasacat/openbfme-godot with this port's GCMouse buttons and key releases) splits the touches of Godot's view by UITouch.type before
## Godot sees them, so this layer only ever gets the fingers' touches:
##   the pointer ................ mouse motion as it hovers (the game's hover, tooltips and edge scrolling: kept on while a mouse is in use)
##   a click .................... mouse buttons as on a Mac (UIEvent.buttonMask, Control-click a right click), right / middle from GCMouse too
##   wheel, two-finger scroll ... InputEventPanGesture (the bridge's, as Godot's macOS layer scales it): made wheel notches here, one per
##                                WHEEL_STEP_PT of scrolling, a shorter scroll still one notch (the HUD and the menus know the wheel only)
##   a trackpad's pinch ......... InputEventMagnifyGesture: nothing reads it (as before IOS-45)
##   an Apple Pencil ............ left-button mouse events of device PENCIL_DEVICE: not "a mouse in use"; its click places and casts as a mouse's
##   keys ....................... Godot's own; a release Godot misses (the Mac host) comes from the bridge (GCKeyboard), a right modifier's fixed here
## "A mouse in use" (IOS-17, mouse_connected): a bridge pointer event (hover, click, scroll, pinch) since the last GCMouse went, never a mouse
## GameController merely lists (the iPhone Duo lists one with nothing paired). IOSInputDevices (iOS builds only) says when the last mouse goes.
## The pointer: fingers move it as before (a tap is a click where the finger is), and so does the mouse, whichever moved last.
## Keys: on the Mac host Godot's iOS layer delivers a hardware key's press but never its release (the game then holds an arrow key forever).
## Godot's presses stay as they are (they carry the layout's character); GCKeyboard's release of a key whose press Godot delivered and whose
## release Godot did not is sent as that press's release (_repair_key_releases). Where Godot's own release does come, nothing is added.

const TAP_MAX_MS := 280          # a finger down longer than this is not a tap
const LONG_PRESS_MS := 450       # a still finger held this long is a right click
const SLOP_PT := 10.0            # movement under this is still a tap / hold (points)
const DOUBLE_TAP_MS := 320       # two taps within this ...
const DOUBLE_TAP_PT := 24.0      # ... and this distance are a double click
const PINCH_STEP := 0.12         # a 12 % change of the fingers' distance is one wheel notch
const TWIST_START_DEG := 8.0     # lane IOS-15: the fingers must turn this much before the camera turns (a pinch or pan wobbles a little)
const ASSIST_PT := 9.0           # lane IOS-10: the tap assist's reach from a button's edge (points)
const ASSIST_TIE_PT := 3.0       # lane IOS-10: a second button within this much of the nearest one's distance makes the tap ambiguous: no assist
const WHEEL_STEP_PT := 12.0      # lane IOS-14: a wheel notch per this much scrolling (UIKit points); to tune from the "TOUCH IOS-14 scroll" lines
const SCROLL_END_MS := 150       # lane IOS-45: a scroll with no pan event for this long has ended (its short remainder is one notch)
const PAN_PER_PT := 0.03         # lane IOS-45: the bridge's InputEventPanGesture delta per UIKit point of scrolling (Godot macOS's scale)
const BRIDGE_DEVICE := 0x14      # lane IOS-14: the device id of the key releases made here (Godot's own keys are device 0)
const TOUCH_DEVICE := 0x15       # lane IOS-45: the device id of this layer's own mouse events (the input bridge's are device 0)
const PENCIL_DEVICE := 1001      # lane IOS-45: the device id of an Apple Pencil's mouse events (GodotIOSTouch.h PencilDevice)
const GHOST_OFFSET_PT := 60.0    # lane IOS-23 (the owner's decision): a placement's ghost sits this far above the fingertip (points)
const GHOST_INSET_PX := 2.0      # lane IOS-23: an offset point above the view's top edge is put this far inside it
const CONFIRM_POLL_MS := 100     # lane IOS-26: while ✓ / ✕ wait, the placement, the ghost's legality and its pixel are read this often ...
const CONFIRM_TRACK_MS := 600    # ... and every frame while two fingers move the camera and this long after (the zoom eases in)
const CONFIRM_RETRY_MS := 400    # lane IOS-26: a ✓ the game did not take (the placement still on after this) shows the buttons again
const CONFIRM_CLEAR_WORLD := 40.0  # lane IOS-26: the ground radius ✓ / ✕ keep clear of the ghost's point (a farm's footprint: the Mac stand-in's
                                   # GondorFarm ghost is ~125 px half wide at ~3.5 px per world unit); the HUD has no footprint query
const CONFIRM_SIDE_MAX_PT := 140.0 # ... but never farther than this from the ghost (zoomed far in, a building is bigger than the view's middle)
const ARM_MS := 3000             # lane IOS-40 (the owner's "~3 s"): a first tap's arm window
const TAPS_COSTS := "costs"      # lane IOS-40: OpenBFMETouchButtonTaps' values
const TAPS_ALL := "all"
const TAPS_ACT := "act"

const PlacementConfirm := preload("res://scripts/touch/placement_confirm.gd")
const ArmedRing := preload("res://scripts/touch/armed_ring.gd")
const CommandToolbar := preload("res://scripts/touch/command_toolbar.gd")
const TOOLBAR_POLL_MS := 250     # lane IOS-37: the toolbar's place, visibility and button states are read this often

enum Gesture { NONE, PENDING, DRAG, HELD, TWO, SCROLL, INFO, PLACE, CONFIRM, PAN, ARMED, TOOLBAR, UNQUEUE, AIM, AIM_CONFIRM, AIM_CANCEL }
# INFO: lane IOS-21, a finger held on a HUD button shows its help; PLACE: lane IOS-23, a finger drags a building's ghost; CONFIRM: lane IOS-26, a finger
# on ✓ / ✕; PAN: lane IOS-35, one finger moves the camera; ARMED: lane IOS-35, a held finger whose drag is a selection box (its lift the right click);
# TOOLBAR: lane IOS-37, a finger on the command toolbar; UNQUEUE: lane IOS-37, a finger on the armed button's ✕ (the production cancel); AIM: lane IOS-43,
# a finger aims a power; AIM_CONFIRM: lane IOS-43, a finger on the aim's ✓ / ✕; AIM_CANCEL: lane IOS-43, a finger on the banner's ✕
const DRAG_SELECT := "select"    # lane IOS-35: OpenBFMETouchDrag's values
const DRAG_PAN := "pan"
const PLACE_CONFIRM := "confirm" # lane IOS-42: OpenBFMETouchPlacement's values
const PLACE_LIFT := "lift"
const PLACE_TAP := "tap"
const TARGET_CONFIRM := "confirm" # lane IOS-43: OpenBFMETouchTargeting's values
const TARGET_TAP := "tap"
const AIM_POLL_MS := 100         # lane IOS-43: while a power waits, the HUD is asked this often (every frame while a finger aims or the camera moves) ...
const AIM_IDLE_POLL_MS := 250    # ... and this often while none waits (a power started by a key or a mouse)
const TouchTargeting := preload("res://scripts/touch/touch_targeting.gd")
const PLACE_WATCH_MS := 1500     # lane IOS-42: how long a "lift" or "tap" placement's click waits for the game to take it (the builders' deselect)

var active := false
var _gesture := Gesture.NONE
var _fingers := {}               # index -> {"start": Vector2, "pos": Vector2, "at": int}
var _first := -1                 # the finger of a one-finger gesture
var _two_start_ms := 0
var _two_moved := false
var _pinch_base := 0.0           # the fingers' distance at the last wheel notch
var _last_centroid := Vector2.ZERO
var _twist_base := 0.0           # lane IOS-15: the fingers' angle at the start of the two-finger gesture, then at the last turn
var _twisting := false
var _last_tap_ms := -100000
var _last_tap_pos := Vector2(-1000, -1000)
var _hud: Node = null            # the game's InGameHudNode while a game is on screen
var _menus: Node = null          # lane IOS-10: the shell's AptMenuPlayer (the menus' tap assist and lists)
var _scale := 1.0                # pixels per point
var tap_assist := true           # lane IOS-10
var list_scroll := true          # lane IOS-10
var _scroll_at := Vector2.ZERO   # lane IOS-10: where the list drag began (the wheel's pointer stays there)
var _scroll_anchor := 0.0        # the finger's stage y at the last notch
var _scroll_row := 0.0           # stage pixels of finger travel per notch (the list's row height)
var stats := {"taps": 0, "double_taps": 0, "drags": 0, "holds": 0, "pans": 0, "zoom_notches": 0, "two_finger_taps": 0, "twists": 0, "assisted_taps": 0,
	"list_scrolls": 0, "pointer_events": 0, "mouse_buttons": 0, "wheel_notches": 0, "repaired_key_releases": 0, "infos": 0, "autocast_taps": 0,
	"waited_taps": 0, "place_drags": 0, "place_lifts": 0, "place_lifts_on_hud": 0, "place_taps": 0, "place_confirms": 0, "place_cancels": 0,
	"finger_pans": 0, "box_arms": 0, "pencil_presses": 0, "place_accepted": 0, "builder_deselects": 0, "arms": 0, "armed_uses": 0, "disarms": 0,
	"toolbar_taps": 0, "toolbar_helps": 0, "groups_made": 0, "ghost_turns": 0, "queue_cancels": 0,
	"aim_starts": 0, "aim_drags": 0, "aim_lifts": 0, "aim_taps": 0, "aim_lifts_on_hud": 0, "aim_fires": 0, "aim_cancels": 0, "aim_refused": 0}
var drag_mode := DRAG_SELECT     # lane IOS-35: OpenBFMETouchDrag (set_drag_mode)
var button_taps := TAPS_COSTS    # lane IOS-40: OpenBFMETouchButtonTaps (set_button_taps)
var _armed := {}                 # lane IOS-40: the armed button: {"key", "name", "until" (msec), "tapped" (msec of the first tap)}
var _ring: CanvasLayer = null    # lane IOS-40: armed_ring.gd, made the first time it is needed
var toolbar_enabled := false     # lane IOS-37: OpenBFMETouchToolbar (set_toolbar); IOS-44: off by default
var _toolbar: CanvasLayer = null # lane IOS-37: command_toolbar.gd, made with the first game HUD
var _tb_id := ""                 # lane IOS-37: the toolbar button a TOOLBAR gesture's finger pressed ("" slid off)
var _tb_done := false            # its hold acted (the help shown, a group made): the lift does nothing
var _toolbar_poll_ms := 0
var _cancel_poll_ms := 0         # lane IOS-37: the armed button's ✕ is checked this often (its queue changes as units come out)
var _pan_world := false          # lane IOS-35: in pan mode the one-finger gesture began on the battlefield (a drag pans, a hold arms the box)
var _pan_last := Vector2.ZERO    # lane IOS-35: the finger's pixel at the last camera step
var _placing := false            # lane IOS-23: the one-finger gesture began on the world while a placement waited for its site (the ghost is offset)
var _confirm: CanvasLayer = null # lane IOS-26: placement_confirm.gd, made the first time it is needed
var _confirming := false         # lane IOS-26: a placement's ghost waits for ✓ / ✕ at _ghost_px
var _ghost_px := Vector2.INF     # its window pixel (the pointer is kept there)
var _anchor := Vector2.INF       # its ground point (INF: the HUD could not say; the ghost then keeps its pixel)
var _confirm_line := false       # a wall span (✓ never dimmed)
var _confirm_poll_ms := 0
var _track_until := 0
var _committed_ms := -1          # ✓ tapped on a legal ghost: the buttons went; they come back if the placement is still on CONFIRM_RETRY_MS later
var _pressed := ""               # the button a CONFIRM gesture's finger pressed
var deselect_builders_after_build := true  # lane IOS-36: an accepted ✓ deselects the builders (IOS-42: OpenBFMETouchDeselectBuilders)
var _builds_at_confirm := -1     # lane IOS-36: touch_placement_at's "builds" when ✓ was last tapped (-1: no ✓ waiting, or an extension without it)
var placement_mode := PLACE_CONFIRM  # lane IOS-42: OpenBFMETouchPlacement
var ghost_above := true          # lane IOS-42: OpenBFMETouchGhostAbove (IOS-23's GHOST_OFFSET_PT)
var hold_shows_info := true      # lane IOS-42: OpenBFMETouchHoldButton "info" (IOS-21); false: "right", IOS-2's right click
var twist_turns_ghost := true    # lane IOS-42: OpenBFMETouchPlaceTwist "building" (IOS-37); false: "camera"
var autocast_double_tap := true  # lane IOS-42: OpenBFMETouchAutocastTap (IOS-21 / IOS-40)
var _no_tap_assist_flag := false # lane IOS-42: --no-tap-assist / --no-list-scroll win over the options for the run
var _no_list_scroll_flag := false
var _place_watch_until := 0      # lane IOS-42: a "lift" / "tap" placement's click waits until then for the game to take it (_watch_placement)
var _tap_placing := false        # lane IOS-42: "tap": the finger came down on the world while a placement waited (its click places, as a mouse's)
var _tap_place_builds := -1      # ... and touch_placement_at's "builds" then (-1: an extension without it)
var targeting_mode := TARGET_CONFIRM  # lane IOS-43: OpenBFMETouchTargeting
var _aim_ui: CanvasLayer = null  # lane IOS-43: touch_targeting.gd (the banner, the ring, the sight), made the first time a power waits
var _aim_confirm: CanvasLayer = null  # lane IOS-43: its ✓ / ✕ (placement_confirm.gd, as IOS-26's)
var _aim_key := ""               # the waiting power (source | button | power; "" none), as the last poll saw it
var _aim_info := {}              # the HUD's touch_targeting_at at the last poll
var _aim_poll_ms := 0
var _aiming := false             # the one-finger gesture began on the map while a power waited (Confirm first): the pointer is the aim, offset
var _aim_live := Vector2.INF     # where that finger's aim is (window pixels)
var _aim_waiting := false        # ✓ / ✕ wait at _aim_px
var _aim_px := Vector2.INF       # the aim's pixel (a ground power: its ground point's; a target power: its target's middle)
var _aim_anchor := Vector2.INF   # a ground power's ground point (INF: the HUD could not say; the aim keeps its pixel)
var _aim_object := 0             # a target power's target (0: none)
var _aim_committed_ms := -1      # ✓ clicked: the buttons went; they come back if the power still waits CONFIRM_RETRY_MS later
var _aim_track_until := 0        # the camera may still ease after a two-finger gesture: the aim follows every frame until then
var _aim_pressed := ""           # the button an AIM_CONFIRM gesture's finger pressed
var _waiting := {}               # lane IOS-21: a tap on an autocast ability waiting for a second one: {"at": the press point, "due": msec, "second":
                                 # a finger came down on it in time (its tap is the second, however long it stays)}
var _touch_help := -1            # lane IOS-21: the touch help the HUD was last given (-1: none yet)
var _devices: RefCounted = null  # lane IOS-45: the extension's IOSInputDevices (iOS builds only): the input bridge is on, and which mice are there
var _mouse := false              # lane IOS-14: a mouse or trackpad is in use (mouse_connected, read four times a second)
var _pointer_seen := false       # lane IOS-45: a bridge pointer event came since the last mouse went (IOS-17)
var _mice := 0                   # lane IOS-45: GCMouse's count at the last look
var _wheel_acc := 0.0           # lane IOS-14: scrolling not yet a whole notch (points)
var _wheel_notches := 0         # notches of the scroll gesture in progress
var _wheel_logged := 0
var _scroll_ms := 0              # lane IOS-45: the last pan event (a scroll's end is a pause: the pan gesture says no end)
var _scroll_pos := Vector2.ZERO  # ... and where it was
var _keys_down := {}             # lane IOS-14: physical keycode -> Godot's press of it whose release Godot has not delivered


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--gpu-probe"):
		add_child(preload("res://scripts/touch/gpu_probe.gd").new()) # lane IOS-7: frame cost on any platform
	active = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")
	set_process(active)
	set_process_input(active)
	if not active:
		return
	Input.emulate_mouse_from_touch = false  # this node makes the mouse events; Godot's own translation would make a second set
	_scale = maxf(1.0, DisplayServer.screen_get_scale())
	_no_tap_assist_flag = OS.get_cmdline_user_args().has("--no-tap-assist")
	_no_list_scroll_flag = OS.get_cmdline_user_args().has("--no-list-scroll")
	tap_assist = not _no_tap_assist_flag
	list_scroll = not _no_list_scroll_flag
	print("TOUCH controls on (%s), %.1f px per point" % ["mobile" if OS.has_feature("mobile") else "--touch", _scale])
	print("TOUCH arguments: engine %s, game %s" % [OS.get_cmdline_args(), OS.get_cmdline_user_args()])
	print("TOUCH tap assist %s (%.0f pt), list scrolling %s, twist turns the camera (IOS-15)" % ["on" if tap_assist else "off", ASSIST_PT, "on" if list_scroll else "off"])
	if ClassDB.class_exists("IOSInputDevices"):
		_devices = ClassDB.instantiate("IOSInputDevices")
		var status: Dictionary = _devices.status()
		_mice = int(status.get("mice", 0))
		print("TOUCH IOS-45 input bridge on (the extension's GodotIOSTouch.mm): %s" % status)
		get_tree().root.window_input.connect(_on_window_input)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--touch-selftest="):
			var test: Node = preload("res://scripts/touch/touch_selftest.gd").new()
			add_child(test)
			test.start(self, a.trim_prefix("--touch-selftest="))


func is_active() -> bool:
	return active


## lane IOS-35: OpenBFMETouchDrag as game_options.gd applies it: "select" (a one-finger drag is a selection box) or "pan" (it moves the camera). Kept on a
## desktop without touch too, where nothing reads it
func set_drag_mode(mode: String) -> void:
	var m := DRAG_PAN if mode == DRAG_PAN else DRAG_SELECT
	if m != drag_mode and active:
		print("TOUCH IOS-35 one finger drag: %s" % m)
	drag_mode = m


## lane IOS-40: OpenBFMETouchButtonTaps as game_options.gd applies it: "costs" (preview what costs), "all" (preview every HUD button) or "act" (act at once)
func set_button_taps(mode: String) -> void:
	var m := mode if mode in [TAPS_COSTS, TAPS_ALL, TAPS_ACT] else TAPS_COSTS
	if m != button_taps and active:
		print("TOUCH IOS-40 button taps: %s" % m)
	button_taps = m
	if m == TAPS_ACT:
		_disarm("act at once")


## lane IOS-37: OpenBFMETouchToolbar as game_options.gd applies it
func set_toolbar(on: bool) -> void:
	if on != toolbar_enabled and active:
		print("TOUCH IOS-37 command toolbar: %s" % ("on" if on else "off"))
	toolbar_enabled = on
	_toolbar_poll_ms = 0


## lane IOS-42: Options > Touch as game_options.gd applies it (`values`: Options.ini's text, game_options.gd current()). Every switch is read by the gesture
## that uses it, so each applies at once; a key `values` lacks keeps its default. Kept on a desktop without touch too, where nothing reads them
func apply_options(values: Dictionary) -> void:
	set_drag_mode(str(values.get("OpenBFMETouchDrag", DRAG_SELECT)))
	set_button_taps(str(values.get("OpenBFMETouchButtonTaps", TAPS_COSTS)))
	set_toolbar(str(values.get("OpenBFMETouchToolbar", "no")) == "yes")
	var was := switches()
	list_scroll = str(values.get("OpenBFMETouchListScroll", "yes")) == "yes" and not _no_list_scroll_flag
	tap_assist = str(values.get("OpenBFMETouchTapAssist", "yes")) == "yes" and not _no_tap_assist_flag
	hold_shows_info = str(values.get("OpenBFMETouchHoldButton", "info")) != "right"
	autocast_double_tap = str(values.get("OpenBFMETouchAutocastTap", "yes")) == "yes"
	var place := str(values.get("OpenBFMETouchPlacement", PLACE_CONFIRM))
	placement_mode = place if place in [PLACE_CONFIRM, PLACE_LIFT, PLACE_TAP] else PLACE_CONFIRM
	ghost_above = str(values.get("OpenBFMETouchGhostAbove", "yes")) == "yes"
	twist_turns_ghost = str(values.get("OpenBFMETouchPlaceTwist", "building")) != "camera"
	deselect_builders_after_build = str(values.get("OpenBFMETouchDeselectBuilders", "yes")) == "yes"
	var aim := str(values.get("OpenBFMETouchTargeting", TARGET_CONFIRM))
	targeting_mode = aim if aim in [TARGET_CONFIRM, TARGET_TAP] else TARGET_CONFIRM
	if targeting_mode != TARGET_CONFIRM:
		_end_aim_wait()  # lane IOS-43: a point waiting for ✓ / ✕ goes (the power still waits); the next tap uses it
	_aim_poll_ms = 0  # the banner's line says the new way at once
	if placement_mode != PLACE_CONFIRM:
		_end_confirm()  # a ghost waiting for ✓ / ✕ stays where it is (the placement goes on); the next finger places by the new mode
	if not autocast_double_tap:
		_press_waiting()  # a tap waiting for its second presses now
	var now := switches()
	if now != was and active:
		print("TOUCH IOS-42 switches: %s" % JSON.stringify(now))


## lane IOS-42: the Touch tab's switches in effect (the log line, the self-test, the tests)
func switches() -> Dictionary:
	return {"list_scroll": list_scroll, "tap_assist": tap_assist, "hold": "info" if hold_shows_info else "right", "autocast_double_tap": autocast_double_tap,
		"placement": placement_mode, "ghost_above": ghost_above, "twist": "building" if twist_turns_ghost else "camera",
		"deselect_builders": deselect_builders_after_build, "targeting": targeting_mode}


## lane IOS-15: a mouse or trackpad is in use (a Mac running the iPhone build has one). IOS-17: only once its pointer showed itself (hovered,
## clicked): the iPhone Duo lists a GameController mouse with nothing paired, which switched touch play to the desktop's right-click orders
func mouse_connected() -> bool:
	return _devices != null and _pointer_seen


## lane IOS-17: the edge scrolling a game gets from the player's option (game_options.gd view_options, and here when a mouse comes or goes). The
## option's "retail" scrolls in a full-screen window, which Godot's iOS window always is: on touch it is off until a mouse is in use, as a finger
## near an edge (the Palantir's buttons sit at the bottom edge) is not a wish to scroll. "always" / "off" stay the player's
func edge_scroll_mode(option: String) -> String:
	_edge_option = option
	if not active or option != "retail":
		return option
	return "retail" if _mouse else "off"


var _edge_option := "retail"  # lane IOS-17: the player's OpenBFMEEdgeScroll as game_options.gd last applied it
var _mouse_check_ms := 0      # lane IOS-17: the bridge's status is read four times a second, not every frame


var _logged_inputs := 0  # lane IOS-14: the first input events of a mobile run are logged (what the device delivers: keys, touches, mouse)


func _input(event: InputEvent) -> void:
	if OS.has_feature("mobile") and _logged_inputs < 3000 and not event is InputEventScreenDrag and not event is InputEventMouseMotion:
		_logged_inputs += 1
		print("TOUCH INPUT %d ms: %s" % [Time.get_ticks_msec(), event.as_text() if not event is InputEventKey else "key %s physical %s pressed %s echo %s" % [
			OS.get_keycode_string((event as InputEventKey).keycode), OS.get_keycode_string((event as InputEventKey).physical_keycode),
			(event as InputEventKey).pressed, (event as InputEventKey).echo]])
	if event is InputEventScreenTouch:
		_touch(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_drag(event)
		get_viewport().set_input_as_handled()
	elif _devices != null:
		_bridge_event(event)


var _status_ms := 0           # lane IOS-14: the bridge's counters are logged when they change (at most every 10 s)
var _status_last := ""


func _process(_delta: float) -> void:
	if _devices != null:
		_poll_devices()
		if Time.get_ticks_msec() - _status_ms > 10000:
			_status_ms = Time.get_ticks_msec()
			var now := JSON.stringify(_bridge_status())
			if now != _status_last:
				_status_last = now
				print("TOUCH IOS-45 status: ", now)
	if not _waiting.is_empty() and Time.get_ticks_msec() >= int(_waiting.due) and not _waiting.get("second", false):
		_press_waiting()  # lane IOS-21: no second tap came: the first one's press
	if not _armed.is_empty() and Time.get_ticks_msec() >= int(_armed.until) and _gesture == Gesture.NONE:
		_disarm("time out")  # lane IOS-40: the arm window ran out
	if Time.get_ticks_msec() - _toolbar_poll_ms >= TOOLBAR_POLL_MS:
		_toolbar_poll_ms = Time.get_ticks_msec()
		_update_toolbar()
	if not _armed.is_empty() and Time.get_ticks_msec() - _cancel_poll_ms >= TOOLBAR_POLL_MS and _gesture != Gesture.UNQUEUE:
		_cancel_poll_ms = Time.get_ticks_msec()
		_update_cancel()  # lane IOS-37: the ✕ follows the armed button's queue
	if _gesture == Gesture.TOOLBAR and not _tb_done and _tb_id != "" and _fingers.has(_first):
		_toolbar_hold(Time.get_ticks_msec() - int(_fingers[_first].at))
	if _confirming:
		_poll_confirm(Time.get_ticks_msec())
	if _place_watch_until > 0:
		_poll_placement_watch(Time.get_ticks_msec())
	_poll_aim(Time.get_ticks_msec())  # lane IOS-43
	# the hold: a still finger that stays down becomes a right click while it is still down (the player feels it fire); lane IOS-21: on a HUD button
	# it shows the button's help instead, until the finger lifts (lane IOS-42: unless Hold a button is "Right-click")
	if _gesture == Gesture.PENDING and _fingers.has(_first) and Time.get_ticks_msec() - int(_fingers[_first].at) >= LONG_PRESS_MS:
		var at: Vector2 = _fingers[_first].pos
		_press_waiting()
		_disarm("hold")  # lane IOS-40: a hold is IOS-21's own preview (on the armed button too); it never uses the button
		var button := _hud_button(at) if hold_shows_info else {}
		if not button.is_empty():
			_move(button.position)  # the pointer on the button (the tap assist's point): the help box's provider is the button under it
			_hud.hold_help(true)
			Input.vibrate_handheld(10)
			_gesture = Gesture.INFO
			stats.infos += 1
			return
		if _pan_world:
			# lane IOS-35: armed: a drag from here is a selection box, a lift the right click (it cannot fire now: the finger may still drag)
			Input.vibrate_handheld(15)
			_gesture = Gesture.ARMED
			stats.box_arms += 1
			return
		_click(MOUSE_BUTTON_RIGHT, at)
		Input.vibrate_handheld(15)
		_gesture = Gesture.HELD
		stats.holds += 1
		_end_confirm()  # lane IOS-26: the hold cancelled the placement the buttons waited on
		_end_aim_wait()  # lane IOS-43: and a power's aim (its right click cancelled the power)


func _touch(e: InputEventScreenTouch) -> void:
	var now := Time.get_ticks_msec()
	if e.pressed:
		_fingers[e.index] = {"start": e.position, "pos": e.position, "at": now}
		if not _waiting.is_empty() and (_fingers.size() > 1 or e.position.distance_to(_waiting.at) > DOUBLE_TAP_PT * _scale):
			_press_waiting()  # lane IOS-21: a finger elsewhere is no second tap: the waiting press goes first
		elif not _waiting.is_empty() and now <= int(_waiting.due):
			_waiting["second"] = true  # its tap toggles the autocast; a hold or a drag of it presses the waiting tap first
		if not _armed.is_empty() and (_fingers.size() > 1 or _button_key(_hud_button(e.position)) != str(_armed.key)) \
				and not (_fingers.size() == 1 and _ring != null and _ring.cancel_hit(e.position)):
			_disarm("finger elsewhere")  # lane IOS-40: a finger elsewhere (or a second one) disarms before its own gesture (the pointer, and the help, move with it)
		match _fingers.size():
			1:
				_gesture = Gesture.PENDING
				_first = e.index
				# lane IOS-37: a finger on the command toolbar is the toolbar's (nothing reaches the game until it acts)
				var tb: String = _toolbar.hit(e.position) if _toolbar != null else ""
				if tb != "":
					_gesture = Gesture.TOOLBAR
					_tb_id = tb
					_tb_done = false
					_toolbar.set_pressed(tb)
					return
				# lane IOS-37: a finger on the armed button's ✕ presses it
				if _ring != null and not _armed.is_empty() and _ring.cancel_hit(e.position):
					_gesture = Gesture.UNQUEUE
					_ring.set_cancel_pressed(true)
					return
				# lane IOS-26: a finger on ✓ / ✕ presses it; the pointer (the ghost) stays where it is
				var on: String = _confirm.hit(e.position) if _confirming else ""
				if on != "":
					_gesture = Gesture.CONFIRM
					_pressed = on
					_confirm.set_pressed(on)
					return
				# lane IOS-43: a finger on the banner's ✕, or on the aim's ✓ / ✕, presses it; the pointer (the aim) stays where it is
				if _aim_ui != null and _aim_ui.cancel_hit(e.position):
					_gesture = Gesture.AIM_CANCEL
					_aim_ui.set_cancel_pressed(true)
					return
				var aim_on: String = _aim_confirm.hit(e.position) if _aim_waiting and _aim_confirm != null else ""
				if aim_on != "":
					_gesture = Gesture.AIM_CONFIRM
					_aim_pressed = aim_on
					_aim_confirm.set_pressed(aim_on)
					return
				_placing = _placement_drag_at(e.position)
				_tap_placing = _tap_placement_at(e.position)  # lane IOS-42: "Place on tap": this finger's click (or drag) places
				_aiming = not _placing and not _tap_placing and _aim_drag_at(e.position)  # lane IOS-43
				_pan_world = drag_mode == DRAG_PAN and not _placing and not _tap_placing and not _aiming \
					and _on_battlefield(e.position)  # IOS-35
				if _confirming:
					if _placing:
						_confirm.hide_now()  # the finger moves the ghost again; the buttons come back where it stops
						_committed_ms = -1
					else:
						_end_confirm()  # a finger on the HUD (or a menu over the game) ends the wait
				if _aim_waiting:
					if _aiming:
						_aim_confirm.hide_now()  # lane IOS-43: the finger aims again; the buttons come back where it stops
						_aim_committed_ms = -1
					else:
						_end_aim_wait()  # a finger on the HUD ends the wait at the point (the power still waits: the banner stays)
				# the pointer goes where the finger is (the game's hover, the cursor's picture); lane IOS-23: a placement's ghost above it; lane IOS-43:
				# a power's aim too
				_aim_live = ghost_point(e.position) if _aiming else Vector2.INF
				_move(ghost_point(e.position) if _placing or _aiming else e.position)
			2:
				_end_info()
				if _gesture == Gesture.TOOLBAR:
					_end_toolbar_press()  # lane IOS-37: a second finger cancels the toolbar's press
				elif _gesture == Gesture.UNQUEUE:
					_ring.set_cancel_pressed(false)
				if _gesture == Gesture.DRAG:
					_button(MOUSE_BUTTON_LEFT, false, _fingers[_first].pos)  # a second finger ends the drag where it is
				# (a list scroll just stops: it pressed nothing)
				# lane IOS-26: two fingers move the camera; the ghost keeps its ground point and the buttons wait for the fingers to lift
				if _gesture == Gesture.CONFIRM:
					_confirm.set_pressed("")
				elif _gesture == Gesture.PENDING and _placing and _confirming:
					_move(_ghost_px)  # the first finger had not moved: the start of a pan, not a new spot; the ghost goes back
				elif _gesture == Gesture.PLACE:
					_offer_confirm(ghost_point(_fingers[_first].pos), false)  # the drag stops the ghost here; ✓ / ✕ after the camera gesture
				# lane IOS-43: the same for a power's aim
				if _gesture == Gesture.AIM_CONFIRM:
					_aim_confirm.set_pressed("")
				elif _gesture == Gesture.AIM_CANCEL:
					_aim_ui.set_cancel_pressed(false)
				elif _gesture == Gesture.PENDING and _aiming and _aim_waiting:
					_move(_aim_px)
				elif _gesture == Gesture.AIM:
					_offer_aim(ghost_point(_fingers[_first].pos), false)
				_aim_live = Vector2.INF
				if _aim_waiting:
					_aim_confirm.hide_now()
				if _confirming:
					_confirm.hide_now()
				_gesture = Gesture.TWO
				_two_start_ms = now
				_two_moved = false
				_pinch_base = _distance()
				_last_centroid = _centroid()
				_twist_base = _finger_angle()
				_twisting = false
		return
	if not _fingers.has(e.index):
		return
	_fingers[e.index].pos = e.position
	var camera_gesture := _gesture == Gesture.TWO or _gesture == Gesture.HELD
	match _gesture:
		Gesture.PENDING when _aiming:
			_offer_aim(e.position)  # lane IOS-43: a tap puts the aim under the tap point and waits for ✓ / ✕ (or picks the target under it)
			stats.aim_taps += 1
		Gesture.AIM:
			if _offer_aim(ghost_point(e.position)):  # lane IOS-43: lifting leaves the aim at the offset point and waits for ✓ / ✕
				stats.aim_lifts += 1
		Gesture.AIM_CONFIRM:
			if _aim_confirm.hit(e.position) == _aim_pressed:  # lifted on the button it pressed
				if _aim_pressed == "build":
					_aim_fire()
				else:
					_aim_cancel()
			if is_instance_valid(_aim_confirm):
				_aim_confirm.set_pressed("")
			_aim_pressed = ""
		Gesture.AIM_CANCEL:
			if _aim_ui.cancel_hit(e.position):
				_aim_cancel()
			_aim_ui.set_cancel_pressed(false)
		Gesture.PENDING:
			if _placing:
				if placement_mode == PLACE_LIFT:
					_place_now(e.position)  # lane IOS-42 "Place when you lift": IOS-23's tap, the building under the tap point at once
				else:
					_offer_confirm(e.position)  # lane IOS-26: a tap puts the ghost under the tap point and waits for ✓ / ✕
				stats.place_taps += 1
			else:
				_tap(e.position, now)  # up before the hold fired and without moving: a tap
				if _tap_placing:
					_watch_placement(_tap_place_builds)  # lane IOS-42 "Place on tap": the left click placed (or the game refused it)
		Gesture.DRAG:
			_button(MOUSE_BUTTON_LEFT, false, e.position)
			if _tap_placing:
				_watch_placement(_tap_place_builds)  # lane IOS-42 "Place on tap": retail's press, turn and release placed
		Gesture.PLACE:
			if placement_mode == PLACE_LIFT:
				if _place_now(ghost_point(e.position)):  # lane IOS-42 "Place when you lift": IOS-23's lift places at the ghost
					stats.place_lifts += 1
			elif _offer_confirm(ghost_point(e.position)):  # lane IOS-26: lifting leaves the ghost there and waits for ✓ / ✕
				stats.place_lifts += 1
		Gesture.CONFIRM:
			if _confirm.hit(e.position) == _pressed:  # lifted on the button it pressed (sliding off and lifting does nothing)
				if _pressed == "build":
					_confirm_build()
				else:
					_confirm_cancel()
			if is_instance_valid(_confirm):
				_confirm.set_pressed("")
			_pressed = ""
		Gesture.INFO:
			_end_info()  # lane IOS-21: lifting ends the preview; nothing is pressed
		Gesture.TOOLBAR:
			# lane IOS-37: lifted on the button it pressed, before its hold acted: the button's command
			if not _tb_done and _tb_id != "" and _toolbar.hit(e.position) == _tb_id:
				var ok: bool = _toolbar.activate(_tb_id)
				stats.toolbar_taps += 1
				print("TOUCH IOS-37 toolbar %s: %s" % [_tb_id, "sent" if ok else "nothing (disabled, or no key)"])
			_end_toolbar_press()
		Gesture.UNQUEUE:
			if _ring.cancel_hit(e.position):
				_unqueue()
			_ring.set_cancel_pressed(false)
		Gesture.ARMED:
			_click(MOUSE_BUTTON_RIGHT, e.position)  # lane IOS-35: an armed finger lifted without a drag: the hold's right click
			stats.holds += 1
		Gesture.TWO:
			if _fingers.size() == 2 and not _two_moved and now - _two_start_ms <= TAP_MAX_MS:
				_click(MOUSE_BUTTON_RIGHT, _centroid())
				stats.two_finger_taps += 1
				_end_confirm()  # lane IOS-26: the two-finger tap cancelled the placement
				_end_aim_wait()  # lane IOS-43: and a power's aim
	_fingers.erase(e.index)
	if _fingers.is_empty():
		_gesture = Gesture.NONE
		_first = -1
		_placing = false
		_tap_placing = false
		_pan_world = false
		_pressed = ""
		_aiming = false
		_aim_live = Vector2.INF
		_aim_poll_ms = 0  # lane IOS-43: the HUD is asked at once (a tap may have started a power, or used one)
		if camera_gesture and _confirming:
			_track_until = now + CONFIRM_TRACK_MS  # lane IOS-26: the camera may still ease (a zoom); the buttons come back beside the ghost
			_follow_anchor(true)
		if camera_gesture and _aim_waiting:
			_aim_track_until = now + CONFIRM_TRACK_MS  # lane IOS-43: as for a ghost
			_follow_aim(true)
	elif _gesture == Gesture.TWO:
		_gesture = Gesture.HELD  # one finger of two lifted: nothing more until both are up (no surprise click or box)


func _drag(e: InputEventScreenDrag) -> void:
	if not _fingers.has(e.index):
		return
	_fingers[e.index].pos = e.position
	match _gesture:
		Gesture.PENDING when e.index == _first and _aiming:
			# lane IOS-43: the aim follows the finger at its offset from the first move; past the slop it is an aim drag (no tap, no hold)
			_aim_live = ghost_point(e.position)
			_move(_aim_live)
			if e.position.distance_to(_fingers[e.index].start) > SLOP_PT * _scale:
				_press_waiting()
				_disarm("drag")
				_gesture = Gesture.AIM
				stats.aim_drags += 1
		Gesture.AIM:
			if e.index == _first:
				_aim_live = ghost_point(e.position)
				_move(_aim_live)
		Gesture.AIM_CONFIRM:
			if e.index == _first:
				_aim_confirm.set_pressed(_aim_pressed if _aim_confirm.hit(e.position) == _aim_pressed else "")
		Gesture.AIM_CANCEL:
			if e.index == _first:
				_aim_ui.set_cancel_pressed(_aim_ui.cancel_hit(e.position))
		Gesture.PENDING:
			if e.index == _first and _placing:
				# lane IOS-23: the ghost follows the finger at its offset from the first move; past the slop it is a placement drag (no tap, no hold)
				_move(ghost_point(e.position))
				if e.position.distance_to(_fingers[e.index].start) > SLOP_PT * _scale:
					_press_waiting()
					_gesture = Gesture.PLACE
					stats.place_drags += 1
			elif e.index == _first and e.position.distance_to(_fingers[e.index].start) > SLOP_PT * _scale:
				_press_waiting()
				_disarm("drag")  # lane IOS-40: a drag is no second tap
				if _pan_world:
					# lane IOS-35: the camera follows the finger from where it came down (the ground there stays under it)
					_gesture = Gesture.PAN
					stats.finger_pans += 1
					_pan_last = _fingers[e.index].start
					_finger_pan(e.position)
				elif _begin_list_scroll(_fingers[e.index].start):
					_gesture = Gesture.SCROLL
					stats.list_scrolls += 1
					_scroll_list(e.position)
				else:
					_gesture = Gesture.DRAG
					stats.drags += 1
					_button(MOUSE_BUTTON_LEFT, true, _fingers[e.index].start)
					_move(e.position)
		Gesture.DRAG:
			if e.index == _first:
				_move(e.position)
		Gesture.PAN:
			if e.index == _first:
				_finger_pan(e.position)
		Gesture.ARMED:
			if e.index == _first and e.position.distance_to(_fingers[e.index].start) > SLOP_PT * _scale:
				# lane IOS-35: the armed finger's drag: the selection box, from where the finger came down
				_gesture = Gesture.DRAG
				stats.drags += 1
				_button(MOUSE_BUTTON_LEFT, true, _fingers[e.index].start)
				_move(e.position)
		Gesture.PLACE:
			if e.index == _first:
				_move(ghost_point(e.position))
		Gesture.CONFIRM:
			if e.index == _first:  # lane IOS-26: the button looks pressed while the finger is on it
				_confirm.set_pressed(_pressed if _confirm.hit(e.position) == _pressed else "")
		Gesture.INFO:
			if e.index == _first and e.position.distance_to(_fingers[e.index].start) > SLOP_PT * _scale:
				_end_info()  # lane IOS-21: sliding off ends the help; the finger does nothing more until it lifts
				_gesture = Gesture.HELD
		Gesture.TOOLBAR:
			if e.index == _first and _tb_id != "" and _toolbar.hit(e.position) != _tb_id:
				_tb_id = ""  # lane IOS-37: slid off: nothing happens at the lift
				_toolbar.set_pressed("")
				_toolbar.set_progress_all(-1.0)
				_toolbar.hide_tip()
		Gesture.UNQUEUE:
			if e.index == _first:
				_ring.set_cancel_pressed(_ring.cancel_hit(e.position))
		Gesture.SCROLL:
			if e.index == _first:
				_scroll_list(e.position)
		Gesture.TWO:
			_two_finger_move()


func _tap(at: Vector2, now: int) -> void:
	var double := now - _last_tap_ms <= DOUBLE_TAP_MS and at.distance_to(_last_tap_pos) <= DOUBLE_TAP_PT * _scale
	var assist := assist_probe(at)
	if assist.snapped:
		stats.assisted_taps += 1
	# lane IOS-40: a button the "Button taps" option previews: the first tap arms it, the second uses it
	if button_taps != TAPS_ACT and not _mouse and _waiting.is_empty():
		var b := _hud_button(at, assist.position)
		if _previews(b):
			_preview_tap(b, now)
			return
	# lane IOS-21: the second tap on an autocast ability toggles its autocast (its right press); the first tap's press is dropped
	if not _waiting.is_empty():
		if double or _waiting.get("second", false):
			var on: Vector2 = _waiting.at
			_waiting = {}
			_click(MOUSE_BUTTON_RIGHT, on)
			stats.autocast_taps += 1
			stats.double_taps += 1
			_last_tap_ms = -100000
			return
		_press_waiting()
	if autocast_double_tap and not double and _hud_button(at, assist.position).get("autocast", false):  # lane IOS-42: the switch
		_waiting = {"at": assist.position, "due": now + DOUBLE_TAP_MS}
		stats.waited_taps += 1
		stats.taps += 1
		_last_tap_ms = now
		_last_tap_pos = at
		return
	_click(MOUSE_BUTTON_LEFT, assist.position, double)
	if double:
		stats.double_taps += 1
		_last_tap_ms = -100000  # a third tap starts over
	else:
		stats.taps += 1
		_last_tap_ms = now
		_last_tap_pos = at


## lane IOS-40: the option previews HUD button `b` (_hud_button's answer)
func _previews(b: Dictionary) -> bool:
	if b.is_empty():
		return false
	return button_taps == TAPS_ALL or (button_taps == TAPS_COSTS and bool(b.get("costs", false)))


## lane IOS-40: a button's identity across taps: the Apt button's path, or the radial bubble's slot ("" none)
func _button_key(b: Dictionary) -> String:
	if b.is_empty():
		return ""
	return "%s:%s" % [b.get("kind", ""), b.get("target", "") if str(b.get("kind", "")) == "movie" else str(b.get("slot", -1))]


## lane IOS-40: a tap on a previewed button: the second on the armed one (the same button holding the same command) uses it, any other arms it
func _preview_tap(b: Dictionary, now: int) -> void:
	var at: Vector2 = b.position
	stats.taps += 1
	_last_tap_ms = -100000  # no world double click across a HUD button
	if not _armed.is_empty() and str(_armed.key) == _button_key(b) and str(_armed.name) == str(b.get("name", "")) and now <= int(_armed.until):
		if autocast_double_tap and now - int(_armed.tapped) <= DOUBLE_TAP_MS and bool(b.get("autocast", false)):  # lane IOS-42: the switch
			_click(MOUSE_BUTTON_RIGHT, at)  # IOS-21's double tap: the autocast toggles (a setting, not a use: the arm goes)
			stats.autocast_taps += 1
			stats.double_taps += 1
			_disarm("autocast toggled")
			return
		# the button stays armed from this tap: a further tap is one more use (no autocast double tap from here)
		_armed.until = now + ARM_MS
		_armed.tapped = -100000
		if _ring != null:
			_ring.used(ARM_MS / 1000.0)
		_click(MOUSE_BUTTON_LEFT, at)
		stats.armed_uses += 1
		_cancel_poll_ms = now - TOOLBAR_POLL_MS + 120  # the ✕ looks at the queue again once the logic took the press
		return
	_disarm("another button")
	_armed = {"key": _button_key(b), "name": str(b.get("name", "")), "until": now + ARM_MS, "tapped": now, "at": at}
	_move(at)  # the help box's provider is the button under the pointer (IOS-21)
	_hud.hold_help(true)
	var rect: Rect2 = b.get("rect", Rect2())
	if rect.has_area():
		if _ring == null:
			_ring = ArmedRing.new()
			_ring.setup(_scale)
			add_child(_ring)
		_ring.arm(rect, ARM_MS / 1000.0)
		_show_cancel(b)
	Input.vibrate_handheld(10)
	stats.arms += 1
	print("TOUCH IOS-40 armed %s (%s %s) at %s" % [_armed.name, b.get("command", ""), _armed.key, at])


## lane IOS-40: the armed button lets go (a tap elsewhere, a gesture, the time out, the option): its help and its ring go
func _disarm(why := "") -> void:
	if _armed.is_empty():
		return
	print("TOUCH IOS-40 disarmed %s (%s)" % [_armed.get("name", ""), why])
	_armed = {}
	stats.disarms += 1
	if is_instance_valid(_hud) and _gesture != Gesture.INFO:
		_hud.hold_help(false)
	if _ring != null:
		_ring.disarm()


## lane IOS-40: the armed button's state for the self-test: { armed, key, name, ring: armed_ring.gd's state }
func armed_state() -> Dictionary:
	return {"armed": not _armed.is_empty(), "key": _armed.get("key", ""), "name": _armed.get("name", ""),
		"ring": _ring.state() if _ring != null else {}}


## lane IOS-37: the ghost waiting for ✓ / ✕ turned by the fingers' twist `turn` (radians on screen): the same angle on the ground, a quarter twist a
## quarter turn, in the fingers' direction as the camera shows the ground (the sign of the ground's x and y axes' turn on screen: a mirrored view turns
## it the other way). Uniform, so the building turns as steadily as the fingers at any pitch. True when the HUD took the angle
func _turn_ghost(hud: Node, turn: float) -> bool:
	if not _anchor.is_finite():
		return false
	var p0: Vector2 = hud.world_to_pixel(_anchor)
	var ex: Vector2 = hud.world_to_pixel(_anchor + Vector2(40.0, 0.0))
	var ey: Vector2 = hud.world_to_pixel(_anchor + Vector2(0.0, 40.0))
	if p0.x < -1e8 or ex.x < -1e8 or ey.x < -1e8:
		return false
	var handed := signf((ex - p0).cross(ey - p0))
	if handed == 0.0:
		return false
	return bool(hud.set_placement_angle(wrapf(float(hud.get_placement().get("angle", 0.0)) + turn * handed, -PI, PI)))


## lane IOS-37: the toolbar's place, visibility and states (every TOOLBAR_POLL_MS): made with the first game HUD; shown in a game with no menu over it,
## touch only (a mouse in use hides it), as the option says
func _update_toolbar() -> void:
	var hud := _game_hud()
	var want := active and toolbar_enabled and hud != null and not _mouse and hud.has_method("command_hotkey")
	if want:
		var menus := _menu_player()
		want = not (menus != null and menus.has_method("modal_menu") and menus.modal_menu())
	if want and _toolbar == null:
		_toolbar = CommandToolbar.new()
		_toolbar.setup(_scale)
		add_child(_toolbar)
		print("TOUCH IOS-37 command toolbar made (%.1f px per point)" % _scale)
	if _toolbar == null:
		return
	_toolbar.hud = hud
	if want:
		_toolbar.layout(_safe_rect(), _fps_right())
		_toolbar.refresh()
	if not want and _gesture == Gesture.TOOLBAR:
		_end_toolbar_press()
	_toolbar.set_shown(want)


## lane IOS-37: the first pixel right of the frame-rate readout's room when it shows (fps_overlay.gd, top left), else -INF
func _fps_right() -> float:
	var scene := get_tree().current_scene
	var overlay = scene.get("_display_overlay") if scene != null else null
	if overlay == null or not is_instance_valid(overlay) or not overlay.has_method("shown") or not overlay.shown():
		return -INF
	var label: Label = overlay.get("_label")
	if label == null:
		return -INF
	var font := label.get_theme_font("font")
	var px: int = overlay.get("_font_px")
	return float(overlay.offset.x) + label.position.x + font.get_string_size(overlay.WIDEST, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 8.0 * _scale


## lane IOS-37: the toolbar's hold: the help after LONG_PRESS_MS; on a control group a ring fills from 120 ms and the group is made at LONG_PRESS_MS
func _toolbar_hold(held_ms: int) -> void:
	if _toolbar.is_group(_tb_id):
		_toolbar.set_progress(_tb_id, clampf(float(held_ms - 120) / float(LONG_PRESS_MS - 120), 0.0, 1.0) if held_ms >= 120 else -1.0)
	if held_ms < LONG_PRESS_MS:
		return
	_tb_done = true
	if _toolbar.is_group(_tb_id):
		_toolbar.set_progress(_tb_id, -1.0)
		if _toolbar.assign(_tb_id):
			stats.groups_made += 1
		Input.vibrate_handheld(15)
		print("TOUCH IOS-37 toolbar hold %s: %s" % [_tb_id, _toolbar.state().tip])
		return
	_toolbar.show_tip(_tb_id)
	stats.toolbar_helps += 1
	Input.vibrate_handheld(10)


## lane IOS-37: the toolbar's press ends (lifted, slid off, a second finger): the button lets go; a help line stays a moment to be read
func _end_toolbar_press() -> void:
	if _toolbar == null:
		return
	_toolbar.set_pressed("")
	_toolbar.set_progress_all(-1.0)
	_toolbar.hide_tip(1.2 if _tb_done else 0.0)
	_tb_id = ""


## lane IOS-37: the armed button's ✕ (armed_ring.gd) where its right press would cancel something queued; hidden otherwise
func _show_cancel(b: Dictionary) -> void:
	if _ring == null:
		return
	if not bool(b.get("cancel", false)):
		_ring.hide_cancel()
		return
	var rect: Rect2 = b.get("rect", Rect2())
	var away: Vector2 = b.get("away", Vector2.ZERO)
	if away == Vector2.ZERO:
		var view := get_viewport().get_visible_rect()
		away = (view.get_center() - rect.get_center()).normalized()  # an arc or side bar button: toward the screen's middle (off the HUD)
	_ring.show_cancel(away, _safe_rect(), _toolbar.rect() if _toolbar != null else Rect2())


## lane IOS-37: the ✕ follows the armed button's queue (a unit came out, the ✕ took one off, another tap queued one)
func _update_cancel() -> void:
	if _armed.is_empty() or _ring == null:
		return
	var b := _hud_button(_armed.at, _armed.at)
	if _button_key(b) != str(_armed.key) or str(b.get("name", "")) != str(_armed.name):
		_ring.hide_cancel()
		return
	_show_cancel(b)


## lane IOS-37: ✕ tapped: the armed button's right press (retail's cancel of one queued unit); the button stays armed
func _unqueue() -> void:
	if _armed.is_empty():
		return
	_click(MOUSE_BUTTON_RIGHT, _armed.at)
	stats.queue_cancels += 1
	_armed.until = Time.get_ticks_msec() + ARM_MS
	_armed.tapped = -100000
	if _ring != null:
		_ring.used(ARM_MS / 1000.0)
	_cancel_poll_ms = Time.get_ticks_msec() - TOOLBAR_POLL_MS + 120
	Input.vibrate_handheld(10)
	print("TOUCH IOS-37 queue cancel on %s" % _armed.name)


## lane IOS-21: the HUD button a finger at `at` is on ({} none): touch_button_at's answer at the tap assist's point (`assisted`, else asked here), with
## "position" the point the pointer goes to. Only over a game's HUD (the menus' hold stays the right click), with an extension that has the call
func _hud_button(at: Vector2, assisted := Vector2.INF) -> Dictionary:
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_button_at"):
		return {}
	var point: Vector2 = assisted if assisted.is_finite() else assist_probe(at).position
	var r: Dictionary = hud.touch_button_at(point)
	if str(r.get("kind", "")) == "":
		return {}
	r["position"] = point
	return r


## lane IOS-23: a finger coming down at `at` drags a placement's ghost: a build button waits for its site and the finger is on the world (not on the
## HUD, the radar or a menu over the game). An extension without the query (built before lane IOS-23) keeps the old gestures
func _placement_drag_at(at: Vector2) -> bool:
	if placement_mode == PLACE_TAP:
		return false  # lane IOS-42: "Place on tap" leaves the placement to the mouse's clicks (_tap_placement_at)
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		return false
	var r: Dictionary = hud.touch_placement_at(at)
	return bool(r.get("placing", false)) and bool(r.get("world", false))


## lane IOS-42 "Place on tap": a finger coming down at `at` is on the world while a placement waits (its tap, or its drag's release, is the mouse's
## placing click); remembers the game's count of issued placements for the builders' deselect (_watch_placement)
func _tap_placement_at(at: Vector2) -> bool:
	_tap_place_builds = -1
	if placement_mode != PLACE_TAP:
		return false
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		return false
	var r: Dictionary = hud.touch_placement_at(at)
	if not bool(r.get("placing", false)) or not bool(r.get("world", false)):
		return false
	_tap_place_builds = int(r.get("builds", -1))
	return true


## lane IOS-42 "Place when you lift" (IOS-23 as it was before IOS-26): the left click at `at` places the building (PlaceEventTranslator: the press
## anchors, the release places, or refuses with retail's message and the placement stays). A point on the HUD clicks nothing: the placement stays
func _place_now(at: Vector2) -> bool:
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		return false
	var r: Dictionary = hud.touch_placement_at(at)
	if not bool(r.get("world", false)):
		stats.place_lifts_on_hud += 1
		return false
	var builds := int(r.get("builds", -1))
	_click(MOUSE_BUTTON_LEFT, at)
	_watch_placement(builds)
	return true


## lane IOS-42: a "lift" or "tap" placement's click was sent with the game's count of issued placements at `builds`: the builders' deselect (IOS-36's
## _after_placement) waits up to PLACE_WATCH_MS for the game to take it (the click reaches the logic a frame or more later)
func _watch_placement(builds: int) -> void:
	if builds < 0:
		return  # an extension without the count
	_builds_at_confirm = builds
	_place_watch_until = Time.get_ticks_msec() + PLACE_WATCH_MS


func _poll_placement_watch(now: int) -> void:
	var hud := _game_hud()
	if hud == null or _confirming or not hud.has_method("touch_placement_at"):
		_place_watch_until = 0
		return
	var r: Dictionary = hud.touch_placement_at(Vector2.ZERO)
	if not bool(r.get("placing", false)) or int(r.get("builds", -1)) > _builds_at_confirm:
		_place_watch_until = 0
		_after_placement()
	elif now >= _place_watch_until:
		_place_watch_until = 0
		_builds_at_confirm = -1  # the game kept the placement (refused: a bad site, no money): nothing to deselect


## lane IOS-23: where a finger at `at` puts a placement's ghost: GHOST_OFFSET_PT above it, kept inside the view (a finger near the top edge holds
## the ghost at the edge; the sides and the bottom cannot be left, as the offset is straight up). Lane IOS-42: under the finger with "Above the finger" off
func ghost_point(at: Vector2) -> Vector2:
	var p := at - Vector2(0.0, GHOST_OFFSET_PT * _scale if ghost_above else 0.0)
	var size := get_viewport().get_visible_rect().size
	return p.clamp(Vector2(GHOST_INSET_PX, GHOST_INSET_PX), size - Vector2(GHOST_INSET_PX, GHOST_INSET_PX))


## lane IOS-26: a lift or a tap leaves the ghost at `at` (window pixels) to wait for ✓ / ✕, shown beside it now (`show`) or once a camera gesture
## ends (true: the ghost waits). A point on the HUD (the ghost dragged over the Palantir) offers nothing: the ghost is under the HUD, and the placement
## stays for another try
func _offer_confirm(at: Vector2, show := true) -> bool:
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		return false
	var r: Dictionary = hud.touch_placement_at(at)
	if not bool(r.get("placing", false)) or not bool(r.get("world", false)):
		if bool(r.get("placing", false)):
			stats.place_lifts_on_hud += 1
		_end_confirm()
		return false
	_move(at)
	_ghost_px = at
	var ground: Vector2 = hud.pixel_to_world(at)
	_anchor = ground if ground.is_finite() and ground.x > -1e8 else Vector2.INF  # (-1e9, -1e9): no ground under the pixel
	_confirm_line = bool(r.get("line_build", false))
	_confirming = true
	_committed_ms = -1
	_confirm_poll_ms = Time.get_ticks_msec()
	if _confirm == null:
		_confirm = PlacementConfirm.new()
		_confirm.setup(_scale)
		add_child(_confirm)
	if show:
		_show_confirm(true)
	return true


## lane IOS-26: ✓ and ✕ beside the waiting ghost, and ✓'s look for its legality. A building: left and right of it, clear of a farm-sized footprint
## at the camera's zoom. A wall span: across the span's line at its end (the ghost segments' direction), else beyond the end
func _show_confirm(animate: bool) -> void:
	var hud := _game_hud()
	var side := 0.0
	var axis := Vector2.RIGHT
	var away: Array = [Vector2.UP, Vector2.DOWN]
	if hud != null and _confirm_line:
		var dir := _span_direction(hud)
		if dir != Vector2.ZERO:
			axis = dir.orthogonal() if dir.orthogonal().x >= 0.0 else -dir.orthogonal()  # across the line: ✓ to the right (above a level span), ✕ opposite
			away = [dir]
	elif hud != null and _anchor.is_finite():
		side = _clear_side(hud)
	_confirm.show_at(_ghost_px, _safe_rect(), _off_hud, animate, side, axis, away)
	_refresh_validity()


## lane IOS-26: pixels from the ghost's point to a button's centre that clear CONFIRM_CLEAR_WORLD of ground around it at the camera's zoom (the larger
## of the ground's two axes on screen), a disc's radius and a little more (0: the HUD could not say)
func _clear_side(hud: Node) -> float:
	var o: Vector2 = hud.world_to_pixel(_anchor)
	var x: Vector2 = hud.world_to_pixel(_anchor + Vector2(CONFIRM_CLEAR_WORLD, 0))
	var y: Vector2 = hud.world_to_pixel(_anchor + Vector2(0, CONFIRM_CLEAR_WORLD))
	if o.x < -1e8 or x.x < -1e8 or y.x < -1e8:
		return 0.0
	var reach := maxf(o.distance_to(x), o.distance_to(y)) + (PlacementConfirm.DIAMETER_PT * 0.5 + 6.0) * _scale
	return minf(reach, CONFIRM_SIDE_MAX_PT * _scale)


## lane IOS-26: a wall span's direction on screen, from its hub to the ghost: the hub is the placement's source (get_placement().source, its position
## from the game's GameWorld); without it, the ghost segments' end farthest from the ghost. ZERO when neither says
func _span_direction(hud: Node) -> Vector2:
	var far := Vector2.INF
	var scene := get_tree().current_scene
	var world = scene.get("_world") if scene != null else null
	if hud.has_method("get_placement") and world != null and world.has_method("get_object"):
		var hub: Dictionary = world.get_object(int(hud.get_placement().get("source", 0)))
		if hub.get("ok", false):
			var p: Vector2 = hud.world_to_pixel(Vector2(float(hub.x), float(hub.y)))
			if p.x > -1e8:
				far = p
	if not far.is_finite() and hud.has_method("get_placement_ghost_state"):
		var icons: Array = hud.get_placement_ghost_state().get("icons", [])
		if icons.size() >= 2:
			for i in [icons[0], icons[icons.size() - 1]]:
				var p: Vector2 = hud.world_to_pixel(Vector2(float(i.get("x", 0.0)), float(i.get("y", 0.0))))
				if p.x > -1e8 and (not far.is_finite() or p.distance_to(_ghost_px) > far.distance_to(_ghost_px)):
					far = p
	if not far.is_finite() or far.distance_to(_ghost_px) < 1.0:
		return Vector2.ZERO
	return (_ghost_px - far).normalized()


## lane IOS-26: a pixel the buttons may cover: on the world, not on the HUD (the Palantir, the side bar, a radial bubble, the radar)
func _off_hud(at: Vector2) -> bool:
	var hud := _game_hud()
	if _toolbar != null and _toolbar.rect().grow(4.0 * _scale).has_point(at):
		return false  # lane IOS-37: nor on the command toolbar
	return hud != null and bool(hud.touch_placement_at(at).get("world", false))


## lane IOS-26: the view less the notch, the rounded corners and the home bar on a phone (the screen's safe area: Godot's iOS window is the screen)
func _safe_rect() -> Rect2:
	var view := get_viewport().get_visible_rect()
	if OS.has_feature("mobile"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if safe.has_area():
			view = view.intersection(safe)
	return view


## lane IOS-26: ✓ is dimmed while the ghost is red (the HUD's legal code for it, judged by PlaceEventTranslator as for a mouse). A wall span is never
## dimmed: its release skips the legality test (RW 0x83E7FE) and the span planner builds what it can
func _refresh_validity() -> void:
	var hud := _game_hud()
	if _confirm_line or hud == null or not hud.has_method("get_placement"):
		_confirm.set_build_enabled(true)
		return
	_confirm.set_build_enabled(int(hud.get_placement().get("legal", 0)) == 0)


## lane IOS-26: ✓: the left click at the ghost's point, IOS-23's lift (the press anchors, the release places, or refuses with retail's message and
## sound and the mode stays). On a legal ghost the buttons go at once; a ✓ the game did not take brings them back (_poll_confirm)
func _confirm_build() -> void:
	var legal: bool = _confirm.build_enabled()
	var hud := _game_hud()
	if hud != null and hud.has_method("touch_placement_at"):
		_builds_at_confirm = int(hud.touch_placement_at(_ghost_px).get("builds", -1))  # lane IOS-36: did the game take it? (_end_confirm)
	_click(MOUSE_BUTTON_LEFT, _ghost_px)
	stats.place_confirms += 1
	Input.vibrate_handheld(10)
	if legal:
		_confirm.hide_now()
		_committed_ms = Time.get_ticks_msec()


## lane IOS-26: ✕: the right click at the ghost's point (the hold's cancel; the pointer stays on the ghost)
func _confirm_cancel() -> void:
	_click(MOUSE_BUTTON_RIGHT, _ghost_px)
	stats.place_cancels += 1
	_end_confirm()


func _end_confirm() -> void:
	if not _confirming:
		return
	_after_placement()
	_confirming = false
	_anchor = Vector2.INF
	_ghost_px = Vector2.INF
	_committed_ms = -1
	_track_until = 0
	if _confirm != null:
		_confirm.hide_now()


## lane IOS-36 (after daisyhasacat/openbfme-godot facef81b), as the wait ends: a ✓ was tapped, the placement is over and the game's count of issued
## construction orders went up since: it took the ✓, so the builders are deselected. A refusal, ✕ or a cancel leave the count (and the selection)
func _after_placement() -> void:
	var before := _builds_at_confirm
	_builds_at_confirm = -1
	var hud := _game_hud()
	if before < 0 or hud == null or not hud.has_method("touch_placement_at"):
		return
	var r: Dictionary = hud.touch_placement_at(Vector2.ZERO)
	if bool(r.get("placing", false)) or int(r.get("builds", -1)) <= before:
		return
	stats.place_accepted += 1
	if deselect_builders_after_build and hud.has_method("deselect_builders") and bool(hud.deselect_builders()):
		stats.builder_deselects += 1


## lane IOS-26, while the ghost waits: the placement still on (else the wait ends: placed, cancelled by a key or the game, the builder gone), the ghost
## on its ground point (the camera may have moved), ✓'s legality. Every CONFIRM_POLL_MS; every frame while the camera may move
func _poll_confirm(now: int) -> void:
	var camera := _gesture == Gesture.TWO or _gesture == Gesture.HELD or now < _track_until
	if not camera and now - _confirm_poll_ms < CONFIRM_POLL_MS:
		return
	_confirm_poll_ms = now
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		_end_confirm()
		return
	var px := _anchor_pixel(hud)
	var r: Dictionary = hud.touch_placement_at(px)
	if not bool(r.get("placing", false)):
		_end_confirm()
		return
	if _placing and (_gesture == Gesture.PENDING or _gesture == Gesture.PLACE):
		return  # a finger is putting the ghost somewhere new
	_settle(px, bool(r.get("world", false)), _gesture == Gesture.NONE)
	if _committed_ms >= 0 and now - _committed_ms >= CONFIRM_RETRY_MS and _gesture == Gesture.NONE:
		_committed_ms = -1  # the game kept the placement after ✓ (no money, a full queue: its message says so): the buttons again
		_show_confirm(true)
	if _confirm.is_shown():
		_refresh_validity()


## lane IOS-26: the waiting ghost's pixel now: its ground point through the drawn camera (the pixel it waited at when the HUD had no ground point)
func _anchor_pixel(hud: Node) -> Vector2:
	if _anchor.is_finite():
		var p: Vector2 = hud.world_to_pixel(_anchor)
		if p.is_finite() and p.x > -1e8:
			return p
	return _ghost_px


## lane IOS-26: the ghost back on its ground point after the camera moved (`show`: and its buttons, if they were hidden)
func _follow_anchor(show: bool) -> void:
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		return
	var px := _anchor_pixel(hud)
	_settle(px, bool(hud.touch_placement_at(px).get("world", false)), show)


## the pointer (the ghost) and the buttons to `px`. A point off the view or under the HUD hides the buttons and leaves the pointer: the ghost stays
## visible where it was, and its buttons come back when its point does (or a finger puts it somewhere new)
func _settle(px: Vector2, world: bool, show: bool) -> void:
	if not world or not get_viewport().get_visible_rect().has_point(px):
		_confirm.hide_now()
		return
	if px.distance_to(_ghost_px) > 1.5:  # the ground point's round trip may differ by a pixel: no jitter
		_ghost_px = px
		_move(px)
		_confirm.move_to(px)
	if show and not _confirm.is_shown() and _committed_ms < 0:
		_show_confirm(true)


## lane IOS-21: the waiting tap's press, now (a second tap did not come, or another gesture began)
func _press_waiting() -> void:
	if _waiting.is_empty():
		return
	var at: Vector2 = _waiting.at
	_waiting = {}
	_click(MOUSE_BUTTON_LEFT, at)


## lane IOS-21: a held finger's help ends (the HUD hides the box with its own count down)
func _end_info() -> void:
	if _gesture == Gesture.INFO and is_instance_valid(_hud):
		_hud.hold_help(false)


## lane IOS-21: the help box shows only for a held finger, unless a mouse is in use (its hover is the desktop's)
func _apply_touch_help() -> void:
	var on := 0 if _mouse else 1
	if _touch_help != on and _hud.has_method("set_touch_help"):
		_hud.set_touch_help(on == 1)
		_touch_help = on


func _two_finger_move() -> void:
	if _fingers.size() != 2:
		return
	var c := _centroid()
	var d := _distance()
	if not _two_moved and (c.distance_to(_last_centroid) > SLOP_PT * _scale or absf(d - _pinch_base) > SLOP_PT * _scale
			or absf(wrapf(_finger_angle() - _twist_base, -PI, PI)) >= deg_to_rad(TWIST_START_DEG)):  # lane IOS-15: a twist alone moves too
		_two_moved = true
	if not _two_moved:
		return
	var hud := _game_hud()
	if hud != null:
		# pan: the world point under the fingers' middle stays under it
		if _pan_camera(hud, _last_centroid, c):
			stats.pans += 1
		var cam: Dictionary = hud.get_camera()
		# pinch: whole wheel notches, apart (zoom in) or together (zoom out)
		if _pinch_base > 0.0:
			var ratio := d / _pinch_base
			while ratio >= 1.0 + PINCH_STEP:
				hud.inject_mouse_wheel(1, c)
				_pinch_base *= 1.0 + PINCH_STEP
				ratio = d / _pinch_base
				stats.zoom_notches += 1
			while ratio <= 1.0 / (1.0 + PINCH_STEP):
				hud.inject_mouse_wheel(-1, c)
				_pinch_base /= 1.0 + PINCH_STEP
				ratio = d / _pinch_base
				stats.zoom_notches += 1
		# lane IOS-15, twist: the camera turns with the fingers (the original turns it with the middle button or numpad 4 / 6); only past
		# TWIST_START_DEG, so a pinch or a pan does not turn it by accident
		var turn := wrapf(_finger_angle() - _twist_base, -PI, PI)
		if not _twisting and absf(turn) >= deg_to_rad(TWIST_START_DEG):
			_twisting = true
			_twist_base = _finger_angle()
			turn = 0.0
		if _twisting and turn != 0.0 and _confirming and twist_turns_ghost and not _confirm_line and hud.has_method("set_placement_angle"):
			# lane IOS-37: while ✓ / ✕ wait the twist turns the building's ghost, not the camera (lane IOS-42: unless the switch says the camera)
			if _turn_ghost(hud, turn):
				stats.ghost_turns += 1
			_twist_base = _finger_angle()
		elif _twisting and turn != 0.0 and cam.has("angle"):
			hud.camera_set_angle_pitch(float(cam.angle) + turn, float(cam.pitch))  # the map turns with the fingers
			_twist_base = _finger_angle()
			stats.twists += 1
		if _confirming:
			_follow_anchor(false)  # lane IOS-26: the ghost keeps its ground point under the moving camera
		if _aim_waiting:
			_follow_aim(false)  # lane IOS-43: the aim keeps its ground point (or its target)
	_last_centroid = c


## the camera moved so that the ground under window pixel `from` is under `to` (true: moved). A pixel with no ground under it ((-1e9, -1e9): above the
## horizon) moves nothing
func _pan_camera(hud: Node, from: Vector2, to: Vector2) -> bool:
	var was: Vector2 = hud.pixel_to_world(from)
	var now_at: Vector2 = hud.pixel_to_world(to)
	var cam: Dictionary = hud.get_camera()
	if not cam.has("position") or not was.is_finite() or not now_at.is_finite() or was.x < -1e8 or now_at.x < -1e8:
		return false
	hud.camera_look_at(Vector2(cam.position) + (was - now_at))
	return true


## lane IOS-35: one finger's camera step to `at` (the pointer follows the finger: the game's hover under it)
func _finger_pan(at: Vector2) -> void:
	var hud := _game_hud()
	if hud != null:
		_pan_camera(hud, _pan_last, at)
	_pan_last = at
	_move(at)


## lane IOS-35: a finger at `at` is on the battlefield: a game is on screen and the point is its world (not the HUD, the radar or a menu over the game:
## the HUD's touch_placement_at, which answers with no placement too). An extension without the query keeps the select mode's gestures
func _on_battlefield(at: Vector2) -> bool:
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		return false
	return bool(hud.touch_placement_at(at).get("world", false))


## lane IOS-15: the angle of the line from the first finger to the second (radians, screen axes)
func _finger_angle() -> float:
	var p: Array = _fingers.values()
	return (p[1].pos - p[0].pos).angle() if p.size() >= 2 else 0.0


func _centroid() -> Vector2:
	var sum := Vector2.ZERO
	for f in _fingers.values():
		sum += f.pos
	return sum / maxf(1.0, _fingers.size())


func _distance() -> float:
	var p: Array = _fingers.values()
	return p[0].pos.distance_to(p[1].pos) if p.size() >= 2 else 0.0


func _apply_edge_scroll() -> void:
	_hud.set_edge_scroll(_mouse)
	_hud.set_view_options({"edge_scroll_mode": edge_scroll_mode(_edge_option)})
	_apply_touch_help()


## the game's HUD node while a game is on screen (null in the menus); edge scrolling goes off for touch the first time it is found
func _game_hud() -> Node:
	if is_instance_valid(_hud) and _hud.is_inside_tree():
		return _hud
	var found := get_tree().root.find_children("*", "InGameHudNode", true, false)
	_hud = found[0] if not found.is_empty() else null
	_touch_help = -1  # a new game's HUD starts with the desktop's hover help
	if _hud != null:
		# a finger near the edge is not a wish to scroll; a mouse's pointer is (lane IOS-14: on while a mouse is in use, _poll_devices follows it).
		# set_edge_scroll replaces the HUD's retail rule (scroll in a full-screen window, which Godot's iOS window always is) and edge_scroll_mode
		# maps the option's "retail" the same way (IOS-17)
		_apply_edge_scroll()
		print("TOUCH game HUD found: edge scrolling %s (option %s)" % [edge_scroll_mode(_edge_option), _edge_option])
	return _hud


## lane IOS-10: the shell's AptMenuPlayer (the menus), or null before it boots
func _menu_player() -> Node:
	if is_instance_valid(_menus) and _menus.is_inside_tree():
		return _menus
	_menus = null
	for p in get_tree().root.find_children("*", "AptMenuPlayer", true, false):
		if p.is_booted():
			_menus = p
			break
	return _menus


## lane IOS-10: where a tap at `at` presses: { position, snapped, target, reason } (no click, nothing counted; touch_selftest.gd asks it too).
## Over a game the HUD answers (its buttons, or a menu over it), else the menus. A tap the answer leaves alone keeps its own point.
func assist_probe(at: Vector2) -> Dictionary:
	var out := {"position": at, "snapped": false, "target": "", "reason": "off"}
	if not tap_assist:
		return out
	var source: Node = _game_hud()
	if source == null:
		source = _menu_player()
	if source == null or not source.has_method("nearest_button"):
		out.reason = "no source"  # in a game's load, or an extension built before lane IOS-10
		return out
	var r: Dictionary = source.nearest_button(at, ASSIST_PT * _scale)
	out.target = str(r.get("target", ""))
	out.reason = str(r.get("reason", ""))
	if not r.get("snapped", false):
		return out
	var runner_up := float(r.get("runner_up", -1.0))
	if runner_up >= 0.0 and runner_up - float(r.get("distance", 0.0)) < ASSIST_TIE_PT * _scale:
		out.reason = "between two"
		return out
	out.position = r.position
	out.snapped = true
	return out


## lane IOS-10: a one-finger drag that starts on a list box scrolls it (true: the gesture is a list scroll). Never over a game's world: there a
## drag is a selection box; only while a menu has the input (the save / load list over a game)
func _begin_list_scroll(start: Vector2) -> bool:
	if not list_scroll:
		return false
	var menus := _menu_player()
	if menus == null or not menus.has_method("scroll_list_at"):
		return false
	if _game_hud() != null and not menus.modal_menu():
		return false
	var list: Dictionary = menus.scroll_list_at(start)
	var row := float(list.get("row_height", 0))
	if not list.get("found", false) or row <= 0.0:
		return false  # an empty list has nothing to scroll: the drag stays a drag
	_scroll_at = start
	_scroll_row = row
	_scroll_anchor = menus.window_to_stage(start).y
	return true


## the finger's travel since the last notch, in rows: a notch each (the content follows the finger: up shows the later rows, the wheel's down)
func _scroll_list(at: Vector2) -> void:
	var menus := _menu_player()
	if menus == null:
		return
	var travel: float = _scroll_anchor - menus.window_to_stage(at).y
	while travel >= _scroll_row:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN, _scroll_at)
		_scroll_anchor -= _scroll_row
		travel -= _scroll_row
	while travel <= -_scroll_row:
		_wheel(MOUSE_BUTTON_WHEEL_UP, _scroll_at)
		_scroll_anchor += _scroll_row
		travel += _scroll_row


func _wheel(button: MouseButton, at: Vector2) -> void:
	for down in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = button
		b.pressed = down
		b.factor = 1.0
		b.position = at
		b.global_position = at
		b.device = TOUCH_DEVICE
		Input.parse_input_event(b)


func _move(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if _gesture == Gesture.DRAG else 0
	m.device = TOUCH_DEVICE
	Input.parse_input_event(m)


func _button(button: MouseButton, down: bool, at: Vector2, double := false) -> void:
	_move(at)
	var b := InputEventMouseButton.new()
	b.button_index = button
	b.pressed = down
	b.position = at
	b.global_position = at
	b.double_click = double and down
	b.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
	b.device = TOUCH_DEVICE
	Input.parse_input_event(b)


func _click(button: MouseButton, at: Vector2, double := false) -> void:
	_button(button, true, at, double)
	_button(button, false, at)


# ---- lane IOS-43: aiming a power or a hero ability (the header's IOS-43 section) ------------------------------------------------------------------

## the HUD's answer for the waiting power at `at` ({}: none waits, or an extension built before lane IOS-43)
func _aim_query(at: Vector2) -> Dictionary:
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_targeting_at"):
		return {}
	var r: Dictionary = hud.touch_targeting_at(at)
	return r if str(r.get("kind", "")) != "" else {}


## a finger coming down at `at` aims the waiting power: "Confirm first", no mouse in use, the finger on the map
func _aim_drag_at(at: Vector2) -> bool:
	if targeting_mode != TARGET_CONFIRM or _mouse:
		return false
	var r := _aim_query(at)
	return not r.is_empty() and bool(r.get("world", false))


## a lift or a tap leaves the aim at `at` (window pixels) to wait for ✓ / ✕, shown now (`show`) or after a camera gesture. A target power picks the
## target under `at`, or refuses (the refusal mark, a vibration) when there is none it can have. A point on the HUD offers nothing (the power waits)
func _offer_aim(at: Vector2, show := true) -> bool:
	var r := _aim_query(at)
	if r.is_empty():
		_end_aim_wait()
		return false
	if not bool(r.get("world", false)):
		stats.aim_lifts_on_hud += 1
		_end_aim_wait()
		return false
	var hud := _game_hud()
	_aim_object = 0
	_aim_anchor = Vector2.INF
	if str(r.kind) == "object":
		var id := int(r.get("object", 0))
		if id == 0 or not bool(r.get("valid", false)):
			_refuse(at)
			_end_aim_wait()
			return false
		_aim_object = id
		var mark := _object_mark(hud, id)
		if Vector2(mark[0]).is_finite():
			at = mark[0]
	else:
		var ground: Vector2 = hud.pixel_to_world(at)
		_aim_anchor = ground if ground.is_finite() and ground.x > -1e8 else Vector2.INF  # (-1e9, -1e9): no ground under the pixel
	_move(at)
	_aim_px = at
	_aim_waiting = true
	_aim_committed_ms = -1
	_aim_poll_ms = 0
	if _aim_confirm == null:
		_aim_confirm = PlacementConfirm.new()
		_aim_confirm.setup(_scale, "Use here", "Cancel")
		add_child(_aim_confirm)
	_update_aim_marks(r, at)  # first: ✓ / ✕ keep outside the sight it draws
	if show:
		_show_aim_confirm(true, r)
	print("TOUCH IOS-43 aim %s at %s: %s" % [r.get("power", ""), at, "target %d" % _aim_object if _aim_object != 0 else ("valid" if r.get("valid", false) else "invalid")])
	return true


## ✓ / ✕ beside the waiting aim (outside the power's ring, or the target's sight), and ✓'s look for whether the game would take it
func _show_aim_confirm(animate: bool, r: Dictionary = {}) -> void:
	if r.is_empty():
		r = _aim_query(_aim_px)
	var reach := 0.0
	if _aim_ui != null:
		var st: Dictionary = _aim_ui.state()
		reach = float(st.target_radius) + 10.0 * _scale if _aim_object != 0 else (float(st.ring_radius) if Vector2(st.ring).is_finite() else _aim_radius_px(r, _aim_px))
	var side := minf(reach + (PlacementConfirm.DIAMETER_PT * 0.5 + 6.0) * _scale, CONFIRM_SIDE_MAX_PT * _scale)
	_aim_confirm.show_at(_aim_px, _safe_rect(), _aim_free, animate, side)
	_aim_confirm.set_build_enabled(bool(r.get("valid", false)))


## a pixel ✓ / ✕ may cover: off the HUD (_off_hud: the Palantir, the side bar, the bubbles, the radar, the toolbar) and off the banner
func _aim_free(at: Vector2) -> bool:
	if _aim_ui != null and _aim_ui.banner_rect().grow(4.0 * _scale).has_point(at):
		return false
	return _off_hud(at)


## a ground power's radius in pixels at `at` (its RadiusCursorRadius on the ground there; 0 none)
func _aim_radius_px(r: Dictionary, at: Vector2) -> float:
	var radius := float(r.get("radius", 0.0))
	var hud := _game_hud()
	if radius <= 0.0 or hud == null:
		return 0.0
	var ground: Vector2 = hud.pixel_to_world(at)
	if not ground.is_finite() or ground.x < -1e8:
		return 0.0
	var o: Vector2 = hud.world_to_pixel(ground)
	var x: Vector2 = hud.world_to_pixel(ground + Vector2(radius, 0))
	var y: Vector2 = hud.world_to_pixel(ground + Vector2(0, radius))
	if o.x < -1e8 or x.x < -1e8 or y.x < -1e8:
		return 0.0
	return maxf(o.distance_to(x), o.distance_to(y))


## a target's sight: [its middle on screen, a radius around it]; [INF, 0] when it is gone. The pick box's points (pick_box_pixels: what a click there
## picks), else its position on the ground
func _object_mark(hud: Node, id: int) -> Array:
	if hud.has_method("pick_box_pixels"):
		var pts: PackedVector2Array = hud.pick_box_pixels(id)
		if pts.size() > 0:
			var lo := pts[0]
			var hi := pts[0]
			for q in pts:
				lo = lo.min(q)
				hi = hi.max(q)
			return [pts[0], maxf((hi - lo).length() * 0.5, 16.0 * _scale) + 6.0 * _scale]
	var scene := get_tree().current_scene
	var world = scene.get("_world") if scene != null else null
	if world != null and world.has_method("get_object"):
		var o: Dictionary = world.get_object(id)
		if o.get("ok", false):
			var p: Vector2 = hud.world_to_pixel(Vector2(float(o.x), float(o.y)))
			if p.x > -1e8:
				return [p, 28.0 * _scale]
	return [Vector2.INF, 0.0]


## the ring (a ground power whose decal is not drawn), the sight (a target power's target, or a valid one under an aiming finger)
func _update_aim_marks(r: Dictionary, at: Vector2) -> void:
	if _aim_ui == null:
		return
	var hud := _game_hud()
	var aiming := _aim_live.is_finite() or _aim_waiting
	if str(r.get("kind", "")) == "location" and aiming and at.is_finite() and not bool(r.get("decal_drawn", false)):
		_aim_ui.set_ring(at, _aim_radius_px(r, at), bool(r.get("valid", false)))
	else:
		_aim_ui.set_ring(Vector2.INF, 0.0, true)
	var id := _aim_object
	if id == 0 and _aim_live.is_finite() and str(r.get("kind", "")) == "object" and bool(r.get("valid", false)):
		id = int(r.get("object", 0))
	if id != 0 and hud != null:
		var mark := _object_mark(hud, id)
		var was: Vector2 = _aim_ui.state().target
		_aim_ui.set_target(mark[0], mark[1], not was.is_finite())
	else:
		_aim_ui.set_target(Vector2.INF, 0.0)


## ✓: the left click at the aim (the cast), when the game would take it there; else the refusal and the aim waits
func _aim_fire() -> void:
	var hud := _game_hud()
	if hud == null:
		return
	if _aim_object != 0:
		var mark := _object_mark(hud, _aim_object)
		if not Vector2(mark[0]).is_finite():
			_end_aim_wait()  # the target is gone
			return
		_aim_px = mark[0]
	var r := _aim_query(_aim_px)
	if r.is_empty():
		_end_aim()
		return
	if not bool(r.get("valid", false)) or (_aim_object != 0 and int(r.get("object", 0)) != _aim_object):
		_refuse(_aim_px)
		return
	_click(MOUSE_BUTTON_LEFT, _aim_px)
	stats.aim_fires += 1
	Input.vibrate_handheld(10)
	print("TOUCH IOS-43 ✓ %s at %s" % [r.get("power", ""), _aim_px])
	_aim_confirm.hide_now()
	_aim_committed_ms = Time.get_ticks_msec()
	_aim_poll_ms = 0


## ✕ (beside the aim, or the banner's): the game's cancel of the waiting power
func _aim_cancel() -> void:
	var hud := _game_hud()
	if hud != null and hud.has_method("cancel_targeting"):
		hud.cancel_targeting()
	stats.aim_cancels += 1
	Input.vibrate_handheld(10)
	_end_aim()


## the refusal at `at`: the game would not take it (the mouse's red cursor, for a finger)
func _refuse(at: Vector2) -> void:
	stats.aim_refused += 1
	Input.vibrate_handheld(25)
	if _aim_ui != null:
		_aim_ui.refuse(at)
	print("TOUCH IOS-43 refused at %s" % at)


## the wait at a point ends (the power may still wait: the banner stays)
func _end_aim_wait() -> void:
	_aim_waiting = false
	_aim_object = 0
	_aim_px = Vector2.INF
	_aim_anchor = Vector2.INF
	_aim_committed_ms = -1
	_aim_track_until = 0
	if _aim_confirm != null:
		_aim_confirm.hide_now()
	if _aim_ui != null:
		_aim_ui.set_ring(Vector2.INF, 0.0, true)
		_aim_ui.set_target(Vector2.INF, 0.0)


## the power is over (cast, cancelled, ended by the game): everything goes
func _end_aim() -> void:
	_end_aim_wait()
	_aim_key = ""
	_aim_info = {}
	if _aim_ui != null:
		_aim_ui.clear()


## the aim's pixel now: a target's middle, a ground point through the drawn camera (the pixel it waited at when the HUD had no ground point); INF: the
## target is gone
func _aim_follow_px(hud: Node) -> Vector2:
	if _aim_object != 0:
		return _object_mark(hud, _aim_object)[0]
	if _aim_anchor.is_finite():
		var p: Vector2 = hud.world_to_pixel(_aim_anchor)
		if p.is_finite() and p.x > -1e8:
			return p
	return _aim_px


## the aim back on its ground point (or its target) after the camera (or the target) moved; `show`: and its buttons, if they were hidden. A point off
## the view or under the HUD hides them; they come back when it is back
func _follow_aim(show: bool) -> void:
	var hud := _game_hud()
	if hud == null:
		return
	var px := _aim_follow_px(hud)
	if not px.is_finite():
		_end_aim_wait()  # the target died or left the view's picture
		return
	if not get_viewport().get_visible_rect().has_point(px) or not _off_hud(px):
		_aim_confirm.hide_now()
		return
	if px.distance_to(_aim_px) > 1.5:
		_aim_px = px
		_move(px)
		_aim_confirm.move_to(px)
	if show and not _aim_confirm.is_shown() and _aim_committed_ms < 0:
		_show_aim_confirm(true)


## the banner's two lines for the waiting power `r`
func aim_banner_text(r: Dictionary) -> Array:
	var target := str(r.get("kind", "")) == "object"
	var label := str(r.get("label", ""))
	var title := ("Choose a target" if target else "Choose where") + (": " + label if label != "" else "")
	var hint := ""
	if targeting_mode == TARGET_CONFIRM:
		hint = "Tap a unit or building, then ✓" if target else "Touch the map to aim, lift, then ✓"
	else:
		hint = "Tap a unit or building to use it" if target else "Tap the map to use it here"
	return [title, hint]


## lane IOS-43, each frame: the waiting power (the HUD asked every AIM_POLL_MS, every frame while a finger aims or the camera moves, AIM_IDLE_POLL_MS
## while none waits): the banner, the ring and the sight; while ✓ / ✕ wait, the aim on its point and ✓'s look; the power's end ends it all
func _poll_aim(now: int) -> void:
	var live := _aim_live.is_finite() and (_gesture == Gesture.PENDING or _gesture == Gesture.AIM)
	var camera := _aim_waiting and (_gesture == Gesture.TWO or _gesture == Gesture.HELD or now < _aim_track_until)
	var every := AIM_POLL_MS if _aim_key != "" else AIM_IDLE_POLL_MS
	if not live and not camera and now - _aim_poll_ms < every:
		return
	_aim_poll_ms = now
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_targeting_at"):
		if _aim_key != "":
			_end_aim()
		return
	var at := _aim_live if live else (_aim_px if _aim_waiting else Vector2(-1, -1))
	var r: Dictionary = hud.touch_targeting_at(at)
	if str(r.get("kind", "")) == "":
		if _aim_key != "":
			print("TOUCH IOS-43 the power no longer waits (%s)" % _aim_key)
			_end_aim()
		return
	var key := "%s|%s|%s" % [r.get("source", ""), r.get("button", ""), r.get("power", "")]
	if key != _aim_key:
		if _aim_key != "":
			_end_aim_wait()  # another power took its place
		_aim_key = key
		stats.aim_starts += 1
		print("TOUCH IOS-43 a power waits: %s" % JSON.stringify(r))
	_aim_info = r
	if _aim_ui == null:
		_aim_ui = TouchTargeting.new()
		_aim_ui.setup(_scale)
		add_child(_aim_ui)
	var menus := _menu_player()
	var covered: bool = menus != null and menus.has_method("modal_menu") and menus.modal_menu()  # a menu over the game: nothing of this over it
	_aim_ui.visible = not covered
	if _aim_confirm != null:
		_aim_confirm.visible = not covered
	if covered or _mouse:
		_aim_ui.hide_banner()  # a mouse in use aims as on a desktop (its cursor and the game's decal)
	else:
		var text := aim_banner_text(r)
		var top: float = _toolbar.rect().end.y if _toolbar != null and _toolbar.is_shown() and _toolbar.rect().has_area() else _safe_rect().position.y
		_aim_ui.show_banner(text[0], text[1], _safe_rect(), top)
	if _aim_waiting and not live:
		if _gesture == Gesture.NONE or camera:
			_follow_aim(_gesture == Gesture.NONE)
		if not _aim_waiting:
			return
		if _aim_committed_ms >= 0 and now - _aim_committed_ms >= CONFIRM_RETRY_MS and _gesture == Gesture.NONE:
			_aim_committed_ms = -1  # the game kept the power waiting after ✓: the buttons again
			_show_aim_confirm(true)
		r = hud.touch_targeting_at(_aim_px)
		if _aim_confirm.is_shown():
			_aim_confirm.set_build_enabled(bool(r.get("valid", false)))
		at = _aim_px
	_update_aim_marks(r, at)


## for the tests and the self-test: { waiting, key, info, aim, object, aiming, ui (touch_targeting.gd's state), confirm (✓ / ✕'s state) }
func aim_state() -> Dictionary:
	return {"waiting": _aim_waiting, "key": _aim_key, "info": _aim_info, "aim": _aim_px, "object": _aim_object, "aiming": _aim_live,
		"ui": _aim_ui.state() if _aim_ui != null else {}, "confirm": _aim_confirm.state() if _aim_confirm != null else {}}


# ---- lane IOS-14 / IOS-45: the mouse, trackpad, Apple Pencil and hardware keyboard (the extension's input bridge) -------------------------------

## An input event that is not a finger's on an iOS build: the input bridge's (GodotIOSTouch.mm) mouse, Pencil and scroll events, which reached
## the game as they are. Here: whether a mouse is in use (IOS-17), the touch layer's waits a mouse ends, and the scroll made wheel notches
func _bridge_event(event: InputEvent) -> void:
	if event is InputEventMouse:
		if event.device == TOUCH_DEVICE:
			return  # this layer's own
		var button := event as InputEventMouseButton
		if event.device == PENCIL_DEVICE:
			# an Apple Pencil is a mouse's left button, not a mouse in use: its click places and casts as a mouse's does
			if button != null and button.pressed:
				stats.pencil_presses += 1
				_end_confirm()
				_end_aim_wait()
			return
		_saw_pointer()
		if button != null:
			_end_confirm()
			_end_aim_wait()
			stats.mouse_buttons += 1
		elif _fingers.is_empty():  # while a finger is down the finger's gesture keeps its waits
			_end_confirm()  # lane IOS-26: the mouse takes the pointer, and with it the ghost; its click places as retail's
			_end_aim_wait()  # lane IOS-43: and a power's aim; its click casts as retail's
	elif event is InputEventPanGesture:
		# a wheel or a trackpad's two-finger scroll (the bridge's recognizer takes no finger): back to UIKit points, then wheel notches
		_saw_pointer()
		var pan := event as InputEventPanGesture
		_scroll_ms = Time.get_ticks_msec()
		_scroll_pos = pan.position
		_mouse_scroll(-pan.delta / PAN_PER_PT, pan.position, false)
		get_viewport().set_input_as_handled()  # the notches stand for it (a Godot list would scroll twice)
	elif event is InputEventMagnifyGesture:
		_saw_pointer()  # a trackpad's pinch: a pointer in use; nothing reads the gesture


func _saw_pointer() -> void:
	stats.pointer_events += 1
	if not _pointer_seen:
		_pointer_seen = true
		_mouse_check_ms = 0  # in use from the next frame


## the bridge's counters and the devices, for the log
func _bridge_status() -> Dictionary:
	var status: Dictionary = _devices.status()
	status["pointer_seen"] = _pointer_seen
	for key in ["pointer_events", "mouse_buttons", "pencil_presses", "wheel_notches", "repaired_key_releases"]:
		status[key] = stats[key]
	return status


func _poll_devices() -> void:
	var now := Time.get_ticks_msec()
	if _wheel_acc != 0.0 or _wheel_notches != 0:
		if now - _scroll_ms >= SCROLL_END_MS:
			_mouse_scroll(Vector2.ZERO, _scroll_pos, true)  # the scroll paused: it ended
	if now - _mouse_check_ms < 250:
		return
	_mouse_check_ms = now
	var mice := int(_devices.status().get("mice", 0))
	if mice == 0 and _mice > 0:
		_pointer_seen = false  # the last mouse went: touch play again until a pointer shows itself (IOS-17)
	_mice = mice
	var mouse := mouse_connected()
	if mouse != _mouse:
		_mouse = mouse
		_disarm("mouse")  # lane IOS-40: a mouse acts at once
		print("TOUCH IOS-14 mouse %s: %s" % ["in use" if mouse else "gone", _bridge_status()])
		if is_instance_valid(_hud) and _hud.is_inside_tree():
			_apply_edge_scroll()


## UIKit's scrolling (+y: the content moves down, the wheel turned up, as a desktop's natural scrolling gives it) in whole notches
func _mouse_scroll(delta: Vector2, at: Vector2, ended: bool) -> void:
	if _wheel_logged < 16:
		_wheel_logged += 1
		print("TOUCH IOS-14 scroll %s pt%s" % [delta, " (end)" if ended else ""])
	_wheel_acc += delta.y
	while _wheel_acc >= WHEEL_STEP_PT:
		_wheel(MOUSE_BUTTON_WHEEL_UP, at)
		_wheel_acc -= WHEEL_STEP_PT
		_wheel_notches += 1
	while _wheel_acc <= -WHEEL_STEP_PT:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN, at)
		_wheel_acc += WHEEL_STEP_PT
		_wheel_notches += 1
	if ended:
		if _wheel_notches == 0 and absf(_wheel_acc) >= 0.5:
			_wheel(MOUSE_BUTTON_WHEEL_UP if _wheel_acc > 0.0 else MOUSE_BUTTON_WHEEL_DOWN, at)  # a wheel's one click scrolls less than a step
			_wheel_notches += 1
		stats.wheel_notches += _wheel_notches
		_wheel_acc = 0.0
		_wheel_notches = 0


## every key event Godot delivers (the root window's, before any node's _input marks it handled): which presses still wait for a release (released
## here when the app loses the focus). The bridge's release of a key Godot missed (GCKeyboard, on the Mac host) names no side: a right modifier's
## (Godot's press had KEY_LOCATION_RIGHT, the HUD's own scan code) is released again as the press had it
func _on_window_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or k.device == BRIDGE_DEVICE or k.echo or k.physical_keycode == KEY_NONE:
		return  # ours; or the on-screen keyboard's typing (no physical key; it sends a press and a release itself)
	var code := int(k.physical_keycode)
	if k.pressed:
		_keys_down[code] = k
	elif _keys_down.has(code):
		var press: InputEventKey = _keys_down[code]
		if press.location == KEY_LOCATION_RIGHT and k.location == KEY_LOCATION_UNSPECIFIED:
			_release_key(code)
		else:
			_keys_down.erase(code)  # Godot's own release came: nothing to repair


func _release_key(code: int) -> void:
	var press: InputEventKey = _keys_down[code]
	_keys_down.erase(code)
	var r := press.duplicate() as InputEventKey
	r.pressed = false
	r.echo = false
	r.unicode = 0
	r.device = BRIDGE_DEVICE
	Input.parse_input_event(r)
	stats.repaired_key_releases += 1


func _notification(what: int) -> void:
	# lane IOS-14: keys held as the app loses the focus (Cmd-Tab on the Mac, the home gesture) are released: no release would ever come
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _devices != null:
		for code in _keys_down.keys():
			_release_key(code)
