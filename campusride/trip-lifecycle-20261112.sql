-- CampusRide : arrivée obligatoire pour toute nouvelle publication ou modification.
-- Aucun trajet existant n’est modifié ; les anciennes arrivées NULL sont conservées.
-- N’appliquer qu’après les migrations CampusRide et les correctifs des avis.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $lifecycle$
DECLARE
 fn_oid oid; definition text; source text; normalized_hash text; matches integer;
 old_hash constant text:='45f79dac6b74c8216c114a50da597285';
 new_hash constant text:='1422c0b5fc2c4ba09c20d2dff9971b6a';
 old_pattern constant text:=$pattern$IF[[:space:]]+arr[[:space:]]+IS[[:space:]]+NOT[[:space:]]+NULL[[:space:]]+AND[[:space:]]+arr[[:space:]]*<=[[:space:]]*dt[[:space:]]+THEN[[:space:]]+RAISE[[:space:]]+EXCEPTION[[:space:]]+'L’arrivée doit être après le départ[.]';[[:space:]]+END[[:space:]]+IF;$pattern$;
 new_guard constant text:=$guard$IF arr IS NULL OR arr<=dt THEN RAISE EXCEPTION 'L’heure d’arrivée est obligatoire et doit être après le départ.'; END IF;$guard$;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('campusride-trip-lifecycle-20261112',0));
 fn_oid:=to_regprocedure('campusride.api(jsonb)');
 IF fn_oid IS NULL THEN RAISE EXCEPTION 'API CampusRide introuvable ; aucune modification effectuée.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=fn_oid
   AND l.lanname='plpgsql' AND NOT p.prosecdef AND NOT p.proretset AND p.prorettype='jsonb'::regtype) THEN
   RAISE EXCEPTION 'Définition API CampusRide inconnue ; vérification manuelle requise.';
 END IF;
 SELECT p.prosrc,pg_get_functiondef(p.oid) INTO source,definition FROM pg_proc p WHERE p.oid=fn_oid;
 normalized_hash:=md5(regexp_replace(source,'[[:space:]]+','','g'));
 IF normalized_hash=new_hash THEN RETURN; END IF;
 IF normalized_hash<>old_hash THEN
   RAISE EXCEPTION 'Définition API CampusRide inconnue ; aucun correctif existant n’a été écrasé.';
 END IF;
 SELECT count(*) INTO matches FROM regexp_matches(source,old_pattern,'g');
 IF matches<>1 THEN RAISE EXCEPTION 'Garde d’arrivée non reconnue ; aucune modification effectuée.'; END IF;
 EXECUTE regexp_replace(definition,old_pattern,new_guard,'g');
 SELECT md5(regexp_replace(p.prosrc,'[[:space:]]+','','g')) INTO normalized_hash FROM pg_proc p WHERE p.oid=fn_oid;
 IF normalized_hash<>new_hash THEN RAISE EXCEPTION 'Validation du correctif d’arrivée impossible ; transaction annulée.'; END IF;
END $lifecycle$;
COMMIT;
SELECT jsonb_build_object('arrival_required',true,'legacy_rows_unchanged',true,'api','campusride.api(jsonb)') AS trip_lifecycle_migration_result;
