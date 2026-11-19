PRESSING DE LA JOIE - GUIDE D'INSTALLATION (CAMEROUN / FCFA)
============================================================

PREREQUIS
- Windows 10 ou 11
- XAMPP avec Apache, MySQL et PHP (PHP 8 recommandé)
- Navigateur web et VS Code (facultatif pour utiliser l'application)

INSTALLATION
1. Décompressez Pressing_de_la_joie.zip.
2. Copiez le dossier Pressing_de_la_joie dans C:\xampp\htdocs\
   Vous devez obtenir C:\xampp\htdocs\Pressing_de_la_joie\
3. Ouvrez XAMPP Control Panel et démarrez Apache et MySQL.
4. Ouvrez http://localhost/phpmyadmin
5. Cliquez sur Importer, choisissez le fichier install.sql du projet,
   puis cliquez sur Importer/Exécuter. La base pressing_de_la_joie est créée.
6. Ouvrez http://localhost/Pressing_de_la_joie/setup.php
7. Connectez-vous sur http://localhost/Pressing_de_la_joie/login.php

IDENTIFIANTS INITIAUX
Email : admin@pressing.local
Mot de passe : Admin123!
Changez ce mot de passe dès que possible et supprimez setup.php après
la création du compte administrateur.

FONCTIONNALITES DISPONIBLES
- Tableau de bord et indicateurs de commandes / chiffre d'affaires.
- Gestion des clients et coordonnées téléphoniques camerounaises.
- Dépôts normaux et express, avec majoration express configurable.
- Prestations et tarifs en FCFA ; coût estimé et marge brute indicative.
- Suivi de production : reçu, lavage, repassage, emballage, prêt, retiré.
- Paiements : espèces, MTN Mobile Money, Orange Money, virement et carte.
- Reçu / bon de dépôt imprimable.
- Préparation de SMS simples : l'application ouvre l'application SMS du
  téléphone compatible avec numéro et texte préremplis. L'utilisateur appuie
  lui-même sur Envoyer. Aucun WhatsApp et aucun SMS automatique n'est utilisé.
- Historique des messages et utilisateurs avec rôles.
- Base de données étendue à 25 tables : commandes, caisse, dépenses,
  réclamations, notifications, fournisseurs, stock, achats, équipements,
  maintenance, présences et courses de livraison.

IMPORTANT - TARIFS ET MARGE
Les prix et coûts présents sont des exemples de démarrage en FCFA. Ils ne
constituent pas une garantie de bénéfice. Modifiez les tarifs et coûts estimés
selon vos dépenses réelles (eau, électricité, lessive, salaires, loyer,
maintenance, transport) et les prix pratiqués dans votre quartier.
La marge brute estimée = prix facturé - coût direct estimé. Elle ne représente
pas le bénéfice net de l'entreprise.

CONFIGURATION MYSQL
Fichier : config/config.php
Par défaut sous XAMPP : hôte 127.0.0.1, base pressing_de_la_joie,
utilisateur root, mot de passe vide. Si votre MySQL a un mot de passe,
modifiez DB_PASS.

SECURITE ET SAUVEGARDE
- Changez immédiatement le mot de passe administrateur.
- Ne laissez pas setup.php accessible après installation.
- N'exposez pas directement XAMPP sur Internet ; utilisez un hébergement
  sécurisé avec HTTPS et des sauvegardes régulières pour un usage réel.
- Sauvegardez la base depuis phpMyAdmin > Exporter.

DEPANNAGE
- Erreur base inconnue : réimportez install.sql et vérifiez DB_NAME.
- Page introuvable : vérifiez le dossier dans htdocs et l'URL.
- Apache/MySQL ne démarre pas : vérifiez les ports 80/443/3306.
- SMS : l'action sms: fonctionne sur un appareil et un navigateur compatibles,
  généralement un téléphone avec application SMS configurée. Sur PC seul,
  aucun SMS ne peut partir sans modem GSM ou fournisseur SMS externe.


MODULES DE GESTION COMPLETS
===========================
Depuis le menu latéral, l'administrateur accède aux modules :
- Stock : création des produits, entrées, sorties, ajustements, seuils et historique.
- Fournisseurs : répertoire des fournisseurs.
- Achats : bons d'achat et réception qui augmente le stock une seule fois.
- Maintenance : équipements, interventions, coûts, durées d'arrêt et état des machines.
- Dépenses : saisie et journal des dépenses en FCFA.

Les écrans de gestion du stock, achats, fournisseurs et maintenance sont réservés au rôle administrateur. Le module Dépenses est accessible à l'administrateur et à l'accueil.

IMPORTANT : faites une sauvegarde de la base avant toute mise à jour. Ces pages utilisent les tables stock_products, stock_movements, stock_alerts, suppliers, purchase_orders, purchase_order_items, equipment, interventions et expenses du fichier install.sql.

MISE A JOUR SI L'ANCIENNE BASE EXISTE DEJA
==========================================
Si vous avez déjà installé une ancienne version de Pressing de la joie et que
la base pressing_de_la_joie contient déjà les 25 tables, NE réimportez PAS
install.sql. Faites d'abord une sauvegarde phpMyAdmin > Exporter, puis importez
upgrade_modules.sql. Ce fichier met à jour les déclencheurs d'alerte de stock.


ENVOI DES E-MAILS (SMTP GMAIL)
==============================
Le canal E-mail du menu Messages utilise PHPMailer via SMTP chiffré.
1. Ne mettez jamais le mot de passe de connexion Gmail dans le dépôt ou dans
   le code. Gmail SMTP demande un mot de passe d'application Google (avec la
   validation en deux étapes activée); le mot de passe principal ne convient
   pas. Cette configuration ne modifie aucun mot de passe existant.
2. Installez Composer et exécutez `composer install` à la racine du projet.
3. Définissez PRESSA_SMTP_USERNAME, PRESSA_SMTP_PASSWORD, PRESSA_SMTP_HOST
   (smtp.gmail.com), PRESSA_SMTP_PORT (587) et PRESSA_SMTP_FROM dans
   l'environnement serveur (Apache/Vercel). .env.example est un modèle;
   ne mettez pas de secret dans config.php ni dans Git.
4. Importez archive/upgrade_email.sql dans phpMyAdmin sur la base pressa
   existante, après sauvegarde. Les nouvelles installations prennent la
   modification dans pressa_complet.sql.
5. Ajoutez une adresse e-mail valide à la fiche du client. Dans Messages,
   choisissez le client, le canal E-mail et envoyez.

Le secret SMTP doit être un mot de passe d'application fourni par le titulaire
du compte et stocké uniquement dans l'environnement du serveur. Aucun mot de
passe Gmail n'est enregistré dans les fichiers du projet.


CONNEXION PHP À SUPABASE POSTGRESQL
===================================
Le dump de démonstration est copié dans le projet Supabase Pressa. Les pages
PHP peuvent utiliser PostgreSQL en définissant côté serveur :
  PRESSA_DB_DRIVER=pgsql
  PRESSA_DATABASE_URL=<URL PostgreSQL Session Pooler copiée dans Supabase > Connect>
Conservez le mot de passe PostgreSQL existant. Ne mettez jamais l’URL avec son
secret dans Git. Le modèle .env.example ne contient aucun secret réel. Le mode
local XAMPP reste MySQL tant que PRESSA_DB_DRIVER n’est pas défini.

PUBLICATION VERCEL
==================
Le dépôt Vercel utilise Dockerfile.vercel et Caddyfile pour exécuter PHP avec
FrankenPHP, PDO PostgreSQL et Composer. Les fichiers SQL, les migrations, la
configuration privée et les secrets sont exclus de l’image ou bloqués par le
serveur web. L’application utilise la table app_sessions de Supabase afin de
conserver les sessions entre instances Vercel. La route /health.php vérifie
que PHP et la connexion à PostgreSQL répondent.
Dans les variables d’environnement Production de Vercel, configurez
PRESSA_DB_DRIVER=pgsql et PRESSA_DATABASE_URL avec l’URL Session Pooler du
projet Pressa, puis redéployez. Le mot de passe de la base n’est pas remplacé.
