-- Uniquement une réservation de démonstration pour garder deux avis rédigeables.
-- Aucun compte, trajet, avis ou réservation existant n’est modifié.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $fixture$
DECLARE
 ns constant text:='campusride-demo-20261111-20261220';
 booking_key constant text:='demo_karim-lea-launch-2026-11-11';
 trip_id bigint; demo_passenger_id bigint; expected_driver bigint; existing_id bigint; new_id bigint;
 trip public.carpools%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(ns,0));
 SELECT entity_id INTO trip_id FROM campusride.demo_entities WHERE namespace=ns AND kind='trip' AND entity_key='lea-launch-2026-11-11';
 SELECT entity_id INTO demo_passenger_id FROM campusride.demo_entities WHERE namespace=ns AND kind='account' AND entity_key='demo_karim';
 SELECT entity_id INTO expected_driver FROM campusride.demo_entities WHERE namespace=ns AND kind='account' AND entity_key='demo_lea';
 IF trip_id IS NULL OR demo_passenger_id IS NULL OR expected_driver IS NULL THEN RAISE EXCEPTION 'Données de démonstration attendues introuvables ; aucune réservation ajoutée.'; END IF;
 SELECT * INTO trip FROM public.carpools WHERE id=trip_id FOR UPDATE;
 IF trip.id IS NULL OR trip.author_id IS DISTINCT FROM expected_driver OR demo_passenger_id=expected_driver
    OR trip.status<>'completed' OR COALESCE(trip.arrival_at,trip.departure_at) IS NULL
    OR COALESCE(trip.arrival_at,trip.departure_at)>now() THEN
   RAISE EXCEPTION 'Le trajet partagé doit être terminé et appartenir à la conductrice de démonstration.';
 END IF;
 SELECT entity_id INTO existing_id FROM campusride.demo_entities WHERE namespace=ns AND kind='booking' AND entity_key=booking_key;
 IF existing_id IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.bookings b WHERE b.id=existing_id AND b.carpools_id=trip_id AND b.passenger_id=demo_passenger_id) THEN
     RAISE EXCEPTION 'La correspondance de démonstration est incohérente ; vérification manuelle requise.';
   END IF;
   RETURN;
 END IF;
 IF EXISTS(SELECT 1 FROM public.bookings b WHERE b.carpools_id=trip_id AND b.passenger_id=demo_passenger_id AND b.status='confirmed') THEN
   RAISE EXCEPTION 'Une réservation existe déjà sans correspondance d’import ; aucune donnée modifiée.';
 END IF;
 IF (SELECT count(*) FROM public.bookings b WHERE b.carpools_id=trip_id AND b.status='confirmed')>=trip.seats_total THEN
   RAISE EXCEPTION 'Le trajet de démonstration ne possède plus de place disponible.';
 END IF;
 INSERT INTO public.bookings(carpools_id,passenger_id,status) VALUES(trip_id,demo_passenger_id,'confirmed') RETURNING id INTO new_id;
 INSERT INTO campusride.demo_entities(namespace,kind,entity_key,entity_id) VALUES(ns,'booking',booking_key,new_id);
END $fixture$;
COMMIT;
SELECT jsonb_build_object('booking_key','demo_karim-lea-launch-2026-11-11','confirmed',b.status='confirmed') AS demonstration_review_opportunity
FROM campusride.demo_entities e JOIN public.bookings b ON b.id=e.entity_id
WHERE e.namespace='campusride-demo-20261111-20261220' AND e.kind='booking' AND e.entity_key='demo_karim-lea-launch-2026-11-11';
