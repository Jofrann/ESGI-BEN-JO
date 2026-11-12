# MVP interaction contract

- Register using name, password and habitual departure; school optional. Show validation and duplicate-name errors. Login establishes an eight-hour server session. Logout revokes it.
- Search future published trips by departure, destination and date. Filter price, departure time and available seats. Empty results invite another search.
- Publish future trips with capacity, price, optional arrival, meeting point and up to five stops. A successful response determines publication.
- Reserve exactly one seat after confirmation. PostgreSQL locks the trip, rejects self-booking, duplicates and overbooking. The request identifier prevents duplicate writes.
- Prepared November feedback: future published trips can be edited by their driver, with a version check and capacity at least equal to confirmed bookings. Search matches ordered intermediate stops and includes owned trips; an empty date includes all upcoming published trips chronologically. Notifications carry route/date/time, message previews and owned navigation targets. See CORRECTIONS-20261104.md for deployment state and remaining viewport-shell work.
- Driver and passenger may cancel applicable future bookings. Driver may cancel the trip. Cancellation releases capacity and records notifications.
- History shows past shared trips. A review requires participation, a past trip and a rating of one to five. One review per participant pair and trip.
- Messages are scoped to the signed-in sender or recipient. Notifications and preferences belong to the signed-in user. Refresh buttons retrieve current data; no background push is promised.
- Dialogs support keyboard focus, Escape and cancel. Destructive business actions use soft cancellation and explicit confirmation. Form failures preserve input.
- Backend QA runs in an intentionally failing anonymous block, so all synthetic rows roll back. QA_PASSED is the expected final marker, not an application error.
- Responsive layout is owned by the shared widget stylesheet and FLUID/AUTO_HEIGHT Appsmith shell. Content determines height; the host owns the only content scroll. At widths up to 900px, the header and combined composer/navigation dock follow the visible part of the iframe while stable spacers keep messages, final fields and actions clear of them. Wider layouts keep normal document flow. A native/screen-height coverage floor supports short pages and height-only growth without deriving height from the growing iframe; extra blank space on short pages is an accepted tradeoff. Forms and filters stack below 420px, names and actions wrap, and navigation remains reachable. Verify at actual CSS viewport widths 320, 390, 768 and a short landscape viewport; use synthetic local data for signed-in screens to avoid production writes.

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Form | Field and Password in widget.jsx | Existing MVP flows | Register, publish, profile | Browser narrow-width forms |
| Date | Native date/time inputs | Existing MVP platform-owned picker | Date and time | Browser open picker and field dimensions |
| Select/Listbox | Native select | Existing MVP platform-owned picker | Seats | Browser popup and keyboard |
| Scrollbar | Global widget.css, Appsmith host scroll | DESIGN.md | Growing iframe content, no inner content scroll | DOM overflow and browser scroll |
| Viewport bars | useMobileViewportBars and navigation-dock in widget.jsx; shared widget.css | DESIGN.md | Anchored through 900px; natural desktop; coarse-touch editing footer in flow | Opaque-iframe fixture plus deployed Appsmith portrait/landscape and height-only resize |

Native date/time and select controls intentionally retain browser/OS popup geometry and interaction. Shared CSS owns the field width and mobile typography.

- Viewport updates preserve mounted React state, drafts and business requests. Native `appsmith.ui` is passed through the Default Model as `viewport`; its initial snapshot is not assumed to update on resize. Intersection geometry is re-read without parent-document access and bar writes are clamped and deduplicated. Hidden tabs suspend sampling and unmount removes all observers, frames and listeners.
- While a text field is focused on a coarse touch screen, the footer returns to flow so the browser can reveal the field; it pins again after focus leaves editable controls. Desktop focus does not release the footer. Real phone keyboard opening/closing and final Send/field reachability require separate device verification and must not be claimed from desktop viewport emulation.

- At widget widths 700–900px, a 48px lower dock reserve keeps the native Appsmith badge clear of Profile and other navigation controls. The reserve participates in the existing dock measurement and stable spacer; narrower portrait layouts are unchanged. Verify Profile remains clickable in the published 840px host landscape view.
