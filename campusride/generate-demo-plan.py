"""Prepare and validate CampusRide demonstration records; never connects to a database.

Example:
  python generate-demo-plan.py --start 2026-11-11 --end 2026-12-20
Use --now only for reproducible validation; actual insertion must recheck timestamps.
 No password, password hash, token, or existing-account mutation is generated.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import date, datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

PARIS = ZoneInfo("Europe/Paris")


def timestamp(day: date, hhmm: str) -> str:
    return datetime.combine(day, time.fromisoformat(hhmm), PARIS).isoformat()


def prepare(start: date, end: date, now: datetime) -> dict:
    if end < start:
        raise ValueError("The end date must not precede the start date.")
    now = now.astimezone(PARIS)
    days = [start + timedelta(days=i) for i in range((end - start).days + 1)]
    weekdays = [day for day in days if day.weekday() < 5]
    accounts = [
        {"key": "demo_alice", "name": "Démo — Alice Martin", "school": "ESGI Nantes (démonstration)", "starting_point": "Beaulieu"},
        {"key": "demo_karim", "name": "Démo — Karim Benali", "school": "ESGI Nantes (démonstration)", "starting_point": "ESGI Nantes"},
        {"key": "demo_lea", "name": "Démo — Léa Dubois", "school": "ESGI Nantes (démonstration)", "starting_point": "Commerce"},
    ]
    for account in accounts:
        account["usage"] = "Principalement conducteur ou conductrice ; quelques réservations comme passager."
    trips: list[dict] = []

    def add_trip(key: str, driver: str, day: date, origin: str, destination: str,
                 departure: str, arrival: str, stops: list[dict], series: str, frequency: str) -> None:
        dep = datetime.fromisoformat(timestamp(day, departure))
        arr = datetime.fromisoformat(timestamp(day, arrival))
        # Already finished rows are the only rows eligible for demonstration reviews.
        status = "completed" if arr <= now else "published"
        trips.append({
            "key": key, "driver_key": driver,
            "starting_point": origin, "end_point": destination,
            "departure_at": dep.isoformat(), "arrival_at": arr.isoformat(),
            "stops": stops, "seats_total": 3, "price_eur": 2.5,
            "meeting_point": "Rendez-vous fictif pour la démonstration ; ne pas utiliser pour un trajet réel.",
            "status": status, "demo_series_key": series, "demo_frequency_label": frequency,
        })

    for day in weekdays:
        add_trip("alice-" + day.isoformat(), "demo_alice", day, "Beaulieu", "Commerce",
                 "08:00", "08:30", [{"place": "Duchesse Anne", "time": "08:15"}],
                 "alice-weekday-morning", "Quotidien en semaine")
        if day.weekday() in (0, 2, 4):
            add_trip("karim-" + day.isoformat(), "demo_karim", day, "ESGI Nantes", "Porte de Vertou",
                     "17:30", "18:05", [], "karim-mon-wed-fri", "Récurrent : lundi, mercredi et vendredi")
        if day.weekday() == 3:
            add_trip("lea-am-" + day.isoformat(), "demo_lea", day, "Commerce", "ESGI Nantes",
                     "07:45", "08:20", [], "lea-thursday-morning", "Hebdomadaire : jeudi matin")
            add_trip("lea-pm-" + day.isoformat(), "demo_lea", day, "ESGI Nantes", "Commerce",
                     "18:15", "18:50", [], "lea-thursday-evening", "Hebdomadaire : jeudi soir")

    # A same-day early example only supplies reviews once its real arrival has passed.
    if start.weekday() < 5:
        add_trip("lea-launch-" + start.isoformat(), "demo_lea", start, "Commerce", "ESGI Nantes",
                 "07:20", "07:50", [], "launch-review-example", "Exemple de démarrage, avis après l’arrivée")
    joliverie = date(2026, 11, 12)
    if start <= joliverie <= end:
        add_trip("joliverie-2026-11-12", "demo_karim", joliverie, "ESGI Nantes", "Porte de Vertou",
                 "17:30", "18:05", [{"place": "Joliverie", "time": "17:45"}],
                 "joliverie-thursday-example", "Exemple avec étape intermédiaire recherchable")

    bookings: list[dict] = []

    def book(trip_key: str, passenger: str, series: str, frequency: str) -> None:
        bookings.append({"key": passenger + "-" + trip_key, "trip_key": trip_key,
                         "passenger_key": passenger, "status": "confirmed",
                         "demo_series_key": series, "demo_frequency_label": frequency})

    # Four consecutive weekdays show daily reservations without making Karim mostly a passenger.
    for day in weekdays[:4]:
        book("alice-" + day.isoformat(), "demo_karim", "karim-alice-daily", "Réservations quotidiennes")
    mondays = [day for day in weekdays if day.weekday() == 0]
    for day in mondays[:3]:
        book("karim-" + day.isoformat(), "demo_alice", "alice-karim-mondays", "Réservations hebdomadaires : lundi")
    thursdays = [day for day in weekdays if day.weekday() == 3]
    for day in thursdays[:3]:
        book("alice-" + day.isoformat(), "demo_lea", "lea-alice-thursdays", "Réservations récurrentes : jeudi")
    if start.weekday() < 5:
        book("lea-launch-" + start.isoformat(), "demo_alice", "launch-review-example", "Exemple de démarrage")

    # Leave one valid participant pair without seeded reviews so the real UI can be tested.
    pending_trip_key = "alice-2026-11-11"
    if any(trip["key"] == pending_trip_key for trip in trips):
        book(pending_trip_key, "demo_lea", "pending-review-example", "Réservation pour tester la rédaction d’un avis")
        bookings[-1]["seed_reviews"] = False
        bookings[-1]["purpose"] = "Conserver les deux avis Alice/Léa non rédigés pour vérification dans l’application."

    by_trip = {trip["key"]: trip for trip in trips}
    reviews: list[dict] = []
    for booking in bookings:
        trip = by_trip[booking["trip_key"]]
        if trip["status"] != "completed" or booking.get("seed_reviews") is False:
            continue
        for author, recipient, rating, comment in (
            (booking["passenger_key"], trip["driver_key"], 5, "Trajet ponctuel et rendez-vous facile à trouver."),
            (trip["driver_key"], booking["passenger_key"], 4, "Bon échange et présence à l’heure prévue."),
        ):
            reviews.append({"trip_key": trip["key"], "author_key": author, "recipient_key": recipient,
                            "rating": rating, "comment": "Avis fictif de démonstration : " + comment,
                            "eligible_after": trip["arrival_at"]})

    balance = [{"account_key": account["key"],
                "driven_trips": sum(trip["driver_key"] == account["key"] for trip in trips),
                "passenger_bookings": sum(booking["passenger_key"] == account["key"] for booking in bookings)}
               for account in accounts]
    return {
        "version": 2, "prepared_at": now.isoformat(), "status": "prepared_only_not_inserted",
        "scope": "CampusRide — données fictives de démonstration", "timezone": "Europe/Paris",
        "window": {"from": start.isoformat(), "through": end.isoformat(), "weekdays_only": True},
        "authentication": {"passwords_included": False, "note": "Provisionnement séparé ; aucun secret ou hachage dans le plan."},
        "preservation": {"existing_accounts_changed": False, "existing_rows_deleted": False, "existing_rows_modified": False,
                         "reuse_rule": "Clés de démonstration stables, avec registre d’import ; ne jamais modifier un compte existant par rapprochement de nom."},
        "recurrence_note": "Séries de trajets et réservations indépendants matérialisés. Aucun abonnement ni réservation automatique n’est prétendu.",
        "review_rule": "Insérer uniquement après vérification que l’arrivée réelle est passée et que la réservation confirmée existe. Ne jamais avancer artificiellement une date pour autoriser un avis.",
        "counts": {"accounts": len(accounts), "trips": len(trips),
                   "past_trips": sum(trip["status"] == "completed" for trip in trips),
                   "future_or_in_progress_trips": sum(trip["status"] == "published" for trip in trips),
                   "bookings": len(bookings), "reviews": len(reviews)},
        "usage_balance": balance, "accounts": accounts,
        "trips": sorted(trips, key=lambda trip: (trip["departure_at"], trip["key"])),
        "bookings": bookings, "reviews": reviews,
        "validation_scenarios": [
            {"case": "intermediate-stop-search", "from": "Joliverie", "to": "Porte de Vertou",
             "date": "2026-11-12", "expected_trip_key": "joliverie-2026-11-12"},
            {"case": "empty-date-search", "expected": "Tous les trajets futurs correspondants, du plus proche au plus éloigné."},
            {"case": "reviews", "expected": "Avis des seuls participants confirmés après l’arrivée réelle ; futur et doublon refusés."},
            {"case": "pending-review", "trip_key": pending_trip_key,
             "participants": ["demo_alice", "demo_lea"],
             "expected": "Réservation confirmée et aucun avis prérempli pour ce duo. Après l’arrivée réelle, Léa peut rédiger son avis sur Alice ; le retour Alice vers Léa reste également disponible."},
        ],
    }


def validate(plan: dict, now: datetime) -> dict:
    start = date.fromisoformat(plan["window"]["from"])
    end = date.fromisoformat(plan["window"]["through"])
    by_trip = {trip["key"]: trip for trip in plan["trips"]}
    account_keys = {account["key"] for account in plan["accounts"]}
    assert len(by_trip) == len(plan["trips"]), "Duplicate trip key"
    assert len({booking["key"] for booking in plan["bookings"]}) == len(plan["bookings"]), "Duplicate booking key"
    assert all(account["name"].startswith("Démo — ") for account in plan["accounts"]), "Unmarked account"
    assert all(start <= datetime.fromisoformat(trip["departure_at"]).date() <= end
               and datetime.fromisoformat(trip["departure_at"]).weekday() < 5
               and datetime.fromisoformat(trip["arrival_at"]) > datetime.fromisoformat(trip["departure_at"])
               and trip["driver_key"] in account_keys for trip in plan["trips"]), "Invalid trip calendar"
    assert all((trip["status"] == "completed") == (datetime.fromisoformat(trip["arrival_at"]) <= now)
               for trip in plan["trips"]), "Incorrect completion state"
    assert all(booking["trip_key"] in by_trip and booking["passenger_key"] in account_keys
               and by_trip[booking["trip_key"]]["driver_key"] != booking["passenger_key"]
               for booking in plan["bookings"]), "Invalid booking participants"
    passenger_counts = Counter(booking["trip_key"] for booking in plan["bookings"])
    assert all(passenger_counts[trip["key"]] <= trip["seats_total"] for trip in plan["trips"]), "Overbooked trip"
    seen = set()
    for review in plan["reviews"]:
        trip = by_trip[review["trip_key"]]
        review_key = (review["trip_key"], review["author_key"], review["recipient_key"])
        assert review_key not in seen, "Duplicate review"
        seen.add(review_key)
        assert datetime.fromisoformat(trip["arrival_at"]) <= now and trip["status"] == "completed", "Future review"
        assert any(booking["trip_key"] == trip["key"]
                   and {trip["driver_key"], booking["passenger_key"]} == {review["author_key"], review["recipient_key"]}
                   for booking in plan["bookings"]), "Ineligible review participants"
    for booking in plan["bookings"]:
        if booking.get("seed_reviews") is False:
            driver = by_trip[booking["trip_key"]]["driver_key"]
            assert not any(review["trip_key"] == booking["trip_key"]
                           and {review["author_key"], review["recipient_key"]} == {driver, booking["passenger_key"]}
                           for review in plan["reviews"]), "Pending review pair was prefilled"
    assert all(item["driven_trips"] > item["passenger_bookings"] for item in plan["usage_balance"]), "Account is not predominantly a driver"
    serialized = json.dumps(plan, ensure_ascii=False).lower()
    assert '"password"' not in serialized and '"password_hash"' not in serialized and '"token"' not in serialized, "Credential material present"
    return {"passed": True, "checks": ["unique keys", "weekday date window", "arrival and completion timestamps",
                                          "booking references and capacity", "past-only eligible reviews", "predominant drivers", "no credentials"]}


def seed_sql(plan: dict) -> str:
    """Return an owner-only additive import; its bcrypt input stays outside this file."""
    compact = {key: plan[key] for key in ("window", "accounts", "trips", "bookings", "reviews")}
    sql = r"""-- CampusRide demo import: 11 November through 20 December 2026.
-- PREPARATION ONLY. Requires the corrections API migration to be installed first.
-- The caller must set campusride.demo_password_hash in THIS SAME SESSION.
-- Supply a bcrypt cost-10 hash, never a plaintext password. No credential is embedded.
-- Existing user records (including Benjamin and Patrick) are never updated.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE TABLE IF NOT EXISTS campusride.demo_entities(
 namespace text NOT NULL,kind text NOT NULL CHECK(kind IN ('account','trip','booking','review')),
 entity_key text NOT NULL,entity_id bigint NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(namespace,kind,entity_key),UNIQUE(namespace,kind,entity_id)
);
ALTER TABLE campusride.demo_entities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON campusride.demo_entities FROM PUBLIC,anon,authenticated;
DO $import$
DECLARE
 plan jsonb:=$demo_plan$__DEMO_PLAN__$demo_plan$::jsonb;
 ns text:='__DEMO_NAMESPACE__';
 supplied_hash text:=current_setting('campusride.demo_password_hash',true);
 item jsonb; existing_id bigint; new_id bigint; driver bigint; passenger bigint;
 trip_id bigint; review_author bigint; review_recipient bigint; review_key text;
 start_date date; end_date date; dep timestamptz; arr timestamptz; loaded_trip public.carpools%ROWTYPE;
BEGIN
 IF supplied_hash IS NULL OR supplied_hash !~ '^\$2a\$10\$[./A-Za-z0-9]{53}$' THEN
   RAISE EXCEPTION 'Missing or invalid private bcrypt cost-10 input; set campusride.demo_password_hash in this session.';
 END IF;
 start_date:=(plan#>>'{window,from}')::date;end_date:=(plan#>>'{window,through}')::date;
 PERFORM pg_advisory_xact_lock(hashtextextended(ns,0));
 FOR item IN SELECT value FROM jsonb_array_elements(plan->'accounts') LOOP
   IF (item->>'name') NOT LIKE 'Démo — %' THEN RAISE EXCEPTION 'Every imported account must be visibly marked as a demo.'; END IF;
   SELECT entity_id INTO existing_id FROM campusride.demo_entities WHERE namespace=ns AND kind='account' AND entity_key=item->>'key';
   IF existing_id IS NOT NULL THEN
     IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=existing_id) THEN RAISE EXCEPTION 'Demo account mapping is stale; manual inspection required.'; END IF;
     CONTINUE;
   END IF;
   IF EXISTS(SELECT 1 FROM public.users WHERE lower(btrim(name))=lower(btrim(item->>'name'))) THEN
     RAISE EXCEPTION 'An account already uses a planned demo name; no existing account has been modified.';
   END IF;
   INSERT INTO public.users(name,password,school,starting_point)
     VALUES(item->>'name','!managed-by-campusride',item->>'school',item->>'starting_point') RETURNING id INTO new_id;
   INSERT INTO campusride.credentials(user_id,password_hash) VALUES(new_id,supplied_hash);
   INSERT INTO campusride.demo_entities VALUES(ns,'account',item->>'key',new_id,now());
 END LOOP;
 FOR item IN SELECT value FROM jsonb_array_elements(plan->'trips') LOOP
   SELECT entity_id INTO existing_id FROM campusride.demo_entities WHERE namespace=ns AND kind='trip' AND entity_key=item->>'key';
   IF existing_id IS NOT NULL THEN
     IF NOT EXISTS(SELECT 1 FROM public.carpools WHERE id=existing_id) THEN RAISE EXCEPTION 'Demo trip mapping is stale; manual inspection required.'; END IF;
     CONTINUE;
   END IF;
   SELECT entity_id INTO driver FROM campusride.demo_entities WHERE namespace=ns AND kind='account' AND entity_key=item->>'driver_key';
   IF driver IS NULL THEN RAISE EXCEPTION 'Missing mapped demo driver.'; END IF;
   dep:=(item->>'departure_at')::timestamptz;arr:=(item->>'arrival_at')::timestamptz;
   IF dep IS NULL OR arr IS NULL OR (dep AT TIME ZONE 'Europe/Paris')::date NOT BETWEEN start_date AND end_date
      OR extract(isodow FROM dep AT TIME ZONE 'Europe/Paris')>5 OR arr<=dep THEN
     RAISE EXCEPTION 'Invalid demonstration date window or arrival.';
   END IF;
   PERFORM campusride.validate_stops(item->'stops');
   INSERT INTO public.carpools(author_id,title,starting_point,end_point,departure_at,arrival_at,seats_total,price,meeting_point,stops,status)
     VALUES(driver,(item->>'starting_point')||' → '||(item->>'end_point'),item->>'starting_point',item->>'end_point',
       dep,arr,(item->>'seats_total')::integer,(item->>'price_eur')::numeric,item->>'meeting_point',item->'stops',
       CASE WHEN arr<=now() THEN 'completed' ELSE 'published' END) RETURNING id INTO new_id;
   INSERT INTO campusride.demo_entities VALUES(ns,'trip',item->>'key',new_id,now());
 END LOOP;
 FOR item IN SELECT value FROM jsonb_array_elements(plan->'bookings') LOOP
   SELECT entity_id INTO existing_id FROM campusride.demo_entities WHERE namespace=ns AND kind='booking' AND entity_key=item->>'key';
   IF existing_id IS NOT NULL THEN
     IF NOT EXISTS(SELECT 1 FROM public.bookings WHERE id=existing_id) THEN RAISE EXCEPTION 'Demo booking mapping is stale; manual inspection required.'; END IF;
     CONTINUE;
   END IF;
   SELECT entity_id INTO trip_id FROM campusride.demo_entities WHERE namespace=ns AND kind='trip' AND entity_key=item->>'trip_key';
   SELECT entity_id INTO passenger FROM campusride.demo_entities WHERE namespace=ns AND kind='account' AND entity_key=item->>'passenger_key';
   SELECT * INTO loaded_trip FROM public.carpools WHERE id=trip_id FOR UPDATE;
   IF loaded_trip.id IS NULL OR passenger IS NULL OR loaded_trip.author_id=passenger OR loaded_trip.status='cancelled'
      OR (SELECT count(*) FROM public.bookings WHERE carpools_id=trip_id AND status='confirmed')>=loaded_trip.seats_total THEN
     RAISE EXCEPTION 'Invalid demo booking, cancelled trip, or insufficient capacity.';
   END IF;
   INSERT INTO public.bookings(carpools_id,passenger_id,status) VALUES(trip_id,passenger,'confirmed') RETURNING id INTO new_id;
   INSERT INTO campusride.demo_entities VALUES(ns,'booking',item->>'key',new_id,now());
 END LOOP;
 FOR item IN SELECT value FROM jsonb_array_elements(plan->'reviews') LOOP
   review_key:=(item->>'trip_key')||':'||(item->>'author_key')||':'||(item->>'recipient_key');
   SELECT entity_id INTO existing_id FROM campusride.demo_entities WHERE namespace=ns AND kind='review' AND entity_key=review_key;
   IF existing_id IS NOT NULL THEN
     IF NOT EXISTS(SELECT 1 FROM campusride.reviews WHERE id=existing_id) THEN RAISE EXCEPTION 'Demo review mapping is stale; manual inspection required.'; END IF;
     CONTINUE;
   END IF;
   SELECT entity_id INTO trip_id FROM campusride.demo_entities WHERE namespace=ns AND kind='trip' AND entity_key=item->>'trip_key';
   SELECT entity_id INTO review_author FROM campusride.demo_entities WHERE namespace=ns AND kind='account' AND entity_key=item->>'author_key';
   SELECT entity_id INTO review_recipient FROM campusride.demo_entities WHERE namespace=ns AND kind='account' AND entity_key=item->>'recipient_key';
   SELECT * INTO loaded_trip FROM public.carpools WHERE id=trip_id FOR UPDATE;
   IF loaded_trip.id IS NULL OR review_author IS NULL OR review_recipient IS NULL OR review_author=review_recipient
      OR loaded_trip.status='cancelled' OR COALESCE(loaded_trip.arrival_at,loaded_trip.departure_at) IS NULL OR COALESCE(loaded_trip.arrival_at,loaded_trip.departure_at)>now()
      OR NOT ((loaded_trip.author_id=review_author AND EXISTS(SELECT 1 FROM public.bookings WHERE carpools_id=trip_id AND passenger_id=review_recipient AND status='confirmed'))
           OR (loaded_trip.author_id=review_recipient AND EXISTS(SELECT 1 FROM public.bookings WHERE carpools_id=trip_id AND passenger_id=review_author AND status='confirmed'))) THEN
     RAISE EXCEPTION 'A demonstration review requires an actually finished shared trip.';
   END IF;
   INSERT INTO campusride.reviews(carpool_id,author_id,recipient_id,rating,comment)
     VALUES(trip_id,review_author,review_recipient,(item->>'rating')::integer,item->>'comment') RETURNING id INTO new_id;
   INSERT INTO campusride.demo_entities VALUES(ns,'review',review_key,new_id,now());
 END LOOP;
END $import$;
COMMIT;
-- Safe import report: no credentials, tokens, or password hashes are returned.
SELECT kind,count(*) AS imported_entities FROM campusride.demo_entities
 WHERE namespace='__DEMO_NAMESPACE__' GROUP BY kind ORDER BY kind;
"""
    namespace = "campusride-demo-" + plan["window"]["from"].replace("-", "") + "-" + plan["window"]["through"].replace("-", "")
    return sql.replace("__DEMO_PLAN__", json.dumps(compact, ensure_ascii=False, separators=(",", ":"))).replace("__DEMO_NAMESPACE__", namespace)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", type=date.fromisoformat, default=date(2026, 11, 11))
    parser.add_argument("--end", type=date.fromisoformat, default=date(2026, 12, 20))
    parser.add_argument("--now", help="Timezone-aware ISO timestamp for deterministic validation")
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("DEMO-20261111-20261220.json"))
    parser.add_argument("--seed-output", type=Path, default=Path(__file__).with_name("seed-demo-20261111-20261220.sql"))
    args = parser.parse_args()
    now = datetime.fromisoformat(args.now) if args.now else datetime.now(PARIS)
    if now.tzinfo is None:
        parser.error("--now must include an explicit UTC offset")
    plan = prepare(args.start, args.end, now)
    plan["validation"] = validate(plan, now)
    args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    args.seed_output.write_text(seed_sql(plan), encoding="utf-8")
    print(json.dumps({"path": str(args.output), "seed_path": str(args.seed_output), "counts": plan["counts"], "validation": plan["validation"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
