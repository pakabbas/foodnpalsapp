FoodnPals — Customer Location Tracking
Context
FoodnPals is a dine-in food ordering app (like UberEats but for table service). The app is a Flutter WebView wrapper around foodnpals.com. When a customer makes an instant table booking (reservation), we need to track their GPS location for up to 1 hour as they travel to the restaurant — including when the app is minimized or the screen is off.
The backend API, database, and restaurant dashboard are already built. This task is Flutter-only.

Packages Required
Add these to pubspec.yaml:
yamldependencies:
  flutter_inappwebview: ^6.0.0
  geolocator: ^11.0.0
  flutter_background_service: ^5.0.0
  flutter_local_notifications: ^17.0.0
  dio: ^5.0.0
  permission_handler: ^11.0.0

Files to Create / Modify
1. lib/services/location_tracking_service.dart — NEW FILE
This is the core background service. Requirements:

Use flutter_background_service to run a persistent background isolate
Use geolocator to get GPS position every 30 seconds
POST location to https://api.foodnpals.com/booking/{bookingId}/location via dio
Accept a start_tracking event with payload { bookingId, restaurantLat, restaurantLng }
Accept a stop_tracking event that calls service.stopSelf()
Auto-stop after 60 minutes using a Timer
Detect arrival: if distance to restaurant is < 150 meters (use Geolocator.distanceBetween), POST with arrived: true then stop the service
On Android: run as a foreground service (isForegroundMode: true) with a persistent notification titled "On my way" and body "FoodnPals is tracking your journey"
On iOS: use IosConfiguration with onBackground handler returning true
All entry points must be annotated with @pragma('vm:entry-point')
Handle GPS errors gracefully — skip the tick, do not crash

POST body shape:
json{
  "lat": 24.8607,
  "lng": 67.0011,
  "accuracy": 10.5,
  "arrived": false,
  "timestamp": "2025-04-01T12:00:00.000Z"
}
Include a public initBackgroundService() async function that configures the service (called once from main.dart before runApp).

2. lib/services/permission_service.dart — NEW FILE
A utility class PermissionService with a single static async method:
dartstatic Future<bool> requestLocationPermission(BuildContext context) async {}

Check current permission with Geolocator.checkPermission()
If denied, call Geolocator.requestPermission()
If deniedForever, show a dialog explaining why the permission is needed with a button that opens app settings via Geolocator.openAppSettings()
Return true only if permission is always (Android) or whileInUse/always (iOS)
On Android 10+, after granting whileInUse, prompt the user to upgrade to "Allow all the time" in settings — show an explanatory dialog before sending them to settings


3. lib/screens/webview_screen.dart — MODIFY or CREATE
The main WebView screen wrapping foodnpals.com. Requirements:

Use InAppWebView from flutter_inappwebview
Load https://foodnpals.com on start
In onLoadStop, inject this JavaScript bridge into every page load:

javascriptwindow.startTracking = function(bookingId, restaurantLat, restaurantLng) {
  window.flutter_inappwebview.callHandler(
    'StartTracking',
    JSON.stringify({ bookingId, restaurantLat, restaurantLng })
  );
};
window.stopTracking = function() {
  window.flutter_inappwebview.callHandler('StopTracking', '{}');
};

Register a JavaScriptHandler named 'StartTracking' that:

Parses the JSON argument
Calls PermissionService.requestLocationPermission(context)
If permission granted, starts the background service and invokes 'start_tracking' with the booking data
If permission denied, shows a snackbar: "Location permission is required to track your journey"


Register a JavaScriptHandler named 'StopTracking' that invokes 'stop_tracking' on the service
Handle onPermissionRequest for the WebView itself (camera, mic if needed by the website)


4. lib/main.dart — MODIFY

Call await initBackgroundService() before runApp()
Ensure WidgetsFlutterBinding.ensureInitialized() is called first


5. android/app/src/main/AndroidManifest.xml — MODIFY
Add inside <manifest>:
xml<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
Add inside <application>:
xml<service
  android:name="id.flutter.flutter_background_service.BackgroundService"
  android:foregroundServiceType="location"
  android:exported="false"/>

6. ios/Runner/Info.plist — MODIFY
Add these keys:
xml<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>FoodnPals tracks your location while you are on your way to the restaurant so we can notify the restaurant of your arrival.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>FoodnPals needs your location to show your journey to the restaurant.</string>

<key>NSLocationAlwaysUsageDescription</key>
<string>FoodnPals tracks your location in the background while you are on your way to your reservation.</string>

<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>fetch</string>
  <string>processing</string>
</array>

Tracking Logic Summary
Booking confirmed on website
  → website calls window.startTracking(bookingId, lat, lng)
  → Flutter JavascriptHandler fires
  → Request location permissions
  → Start FlutterBackgroundService
  → Service polls GPS every 30 seconds
  → POST { lat, lng, accuracy, arrived, timestamp } to API
  → If distance to restaurant < 150m → POST with arrived: true → stop service
  → If 60 minutes elapsed → stop service
  → website can also call window.stopTracking() to stop early

API Contract
Endpoint: POST https://api.foodnpals.com/booking/{bookingId}/location
Headers:

Content-Type: application/json
Authorization: Bearer {userToken} — retrieve token from shared preferences or secure storage; the website sets it after login

Body:
json{
  "lat": 24.8607,
  "lng": 67.0011,
  "accuracy": 12.3,
  "arrived": false,
  "timestamp": "2025-04-01T14:23:00.000Z"
}
Expected response: 200 OK — no body processing needed, fire and forget.

Error Handling Requirements

Wrap every Geolocator.getCurrentPosition() call in try/catch — skip the tick silently on failure
Wrap every dio.post() call in try/catch — skip on network failure, do not retry within the same tick (next tick will retry naturally)
If the background service fails to start, show a snackbar on the WebView screen
If the app is killed entirely by the OS (both platforms), the service will stop — this is acceptable behavior, do not implement a restart mechanism


Testing Notes for Cursor

The JS bridge (window.startTracking) must be injected on every onLoadStop — not just the first load — because the user may navigate within the SPA
On iOS simulator, background location does not work — test on a real device
On Android emulator, you can simulate GPS via the emulator's Extended Controls > Location
To test the 150m arrival detection without walking, temporarily lower the threshold to 50000m during development, then restore to 150
The background service runs in a separate Dart isolate — it cannot access any state from the main isolate. All data must be passed via service.invoke() / service.on()


Also create php api(s) in a new php folder as per requirements
reservation table columns are below
  "reservations": [
    {"ReservationID":"int"}, {"CustomerID":"int"}, {"RestaurantID":"int"}, {"ReservationDateTime":"datetime"}, {"TableNumber":"int"},
    {"Status":"varchar"}, {"SpecialRequests":"text"}, {"NumberofGuests":"int"}, {"CheckInTime":"datetime"}, {"CheckOutTime":"datetime"},
    {"TableID":"int"}, {"ActDate":"datetime"}, {"RestaurantLatitude":"varchar"}, {"RestaurantLongitude":"varchar"},
    {"CustomerLatitude":"varchar"}, {"CustomerLongitude":"varchar"}, {"ExtendedTime":"datetime"}, {"ExtensionReason":"varchar"},
    {"DeclineReason":"varchar"}, {"Details":"varchar"}

use creds.php file for db conn in php api