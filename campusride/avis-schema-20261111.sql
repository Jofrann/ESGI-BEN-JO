-- Déplacement réel de la table des avis vers public.avis.
-- Ni copie, ni table vide, ni vue : les lignes, identifiants et dépendances sont conservés.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $migration$
DECLARE
 old_oid oid:=to_regclass('campusride.reviews');
 target_oid oid:=to_regclass('public.avis');
 source_oid oid; seq_oid oid; fn_oid oid; definition text;
 before_count bigint; after_count bigint; before_checksum text; after_checksum text;
 id_att smallint; trip_att smallint; author_att smallint; recipient_att smallint;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('campusride-public-avis-20261111',0));
 IF old_oid IS NOT NULL AND target_oid IS NOT NULL THEN
   RAISE EXCEPTION 'Deux relations d’avis existent déjà. Aucune fusion ni suppression implicite : vérification manuelle requise.';
 END IF;
 source_oid:=COALESCE(old_oid,target_oid);
 IF source_oid IS NULL THEN RAISE EXCEPTION 'Table d’avis existante introuvable ; aucune table vide n’a été créée.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=source_oid AND relkind IN ('r','p')) THEN
   RAISE EXCEPTION 'La relation d’avis doit être une table physique, pas une vue.';
 END IF;
 EXECUTE format('LOCK TABLE %s IN ACCESS EXCLUSIVE MODE',source_oid::regclass);

 -- Une cible préexistante n’est acceptée que si elle conserve le contrat actuel.
 IF EXISTS(
   SELECT 1 FROM (VALUES
     ('id','bigint'::regtype),('carpool_id','bigint'::regtype),('author_id','bigint'::regtype),
     ('recipient_id','bigint'::regtype),('rating','integer'::regtype),('comment','text'::regtype),
     ('created_at','timestamp with time zone'::regtype)
   ) AS expected(name,type_oid)
   WHERE NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=source_oid AND a.attname=expected.name
      AND a.atttypid=expected.type_oid AND a.attnotnull AND NOT a.attisdropped)
 ) THEN RAISE EXCEPTION 'Structure de la table d’avis incompatible ; aucune donnée modifiée.'; END IF;
 SELECT attnum INTO id_att FROM pg_attribute WHERE attrelid=source_oid AND attname='id';
 SELECT attnum INTO trip_att FROM pg_attribute WHERE attrelid=source_oid AND attname='carpool_id';
 SELECT attnum INTO author_att FROM pg_attribute WHERE attrelid=source_oid AND attname='author_id';
 SELECT attnum INTO recipient_att FROM pg_attribute WHERE attrelid=source_oid AND attname='recipient_id';
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=source_oid AND contype='p' AND conkey=ARRAY[id_att]::smallint[])
    OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=source_oid AND contype='u' AND conkey=ARRAY[trip_att,author_att,recipient_att]::smallint[])
    OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=source_oid AND contype='f' AND conkey=ARRAY[trip_att]::smallint[] AND confrelid='public.carpools'::regclass)
    OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=source_oid AND contype='f' AND conkey=ARRAY[author_att]::smallint[] AND confrelid='public.users'::regclass)
    OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=source_oid AND contype='f' AND conkey=ARRAY[recipient_att]::smallint[] AND confrelid='public.users'::regclass)
    OR NOT COALESCE((SELECT array_agg(lower(regexp_replace(pg_get_expr(conbin,conrelid),'[()[:space:]]','','g')))
      FROM pg_constraint WHERE conrelid=source_oid AND contype='c') @>
      ARRAY['rating>=1andrating<=5','lengthcomment<=2000','author_id<>recipient_id']::text[],false)
    OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=source_oid AND attname='id' AND attidentity IN ('a','d')) THEN
   RAISE EXCEPTION 'Contraintes ou identité de la table d’avis incompatibles ; migration annulée.';
 END IF;
 EXECUTE format('SELECT count(*),md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id)::text,''[]'')) FROM %s t',source_oid::regclass)
   INTO before_count,before_checksum;
 IF old_oid IS NOT NULL THEN
   ALTER TABLE campusride.reviews SET SCHEMA public;
   ALTER TABLE public.reviews RENAME TO avis;
 END IF;
 target_oid:=to_regclass('public.avis');
 IF target_oid IS DISTINCT FROM source_oid THEN RAISE EXCEPTION 'L’identité de la table d’avis a changé ; migration annulée.'; END IF;
 ALTER TABLE public.avis ENABLE ROW LEVEL SECURITY;
 REVOKE ALL ON TABLE public.avis FROM PUBLIC,anon,authenticated;
 FOR seq_oid IN
   SELECT s.oid FROM pg_class s JOIN pg_depend d ON d.objid=s.oid AND d.classid='pg_class'::regclass
   WHERE d.refclassid='pg_class'::regclass AND d.refobjid=target_oid AND d.deptype IN ('a','i') AND s.relkind='S'
 LOOP
   EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM PUBLIC,anon,authenticated',seq_oid::regclass);
 END LOOP;

 -- Réécrire uniquement la référence de table dans les fonctions ACTUELLES.
 -- Les fonctionnalités et protections déjà déployées restent inchangées.
 IF to_regprocedure('campusride.api(jsonb)') IS NULL OR to_regprocedure('campusride.snapshot(bigint)') IS NULL THEN
   RAISE EXCEPTION 'API CampusRide manquante ; migration annulée.';
 END IF;
 FOREACH fn_oid IN ARRAY ARRAY['campusride.api(jsonb)'::regprocedure::oid,'campusride.snapshot(bigint)'::regprocedure::oid] LOOP
   definition:=pg_get_functiondef(fn_oid);
   IF position('campusride.reviews' IN definition)>0 THEN
     EXECUTE replace(definition,'campusride.reviews','public.avis');
   ELSIF position('public.avis' IN definition)=0 THEN
     RAISE EXCEPTION 'Référence de table d’avis non reconnue dans une fonction ; vérification manuelle requise.';
   END IF;
 END LOOP;
 EXECUTE 'SELECT count(*),md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id)::text,''[]'')) FROM public.avis t'
   INTO after_count,after_checksum;
 IF before_count IS DISTINCT FROM after_count OR before_checksum IS DISTINCT FROM after_checksum THEN
   RAISE EXCEPTION 'Les avis n’ont pas été conservés à l’identique ; migration annulée.';
 END IF;
END $migration$;
COMMENT ON TABLE public.avis IS 'Avis CampusRide après un trajet partagé terminé. Table physique déplacée sans copie ; accès uniquement via l’API privée CampusRide.';
COMMENT ON COLUMN public.avis.carpool_id IS 'Trajet partagé auquel se rapporte l’avis.';
COMMENT ON COLUMN public.avis.author_id IS 'Compte ayant rédigé l’avis après sa participation au trajet.';
COMMENT ON COLUMN public.avis.recipient_id IS 'Conducteur ou passager évalué pour ce trajet.';
COMMENT ON COLUMN public.avis.rating IS 'Note entière de 1 à 5.';
COMMENT ON COLUMN public.avis.comment IS 'Commentaire facultatif, limité à 2000 caractères.';
COMMIT;
SELECT jsonb_build_object('table','public.avis','physical_table',c.relkind IN ('r','p'),
 'row_count',(SELECT count(*) FROM public.avis),'rls_enabled',c.relrowsecurity,
 'anon_denied',NOT has_table_privilege('anon','public.avis','SELECT,INSERT,UPDATE,DELETE'),
 'authenticated_denied',NOT has_table_privilege('authenticated','public.avis','SELECT,INSERT,UPDATE,DELETE')) AS avis_migration_result
FROM pg_class c WHERE c.oid='public.avis'::regclass;
