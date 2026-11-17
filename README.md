# PICO-8 for Android

This application is a specialized frontend for the Android platform that allows you to run and play with the original PICO-8 (specifically the Raspberry Pi build) on your Android device.

**Note:** This application is a wrapper/launcher; it does **not** contain PICO-8 itself. You must provide your own legally purchased copy of the PICO-8 Raspberry Pi executable at the start of the application.

**PICO-8 logo used with permission from Lexaloffle**

## ⚠️ Important Technical Details

### Android Version Target & Warning
To enable the execution of the external PICO-8 executable provided by the user, this application targets an older Android SDK version.
*   **Why?** Newer Android versions restrict the execution of binaries downloaded or copied to the device storage for security reasons. Targeting an older SDK bypasses this restriction.
*   **Result:** You may see a system warning stating that this app was built for an older version of Android. This is expected and necessary for the app to function.

### Storage Permissions
The application requires permission to access the device's storage (specifically the media/documents folder).
*   **Usage:** This is needed to copy the default PICO-8 configuration files into `/Documents/pico8/data`.
*   You will be asked to grant this permission upon first launch.

### 📱 Compatibility
The current version of the APK has the following requirements:
*   **Operating System:** Android 9.0 (Pie) or higher (API level 28+)
*   **Architecture:** 64-bit (arm64-v8a)
*   **Note:** 32-bit devices (armeabi-v7a) and versions older than Android 9 are not supported.


### User Data & Cartridges
The `/Documents/pico8/data` folder is automatically populated during the first execution of PICO-8, exactly mirroring the behavior of a standard PC installation.
*   **Cross-Platform Compatibility:** Because the structure is identical, if you have an existing PICO-8 installation on another platform, you can copy your `carts`, favorites, and save data directly into this folder.
*   **Migration:** simply copy your files into the corresponding subfolders in `/Documents/pico8/data` to carry over your progress and library to Android.
*   **Synchronization:** You can use external tools like **Syncthing** to keep this folder in sync with your other devices (PC, raspberry pi, etc.). Please refer to the specific documentation of your chosen tool for setup details.


## 🌟 Key Features (Fork)
This fork introduces several enhancements to improve the experience on Android devices:

*   **Landscape Mode:** Optimized UI and display for landscape orientation.
*   **Controller Support:** Full support for external game controllers.
*   **Android Handheld Support:** Tested and verified on devices like the **RG Cube**.
*   **Virtual Keyboard:** Access the Android keyboard at any time by sliding up from the bottom of the screen.
*   **Options Menu:** Access the side menu for settings and options by sliding from the left side of the screen or pressing the **Left Shoulder (L1/LB)** button on a controller.
*   **Frontend Integration:** Compatible with frontends like **ES-DE** to launch PICO-8 games directly or access Splore (see v0.0.7 release notes for setup instructions; pending official integration from the ES-DE team). **Beacon Launcher** support added since v1.0.0. Please check the [wiki pages](https://github.com/Macs75/pico8-android/wiki/Frontends-Integration) for the setup.
*   **Direct Cart Launch:** Launch `.p8.png` cartridges directly from any file manager or web browser. Supports **Deep Links** to launch carts directly from the [Lexaloffle website](https://www.lexaloffle.com/), as well as standard Android "Share Link" and "Share Image" actions.
*   **Home Screen Shortcuts:** Create shortcuts to launch your favorite games directly from your home screen.
*   **Favourites Management:** Reorder your Splore favorites list with easy drag-and-drop or using predefined sorts (name, author, most played).
*   **Play Stats:** Review your play statistics as recorded by PICO-8.
*   **Theme Support:** Create your own custom theme or use one of the pre-made ones. Check the [wiki](https://github.com/Macs75/pico8-android/wiki/Themes) for more details.
*   **2 Player Support:** Connect 2 controllers to play games that support multiplayer.
*   **Integrated Shaders:** Try one of the integrated shaders for a custom retro look. Shaders can be modified in `/Documents/pico8/shaders`. Simply rename an existing shader to `[name].custom.gslang` and it will be loaded without a restart.
*   **Bezel Support:** Activate a bezel around the PICO-8 screen and personalize it by changing the PNG in `/Documents/pico8/bezel.png`.
*   **Custom Color Calibration:** Take control over the visual profile by adjusting color parameters to your preference.
*   **Custom Layout Adjustments:** Move and zoom the on-screen controls to adjust them to your preferences.
*   **Controller Mapping:** Easily map your controller buttons if they aren't recognized correctly. Check the [wiki](https://github.com/Macs75/pico8-android/wiki/Controller-Mapping) for more details.
*   **Physical Keyboard Support:** For devices with a built-in or attached keyboard (e.g. Unihertz Titan 2). Game keys for Splore/in-game, rebindable PICO-8 shortcuts, extra on-screen keys and code editor helpers. See [Physical keyboards](#-physical-keyboards).


## ⌨ Physical keyboards
Open **Options > Controls > Keyboard Mapping**.

*   **Game keys** – in Splore and while a cart runs, `W` `A` `S` `D` act as the d-pad, `O` / `P` as the 🅾️ / ❎ buttons and `Q` as Esc. *Auto* needs PICO-8 0.2.7 to know which screen is showing; otherwise pick *Always*, or flip them with **Game keys on/off** (`Ctrl+Shift+G`), e.g. to type in the Splore search.
*   **Missing keys / Characters** – give keys your keyboard lacks (Esc, arrows, Tab, `[` `]` `{` `}` …) a key combination. `Ctrl+Q` sends Esc by default.
*   **PICO-8 shortcuts** – move PICO-8's fixed shortcuts (screenshot `F6`, cart label `F7`, …) to combinations you can reach, or clear one to disable it. A cleared or moved shortcut no longer reacts to its original combination.
*   Tap a key box and press the combination to bind it, **✖** clears it, **↺** restores the default. A combination used by more than one action turns orange and lists the other actions. It still works: pressing it triggers all of them.
*   **📱** puts any action on screen as a button. Move and resize the buttons with **Options > Display > Customize Layout**, like the built-in controls.
*   **Code editor helpers** (each can be switched off): touch and hold a PICO-8 keyword for a short description, name suggestions while typing (tap one or press `Ctrl+Space`), and a usage hint for the function being typed.

Everything lives in `frontend/physkb/`; see the README there for how it hooks into the app.

## 📂 Project Structure
- `frontend/`: Godot app part; sets up environment and handles video output and keyboard/mouse input.
- `bootstrap/` (in git soon): Enviroment for running PICO-8, including scripts, proot, and a minimal rootfs.
- `shim/`: Library LD_PRELOAD'ed into PICO-8 to handle streaming i/o and making sure SDL acts exactly as needed.

## 🛠️ Building
### Godot Frontend
1. Download [Godot](https://godotengine.org) version ≥4.6.
2. Put `package.dat` from Releases in the project ~~or build it from bootstrap/ (soon)~~; this is the bootstrap package and is pretty essential
3. In Godot, **Project > Install Android Build Template**
4. then just do the normal **Project > Export**

### GitHub Actions
`.github/workflows/build-apk.yml` builds a release APK on every push and pull request and uploads it as the `pico8-android-apk` artifact. `package.dat` is taken from the matching upstream release unless it is present in `frontend/`. Without signing secrets the APK is signed with the public CI key in `.github/ci/` (see the README there); Android will not install it over a build signed with a different key.



## 🙏 Acknowledgments
First and foremost, a massive thank you to **[Zep (Joseph White)](https://www.lexaloffle.com/)**, the author of the fantastic **PICO-8** fantasy console.

A huge thank you to **[UnmatchedBracket](https://github.com/UnmatchedBracket)**, the original creator of this Android wrapper. He did all the heavy lifting of building the bridge between native PICO-8 and Android; without his incredible effort, this project would not be possible.

Also, a big thanks to **[kishan-dhankecha](https://github.com/kishan-dhankecha)** for his contributions and modifications to the original frontend which this fork builds upon.


## ☕ Support Me
If you enjoy this project and would like to support its ongoing development and future improvements, please consider buying me a coffee! Your support is greatly appreciated.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/macs34661)
