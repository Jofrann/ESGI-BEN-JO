DO $qa$
DECLARE a jsonb; b jsonb; c jsonb; r jsonb; t bigint; booking bigint; base jsonb; n text:=encode(extensions.gen_random_bytes(8),'hex'); pw text:=encode(extensions.gen_random_bytes(20),'hex');
BEGIN
 a:=campusride.api(jsonb_build_object('op','register','name','QA-driver-'||n,'password',pw,'starting_point','Nantes'));
 b:=campusride.api(jsonb_build_object('op','register','name','QA-passenger-'||n,'password',pw,'starting_point','Reze'));
 c:=campusride.api(jsonb_build_object('op','register','name','QA-third-'||n,'password',pw,'starting_point','Reze'));
 IF NOT (a->>'ok')::boolean OR NOT (b->>'ok')::boolean OR NOT (c->>'ok')::boolean THEN RAISE EXCEPTION 'QA register failed: % % %',a,b,c; END IF;
 r:=campusride.api(jsonb_build_object('op','login','name','QA-driver-'||n,'password',pw)); IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA login failed'; END IF;
 r:=campusride.api(jsonb_build_object('op','publish','token',a->>'token','request_id','publish','starting_point','Nantes','end_point','ESGI','departure_at',now()+interval '1 day','seats_total',1,'price',2));
 IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA publish failed: %',r; END IF; t:=(r->>'trip_id')::bigint;
 base:=jsonb_build_object('op','reserve','token',b->>'token','request_id','reserve','trip_id',t); r:=campusride.api(base); IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA reserve failed: %',r; END IF;
 r:=campusride.api(base); IF NOT (r->>'ok')::boolean OR (SELECT count(*) FROM public.bookings WHERE carpools_id=t)<>1 THEN RAISE EXCEPTION 'QA duplicate failed'; END IF;
 r:=campusride.api(jsonb_build_object('op','reserve','token',c->>'token','request_id','full','trip_id',t)); IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA overbooking'; END IF;
 r:=campusride.api(jsonb_build_object('op','cancel_trip','token',b->>'token','request_id','forbidden','trip_id',t)); IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA authorization'; END IF;
 r:=campusride.api(jsonb_build_object('op','message','token',b->>'token','request_id','message','trip_id',t,'recipient_id',a#>>'{data,profile,id}','content','QA message')); IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA message: %',r; END IF;
 SELECT id INTO booking FROM public.bookings WHERE carpools_id=t;
 r:=campusride.api(jsonb_build_object('op','cancel_booking','token',b->>'token','request_id','cancel','trip_id',t,'booking_id',booking)); IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA cancel'; END IF;
 r:=campusride.api(jsonb_build_object('op','reserve','token',c->>'token','request_id','freed','trip_id',t)); IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA freed seat'; END IF;
 UPDATE public.carpools SET departure_at=now()-interval '2 hours',arrival_at=now()-interval '1 hour' WHERE id=t;
 r:=campusride.api(jsonb_build_object('op','review','token',c->>'token','request_id','review','trip_id',t,'recipient_id',a#>>'{data,profile,id}','rating',5,'comment','QA review')); IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA review: %',r; END IF;
 IF (SELECT count(*) FROM campusride.notifications WHERE carpool_id=t)<4 THEN RAISE EXCEPTION 'QA notifications'; END IF;
 r:=campusride.api(jsonb_build_object('op','refresh','token',b->>'token')); IF jsonb_array_length(r#>'{data,messages}')<>1 THEN RAISE EXCEPTION 'QA message scope'; END IF;
 r:=campusride.api(jsonb_build_object('op','refresh','token','invalid')); IF r->>'code'<>'SESSION_EXPIRED' THEN RAISE EXCEPTION 'QA unauthenticated'; END IF;
 r:=campusride.api(jsonb_build_object('op','profile','token',a->>'token','request_id','invalid-photo','name','QA-driver-'||n,'starting_point','Nantes','avatar_url','javascript:alert(1)')); IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA invalid photo accepted'; END IF;
r:=campusride.api(jsonb_build_object('op','profile','token',a->>'token','request_id','valid-photo','name','QA-driver-'||n,'starting_point','Nantes','avatar_url','data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jE1sAAAAASUVORK5CYII=')); IF NOT (r->>'ok')::boolean OR r#>>'{data,profile,avatar_url}' IS NULL THEN RAISE EXCEPTION 'QA photo save failed: %',r; END IF;
r:=campusride.api(jsonb_build_object('op','message','token',a->>'token','request_id','missing-trip','recipient_id',b#>>'{data,profile,id}','content','invalid')); IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'QA missing trip accepted'; END IF;
RAISE EXCEPTION 'QA_PASSED: photo validation and persistence, missing trip guard,  registration, login, publish, reserve, idempotency, capacity, authorization, messages, cancellation, freed seats, reviews, notifications, privacy, session. ALL TEST ROWS ROLLED BACK.';
END $qa$;