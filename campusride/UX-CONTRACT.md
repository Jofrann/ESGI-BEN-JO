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
- Responsive layout is owned by the shared widget stylesheet and FLUID/AUTO_HEIGHT Appsmith shell. Content determines height; the host owns scrolling. Forms and filters stack below 420px, names and actions wrap, and navigation remains reachable. Verify at actual CSS viewport widths 320, 390, 768 and a short landscape viewport; use synthetic local data for signed-in screens to avoid production writes.

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Form | Field and Password in widget.jsx | Existing MVP flows | Register, publish, profile | Browser narrow-width forms |
| Date | Native date/time inputs | Existing MVP platform-owned picker | Date and time | Browser open picker and field dimensions |
| Select/Listbox | Native select | Existing MVP platform-owned picker | Seats | Browser popup and keyboard |
| Scrollbar | Global widget.css, Appsmith host scroll | DESIGN.md | Growing iframe content | DOM overflow and browser scroll |

Native date/time and select controls intentionally retain browser/OS popup geometry and interaction. Shared CSS owns the field width and mobile typography.
