# Horaires et états des trajets

Les trois corrections de « Configurer ESGI-BEN-JO » sont intégrées à la version contenant les barres mobiles fixes : arrivée obligatoire et strictement après le départ, En cours au départ avec réservations fermées, Terminé à l’arrivée sans capacité restante dans l’historique.

Les libellés suivent les horaires prévus, avec priorité à l’annulation et à une clôture explicite. La confirmation d’une réservation ne masque jamais l’état du trajet. L’horloge locale actualise l’interface sans requête serveur. Une confirmation ouverte avant le départ se désactive au départ et recontrôle l’heure au clic.

La validation partagée du formulaire concerne publication et modification. Elle conserve la saisie, associe l’erreur au champ et lui donne le focus. Les dates impossibles, arrivées absentes, égales ou antérieures sont rejetées avant toute requête.

## Serveur et préservation

`trip-lifecycle-20261112.sql` a été appliqué sur le projet Supabase `hsnzrpcficwwmyezdjsj`. La migration remplace uniquement la garde d’arrivée dans la définition reconnue de `campusride.api(jsonb)` ; elle est idempotente et refuse une définition inconnue. Les sources d’installation et de corrections incluent également cette règle.

La comparaison avant/après confirme les mêmes empreintes pour 10 utilisateurs, 70 trajets, 21 réservations, 4 messages et 10 avis. OID, propriétaire, search_path, SECURITY INVOKER et ACL de la fonction sont conservés. Les trois anciennes arrivées NULL sont conservées ; ces trajets restent En cours après leur départ jusqu’à une clôture explicite.

## Vérification

- PostgreSQL 17 isolé : publication et modification avec arrivée absente, NULL, vide, égale, antérieure et valide ; fermeture des réservations après départ ; préservation, idempotence, rejet atomique d’une définition inconnue ; suites backend existantes avec rollback.
- 15 groupes React indépendants : cartes, détails, historique, validation accessible, brouillon, confirmation devenue périmée et nettoyage de l’horloge.
- Tests de frontières temporelles et de validation, 8 recherches par itinéraire/étapes, compilation JSX et audit UI strict sans anomalie.
- Navigateur local avec véritable JSX/CSS, iframe opaque, horloge et pont fictifs : Confirmée avant départ, En cours au départ, Terminé à l’arrivée ; historique sans capacité ; trois arrivées invalides sans requête supplémentaire.

Les preuves détaillées et sauvegardes sont conservées localement sous `work/lifecycle-20261112/`. Aucun message ni trajet de test n’a été créé dans la base hébergée. Les tests à horloge contrôlée sont distincts de la vérification de l’application publiée.
