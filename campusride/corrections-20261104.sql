-- CampusRide corrections from the 4 November 2026 feedback.
-- Additive; existing accounts, trips, bookings, messages and reviews are preserved.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE campusride.notifications ADD COLUMN IF NOT EXISTS actor_id bigint REFERENCES public.users(id);
ALTER TABLE campusride.notifications ADD COLUMN IF NOT EXISTS message_id bigint REFERENCES public.messages(id);
CREATE INDEX IF NOT EXISTS notifications_actor ON campusride.notifications(actor_id);
CREATE INDEX IF NOT EXISTS notifications_message ON campusride.notifications(message_id);
CREATE OR REPLACE FUNCTION campusride.route_label(c public.carpools) RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT COALESCE(c.starting_point,'Départ')||' → '||COALESCE(c.end_point,'Destination')||' · '||COALESCE(to_char(c.departure_at AT TIME ZONE 'Europe/Paris','DD/MM/YYYY HH24:MI'),'Horaire à confirmer');
$$;
CREATE OR REPLACE FUNCTION campusride.validate_stops(stops jsonb) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE stop jsonb;
BEGIN
 IF jsonb_typeof(stops) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Les étapes doivent former une liste.'; END IF;
 IF jsonb_array_length(stops)>5 THEN RAISE EXCEPTION 'Cinq étapes maximum.'; END IF;
 FOR stop IN SELECT value FROM jsonb_array_elements(stops) LOOP
   IF jsonb_typeof(stop) IS DISTINCT FROM 'object' OR jsonb_typeof(stop->'place') IS DISTINCT FROM 'string' OR length(btrim(COALESCE(stop->>'place','')))<2 OR length(stop->>'place')>300 THEN RAISE EXCEPTION 'Chaque étape doit contenir un lieu de 2 à 300 caractères.'; END IF;
   IF stop ? 'time' AND (jsonb_typeof(stop->'time') IS DISTINCT FROM 'string' OR (stop->>'time'<>'' AND stop->>'time' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')) THEN RAISE EXCEPTION 'Vérifiez les heures des étapes (HH:MM).'; END IF;
 END LOOP;
END;
$$;
CREATE OR REPLACE FUNCTION campusride.snapshot(uid bigint) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
SELECT jsonb_build_object(
 'profile',(SELECT jsonb_build_object('id',u.id,'name',u.name,'school',u.school,'starting_point',u.starting_point,'avatar_url',u.avatar_url,'preferences',u.notification_preferences) FROM public.users u WHERE u.id=uid),
 'trips',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.departure_at,t.id) FROM (
   SELECT c.*,u.name AS driver_name,u.school AS driver_school,
     c.seats_total-(SELECT count(*) FROM public.bookings b WHERE b.carpools_id=c.id AND b.status='confirmed') AS seats_available
   FROM public.carpools c JOIN public.users u ON u.id=c.author_id
   WHERE c.departure_at IS NOT NULL AND c.id IN (
     (SELECT f.id FROM public.carpools f WHERE f.status='published' AND f.departure_at>=now())
     UNION
     (SELECT h.id FROM public.carpools h WHERE h.author_id=uid OR EXISTS(SELECT 1 FROM public.bookings b WHERE b.carpools_id=h.id AND b.passenger_id=uid AND b.status='confirmed') ORDER BY h.departure_at DESC,h.id DESC LIMIT 300)
     UNION
     (SELECT n.carpool_id FROM campusride.notifications n WHERE n.user_id=uid AND n.carpool_id IS NOT NULL ORDER BY n.created_at DESC,n.id DESC LIMIT 100)
     UNION
     (SELECT m.carpool_id FROM public.messages m WHERE (m.sender_id=uid OR m.recipient_id=uid) AND m.carpool_id IS NOT NULL ORDER BY m.created_at DESC,m.id DESC LIMIT 500)
   ))t),'[]'),
 'bookings',COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM (SELECT b.*,u.name AS passenger_name FROM public.bookings b JOIN public.users u ON u.id=b.passenger_id JOIN public.carpools c ON c.id=b.carpools_id WHERE b.passenger_id=uid OR c.author_id=uid)t),'[]'),
 'messages',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.created_at) FROM (SELECT m.*,s.name AS sender_name,r.name AS recipient_name FROM public.messages m JOIN public.users s ON s.id=m.sender_id JOIN public.users r ON r.id=m.recipient_id WHERE m.sender_id=uid OR m.recipient_id=uid ORDER BY m.created_at DESC LIMIT 500)t),'[]'),
 'notifications',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC) FROM (SELECT n.*,a.name AS actor_name FROM campusride.notifications n LEFT JOIN public.users a ON a.id=n.actor_id WHERE n.user_id=uid ORDER BY n.created_at DESC,n.id DESC LIMIT 100)t),'[]'),
 'reviews',COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM (SELECT r.*,u.name AS author_name,v.name AS recipient_name FROM campusride.reviews r JOIN public.users u ON u.id=r.author_id JOIN public.users v ON v.id=r.recipient_id WHERE r.author_id=uid OR r.recipient_id=uid)t),'[]')
);
$$;
CREATE OR REPLACE FUNCTION campusride.api(p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE op text:=COALESCE(p->>'op','ping'); uid bigint; tid bigint; bid bigint; other_id bigint; tok text; result jsonb; old_result jsonb; trip public.carpools%ROWTYPE; bk public.bookings%ROWTYPE; nm text; pw text; hash text; cnt integer; dt timestamptz; arr timestamptz; capacity integer; fare numeric; mid bigint; expected_stamp timestamptz; rid text:=p->>'request_id';
BEGIN
 IF op='ping' THEN RETURN jsonb_build_object('ok',true,'version','CampusRide corrections 2026-11-04'); END IF;
 IF op IN ('register','login') THEN
   nm:=btrim(COALESCE(p->>'name','')); pw:=COALESCE(p->>'password','');
   IF length(nm)<2 OR length(nm)>100 THEN RETURN jsonb_build_object('ok',false,'error','Saisissez un nom de 2 à 100 caractères.'); END IF;
   INSERT INTO campusride.login_attempts(name) VALUES(lower(nm)) ON CONFLICT DO NOTHING;
   UPDATE campusride.login_attempts SET failures=0,window_start=now() WHERE name=lower(nm) AND window_start<now()-interval '15 minutes';
   SELECT failures INTO cnt FROM campusride.login_attempts WHERE name=lower(nm) FOR UPDATE;
   IF cnt>=5 THEN RETURN jsonb_build_object('ok',false,'error','Trop de tentatives. Réessayez dans 15 minutes.'); END IF;
   IF op='register' THEN
     IF length(pw)<10 OR octet_length(pw)>72 THEN RETURN jsonb_build_object('ok',false,'error','Choisissez un mot de passe de 10 à 72 caractères.'); END IF;
     IF length(btrim(COALESCE(p->>'starting_point','')))<2 THEN RETURN jsonb_build_object('ok',false,'error','Indiquez votre lieu de départ habituel.'); END IF;
     IF EXISTS(SELECT 1 FROM public.users WHERE lower(btrim(name))=lower(nm)) THEN RETURN jsonb_build_object('ok',false,'error','Ce nom est déjà utilisé. Choisissez un autre identifiant.'); END IF;
     INSERT INTO public.users(name,password,school,starting_point) VALUES(nm,'!managed-by-campusride',left(COALESCE(p->>'school',''),150),left(btrim(p->>'starting_point'),300)) RETURNING id INTO uid;
     INSERT INTO campusride.credentials VALUES(uid,extensions.crypt(pw,extensions.gen_salt('bf',10)));
   ELSE
     SELECT u.id,c.password_hash INTO uid,hash FROM public.users u JOIN campusride.credentials c ON c.user_id=u.id WHERE lower(btrim(u.name))=lower(nm);
     IF uid IS NULL OR hash<>extensions.crypt(pw,hash) THEN
       UPDATE campusride.login_attempts SET failures=failures+1 WHERE name=lower(nm);
       RETURN jsonb_build_object('ok',false,'error','Nom ou mot de passe incorrect.');
     END IF;
   END IF;
   UPDATE campusride.login_attempts SET failures=0 WHERE name=lower(nm);
   tok:=encode(extensions.gen_random_bytes(32),'hex');
   INSERT INTO campusride.sessions(token_hash,user_id) VALUES(encode(extensions.digest(tok,'sha256'),'hex'),uid);
   RETURN jsonb_build_object('ok',true,'token',tok,'data',campusride.snapshot(uid));
 END IF;
 SELECT user_id INTO uid FROM campusride.sessions WHERE token_hash=encode(extensions.digest(COALESCE(p->>'token',''),'sha256'),'hex') AND expires_at>now();
 IF uid IS NULL THEN RETURN jsonb_build_object('ok',false,'code','SESSION_EXPIRED','error','Votre session a expiré. Reconnectez-vous.'); END IF;
 IF op='logout' THEN DELETE FROM campusride.sessions WHERE token_hash=encode(extensions.digest(p->>'token','sha256'),'hex'); RETURN jsonb_build_object('ok',true); END IF;
 IF op='refresh' THEN RETURN jsonb_build_object('ok',true,'data',campusride.snapshot(uid)); END IF;
 IF rid IS NULL OR length(rid)>100 THEN RAISE EXCEPTION 'Identifiant de requête manquant.'; END IF;
 -- Serialize mutations from the same session owner; duplicate requests are harmless.
 PERFORM pg_advisory_xact_lock(uid);
 SELECT response INTO old_result FROM campusride.requests WHERE user_id=uid AND request_id=rid;
 IF old_result IS NOT NULL THEN RETURN old_result; END IF;
 IF op IN ('publish','update_trip') THEN
   IF op='update_trip' THEN
     tid:=(p->>'trip_id')::bigint;
     SELECT * INTO trip FROM public.carpools WHERE id=tid FOR UPDATE;
     IF trip.id IS NULL OR trip.author_id<>uid OR trip.status<>'published' OR trip.departure_at IS NULL OR trip.departure_at<=now() THEN RAISE EXCEPTION 'Seul le conducteur peut modifier un trajet publié à venir.'; END IF;
     expected_stamp:=NULLIF(p->>'expected_updated_at','')::timestamptz;
     IF expected_stamp IS NULL OR expected_stamp IS DISTINCT FROM trip.updated_at THEN
       RETURN jsonb_build_object('ok',false,'code','TRIP_CONFLICT','error','Ce trajet a changé. Actualisez avant de le modifier.');
     END IF;
   END IF;
   dt:=(p->>'departure_at')::timestamptz; arr:=NULLIF(p->>'arrival_at','')::timestamptz; capacity:=(p->>'seats_total')::integer; fare:=(p->>'price')::numeric;
   IF dt IS NULL OR dt<=now() OR capacity IS NULL OR capacity NOT BETWEEN 1 AND 8 OR fare IS NULL OR fare<0 OR fare>9999 OR length(btrim(COALESCE(p->>'starting_point','')))<2 OR length(btrim(COALESCE(p->>'end_point','')))<2 OR lower(btrim(p->>'starting_point'))=lower(btrim(p->>'end_point')) THEN RAISE EXCEPTION 'Vérifiez les lieux, la date future, les places et le prix.'; END IF;
   IF arr IS NOT NULL AND arr<=dt THEN RAISE EXCEPTION 'L’arrivée doit être après le départ.'; END IF;
   PERFORM campusride.validate_stops(COALESCE(p->'stops','[]'::jsonb));
   IF op='publish' THEN
   INSERT INTO public.carpools(author_id,title,starting_point,end_point,departure_at,arrival_at,seats_total,price,meeting_point,stops) VALUES(uid,left(p->>'starting_point',200)||' → '||left(p->>'end_point',200),left(btrim(p->>'starting_point'),300),left(btrim(p->>'end_point'),300),dt,arr,capacity,fare,left(p->>'meeting_point',2000),COALESCE(p->'stops','[]')) RETURNING id INTO tid;
   ELSE
     SELECT count(*) INTO cnt FROM public.bookings WHERE carpools_id=tid AND status='confirmed';
     IF capacity<cnt THEN RAISE EXCEPTION 'Le nombre de places ne peut pas être inférieur aux réservations confirmées.'; END IF;
     UPDATE public.carpools SET title=left(p->>'starting_point',200)||' → '||left(p->>'end_point',200),
       starting_point=left(btrim(p->>'starting_point'),300),end_point=left(btrim(p->>'end_point'),300),
       departure_at=dt,arrival_at=arr,seats_total=capacity,price=fare,
       meeting_point=left(p->>'meeting_point',2000),stops=COALESCE(p->'stops','[]'::jsonb),updated_at=clock_timestamp()
       WHERE id=tid RETURNING * INTO trip;
     INSERT INTO campusride.notifications(user_id,kind,title,body,carpool_id,actor_id)
       SELECT b.passenger_id,'booking','Trajet modifié',campusride.route_label(trip)||' · Consultez les nouvelles informations.',tid,uid
       FROM public.bookings b WHERE b.carpools_id=tid AND b.status='confirmed';
   END IF;
 ELSIF op IN ('reserve','cancel_booking','cancel_trip','complete_trip','review') THEN
   tid:=(p->>'trip_id')::bigint;
   SELECT * INTO trip FROM public.carpools WHERE id=tid FOR UPDATE;
   IF trip.id IS NULL THEN RAISE EXCEPTION 'Trajet introuvable.'; END IF;
   IF op='reserve' THEN
     IF trip.departure_at IS NULL OR trip.author_id=uid OR trip.status<>'published' OR trip.departure_at<=now() THEN RAISE EXCEPTION 'Ce trajet ne peut pas être réservé.'; END IF;
     IF EXISTS(SELECT 1 FROM public.bookings WHERE carpools_id=tid AND passenger_id=uid AND status='confirmed') THEN RAISE EXCEPTION 'Vous avez déjà réservé ce trajet.'; END IF;
     SELECT count(*) INTO cnt FROM public.bookings WHERE carpools_id=tid AND status='confirmed';
     IF cnt>=trip.seats_total THEN RAISE EXCEPTION 'Ce trajet est complet.'; END IF;
     INSERT INTO public.bookings(carpools_id,passenger_id) VALUES(tid,uid) RETURNING id INTO bid;
     INSERT INTO campusride.notifications(user_id,kind,title,body,carpool_id,actor_id) VALUES(trip.author_id,'booking','Nouvelle réservation',(SELECT name FROM public.users WHERE id=uid)||' a réservé une place · '||campusride.route_label(trip),tid,uid),(uid,'booking','Réservation confirmée',campusride.route_label(trip)||' · 1 place confirmée.',tid,trip.author_id);
   ELSIF op='cancel_booking' THEN
     bid:=(p->>'booking_id')::bigint;
     SELECT * INTO bk FROM public.bookings WHERE id=bid AND carpools_id=tid FOR UPDATE;
     IF bk.id IS NULL OR (bk.passenger_id<>uid AND trip.author_id<>uid) OR trip.departure_at<=now() THEN RAISE EXCEPTION 'Annulation non autorisée.'; END IF;
     UPDATE public.bookings SET status='cancelled',cancelled_at=now(),updated_at=now() WHERE id=bid AND status='confirmed';
     IF FOUND THEN INSERT INTO campusride.notifications(user_id,kind,title,body,carpool_id,actor_id) VALUES(CASE WHEN uid=trip.author_id THEN bk.passenger_id ELSE trip.author_id END,'cancellation','Réservation annulée',campusride.route_label(trip)||' · Une place a été libérée.',tid,uid); END IF;
   ELSIF op='cancel_trip' THEN
     IF trip.author_id<>uid OR trip.departure_at<=now() THEN RAISE EXCEPTION 'Annulation non autorisée.'; END IF;
     IF trip.status='published' THEN
       INSERT INTO campusride.notifications(user_id,kind,title,body,carpool_id,actor_id) SELECT passenger_id,'cancellation','Trajet annulé',campusride.route_label(trip),tid,uid FROM public.bookings WHERE carpools_id=tid AND status='confirmed';
       UPDATE public.bookings SET status='cancelled',cancelled_at=now(),updated_at=now() WHERE carpools_id=tid AND status='confirmed';
       UPDATE public.carpools SET status='cancelled',updated_at=now() WHERE id=tid;
     END IF;
   ELSIF op='complete_trip' THEN
     IF trip.author_id<>uid OR trip.status<>'published' OR COALESCE(trip.arrival_at,trip.departure_at)>now() THEN RAISE EXCEPTION 'Ce trajet ne peut pas être terminé.'; END IF;
     UPDATE public.carpools SET status='completed',updated_at=now() WHERE id=tid;
   ELSE
     other_id:=(p->>'recipient_id')::bigint;
     IF trip.status='cancelled' OR COALESCE(trip.arrival_at,trip.departure_at)>now() OR other_id=uid OR NOT ((trip.author_id=uid AND EXISTS(SELECT 1 FROM public.bookings WHERE carpools_id=tid AND passenger_id=other_id AND status='confirmed')) OR (trip.author_id=other_id AND EXISTS(SELECT 1 FROM public.bookings WHERE carpools_id=tid AND passenger_id=uid AND status='confirmed'))) THEN RAISE EXCEPTION 'Un avis nécessite un trajet effectué ensemble.'; END IF;
     INSERT INTO campusride.reviews(carpool_id,author_id,recipient_id,rating,comment) VALUES(tid,uid,other_id,(p->>'rating')::integer,left(COALESCE(p->>'comment',''),2000));
   END IF;
 ELSIF op='message' THEN
   tid:=(p->>'trip_id')::bigint; other_id:=(p->>'recipient_id')::bigint;
   SELECT * INTO trip FROM public.carpools WHERE id=tid;
   IF trip.id IS NULL OR other_id IS NULL OR other_id=uid OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=other_id) OR NOT (trip.author_id=other_id OR (trip.author_id=uid AND EXISTS(SELECT 1 FROM public.bookings WHERE carpools_id=tid AND passenger_id=other_id))) THEN RAISE EXCEPTION 'Destinataire non autorisé pour ce trajet.'; END IF;
   IF length(btrim(COALESCE(p->>'content','')))=0 OR length(p->>'content')>2000 THEN RAISE EXCEPTION 'Saisissez un message de 1 à 2000 caractères.'; END IF;
   INSERT INTO public.messages(sender_id,recipient_id,content,carpool_id) VALUES(uid,other_id,btrim(p->>'content'),tid) RETURNING id INTO mid;
   INSERT INTO campusride.notifications(user_id,kind,title,body,carpool_id,actor_id,message_id) VALUES(other_id,'message','Nouveau message',(SELECT name FROM public.users WHERE id=uid)||' : '||left(btrim(p->>'content'),120)||CASE WHEN length(btrim(p->>'content'))>120 THEN '…' ELSE '' END||' · '||campusride.route_label(trip),tid,uid,mid);
 ELSIF op='read_messages' THEN UPDATE public.messages SET read_at=now() WHERE recipient_id=uid AND sender_id=(p->>'sender_id')::bigint AND read_at IS NULL;
 ELSIF op='read_notifications' THEN UPDATE campusride.notifications SET read_at=now() WHERE user_id=uid AND read_at IS NULL;
 ELSIF op='read_notification' THEN
   UPDATE campusride.notifications SET read_at=COALESCE(read_at,now()) WHERE id=(p->>'notification_id')::bigint AND user_id=uid;
   IF NOT FOUND THEN RAISE EXCEPTION 'Notification introuvable.'; END IF;
 ELSIF op='profile' THEN
   IF p ? 'avatar_url' AND COALESCE(p->>'avatar_url','')<>'' AND (length(p->>'avatar_url')>100000 OR (p->>'avatar_url') !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$') THEN RAISE EXCEPTION 'Photo invalide ou trop volumineuse.'; END IF;
   IF length(btrim(COALESCE(p->>'name','')))<2 OR length(btrim(COALESCE(p->>'starting_point','')))<2 THEN RAISE EXCEPTION 'Indiquez votre nom et votre lieu de départ.'; END IF;
   UPDATE public.users SET name=left(btrim(p->>'name'),100),school=left(COALESCE(p->>'school',''),150),starting_point=left(btrim(p->>'starting_point'),300),avatar_url=CASE WHEN p ? 'avatar_url' THEN NULLIF(p->>'avatar_url','') ELSE avatar_url END,updated_at=now() WHERE id=uid;
 ELSIF op='preferences' THEN UPDATE public.users SET notification_preferences=jsonb_build_object('booking',COALESCE((p->>'booking')::boolean,true),'cancellation',COALESCE((p->>'cancellation')::boolean,true),'message',COALESCE((p->>'message')::boolean,true)),updated_at=now() WHERE id=uid;
 ELSE RAISE EXCEPTION 'Action inconnue.';
 END IF;
 result:=jsonb_build_object('ok',true,'trip_id',tid,'data',campusride.snapshot(uid));
 INSERT INTO campusride.requests(user_id,request_id,response) VALUES(uid,rid,result);
 RETURN result;
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('ok',false,'error','Cette opération existe déjà. Actualisez la page.');
 WHEN invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('ok',false,'error','Vérifiez les dates et les valeurs saisies.');
 WHEN raise_exception THEN RETURN jsonb_build_object('ok',false,'error',SQLERRM);
END;
$$;
REVOKE ALL ON ALL TABLES IN SCHEMA campusride FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA campusride FROM PUBLIC,anon,authenticated;
COMMIT;
SELECT campusride.api('{"op":"ping"}'::jsonb) AS corrections_result;
