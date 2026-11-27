# SafeSpend logo and icons

Source files are in `assets/logo/` (`logo.svg` is the master). The logo is a shield (safe) with a coin
and a check mark (spend), in the app's aqua/cyan on deep navy.

## Apply it to every platform
After `flutter create .` has made the platform folders, run:

    flutter pub get
    dart run flutter_launcher_icons

This writes the Android (including adaptive icon), iOS, web (favicon + PWA icons + manifest colours),
Windows and macOS icons from the files in `assets/logo/`.

`web_icons/` holds ready-made web icons (favicon.png, Icon-192/512, Icon-maskable-192/512) if you prefer to
copy them into `web/` and `web/icons/` by hand.

## In the app
`AppLogo` (lib/widgets/app_logo.dart) shows it on the welcome screen and in the navigation rail.
