# Playing OpenBFME on your iPhone or iPad (sideloading)

OpenBFME is not in the App Store. You can still put it on your own iPhone or iPad with a free tool and your own Apple ID, then add
**your own copy** of the games. This page walks through it in plain steps.

## What you need

- An iPhone or iPad on **iOS 17 or newer**, with about **15 GB free** while the game installs (8.5 GB stays afterwards).
- A Mac or a Windows PC, and a USB cable for the first install.
- An **Apple ID** (a free one works; see the limits below).
- **Your own** The Lord of the Rings: The Rise of the Witch-king **2.01** and The Battle for Middle-earth II **1.06**, installed on a
  computer. OpenBFME contains no game files and never will: the app is the engine only, the game data is yours.
- The file **`OpenBFME-unsigned.ipa`** (the app). It is unsigned on purpose: your sideloading tool signs it with your Apple ID when it
  installs it. Whoever builds it uses `tools/ios/package_unsigned_ipa.sh` from this repository.

## 1. Install the app

Pick **one** of the two tools. Both are free and do the same job.

### With Sideloadly (Mac or Windows, the simplest)

1. Download Sideloadly from its official site, install it and open it.
2. Connect the iPhone or iPad with the cable, unlock it and tap **Trust** if it asks.
3. Drag `OpenBFME-unsigned.ipa` onto Sideloadly's window.
4. Type your Apple ID in the Apple account field and press **Start**. Enter your password (and the two-factor code) when it asks.
5. Wait for "Done". The OpenBFME icon is now on the device.

### With AltStore (Mac or Windows)

1. Download AltServer from AltStore's official site and install it on the computer.
2. Connect the device, then use AltServer's menu (the menu bar on a Mac, the system tray on Windows) to **Install AltStore** on it with
   your Apple ID.
3. On the device, open **AltStore › My Apps**, tap **+** and choose `OpenBFME-unsigned.ipa` (save it to the Files app first, for example
   with AirDrop).

### Then, once, on the device

- **Developer Mode:** Settings › Privacy & Security › **Developer Mode** › on. The device restarts and asks you to confirm.
- **Trust your Apple ID:** Settings › General › **VPN & Device Management** › your Apple ID › **Trust**.

Open OpenBFME. It starts on a screen that asks for the game.

## 2. Add your game (the one-file install)

The game goes in as **one file**, `OpenBFME-GameData.obfme` (about 6.5 GB), made from your own installed games on a computer.

**Make the file**, either way:

- **With OpenBFME on the computer** (easiest if you already play it there): the main menu's Options › **Settings** › the
  **iPhone / iPad** tab › **PREPARE**. It writes the file to your Desktop. You can keep using the menus while it works.
- **With the script** (no desktop game needed):
  `python3 tools/ios/make_game_file.py --rotwk "<your RotWK folder>" --bfme2 "<your BFME2 folder>"`

Both check every game file first and leave your install folders untouched.

**Send it to the device**, any of:

- **Mac:** Finder › your device › **Files** › drag the file onto **OpenBFME**.
- **AirDrop** it, then choose **Save to Files › On My iPhone › OpenBFME**.
- Put it in **iCloud Drive** or on a USB drive and pick it from OpenBFME's start screen.

**Install it:** open OpenBFME. The start screen finds the file and offers **Install**. It checks every file and deletes the 6.5 GB file
when it is done. Then press **Play**.

## 3. Every 7 days: re-sign

With a **free** Apple ID, Apple lets a sideloaded app run for **7 days**. After that it will not open until you re-sign it.

- **Sideloadly:** connect the device and drag the same ipa in again with the same Apple ID (or turn on Sideloadly's automatic refresh,
  which works over Wi-Fi while the computer is on).
- **AltStore:** open AltStore › My Apps › **Refresh All** while the computer with AltServer is on the same Wi-Fi.

**Your game files and saves stay** as long as you re-sign the app (same Apple ID, same tool). **Do not delete the app** to fix an expired
one: deleting it deletes the 8.5 GB of game data and your saves with it, and you would install the game file again.

## Limits of a free Apple ID

- **3 apps at a time.** A free Apple ID can have at most three sideloaded apps active on a device. AltStore itself counts as one, so
  with AltStore you have room for two more.
- **10 new app IDs a week.** Installing many different apps in one week can hit Apple's weekly limit; re-signing OpenBFME does not use a
  new one.
- **7 days**, as above.
- **Capabilities.** OpenBFME asks for iOS's higher memory limit when a developer signs it. A sideloading tool may leave that out for a
  free Apple ID. The game still runs; on a phone with little memory a long, large battle is more likely to be closed by iOS.

## If something goes wrong

| What you see | What to do |
| --- | --- |
| "Untrusted Developer" | Settings › General › VPN & Device Management › your Apple ID › Trust. |
| "Developer Mode required" or the app will not open after installing | Settings › Privacy & Security › Developer Mode › on. |
| The app stopped opening after a week | Re-sign it (step 3). Do not delete it. |
| "Maximum number of apps" (or similar) | A free Apple ID's three-app limit: remove another sideloaded app, or use a paid developer account. |
| The start screen refuses the game file | It names the file that failed. Make the file again from a complete 2.01 / 1.06 install. |
| Not enough space | The install needs about 15 GB free while it runs; 8.5 GB stays afterwards. |

## What a paid Apple Developer account or TestFlight would change

This part is for the project, not for players. **Nothing here has been signed up for**; whether to do it is the project owner's decision.

- **The Apple Developer Program** (a yearly fee, about USD 99) gives a signing certificate that lasts a year instead of 7 days, no
  three-app limit, and the higher memory limit capability. With it the project could sign builds itself.
- **TestFlight** (needs that program): players install from a link or an invitation through Apple's TestFlight app, with no computer and
  no re-signing. Up to 10,000 outside testers; each build runs for **90 days**; builds for outside testers go through Apple's beta
  review first.
- **Ad Hoc** builds (also the program): signed for up to 100 registered devices per device type a year, each added by its identifier.
- **The App Store** would need full App Review. A game that runs only with files the player brings, and that carries a well-known
  licensed name, may well be refused there; TestFlight's beta review asks some of the same questions.
- None of these changes the rule that **players bring their own game**: no build, signed or not, ever contains game data.
