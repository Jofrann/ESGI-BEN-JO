# MVP interaction contract

- Register using name, password and habitual departure; school optional. Show validation and duplicate-name errors. Login establishes an eight-hour server session. Logout revokes it.
- Search future published trips by departure, destination and date. Filter price, departure time and available seats. Empty results invite another search.
- Publish future trips with capacity, price, optional arrival, meeting point and up to five stops. A successful response determines publication.
- Reserve exactly one seat after confirmation. PostgreSQL locks the trip, rejects self-booking, duplicates and overbooking. The request identifier prevents duplicate writes.
- Driver and passenger may cancel applicable future bookings. Driver may cancel the trip. Cancellation releases capacity and records notifications.
- History shows past shared trips. A review requires participation, a past trip and a rating of one to five. One review per participant pair and trip.
- Messages are scoped to the signed-in sender or recipient. Notifications and preferences belong to the signed-in user. Refresh buttons retrieve current data; no background push is promised.
- Dialogs support keyboard focus, Escape and cancel. Destructive business actions use soft cancellation and explicit confirmation. Form failures preserve input.
- Backend QA runs in an intentionally failing anonymous block, so all synthetic rows roll back. QA_PASSED is the expected final marker, not an application error.
