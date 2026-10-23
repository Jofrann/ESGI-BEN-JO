# CampusRide — livraison du MVP

Application existante : https://jo-ben.appsmith.com/app/esgi-benjamin-jofran/page1-6aabbe1923246bf3eb399479?branch=master

Interface refaite depuis la maquette fournie : accueil, inscription/connexion, tableau de bord, recherche et filtres, détails, publication avec étapes, gestion des passagers, réservations et annulations, historique, avis, profil, messages et notifications.

La migration ajoute les champs nécessaires aux quatre tables existantes, puis un backend privé pour les mots de passe hachés, sessions, avis, notifications et requêtes dédupliquées. Elle conserve les tables et données existantes. Les annulations métier changent un statut ; elles ne suppriment pas les lignes.

Le paiement reste entre étudiants, conformément au MVP. Les notifications sont internes à l’application. Les actualisations sont explicites. Une session serveur dure huit heures et une actualisation complète du navigateur demande de se reconnecter. Le nom est aussi l’identifiant de connexion.

Validation : compilation JSX ; tests PostgreSQL avec données entièrement annulées ; contrôle du pont interface/base avec une connexion invalide ; parcours d’interface authentifiée sur jeu synthétique local ; contrôles portrait et paysage sans débordement horizontal. Le scénario navigateur avec deux comptes réels n’a pas été exécuté. Le transfert d’une photo par l’extension de navigateur est bloqué par sa permission locale ; sa validation et sa persistance côté base sont testées séparément.

`migration.sql` décrit le schéma livré ; `backend-qa.sql` est une suite transactionnelle dont l’exception finale QA_PASSED annule volontairement toutes les données de test. `verification.sql` est en lecture seule. `verification.json` conserve les résultats observés. Les sources du widget et les contrats de design figurent dans ce dossier et dans le dépôt Git de l’application. Une sauvegarde exportée de l’application précédente est conservée localement dans work/mvp/appsmith-before.json ; le commit 2959991 précède la refonte.
