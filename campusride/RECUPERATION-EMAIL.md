# Récupération par e-mail — préparation

État au 23 octobre 2026 : le lien et la page d’attente sont intégrés. Le bouton d’envoi est désactivé. Aucun e-mail ni nouvelle adresse ne sont enregistrés. La base et l’authentification existantes restent inchangées.

## Configuration par l’administrateur

Dans Supabase > Authentication > Email > SMTP Settings, saisir directement les paramètres du fournisseur : hôte, port, utilisateur, mot de passe, adresse et nom d’expéditeur. Ne pas transmettre ces secrets dans le chat ni les committer. Vérifier le domaine expéditeur chez le fournisseur.

Documentation officielle : https://supabase.com/docs/guides/auth/auth-smtp

## Raccordement à réaliser après configuration

Les comptes CampusRide utilisent actuellement une authentification privée PostgreSQL par nom et mot de passe. Configurer le SMTP ne suffit donc pas à activer la récupération de ces comptes.

1. Depuis un compte connecté, proposer « Sécuriser mon compte » : adresse e-mail et mot de passe actuel, puis preuve de possession par code Supabase Auth. Associer l’adresse au compte seulement après vérification serveur du code et réauthentification. Ne jamais associer un compte uniquement par son nom ou par une adresse saisie.
2. À la connexion : adresse de récupération, demande de code, code reçu, nouveau mot de passe et confirmation. Donner une réponse neutre, même si l’adresse n’existe pas. Limiter les demandes et les essais.
3. Côté serveur, vérifier la preuve auprès de Supabase Auth et son identité liée au compte. Exiger une preuve récente à usage unique. Mettre à jour le hachage du mot de passe et révoquer les sessions existantes dans une transaction. Ne jamais confier cette décision au navigateur ni y placer une clé secrète.
4. Adapter les modèles d’e-mail Supabase pour afficher le code `{{ .Token }}` si le parcours utilise des codes OTP.
5. Tester avec une vraie boîte : liaison d’adresse, code invalide/expiré/réutilisé, adresse inconnue, changement du mot de passe, ancien mot de passe refusé, sessions révoquées et nouvelle connexion réussie. L’utilisateur saisit lui-même son nouveau mot de passe.
6. Activer le bouton uniquement une fois le raccordement serveur et ces essais terminés.

Les anciens comptes devront se connecter une fois pour associer une adresse vérifiée. Aucune récupération fiable n’est possible pour un ancien compte sans adresse déjà liée.

Documentation OTP : https://supabase.com/docs/guides/auth/auth-email-passwordless

## Vérification visuelle

Depuis « Se connecter », « Mot de passe oublié ? » ouvre la page d’attente. L’envoi est indisponible et aucun faux message « e-mail envoyé » n’est affiché. Les deux retours vers la connexion fonctionnent.
