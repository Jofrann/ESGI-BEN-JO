# Corrections des retours du 4 novembre 2026

État : préparées et testées localement, **non appliquées à Supabase et non publiées dans Appsmith**.

Sources : PDF d’une page reçu le 4 novembre et capture de la discussion. Les éléments relatifs au dossier de cours, à la notation et à la présentation sont exclus.

| Retour | Préparation | Vérification |
|---|---|---|
| Modifier un trajet depuis Gérer | Formulaire prérempli ; conducteur seul, trajet publié et futur, capacité préservant les réservations, contrôle de version | SQL local + composants React |
| Rechercher Joliverie et les étapes | Recherche sur la séquence départ, étapes, destination ; ordre respecté ; trajets personnels inclus | 8 cas purs + composant |
| Recherche sans date | Tous les trajets publiés futurs, sans plafond arbitraire de 300 ; tri chronologique | Source SQL + composant |
| Libellé ambigu | « Retour » dans les confirmations | Composant React |
| Notifications précises | Trajet, date/heure Europe/Paris, aperçu du message, auteur et cibles de navigation | SQL local + composants |
| Notifications cliquables | Conversation ou détail/gestion du trajet ; lecture individuelle contrôlée par propriétaire | SQL local + composants |
| Avis impossibles à tester avant la fin | Règle conservée ; essais sur trajets passés synthétiques, avec rejets futur/doublon/tiers | SQL local, toutes lignes annulées |
| Champ de message au-dessus de la navigation | Formulaire déplacé dans un bloc adjacent à la barre du bas | Compilation + composant |
| Barres permanentes, hauteur remplissant l’écran, un seul scroll | **À terminer côté Appsmith** | Accès navigateur requis |
| Données de démonstration | Plan de 3 comptes Démo, 42 trajets de semaine en novembre, 9 réservations et 5 avis ; aucun mot de passe dans le fichier | Plan validé, aucune insertion |

## Limite de mise en page à résoudre

Le widget classique actuel est dans une iframe `AUTO_HEIGHT`. Les positions fixed/sticky y restent liées à l’iframe ; elles n’ancrent pas une barre au viewport extérieur Appsmith. Imposer une hauteur mobile constante réintroduirait le problème de double défilement.

Vérifier l’accès aux Responsive Custom Widgets / Fit page dans le projet Appsmith avant de choisir le changement de shell. Ne pas présenter un simple sticky CSS comme une correction validée dans l’application publiée. Aucun changement de forfait payant n’est autorisé ni effectué.

## Validation effectuée

- JSX compilé avec esbuild.
- Audit frontend strict : zéro anomalie détectée.
- 8 cas de recherche ordonnée.
- 12 scénarios de composants React avec pont Appsmith simulé : formulaire prérempli, version envoyée, échec conservant la saisie, confirmation avant navigation, sauvegarde, confirmation et rechargement de la version concurrente, recherche par étape, destinations de notifications et libellé Retour.
- PostgreSQL 17 isolé, sans réseau : migration additive exécutée et réexécutée ; tests `CORRECTIONS_QA_PASSED` puis tests du MVP existant. Toutes les lignes synthétiques sont annulées.
- Les quatre tables publiques locales sont une approximation des anciennes tables. La structure et les données réelles doivent être relues avant application.

## Reprise de la mise en ligne

1. Réactiver l’accès navigateur dans Work ; inspecter l’application et les fonctions PostgreSQL actuelles. Sauvegarder les sources des fonctions et relever les comptes existants sans exposer leurs secrets.
2. Appliquer `corrections-20261104.sql` uniquement après cette comparaison ; vérifier par lectures et tests sans effet persistant sur les comptes réels.
3. Résoudre le shell permanent et tester de vrais viewports 320/390, paysage court et tablette, clavier et messagerie.
4. Publier les sources Appsmith après validation de l’API. Ne pas publier le frontend dépendant de `update_trip` avant le backend.
5. Insérer les données de démonstration seulement après confirmation de l’utilisateur. Conserver Benjamin, Patrick et les autres comptes existants. L’enregistrement du mot de passe des nouveaux comptes sera réalisé dans l’interface prévue, sans secret committé ou affiché dans le chat.

SMTP et récupération de compte ne font pas partie de ces retours ; leur état indisponible reste inchangé.
