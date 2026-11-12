-- PostgreSQL backend regression test. The final expected error rolls back all fixture rows.
DO $qa$
DECLARE
 a jsonb; b jsonb; r jsonb; payload jsonb; invalid_arrival jsonb;
 trip_id bigint; before_count bigint; before_row jsonb; stamp timestamptz;
 suffix text:=encode(extensions.gen_random_bytes(8),'hex');
 pw text:=encode(extensions.gen_random_bytes(20),'hex');
 departure timestamptz:=now()+interval '1 day';
 arrival timestamptz:=now()+interval '1 day 1 hour';
BEGIN
 a:=campusride.api(jsonb_build_object('op','register','name','QA-lifecycle-driver-'||suffix,'password',pw,'starting_point','Nantes'));
 b:=campusride.api(jsonb_build_object('op','register','name','QA-lifecycle-passenger-'||suffix,'password',pw,'starting_point','Rezé'));
 IF a->>'ok' IS DISTINCT FROM 'true' OR b->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'QA lifecycle registration failed'; END IF;
 payload:=jsonb_build_object('op','publish','token',a->>'token','request_id','publish-missing','starting_point','Nantes','end_point','ESGI','departure_at',departure,'seats_total',3,'price',2,'stops','[]'::jsonb);
 SELECT count(*) INTO before_count FROM public.carpools;
 r:=campusride.api(payload);
 IF r->>'ok'='true' OR r->>'error'<>'L’heure d’arrivée est obligatoire et doit être après le départ.' THEN RAISE EXCEPTION 'QA missing publish arrival accepted: %',r->>'error'; END IF;
 FOR invalid_arrival IN SELECT value FROM jsonb_array_elements(jsonb_build_array(NULL,'',departure,departure-interval '1 minute')) LOOP
   r:=campusride.api(payload||jsonb_build_object('request_id',gen_random_uuid()::text,'arrival_at',invalid_arrival));
   IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA invalid publish arrival accepted'; END IF;
 END LOOP;
 IF (SELECT count(*) FROM public.carpools)<>before_count THEN RAISE EXCEPTION 'QA invalid publish persisted a row'; END IF;
 r:=campusride.api(payload||jsonb_build_object('request_id','publish-valid','arrival_at',arrival));
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'QA valid publish failed: %',r->>'error'; END IF;
 trip_id:=(r->>'trip_id')::bigint;
 SELECT to_jsonb(c),updated_at INTO before_row,stamp FROM public.carpools c WHERE c.id=trip_id;
 payload:=payload||jsonb_build_object('op','update_trip','trip_id',trip_id,'expected_updated_at',stamp,'request_id','update-missing');
 r:=campusride.api(payload);
 IF r->>'ok'='true' OR r->>'error'<>'L’heure d’arrivée est obligatoire et doit être après le départ.' THEN RAISE EXCEPTION 'QA missing update arrival accepted: %',r->>'error'; END IF;
 FOR invalid_arrival IN SELECT value FROM jsonb_array_elements(jsonb_build_array(NULL,'',departure,departure-interval '1 minute')) LOOP
   r:=campusride.api(payload||jsonb_build_object('request_id',gen_random_uuid()::text,'arrival_at',invalid_arrival));
   IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA invalid update arrival accepted'; END IF;
 END LOOP;
 IF (SELECT to_jsonb(c) FROM public.carpools c WHERE c.id=trip_id) IS DISTINCT FROM before_row THEN RAISE EXCEPTION 'QA failed update changed existing trip'; END IF;
 r:=campusride.api(payload||jsonb_build_object('request_id','update-valid','arrival_at',arrival+interval '15 minutes'));
 IF r->>'ok' IS DISTINCT FROM 'true' OR (SELECT arrival_at FROM public.carpools WHERE id=trip_id) IS DISTINCT FROM arrival+interval '15 minutes' THEN RAISE EXCEPTION 'QA valid update failed: %',r->>'error'; END IF;

 -- A trip in progress is not bookable even while its required arrival remains in the future.
 UPDATE public.carpools SET departure_at=now()-interval '1 minute',arrival_at=now()+interval '30 minutes' WHERE id=trip_id;
 r:=campusride.api(jsonb_build_object('op','reserve','token',b->>'token','request_id','reserve-in-progress','trip_id',trip_id));
 IF r->>'ok'='true' OR EXISTS(SELECT 1 FROM public.bookings WHERE carpools_id=trip_id) THEN RAISE EXCEPTION 'QA reservation after departure accepted'; END IF;
 RAISE EXCEPTION 'TRIP_LIFECYCLE_QA_PASSED: publish and update reject missing/null/empty/equal/earlier arrival, accept valid arrival; invalid updates preserve row; bookings stay closed after departure. ALL FIXTURE ROWS ROLLED BACK.';
END $qa$;
