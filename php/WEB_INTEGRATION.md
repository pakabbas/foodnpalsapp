# FoodnPals mobile app — reservation tracking (website integration)

The Flutter app injects a JavaScript bridge on every page load of the embedded WebView. Call these functions from **foodnpals.com** (customer flows) after a reservation exists in the database.

## Rules

1. Call **`window.startTracking(bookingId, restaurantLat, restaurantLng)`** only when the reservation **`Status`** is **`Pending`** or **`Accepted`** (same values the PHP APIs allow). `bookingId` must be the database **`ReservationID`** (integer as string or number is fine).
2. When the status changes to anything else (declined, completed, cancelled, etc.), or when the customer should no longer be tracked, call **`window.stopTracking()`**.
3. Use the same **Bearer token** the app stores after login (`ManualToken` / `LoginToken` in `AppUsers`) — the PHP endpoints validate `Authorization: Bearer …` against `AppUsers.LoginToken`. The logged-in WebView session should correspond to that user; **`CustomerID`** on the reservation must match **`AppUsers.UserID`** for the authenticated token.

## Example (after successful booking create)

```javascript
if (status === 'Pending' || status === 'Accepted') {
  if (window.startTracking) {
    window.startTracking(reservationId, restaurantLat, restaurantLng);
  }
}
```

## Example (status no longer trackable)

```javascript
if (window.stopTracking) {
  window.stopTracking();
}
```

## Deployed API base URL

Default in the app: `https://foodnpals.com/php` (override at build time with `--dart-define=TRACKING_API_BASE=https://your-host/path`).

Endpoints:

- `GET get_reservation_tracking_allowed.php?reservationId=…`
- `POST post_reservation_location.php?reservationId=…` (JSON body: `lat`, `lng`, `accuracy`, `arrived`, `timestamp`)

## Database note

The PHP scripts use the table name **`reservations`**. If your MySQL table is **`Reservations`** or different, update the SQL in:

- `get_reservation_tracking_allowed.php`
- `post_reservation_location.php`

Ensure **`AppUsers.UserID`** matches **`reservations.CustomerID`** for your schema.
