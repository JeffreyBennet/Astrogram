# Astrogram

**Group number**: 13
**Team members**: Jeffrey Bennet, Helial Mordahl, Braden Carter, Suyog Valsangkar  
**Name of project**: Astrogram

## Dependencies
- Xcode 26
- Swift 5.0
- iOS deployment target 26.2
- Firebase iOS SDK 12.10.0 (FirebaseCore, FirebaseAuth, FirebaseFirestore, FirebaseStorage), pulled in via Swift Package Manager — Xcode resolves on first open, no `pod install` needed
- Built-in Apple frameworks: UIKit, MapKit, AVFoundation, CoreLocation, CoreMotion, PhotosUI

## Special Instructions
- Open `Astrogram.xcodeproj` (no `.xcworkspace`, no Podfile). On first open, let Xcode finish resolving Swift Package Manager dependencies before building.
- `GoogleService-Info.plist` is checked in, so Firebase auth, Firestore, and Storage all work out of the box — no extra config required.
- Run on an iOS 26.2 simulator or a physical device. The AR / camera screen needs a real device for live camera feed and motion data; every other screen works in the simulator.
- Allow location permission ("While Using the App") when prompted — the Map and AR screens compute results from your current location.
- Test login (preloaded with sample posts):
  - email: `test@gmail.com`
  - password: `test123`
- Or sign up with any email + password through the in-app Sign Up flow.

## Features

| Feature | Description | Release Planned | Release Actual | Deviations | Who/Percentage Worked On |
| ------- | ----------- | --------------- | -------------- | ---------- | ------------------------ |
| UI | App logo, colors, splash screen, navigation, layouts | Final | Final | None | Braden (50%)<br>Jeffrey (50%) |
| Splash Screen | Shining star animations upon launch before log-in screen | Not planned but extra | Final | Added as an extra polish item | Braden (100%) |
| Scrollable Feed | Feed of other users' posts: posts can be starred and contain metadata of their origin/capturer | Beta | Beta | None | Jeffrey (50%)<br>Helial (50%) |
| Access post location from feed | Clicking on the location icon on a post opens that post up in the map | Beta | Beta | None | Suyog (100%) |
| Create Post | Upload a picture to our Firebase storage so that it may be available on your profile & on others' feeds | Beta | Beta | None | Helial (75%)<br>Suyog (25%) |
| Edit Post | Modify the metadata of your uploaded pictures | Beta | Beta | None | Helial (70%)<br>Suyog (30%) |
| Login/Signup | Create/login to your account via Firebase Auth | Beta | Alpha | Implemented early | Jeffrey (50%)<br>Braden (50%) |
| Map Feature | Shows the best places to explore for pictures; built via API calls + internal calculations | Alpha | Alpha | None | Jeffrey (34%)<br>Helial (33%)<br>Suyog (33%) |
| Map Layer Filtering | Changeable filters that our map uses to build itself visually (cloud coverage, weather data, etc.) | Alpha | Alpha | None | Suyog (75%)<br>Helial (25%) |
| Profile Page | Contains settings, the user's posts, ability to log out / delete account | Beta | Beta | None | Suyog (30%)<br>Helial (50%)<br>Jeffrey (20%) |
| Firebase Auth | Used directly in login/signup; how we manage our users' identities | Beta | Alpha | Implemented early | Jeffrey (100%) |
| Firebase Storage | Stores the user's posts and metadata; supplies the feed with posts | Beta | Alpha | Implemented early | Jeffrey (100%) |
| AR Screen w/ Camera | Shows information about the bodies in the sky and if/when the sun/moon passes the spot aimed at | Final | Final | None | Helial (80%)<br>Suyog (20%) |
