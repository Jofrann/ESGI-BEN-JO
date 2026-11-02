# CampusRide

Source of truth: supplied maquette_ecrans.png and project brief from OneDrive_1_23-10-2026.zip. French student carpooling MVP; teal/white, compact mobile forms, five persistent navigation entries, route cards and explicit confirmation modals. No invented sample trips. Payment is agreed directly between students.

Palette: primary #09967d; dark primary #087966; ink #19232f; panel #f5f6f8; border #e7eaee. Segoe UI/system sans. Card radius 10px. Buttons and fields at least 44px high. The Appsmith canvas uses fluid width. Forms remain readable at 560px; signed-in content uses up to 1000px. The widget grows with its content so the host page owns scrolling. Keyboard focus is visible; motion respects reduced-motion preferences.

Screen families: landing/authentication; dashboard/search/results/detail; publish/manage; history/reviews; profile/preferences; messages/notifications. Empty, pending, failed and successful states use actual backend outcomes.

Implementation: Appsmith Custom1 React widget, fixed prepared Query1 bridge, private PostgreSQL campusride API. Password hashes and session hashes remain in the private schema. The widget receives only the signed-in user's snapshot. Sessions are in-memory and require login after a reload. Existing public tables are extended without deletion.

Responsive layout: `widget.css` is the shared runtime owner. No fixed or minimum phone-frame height and no viewport-height units inside the auto-height iframe. At 540px and below, inputs use 16px type and compact gutters; at 420px and below, paired form fields and search filters stack. Grid tracks use `minmax(0,1fr)`; long names, locations and actions wrap. The five navigation entries remain available with touch targets at least 44px tall. Desktop max-widths limit reading length, never the mobile canvas width.
