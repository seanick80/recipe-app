/**
 * Expo config plugin: enable `use_modular_headers!` in the generated Podfile.
 *
 * `expo prebuild` regenerates ios/Podfile every build (ios/ is gitignored), so
 * this fix can't live in the Podfile itself — it must be reapplied here.
 *
 * Why: @react-native-google-signin/google-signin pulls in Swift pods
 * (GoogleSignIn → AppCheckCore) that depend on GoogleUtilities and
 * RecaptchaInterop, which don't define modules. As static libraries (Expo's
 * default) they can't be imported from Swift, so `pod install` fails with:
 *   "The following Swift pods cannot yet be integrated as static libraries:
 *    The Swift pod `AppCheckCore` depends upon `GoogleUtilities` and
 *    `RecaptchaInterop`, which do not define modules."
 * Enabling modular headers globally makes those pods generate module maps.
 * Preferred over `useFrameworks: "static"`, which is riskier alongside
 * react-native-reanimated + the RN JS engine.
 */
const { withDangerousMod } = require('expo/config-plugins');
const fs = require('fs');
const path = require('path');

const MARKER = 'use_modular_headers!';

module.exports = function withModularHeaders(config) {
  return withDangerousMod(config, [
    'ios',
    (config) => {
      const podfile = path.join(
        config.modRequest.platformProjectRoot,
        'Podfile'
      );
      let contents = fs.readFileSync(podfile, 'utf8');

      if (!contents.includes(MARKER)) {
        // Insert at top level, right after the `platform :ios, ...` line.
        contents = contents.replace(
          /^(platform :ios.*\n)/m,
          `$1${MARKER}\n`
        );
        fs.writeFileSync(podfile, contents);
      }

      return config;
    },
  ]);
};
