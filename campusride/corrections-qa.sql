-- Run only after corrections-20261104.sql. Expected final error: CORRECTIONS_QA_PASSED.
-- The deliberate final exception rolls back every synthetic row and row update.
DO $qa$
DECLARE
 a jsonb; b jsonb; c jsonb; outsider jsonb; r jsonb; payload jsonb; snap jsonb;
 t bigint; nid bigint; mid bigint; stamp timestamptz; before_count integer;
 n text:=encode(extensions.gen_random_bytes(8),'hex');
 pw text:=encode(extensions.gen_random_bytes(20),'hex');
BEGIN
 -- Physical table and security must match both fresh installs and moved installs.
 IF to_regclass('public.avis') IS NULL OR to_regclass('campusride.reviews') IS NOT NULL THEN RAISE EXCEPTION 'QA avis physical table mismatch'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.avis'::regclass) THEN RAISE EXCEPTION 'QA avis RLS disabled'; END IF;
 IF has_table_privilege('anon','public.avis','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') OR has_table_privilege('authenticated','public.avis','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='public.avis'::regclass AND a.grantee=0) THEN RAISE EXCEPTION 'QA avis direct table privileges exposed'; END IF;
 IF pg_get_serial_sequence('public.avis','id') IS NULL THEN RAISE EXCEPTION 'QA avis identity sequence missing'; END IF;
 IF has_sequence_privilege('anon',pg_get_serial_sequence('public.avis','id'),'USAGE,SELECT,UPDATE') OR has_sequence_privilege('authenticated',pg_get_serial_sequence('public.avis','id'),'USAGE,SELECT,UPDATE') OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('S',c.relowner))) a WHERE c.oid=pg_get_serial_sequence('public.avis','id')::regclass AND a.grantee=0) THEN RAISE EXCEPTION 'QA avis identity privileges exposed'; END IF;
 a:=campusride.api(jsonb_build_object('op','register','name','QA-corrections-driver-'||n,'password',pw,'starting_point','Beaulieu'));
 b:=campusride.api(jsonb_build_object('op','register','name','QA-corrections-passenger-'||n,'password',pw,'starting_point','Commerce'));
 c:=campusride.api(jsonb_build_object('op','register','name','QA-corrections-second-'||n,'password',pw,'starting_point','Duchesse Anne'));
 outsider:=campusride.api(jsonb_build_object('op','register','name','QA-corrections-outsider-'||n,'password',pw,'starting_point','Nantes'));
 IF a->>'ok' IS DISTINCT FROM 'true' OR b->>'ok' IS DISTINCT FROM 'true' OR c->>'ok' IS DISTINCT FROM 'true' OR outsider->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'QA register failed'; END IF;

 payload:=jsonb_build_object('op','publish','token',a->>'token','request_id','bad-publish','starting_point','Beaulieu','end_point','Commerce','departure_at',now()+interval '2 days','seats_total',3,'price',3,'stops',jsonb_build_array(jsonb_build_object('place','Joliverie','time','25:00')));
 r:=campusride.api(payload); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA invalid stop time accepted'; END IF;
 r:=campusride.api(payload||jsonb_build_object('request_id','bad-place','stops','[null]'::jsonb)); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA malformed stop accepted'; END IF;
 r:=campusride.api(payload||jsonb_build_object('request_id','bad-null','stops','null'::jsonb)); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA null stops accepted'; END IF;
 r:=campusride.api(payload||jsonb_build_object('request_id','publish','stops',jsonb_build_array(jsonb_build_object('place','Joliverie','time','08:15'))));
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'QA publish: %',r; END IF;
 t:=(r->>'trip_id')::bigint;
 r:=campusride.api(jsonb_build_object('op','reserve','token',b->>'token','request_id','reserve-b','trip_id',t)); IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'QA reserve b'; END IF;
 r:=campusride.api(jsonb_build_object('op','reserve','token',c->>'token','request_id','reserve-c','trip_id',t)); IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'QA reserve c'; END IF;
 IF NOT EXISTS(SELECT 1 FROM campusride.notifications WHERE carpool_id=t AND title='Nouvelle réservation' AND actor_id=(b#>>'{data,profile,id}')::bigint AND body LIKE '%Beaulieu → Commerce%' AND body LIKE '%'||to_char((now()+interval '2 days') AT TIME ZONE 'Europe/Paris','DD/MM/YYYY HH24:MI')||'%') THEN RAISE EXCEPTION 'QA booking notification missing route/date/time/actor'; END IF;

 SELECT updated_at INTO stamp FROM public.carpools WHERE id=t;
 payload:=jsonb_build_object('op','update_trip','token',a->>'token','request_id','update','trip_id',t,'expected_updated_at',stamp,'starting_point','Beaulieu','end_point','Commerce','departure_at',now()+interval '3 days','arrival_at',now()+interval '3 days 1 hour','seats_total',2,'price',4,'meeting_point','Entrée principale','stops',jsonb_build_array(jsonb_build_object('place','Joliverie','time','08:15')));
 r:=campusride.api(payload||jsonb_build_object('token',b->>'token','request_id','update-forbidden')); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA passenger could edit trip'; END IF;
 r:=campusride.api(payload||jsonb_build_object('expected_updated_at',stamp-interval '1 hour','request_id','update-stale')); IF r->>'code' IS DISTINCT FROM 'TRIP_CONFLICT' THEN RAISE EXCEPTION 'QA stale guard: %',r; END IF;
 r:=campusride.api(payload||jsonb_build_object('expected_updated_at',NULL,'request_id','update-missing-stamp')); IF r->>'code' IS DISTINCT FROM 'TRIP_CONFLICT' THEN RAISE EXCEPTION 'QA missing stamp guard'; END IF;
 r:=campusride.api(payload||jsonb_build_object('seats_total',1,'request_id','update-capacity')); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA capacity below reservations accepted'; END IF;
 r:=campusride.api(payload||jsonb_build_object('stops','[{"place":"Joliverie","time":"99:99"}]'::jsonb,'request_id','update-bad-stop')); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA invalid update stop accepted'; END IF;
 r:=campusride.api(payload); IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'QA valid update: %',r; END IF;
 IF (SELECT seats_total FROM public.carpools WHERE id=t)<>2 OR (SELECT count(*) FROM public.bookings WHERE carpools_id=t AND status='confirmed')<>2 THEN RAISE EXCEPTION 'QA update lost reservations'; END IF;
 SELECT count(*) INTO before_count FROM campusride.notifications WHERE carpool_id=t AND title='Trajet modifié';
 IF before_count<>2 THEN RAISE EXCEPTION 'QA update passenger notifications'; END IF;
 r:=campusride.api(payload); IF r->>'ok' IS DISTINCT FROM 'true' OR (SELECT count(*) FROM campusride.notifications WHERE carpool_id=t AND title='Trajet modifié')<>before_count THEN RAISE EXCEPTION 'QA update idempotency'; END IF;
 r:=campusride.api(payload||jsonb_build_object('request_id','update-new-stale')); IF r->>'code' IS DISTINCT FROM 'TRIP_CONFLICT' THEN RAISE EXCEPTION 'QA old stamp accepted after update'; END IF;

 SELECT updated_at INTO stamp FROM public.carpools WHERE id=t;
 payload:=payload||jsonb_build_object('expected_updated_at',stamp);
 UPDATE public.carpools SET status='cancelled' WHERE id=t;
 r:=campusride.api(payload||jsonb_build_object('request_id','update-cancelled')); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA cancelled trip editable'; END IF;
 UPDATE public.carpools SET status='completed' WHERE id=t;
 r:=campusride.api(payload||jsonb_build_object('request_id','update-completed')); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA completed trip editable'; END IF;
 UPDATE public.carpools SET status='published',departure_at=now()-interval '2 hours' WHERE id=t;
 r:=campusride.api(payload||jsonb_build_object('request_id','update-past')); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA past trip editable'; END IF;
 UPDATE public.carpools SET departure_at=now()+interval '3 days' WHERE id=t;

 r:=campusride.api(jsonb_build_object('op','message','token',b->>'token','request_id','message','trip_id',t,'recipient_id',a#>>'{data,profile,id}','content','Bonjour, rendez-vous devant le portail du campus.'));
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'QA message: %',r; END IF;
 SELECT id,message_id INTO nid,mid FROM campusride.notifications WHERE carpool_id=t AND kind='message' ORDER BY id DESC LIMIT 1;
 IF mid IS NULL OR NOT EXISTS(SELECT 1 FROM campusride.notifications WHERE id=nid AND actor_id=(b#>>'{data,profile,id}')::bigint AND body LIKE '%Bonjour, rendez-vous devant le portail%' AND body LIKE '%Beaulieu → Commerce%') THEN RAISE EXCEPTION 'QA message preview or target missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.messages WHERE id=mid AND sender_id=(b#>>'{data,profile,id}')::bigint) THEN RAISE EXCEPTION 'QA invalid notification message target'; END IF;
 r:=campusride.api(jsonb_build_object('op','read_notification','token',b->>'token','request_id','read-forbidden','notification_id',nid)); IF r->>'ok'='true' OR EXISTS(SELECT 1 FROM campusride.notifications WHERE id=nid AND read_at IS NOT NULL) THEN RAISE EXCEPTION 'QA another user could mark notification read'; END IF;
 r:=campusride.api(jsonb_build_object('op','read_notification','token',a->>'token','request_id','read-owned','notification_id',nid)); IF r->>'ok' IS DISTINCT FROM 'true' OR NOT EXISTS(SELECT 1 FROM campusride.notifications WHERE id=nid AND read_at IS NOT NULL) THEN RAISE EXCEPTION 'QA own notification read failed'; END IF;
 snap:=campusride.snapshot((outsider#>>'{data,profile,id}')::bigint);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'notifications') x WHERE (x->>'id')::bigint=nid) OR EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'messages') x WHERE (x->>'id')::bigint=mid) THEN RAISE EXCEPTION 'QA notification/message privacy'; END IF;

 r:=campusride.api(jsonb_build_object('op','review','token',b->>'token','request_id','future-review','trip_id',t,'recipient_id',a#>>'{data,profile,id}','rating',5)); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA future review accepted'; END IF;
 UPDATE public.carpools SET departure_at=now()-interval '2 hours',arrival_at=now()-interval '1 hour' WHERE id=t;
 r:=campusride.api(jsonb_build_object('op','review','token',outsider->>'token','request_id','outsider-review','trip_id',t,'recipient_id',a#>>'{data,profile,id}','rating',5)); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA outsider review accepted'; END IF;
 r:=campusride.api(jsonb_build_object('op','review','token',b->>'token','request_id','passenger-review','trip_id',t,'recipient_id',c#>>'{data,profile,id}','rating',5)); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA unrelated passenger review accepted'; END IF;
 r:=campusride.api(jsonb_build_object('op','review','token',b->>'token','request_id','valid-review','trip_id',t,'recipient_id',a#>>'{data,profile,id}','rating',5,'comment','Trajet de test terminé, avis vérifié.')); IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'QA valid past review: %',r; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.avis WHERE carpool_id=t AND author_id=(b#>>'{data,profile,id}')::bigint AND recipient_id=(a#>>'{data,profile,id}')::bigint AND rating=5) THEN RAISE EXCEPTION 'QA review not stored in public.avis'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r#>'{data,reviews}') x WHERE (x->>'carpool_id')::bigint=t AND (x->>'author_id')::bigint=(b#>>'{data,profile,id}')::bigint) THEN RAISE EXCEPTION 'QA reviews API key compatibility failed'; END IF;
 r:=campusride.api(jsonb_build_object('op','review','token',b->>'token','request_id','duplicate-review','trip_id',t,'recipient_id',a#>>'{data,profile,id}','rating',4)); IF r->>'ok'='true' THEN RAISE EXCEPTION 'QA duplicate review accepted'; END IF;

 -- A past cancelled reservation remains reachable from its owned notification.
 UPDATE public.bookings SET status='cancelled' WHERE carpools_id=t AND passenger_id=(b#>>'{data,profile,id}')::bigint;
 snap:=campusride.snapshot((b#>>'{data,profile,id}')::bigint);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'trips') x WHERE (x->>'id')::bigint=t) THEN RAISE EXCEPTION 'QA notified past trip absent from snapshot'; END IF;
 INSERT INTO public.carpools(author_id,title,starting_point,end_point,departure_at,seats_total,price)
 SELECT (a#>>'{data,profile,id}')::bigint,'QA future limit','Beaulieu','Commerce',now()+interval '10 days'+g*interval '1 hour',3,3 FROM generate_series(1,301) g;
 snap:=campusride.snapshot((outsider#>>'{data,profile,id}')::bigint);
 IF (SELECT count(*) FROM jsonb_array_elements(snap->'trips') q WHERE q->>'title'='QA future limit')<>301 THEN RAISE EXCEPTION 'QA future results truncated'; END IF;
 RAISE EXCEPTION 'CORRECTIONS_QA_PASSED: stop validation, edit ownership, conflict, capacity, future-state guards, idempotency, detailed actionable notifications, read ownership, privacy, past review, duplicate/future/outsider review rejection. ALL SYNTHETIC ROWS ROLLED BACK.';
END $qa$;
