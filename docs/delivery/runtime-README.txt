HD-2D / Riverside Waystation — P8 adjustable parallax

Run ./waystation.x86_64. After extraction, restore its executable permission if necessary.
No Godot editor or Blender is needed. Tested on Linux x86_64, Fedora 43,
RTX 4070 SUPER, Vulkan / Forward+. Other platforms are not validated.

Walk south across the bridge and left/right on the 30m stone path.
Camera following starts enabled. Natural mode preserves the original parallax.

WASD / arrows: walk. E: interact. T: cycle day/dusk/night.
1/2/3: dusk/night/day. F2: camera tour. F3: post-effects bypass.
F4: camera follow. F5: DOF toggle. F6: DOF settings. F7: background visibility.
F8: parallax panel. Basic: presets and overall multiplier.
Advanced: three mountain layers, two cloud layers, horizontal camera settings and wind.
Sliders and numeric fields are linked. Applied ratios and warnings are displayed.
1.0 is each layer's natural motion; 0.0 cancels only its horizontal camera parallax.
Wind is independent. Ground, buildings, player and collision are not compensated.

Save explicitly with the panel button to restore preferences next time.
Load retrieves saved preferences. Natural only preserves camera/wind choices;
Reset all restores project defaults. Close does not save automatically.
Tab/H hides the interface and closes tuning. Esc stops comparison first,
then closes the panel or dialogue, otherwise exits. F12 captures a screenshot.

The comparison video repeats the same path with soft, natural and enhanced ratios.
It is 36 seconds, 1280x720 at 30 fps, with explicit cuts between the three passes.
This is original procedural art, not official or extracted Octopath Traveler art.
See NOTICE.md and licenses/. No combat, audio or real water reflections.
Full source, tests, editable assets and documentation are delivered separately.
