-- =====================================================================
--  PRESSA - Base de données complète pour pressing
--  MySQL 8 / MariaDB 10.4+ (XAMPP) - InnoDB - utf8mb4 - devise FCFA
--
--  Ce script couvre : clients, dépôts et tarifs, paiements et caisse,
--  remboursements, retraits, livraisons, réclamations, communications
--  (SMS préparés), stock et alertes, fournisseurs et achats,
--  équipements et maintenance, dépenses, salaires et présences,
--  utilisateurs et rôles, journal d'audit infalsifiable, et tables de
--  synchronisation pour un fonctionnement hors ligne.
--
--  Principes :
--   - Les règles de gestion critiques sont appliquées par la base
--     (triggers, contraintes, procédures), pas seulement par l'appareil.
--   - Les prix sont copiés à la commande ; les totaux sont recalculés
--     automatiquement.
--   - Les paiements et mouvements de stock ne sont jamais modifiés ni
--     supprimés (on corrige par remboursement ou contre-écriture).
--   - Chaque enregistrement possède un UUID : indispensable pour la
--     synchronisation sans doublon.
--
--  AVANT D'EXÉCUTER : pour une réinstallation complète, supprimez d'abord
--  l'ancienne base (DROP DATABASE pressa;). L'application doit
--  renseigner la variable @app_user_id à chaque connexion (voir README).
-- =====================================================================

CREATE DATABASE IF NOT EXISTS pressa CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE pressa;
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 1. PARAMÈTRES DU PRESSING (une seule source de vérité)
-- ---------------------------------------------------------------------
CREATE TABLE parametres (
  cle VARCHAR(60) NOT NULL PRIMARY KEY,
  valeur VARCHAR(255) NOT NULL,
  description VARCHAR(255) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 2. UTILISATEURS (comptes de connexion)
-- ---------------------------------------------------------------------
CREATE TABLE utilisateurs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  nom VARCHAR(120) NOT NULL,
  email VARCHAR(160) NOT NULL UNIQUE,
  mot_de_passe VARCHAR(255) NOT NULL,              -- haché avec password_hash() côté PHP
  role ENUM('admin','caissier','accueil','production','livreur') NOT NULL DEFAULT 'accueil',
  actif TINYINT(1) NOT NULL DEFAULT 1,
  tentatives_echec INT NOT NULL DEFAULT 0,         -- anti force brute
  verrouille_jusqu_a DATETIME NULL,
  derniere_connexion DATETIME NULL,
  cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modifie_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 3. EMPLOYÉS ET POSTES (une personne peut ne pas avoir de compte)
-- ---------------------------------------------------------------------
CREATE TABLE employes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  utilisateur_id INT NULL UNIQUE,
  nom VARCHAR(120) NOT NULL,
  prenom VARCHAR(120) NULL,
  telephone VARCHAR(30) NULL,
  poste ENUM('gerant','caissier','accueil','laveur','repasseur','detacheur',
             'emballeur','livreur','comptable','autre') NOT NULL,
  date_embauche DATE NULL,
  salaire_mensuel DECIMAL(12,2) NOT NULL DEFAULT 0,
  actif TINYINT(1) NOT NULL DEFAULT 1,
  notes TEXT NULL,
  FOREIGN KEY (utilisateur_id) REFERENCES utilisateurs(id),
  CHECK (salaire_mensuel >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE presences (
  id INT AUTO_INCREMENT PRIMARY KEY,
  employe_id INT NOT NULL,
  date_presence DATE NOT NULL,
  creneau ENUM('matin','apres_midi','journee') NOT NULL DEFAULT 'journee',
  statut ENUM('present','absent','retard','conge','repos') NOT NULL,
  UNIQUE KEY uq_presence (employe_id, date_presence),
  FOREIGN KEY (employe_id) REFERENCES employes(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE salaires (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  employe_id INT NOT NULL,
  periode CHAR(7) NOT NULL,                        -- format AAAA-MM
  montant DECIMAL(12,2) NOT NULL,
  date_paiement DATE NOT NULL,
  mode_paiement ENUM('especes','mtn_momo','orange_money','virement') NOT NULL DEFAULT 'especes',
  session_id INT NULL,                             -- clé ajoutée après la table sessions_caisse
  enregistre_par INT NULL,
  FOREIGN KEY (employe_id) REFERENCES employes(id),
  FOREIGN KEY (enregistre_par) REFERENCES utilisateurs(id),
  CHECK (montant > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 4. CLIENTS (avec consentement pour les messages)
-- ---------------------------------------------------------------------
CREATE TABLE clients (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  nom VARCHAR(120) NOT NULL,
  prenom VARCHAR(120) NULL,
  type_client ENUM('particulier','entreprise') NOT NULL DEFAULT 'particulier',
  telephone VARCHAR(30) NOT NULL,
  telephone_secondaire VARCHAR(30) NULL,
  email VARCHAR(160) NULL,
  adresse VARCHAR(255) NULL,
  quartier VARCHAR(120) NULL,
  canal_prefere ENUM('sms','appel','aucun') NOT NULL DEFAULT 'sms',
  accepte_sms TINYINT(1) NOT NULL DEFAULT 0,       -- 0 par défaut : consentement explicite
  accepte_promotions TINYINT(1) NOT NULL DEFAULT 0,
  date_consentement DATETIME NULL,
  notes TEXT NULL,
  supprime TINYINT(1) NOT NULL DEFAULT 0,          -- suppression logique
  version INT NOT NULL DEFAULT 1,                  -- contrôle de concurrence (synchro)
  cree_par INT NULL,
  cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modifie_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_client_tel (telephone),
  INDEX idx_client_nom (nom, prenom),
  FOREIGN KEY (cree_par) REFERENCES utilisateurs(id),
  CHECK (accepte_sms IN (0,1)),
  CHECK (accepte_promotions IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 5. SERVICES, TYPES D'ARTICLES ET TARIFS HISTORISÉS
-- ---------------------------------------------------------------------
CREATE TABLE services (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  code VARCHAR(20) NOT NULL UNIQUE,
  nom VARCHAR(100) NOT NULL,
  description VARCHAR(255) NULL,
  delai_jours INT NOT NULL DEFAULT 2,
  actif TINYINT(1) NOT NULL DEFAULT 1,
  CHECK (delai_jours >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE types_articles (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  nom VARCHAR(100) NOT NULL UNIQUE,
  unite ENUM('piece','ensemble','kg') NOT NULL DEFAULT 'piece',
  actif TINYINT(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Un tarif = un service appliqué à un type d'article, à partir d'une date.
-- On ne modifie jamais un tarif : on en crée un nouveau avec une nouvelle date.
CREATE TABLE tarifs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  service_id INT NOT NULL,
  type_article_id INT NOT NULL,
  prix DECIMAL(12,2) NOT NULL,
  cout_estime DECIMAL(12,2) NOT NULL DEFAULT 0,
  date_effet DATE NOT NULL,
  UNIQUE KEY uq_tarif (service_id, type_article_id, date_effet),
  FOREIGN KEY (service_id) REFERENCES services(id),
  FOREIGN KEY (type_article_id) REFERENCES types_articles(id),
  CHECK (prix >= 0),
  CHECK (cout_estime >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 6. COMMANDES (dépôts) ET LIGNES
-- ---------------------------------------------------------------------
CREATE TABLE commandes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  reference VARCHAR(30) NOT NULL UNIQUE,           -- ex. PR-261118-A3F9
  client_id INT NOT NULL,
  depose_par INT NULL,
  type_depot ENUM('normal','express') NOT NULL DEFAULT 'normal',
  mode_remise ENUM('retrait','livraison') NOT NULL DEFAULT 'retrait',
  statut ENUM('recu','lavage','repassage','emballage','pret','retire','annule')
         NOT NULL DEFAULT 'recu',
  date_depot DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  date_promise DATE NOT NULL,
  date_pret DATETIME NULL,
  date_retrait DATETIME NULL,
  emplacement VARCHAR(30) NULL,                    -- rayon / étagère
  sous_total DECIMAL(12,2) NOT NULL DEFAULT 0,     -- calculé automatiquement
  remise_montant DECIMAL(12,2) NOT NULL DEFAULT 0,
  motif_remise VARCHAR(255) NULL,
  surcharge_express DECIMAL(12,2) NOT NULL DEFAULT 0, -- calculé automatiquement
  total DECIMAL(12,2) NOT NULL DEFAULT 0,          -- calculé automatiquement
  notes TEXT NULL,
  motif_annulation VARCHAR(255) NULL,
  version INT NOT NULL DEFAULT 1,
  cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modifie_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_cmd_statut (statut),
  INDEX idx_cmd_date (date_depot),
  FOREIGN KEY (client_id) REFERENCES clients(id),
  FOREIGN KEY (depose_par) REFERENCES utilisateurs(id),
  CHECK (remise_montant >= 0),
  CHECK (total >= 0),
  CHECK (statut <> 'annule' OR motif_annulation IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE commande_lignes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  commande_id INT NOT NULL,
  tarif_id INT NOT NULL,
  description VARCHAR(160) NOT NULL,               -- ex. « Chemise blanche Mme Kamga »
  quantite INT NOT NULL DEFAULT 1,
  prix_unitaire DECIMAL(12,2) NOT NULL DEFAULT 0,  -- copié du tarif par trigger
  cout_unitaire DECIMAL(12,2) NOT NULL DEFAULT 0,  -- copié du tarif par trigger
  remise_pct DECIMAL(5,2) NOT NULL DEFAULT 0,
  sous_total DECIMAL(12,2) AS (ROUND(quantite * prix_unitaire * (1 - remise_pct/100), 0)) STORED,
  FOREIGN KEY (commande_id) REFERENCES commandes(id),
  FOREIGN KEY (tarif_id) REFERENCES tarifs(id),
  CHECK (quantite > 0),
  CHECK (remise_pct BETWEEN 0 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE historique_statuts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  commande_id INT NOT NULL,
  ancien_statut VARCHAR(20) NULL,
  nouveau_statut VARCHAR(20) NOT NULL,
  utilisateur_id INT NULL,
  date_changement DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  FOREIGN KEY (commande_id) REFERENCES commandes(id),
  FOREIGN KEY (utilisateur_id) REFERENCES utilisateurs(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 7. CAISSE : sessions, paiements, remboursements
-- ---------------------------------------------------------------------
CREATE TABLE sessions_caisse (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  utilisateur_id INT NOT NULL,
  date_ouverture DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fond_ouverture DECIMAL(12,2) NOT NULL DEFAULT 0,
  date_fermeture DATETIME NULL,
  total_theorique DECIMAL(12,2) NOT NULL DEFAULT 0,  -- espèces nettes (encaissées - sorties)
  total_compte DECIMAL(12,2) NULL,                   -- espèces comptées
  ecart DECIMAL(12,2) AS (total_compte - (fond_ouverture + total_theorique)) STORED, -- compté - attendu
  commentaire_ecart TEXT NULL,
  valide_par INT NULL,
  date_validation DATETIME NULL,
  FOREIGN KEY (utilisateur_id) REFERENCES utilisateurs(id),
  FOREIGN KEY (valide_par) REFERENCES utilisateurs(id),
  CHECK (fond_ouverture >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE salaires ADD CONSTRAINT fk_salaire_session FOREIGN KEY (session_id) REFERENCES sessions_caisse(id);

CREATE TABLE paiements (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),  -- évite les doublons en synchro
  commande_id INT NOT NULL,
  session_id INT NULL,
  montant DECIMAL(12,2) NOT NULL,
  mode ENUM('especes','mtn_momo','orange_money','virement','carte','cheque') NOT NULL,
  reference VARCHAR(100) NULL,                     -- ID de transaction Mobile Money
  enregistre_par INT NULL,
  date_paiement DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_paie_commande (commande_id),
  FOREIGN KEY (commande_id) REFERENCES commandes(id),
  FOREIGN KEY (session_id) REFERENCES sessions_caisse(id),
  FOREIGN KEY (enregistre_par) REFERENCES utilisateurs(id),
  CHECK (montant > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE remboursements (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  commande_id INT NOT NULL,
  session_id INT NULL,
  montant DECIMAL(12,2) NOT NULL,
  mode ENUM('especes','mtn_momo','orange_money','virement','carte','cheque') NOT NULL DEFAULT 'especes',
  motif VARCHAR(255) NOT NULL,
  enregistre_par INT NULL,
  date_remboursement DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  FOREIGN KEY (commande_id) REFERENCES commandes(id),
  FOREIGN KEY (session_id) REFERENCES sessions_caisse(id),
  FOREIGN KEY (enregistre_par) REFERENCES utilisateurs(id),
  CHECK (montant > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 8. LIVRAISONS / COLLECTES, RÉCLAMATIONS, COMMUNICATIONS
-- ---------------------------------------------------------------------
CREATE TABLE courses (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  commande_id INT NOT NULL,
  type ENUM('collecte','livraison') NOT NULL,
  date_prevue DATE NOT NULL,
  creneau ENUM('matin','apres_midi','soir') NOT NULL DEFAULT 'matin',
  adresse VARCHAR(255) NULL,
  statut ENUM('planifiee','en_cours','effectuee','annulee') NOT NULL DEFAULT 'planifiee',
  frais DECIMAL(12,2) NOT NULL DEFAULT 0,
  livreur_id INT NULL,
  date_realisation DATETIME NULL,
  notes VARCHAR(255) NULL,
  FOREIGN KEY (commande_id) REFERENCES commandes(id),
  FOREIGN KEY (livreur_id) REFERENCES employes(id),
  CHECK (frais >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE reclamations (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  client_id INT NOT NULL,
  commande_id INT NULL,
  date_reclamation DATE NOT NULL,
  nature VARCHAR(120) NOT NULL,
  demande TEXT NULL,
  decision TEXT NULL,
  statut ENUM('ouverte','en_cours','cloturee') NOT NULL DEFAULT 'ouverte',
  traite_par INT NULL,
  date_info_client DATE NULL,
  date_cloture DATETIME NULL,
  FOREIGN KEY (client_id) REFERENCES clients(id),
  FOREIGN KEY (commande_id) REFERENCES commandes(id),
  FOREIGN KEY (traite_par) REFERENCES utilisateurs(id),
  CHECK (statut <> 'cloturee' OR decision IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Messages : seulement SMS, appel ou interne (pas de WhatsApp).
CREATE TABLE communications (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  client_id INT NOT NULL,
  commande_id INT NULL,
  canal ENUM('sms','appel','interne') NOT NULL DEFAULT 'sms',
  type ENUM('commande_recue','commande_prete','rappel_retrait','relance_impaye','promotion','autre')
       NOT NULL DEFAULT 'autre',
  contenu TEXT NOT NULL,
  statut ENUM('prepare','envoye_manuellement','echec','annule') NOT NULL DEFAULT 'prepare',
  date_programmee DATETIME NULL,
  date_envoi DATETIME NULL,
  cree_par INT NULL,
  cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (client_id) REFERENCES clients(id),
  FOREIGN KEY (commande_id) REFERENCES commandes(id),
  FOREIGN KEY (cree_par) REFERENCES utilisateurs(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 9. STOCK : produits, mouvements, alertes
-- ---------------------------------------------------------------------
CREATE TABLE produits_stock (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  reference VARCHAR(30) NULL UNIQUE,
  libelle VARCHAR(150) NOT NULL,
  categorie ENUM('consommable','emballage','outillage','autre') NOT NULL DEFAULT 'consommable',
  unite ENUM('kg','litre','paquet','piece','bidon') NOT NULL DEFAULT 'piece',
  quantite_stock DECIMAL(12,3) NOT NULL DEFAULT 0,  -- mis à jour par trigger uniquement
  seuil_min DECIMAL(12,3) NOT NULL DEFAULT 0,
  cout_moyen DECIMAL(12,2) NOT NULL DEFAULT 0,      -- coût moyen pondéré (trigger)
  actif TINYINT(1) NOT NULL DEFAULT 1,
  version INT NOT NULL DEFAULT 1,
  CHECK (quantite_stock >= 0),
  CHECK (seuil_min >= 0),
  CHECK (cout_moyen >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Un mouvement n'est jamais modifié ni supprimé. Les quantités avant/après
-- et le coût moyen sont calculés par trigger, pas par l'application.
CREATE TABLE mouvements_stock (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  produit_id INT NOT NULL,
  type ENUM('entree','sortie','ajustement') NOT NULL,
  quantite DECIMAL(12,3) NOT NULL,                 -- pour un ajustement : stock réel compté
  prix_unitaire DECIMAL(12,2) NULL,                -- uniquement pour une entrée d'achat
  quantite_avant DECIMAL(12,3) NOT NULL DEFAULT 0,
  quantite_apres DECIMAL(12,3) NOT NULL DEFAULT 0,
  cout_moyen_apres DECIMAL(12,2) NOT NULL DEFAULT 0,
  motif VARCHAR(255) NULL,
  reference_document VARCHAR(50) NULL,
  utilisateur_id INT NULL,
  date_mouvement DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  FOREIGN KEY (produit_id) REFERENCES produits_stock(id),
  FOREIGN KEY (utilisateur_id) REFERENCES utilisateurs(id),
  CHECK (quantite >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE alertes_stock (
  id INT AUTO_INCREMENT PRIMARY KEY,
  produit_id INT NOT NULL,
  date_alerte DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  etat ENUM('ouverte','traitee') NOT NULL DEFAULT 'ouverte',
  traitee_par INT NULL,
  date_traitement DATETIME NULL,
  FOREIGN KEY (produit_id) REFERENCES produits_stock(id),
  FOREIGN KEY (traitee_par) REFERENCES utilisateurs(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 10. FOURNISSEURS, ACHATS, RÈGLEMENTS
-- ---------------------------------------------------------------------
CREATE TABLE fournisseurs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  nom VARCHAR(150) NOT NULL,
  telephone VARCHAR(30) NULL,
  email VARCHAR(160) NULL,
  adresse VARCHAR(255) NULL,
  actif TINYINT(1) NOT NULL DEFAULT 1,
  notes TEXT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE bons_achat (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  reference VARCHAR(30) NOT NULL UNIQUE,
  fournisseur_id INT NOT NULL,
  date_bon DATE NOT NULL,
  statut ENUM('brouillon','envoye','recu_partiel','recu','annule') NOT NULL DEFAULT 'brouillon',
  date_reception DATE NULL,
  cree_par INT NULL,
  notes VARCHAR(255) NULL,
  FOREIGN KEY (fournisseur_id) REFERENCES fournisseurs(id),
  FOREIGN KEY (cree_par) REFERENCES utilisateurs(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE bons_achat_lignes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  bon_id INT NOT NULL,
  produit_id INT NOT NULL,
  quantite_commandee DECIMAL(12,3) NOT NULL,
  quantite_recue DECIMAL(12,3) NOT NULL DEFAULT 0,
  prix_unitaire DECIMAL(12,2) NOT NULL,
  FOREIGN KEY (bon_id) REFERENCES bons_achat(id),
  FOREIGN KEY (produit_id) REFERENCES produits_stock(id),
  CHECK (quantite_commandee > 0),
  CHECK (quantite_recue >= 0),
  CHECK (quantite_recue <= quantite_commandee),
  CHECK (prix_unitaire >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE reglements_fournisseurs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  fournisseur_id INT NOT NULL,
  bon_id INT NULL,
  session_id INT NULL,
  montant DECIMAL(12,2) NOT NULL,
  mode ENUM('especes','mtn_momo','orange_money','virement','cheque') NOT NULL DEFAULT 'virement',
  reference VARCHAR(100) NULL,
  enregistre_par INT NULL,
  date_reglement DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  FOREIGN KEY (fournisseur_id) REFERENCES fournisseurs(id),
  FOREIGN KEY (bon_id) REFERENCES bons_achat(id),
  FOREIGN KEY (session_id) REFERENCES sessions_caisse(id),
  FOREIGN KEY (enregistre_par) REFERENCES utilisateurs(id),
  CHECK (montant > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 11. ÉQUIPEMENTS ET MAINTENANCE
-- ---------------------------------------------------------------------
CREATE TABLE equipements (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  designation VARCHAR(150) NOT NULL,
  numero_serie VARCHAR(100) NULL,
  categorie ENUM('machine_laver','presse','secheuse','table_repassage','generateur','autre')
            NOT NULL DEFAULT 'autre',
  date_acquisition DATE NULL,
  valeur_acquisition DECIMAL(12,2) NOT NULL DEFAULT 0,
  fournisseur_id INT NULL,
  etat ENUM('en_service','en_panne','hors_service') NOT NULL DEFAULT 'en_service',
  actif TINYINT(1) NOT NULL DEFAULT 1,
  FOREIGN KEY (fournisseur_id) REFERENCES fournisseurs(id),
  CHECK (valeur_acquisition >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE interventions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  equipement_id INT NOT NULL,
  date_intervention DATE NOT NULL,
  type ENUM('preventive','corrective','nettoyage','autre') NOT NULL DEFAULT 'corrective',
  description TEXT NULL,
  technicien VARCHAR(120) NULL,
  duree_arret_min INT NOT NULL DEFAULT 0,          -- durée d'arrêt en MINUTES
  cout DECIMAL(12,2) NOT NULL DEFAULT 0,
  FOREIGN KEY (equipement_id) REFERENCES equipements(id),
  CHECK (duree_arret_min >= 0),
  CHECK (cout >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 12. DÉPENSES
-- ---------------------------------------------------------------------
CREATE TABLE depenses (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  date_depense DATE NOT NULL,
  categorie ENUM('loyer','electricite_eau','produits_lavage','transport','maintenance',
                 'internet_telephone','impots_taxes','fournitures','publicite','autre') NOT NULL,
  libelle VARCHAR(160) NULL,
  montant DECIMAL(12,2) NOT NULL,
  mode_paiement ENUM('especes','mtn_momo','orange_money','virement','carte','cheque')
                NOT NULL DEFAULT 'especes',
  justificatif VARCHAR(100) NULL,                  -- numéro de reçu ou de facture
  commentaire TEXT NULL,
  fournisseur_id INT NULL,
  intervention_id INT NULL,
  session_id INT NULL,
  enregistre_par INT NULL,
  cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (fournisseur_id) REFERENCES fournisseurs(id),
  FOREIGN KEY (intervention_id) REFERENCES interventions(id),
  FOREIGN KEY (session_id) REFERENCES sessions_caisse(id),
  FOREIGN KEY (enregistre_par) REFERENCES utilisateurs(id),
  CHECK (montant > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 13. JOURNAL D'AUDIT (infalsifiable) ET SYNCHRONISATION HORS LIGNE
-- ---------------------------------------------------------------------
CREATE TABLE journal_audit (
  id INT AUTO_INCREMENT PRIMARY KEY,
  date_heure DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  utilisateur_id INT NULL,
  action VARCHAR(60) NOT NULL,
  table_cible VARCHAR(60) NOT NULL,
  enregistrement_id INT NULL,
  ancienne_valeur TEXT NULL,
  nouvelle_valeur TEXT NULL,
  appareil_uuid CHAR(36) NULL,
  FOREIGN KEY (utilisateur_id) REFERENCES utilisateurs(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE appareils (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE DEFAULT (UUID()),
  nom VARCHAR(100) NOT NULL,
  type ENUM('caisse','tablette','telephone','serveur') NOT NULL DEFAULT 'caisse',
  actif TINYINT(1) NOT NULL DEFAULT 1,
  derniere_synchro DATETIME NULL,
  cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- File d'attente des opérations faites hors ligne sur un appareil.
-- Le serveur les applique une seule fois (idempotence par uuid).
CREATE TABLE file_synchro (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uuid CHAR(36) NOT NULL UNIQUE,                   -- généré sur l'appareil
  appareil_uuid CHAR(36) NOT NULL,
  table_cible VARCHAR(60) NOT NULL,
  enregistrement_uuid CHAR(36) NOT NULL,
  operation ENUM('insert','update','delete') NOT NULL,
  contenu JSON NOT NULL,
  date_locale DATETIME(6) NOT NULL,                -- heure sur l'appareil au moment de l'action
  recu_le DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  statut ENUM('en_attente','appliquee','conflit','rejetee') NOT NULL DEFAULT 'en_attente',
  message_erreur TEXT NULL,
  traitee_le DATETIME NULL,
  INDEX idx_sync_statut (statut)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
--  TRIGGERS : règles de gestion appliquées par la base
-- =====================================================================
DELIMITER $$

-- ---- 13.1 Commandes : copie du prix et du coût à partir du tarif ----
CREATE TRIGGER trg_lignes_avant_insert BEFORE INSERT ON commande_lignes
FOR EACH ROW
BEGIN
  DECLARE v_prix DECIMAL(12,2);
  DECLARE v_cout DECIMAL(12,2);
  DECLARE v_nom VARCHAR(100);
  DECLARE v_statut VARCHAR(20);

  SELECT statut INTO v_statut FROM commandes WHERE id = NEW.commande_id;
  IF v_statut IN ('retire','annule') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Commande clôturée : ajout de ligne impossible';
  END IF;

  SELECT t.prix, t.cout_estime, s.nom INTO v_prix, v_cout, v_nom
  FROM tarifs t JOIN services s ON s.id = t.service_id
  WHERE t.id = NEW.tarif_id;
  IF v_prix IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tarif introuvable';
  END IF;

  SET NEW.prix_unitaire = v_prix;
  SET NEW.cout_unitaire = v_cout;
  IF NEW.description IS NULL OR TRIM(NEW.description) = '' THEN
    SET NEW.description = v_nom;
  END IF;
END$$

-- Le prix figé à la commande ne peut plus changer
CREATE TRIGGER trg_lignes_avant_maj BEFORE UPDATE ON commande_lignes
FOR EACH ROW
BEGIN
  SET NEW.prix_unitaire = OLD.prix_unitaire;
  SET NEW.cout_unitaire = OLD.cout_unitaire;
END$$

-- Après chaque changement de ligne, on demande le recalcul des totaux
CREATE TRIGGER trg_lignes_apres_insert AFTER INSERT ON commande_lignes
FOR EACH ROW
BEGIN
  UPDATE commandes SET sous_total = sous_total WHERE id = NEW.commande_id;
END$$

CREATE TRIGGER trg_lignes_apres_maj AFTER UPDATE ON commande_lignes
FOR EACH ROW
BEGIN
  UPDATE commandes SET sous_total = sous_total WHERE id = NEW.commande_id;
END$$

CREATE TRIGGER trg_lignes_apres_suppr AFTER DELETE ON commande_lignes
FOR EACH ROW
BEGIN
  UPDATE commandes SET sous_total = sous_total WHERE id = OLD.commande_id;
END$$

-- Recalcul des totaux et contrôle des changements de statut
CREATE TRIGGER trg_commande_avant_maj BEFORE UPDATE ON commandes
FOR EACH ROW
BEGIN
  DECLARE v_sous DECIMAL(12,2);
  DECLARE v_pct DECIMAL(6,2);
  DECLARE v_surcharge DECIMAL(12,2);
  DECLARE v_paye DECIMAL(12,2);

  -- 1. Totaux toujours recalculés à partir des lignes
  SELECT COALESCE(SUM(sous_total), 0) INTO v_sous
  FROM commande_lignes WHERE commande_id = OLD.id;
  SELECT CAST(valeur AS DECIMAL(6,2)) INTO v_pct
  FROM parametres WHERE cle = 'surcharge_express_pct';
  SET v_surcharge = IF(NEW.type_depot = 'express', ROUND(v_sous * v_pct / 100), 0);
  SET NEW.sous_total = v_sous;
  SET NEW.surcharge_express = v_surcharge;
  SET NEW.total = v_sous - NEW.remise_montant + v_surcharge;

  -- 2. Solde net (paiements moins remboursements)
  SELECT COALESCE((SELECT SUM(montant) FROM paiements WHERE commande_id = OLD.id), 0)
       - COALESCE((SELECT SUM(montant) FROM remboursements WHERE commande_id = OLD.id), 0)
  INTO v_paye;

  -- 3. Règles de changement de statut
  IF NEW.statut <> OLD.statut THEN
    IF OLD.statut IN ('retire','annule') THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Commande clôturée : statut non modifiable';
    END IF;
    IF NEW.statut = 'retire' AND OLD.statut <> 'pret' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Retrait possible uniquement si la commande est prête';
    END IF;
    IF NEW.statut = 'retire' AND v_paye < NEW.total THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Retrait refusé : solde non réglé';
    END IF;
    IF NEW.statut = 'annule' AND v_paye > 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Annulation refusée : rembourser les paiements d''abord';
    END IF;
    IF NEW.statut = 'pret' AND NEW.date_pret IS NULL THEN
      SET NEW.date_pret = NOW();
    END IF;
    IF NEW.statut = 'retire' THEN
      SET NEW.date_retrait = NOW();
    END IF;
  END IF;
END$$

-- Historique des statuts et journal d'audit
CREATE TRIGGER trg_commande_apres_maj AFTER UPDATE ON commandes
FOR EACH ROW
BEGIN
  IF OLD.statut <> NEW.statut THEN
    INSERT INTO historique_statuts(commande_id, ancien_statut, nouveau_statut, utilisateur_id)
    VALUES (NEW.id, OLD.statut, NEW.statut, @app_user_id);
    INSERT INTO journal_audit(utilisateur_id, action, table_cible, enregistrement_id, ancienne_valeur, nouvelle_valeur)
    VALUES (@app_user_id, 'CHANGEMENT_STATUT', 'commandes', NEW.id, OLD.statut, NEW.statut);
  END IF;
  IF OLD.remise_montant <> NEW.remise_montant THEN
    INSERT INTO journal_audit(utilisateur_id, action, table_cible, enregistrement_id, ancienne_valeur, nouvelle_valeur)
    VALUES (@app_user_id, 'CHANGEMENT_REMISE', 'commandes', NEW.id, OLD.remise_montant, NEW.remise_montant);
  END IF;
END$$

-- ---- 13.2 Paiements : contrôle du solde et immuabilité ----
CREATE TRIGGER trg_paiement_avant_insert BEFORE INSERT ON paiements
FOR EACH ROW
BEGIN
  DECLARE v_total DECIMAL(12,2);
  DECLARE v_statut VARCHAR(20);
  DECLARE v_solde DECIMAL(12,2);

  SELECT total, statut INTO v_total, v_statut FROM commandes WHERE id = NEW.commande_id;
  IF v_statut = 'annule' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Paiement impossible : commande annulée';
  END IF;
  SELECT (v_total
          - COALESCE((SELECT SUM(montant) FROM paiements WHERE commande_id = NEW.commande_id), 0)
          + COALESCE((SELECT SUM(montant) FROM remboursements WHERE commande_id = NEW.commande_id), 0))
  INTO v_solde;
  IF NEW.montant > v_solde THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Montant supérieur au solde restant';
  END IF;
  IF NEW.enregistre_par IS NULL THEN SET NEW.enregistre_par = @app_user_id; END IF;
END$$

CREATE TRIGGER trg_paiement_apres_insert AFTER INSERT ON paiements
FOR EACH ROW
BEGIN
  INSERT INTO journal_audit(utilisateur_id, action, table_cible, enregistrement_id, nouvelle_valeur)
  VALUES (NEW.enregistre_par, 'PAIEMENT', 'paiements', NEW.id, CONCAT(NEW.montant, ' FCFA ', NEW.mode));
  IF NEW.session_id IS NOT NULL AND NEW.mode = 'especes' THEN
    UPDATE sessions_caisse SET total_theorique = total_theorique + NEW.montant WHERE id = NEW.session_id;
  END IF;
END$$

CREATE TRIGGER trg_paiement_avant_maj BEFORE UPDATE ON paiements
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Paiement non modifiable : utiliser un remboursement';
END$$

CREATE TRIGGER trg_paiement_avant_suppr BEFORE DELETE ON paiements
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Paiement non supprimable : utiliser un remboursement';
END$$

-- ---- 13.3 Remboursements ----
CREATE TRIGGER trg_remboursement_avant_insert BEFORE INSERT ON remboursements
FOR EACH ROW
BEGIN
  DECLARE v_solde_encaisse DECIMAL(12,2);
  SELECT COALESCE((SELECT SUM(montant) FROM paiements WHERE commande_id = NEW.commande_id), 0)
       - COALESCE((SELECT SUM(montant) FROM remboursements WHERE commande_id = NEW.commande_id), 0)
  INTO v_solde_encaisse;
  IF NEW.montant > v_solde_encaisse THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Remboursement supérieur aux sommes encaissées';
  END IF;
  IF NEW.enregistre_par IS NULL THEN SET NEW.enregistre_par = @app_user_id; END IF;
END$$

CREATE TRIGGER trg_remboursement_apres_insert AFTER INSERT ON remboursements
FOR EACH ROW
BEGIN
  INSERT INTO journal_audit(utilisateur_id, action, table_cible, enregistrement_id, nouvelle_valeur)
  VALUES (NEW.enregistre_par, 'REMBOURSEMENT', 'remboursements', NEW.id,
          CONCAT(NEW.montant, ' FCFA - ', NEW.motif));
  IF NEW.session_id IS NOT NULL AND NEW.mode = 'especes' THEN
    UPDATE sessions_caisse SET total_theorique = total_theorique - NEW.montant WHERE id = NEW.session_id;
  END IF;
END$$

-- Sorties d'espèces : dépenses, règlements fournisseurs, salaires
CREATE TRIGGER trg_depense_apres_insert AFTER INSERT ON depenses
FOR EACH ROW
BEGIN
  IF NEW.session_id IS NOT NULL AND NEW.mode_paiement = 'especes' THEN
    UPDATE sessions_caisse SET total_theorique = total_theorique - NEW.montant WHERE id = NEW.session_id;
  END IF;
END$$

CREATE TRIGGER trg_reglement_fournisseur_apres_insert AFTER INSERT ON reglements_fournisseurs
FOR EACH ROW
BEGIN
  IF NEW.session_id IS NOT NULL AND NEW.mode = 'especes' THEN
    UPDATE sessions_caisse SET total_theorique = total_theorique - NEW.montant WHERE id = NEW.session_id;
  END IF;
END$$

CREATE TRIGGER trg_salaire_apres_insert AFTER INSERT ON salaires
FOR EACH ROW
BEGIN
  IF NEW.session_id IS NOT NULL AND NEW.mode_paiement = 'especes' THEN
    UPDATE sessions_caisse SET total_theorique = total_theorique - NEW.montant WHERE id = NEW.session_id;
  END IF;
END$$

-- ---- 13.4 Caisse : une session clôturée n'est plus modifiable ----
CREATE TRIGGER trg_session_avant_maj BEFORE UPDATE ON sessions_caisse
FOR EACH ROW
BEGIN
  IF OLD.date_fermeture IS NOT NULL AND (NEW.total_compte <> OLD.total_compte
     OR NEW.total_theorique <> OLD.total_theorique) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Caisse déjà clôturée : montants figés';
  END IF;
END$$

-- ---- 13.5 Tarifs historisés : on ne modifie pas un tarif ----
CREATE TRIGGER trg_tarif_avant_maj BEFORE UPDATE ON tarifs
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tarif historisé : créer un nouveau tarif avec une nouvelle date d''effet';
END$$

-- ---- 13.6 Utilisateurs : journal des changements de rôle ou d'accès ----
CREATE TRIGGER trg_utilisateur_apres_maj AFTER UPDATE ON utilisateurs
FOR EACH ROW
BEGIN
  IF OLD.role <> NEW.role THEN
    INSERT INTO journal_audit(utilisateur_id, action, table_cible, enregistrement_id, ancienne_valeur, nouvelle_valeur)
    VALUES (@app_user_id, 'CHANGEMENT_ROLE', 'utilisateurs', NEW.id, OLD.role, NEW.role);
  END IF;
  IF OLD.actif <> NEW.actif THEN
    INSERT INTO journal_audit(utilisateur_id, action, table_cible, enregistrement_id, ancienne_valeur, nouvelle_valeur)
    VALUES (@app_user_id, 'ACTIVATION', 'utilisateurs', NEW.id, OLD.actif, NEW.actif);
  END IF;
END$$

-- ---- 13.7 Stock : calcul des quantités, refus si stock insuffisant ----
CREATE TRIGGER trg_mvt_avant_insert BEFORE INSERT ON mouvements_stock
FOR EACH ROW
BEGIN
  DECLARE v_qte DECIMAL(12,3);
  DECLARE v_cout DECIMAL(12,2);

  SELECT quantite_stock, cout_moyen INTO v_qte, v_cout
  FROM produits_stock WHERE id = NEW.produit_id FOR UPDATE;
  IF v_qte IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Produit introuvable';
  END IF;

  SET NEW.quantite_avant = v_qte;
  SET NEW.cout_moyen_apres = v_cout;

  IF NEW.type = 'entree' THEN
    IF NEW.quantite <= 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantité d''entrée doit être positive';
    END IF;
    SET NEW.quantite_apres = v_qte + NEW.quantite;
    -- Coût moyen pondéré si un prix d'achat est fourni
    IF NEW.prix_unitaire IS NOT NULL AND (v_qte + NEW.quantite) > 0 THEN
      SET NEW.cout_moyen_apres = ((v_qte * v_cout) + (NEW.quantite * NEW.prix_unitaire)) / (v_qte + NEW.quantite);
    END IF;
  ELSEIF NEW.type = 'sortie' THEN
    IF NEW.quantite <= 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantité de sortie doit être positive';
    END IF;
    IF NEW.quantite > v_qte THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock insuffisant pour cette sortie';
    END IF;
    SET NEW.quantite_apres = v_qte - NEW.quantite;
  ELSE
    -- ajustement : la quantité saisie est le stock réel compté (0 accepté)
    SET NEW.quantite_apres = NEW.quantite;
  END IF;

  IF NEW.utilisateur_id IS NULL THEN SET NEW.utilisateur_id = @app_user_id; END IF;
END$$

CREATE TRIGGER trg_mvt_apres_insert AFTER INSERT ON mouvements_stock
FOR EACH ROW
BEGIN
  UPDATE produits_stock
     SET quantite_stock = NEW.quantite_apres,
         cout_moyen = NEW.cout_moyen_apres,
         version = version + 1
   WHERE id = NEW.produit_id;
END$$

CREATE TRIGGER trg_mvt_avant_maj BEFORE UPDATE ON mouvements_stock
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Mouvement de stock non modifiable : faire une contre-écriture';
END$$

CREATE TRIGGER trg_mvt_avant_suppr BEFORE DELETE ON mouvements_stock
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Mouvement de stock non supprimable';
END$$

-- ---- 13.8 Alertes : créée au passage sous le seuil, une seule ouverte à la fois ----
CREATE TRIGGER trg_produit_apres_insert AFTER INSERT ON produits_stock
FOR EACH ROW
BEGIN
  IF NEW.quantite_stock <= NEW.seuil_min THEN
    INSERT INTO alertes_stock(produit_id, etat) VALUES (NEW.id, 'ouverte');
  END IF;
END$$

CREATE TRIGGER trg_produit_apres_maj AFTER UPDATE ON produits_stock
FOR EACH ROW
BEGIN
  IF NEW.quantite_stock <= NEW.seuil_min AND NOT EXISTS (
       SELECT 1 FROM alertes_stock WHERE produit_id = NEW.id AND etat = 'ouverte') THEN
    INSERT INTO alertes_stock(produit_id, etat) VALUES (NEW.id, 'ouverte');
  END IF;
END$$

-- ---- 13.9 Journal d'audit : jamais modifiable ni supprimable ----
CREATE TRIGGER trg_journal_avant_maj BEFORE UPDATE ON journal_audit
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Journal d''audit en lecture seule';
END$$

CREATE TRIGGER trg_journal_avant_suppr BEFORE DELETE ON journal_audit
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Journal d''audit en lecture seule';
END$$

DELIMITER ;


-- =====================================================================
--  PROCÉDURES : opérations sensibles en une seule transaction verrouillée
-- =====================================================================
DELIMITER $$

-- Encaissement sûr : verrouille la commande pour éviter les doubles paiements
CREATE PROCEDURE sp_enregistrer_paiement(
  IN p_commande_id INT, IN p_montant DECIMAL(12,2), IN p_mode VARCHAR(20),
  IN p_reference VARCHAR(100), IN p_utilisateur_id INT, IN p_session_id INT)
BEGIN
  DECLARE v_total DECIMAL(12,2);
  DECLARE v_statut VARCHAR(20);
  DECLARE v_solde DECIMAL(12,2);

  START TRANSACTION;
  SELECT total, statut INTO v_total, v_statut
  FROM commandes WHERE id = p_commande_id FOR UPDATE;
  IF v_total IS NULL THEN
    ROLLBACK;
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Commande introuvable';
  END IF;

  SELECT v_total
         - COALESCE((SELECT SUM(montant) FROM paiements WHERE commande_id = p_commande_id), 0)
         + COALESCE((SELECT SUM(montant) FROM remboursements WHERE commande_id = p_commande_id), 0)
  INTO v_solde;

  IF p_montant <= 0 OR p_montant > v_solde THEN
    ROLLBACK;
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Montant invalide par rapport au solde';
  END IF;

  SET @app_user_id = p_utilisateur_id;
  INSERT INTO paiements(commande_id, session_id, montant, mode, reference, enregistre_par)
  VALUES (p_commande_id, p_session_id, p_montant, p_mode, p_reference, p_utilisateur_id);
  COMMIT;
END$$

-- Réception d'une ligne de bon d'achat : entrée de stock et mise à jour du bon
CREATE PROCEDURE sp_receptionner_ligne(
  IN p_ligne_id INT, IN p_quantite DECIMAL(12,3), IN p_utilisateur_id INT)
BEGIN
  DECLARE v_bon INT;
  DECLARE v_produit INT;
  DECLARE v_commande DECIMAL(12,3);
  DECLARE v_recue DECIMAL(12,3);
  DECLARE v_prix DECIMAL(12,2);
  DECLARE v_ref VARCHAR(30);
  DECLARE v_restantes INT;

  START TRANSACTION;
  SELECT bon_id, produit_id, quantite_commandee, quantite_recue, prix_unitaire
    INTO v_bon, v_produit, v_commande, v_recue, v_prix
  FROM bons_achat_lignes WHERE id = p_ligne_id FOR UPDATE;
  IF v_produit IS NULL THEN
    ROLLBACK;
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ligne de bon introuvable';
  END IF;
  IF p_quantite <= 0 OR p_quantite > (v_commande - v_recue) THEN
    ROLLBACK;
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantité reçue supérieure au reste à recevoir';
  END IF;

  SELECT reference INTO v_ref FROM bons_achat WHERE id = v_bon;
  SET @app_user_id = p_utilisateur_id;
  INSERT INTO mouvements_stock(produit_id, type, quantite, prix_unitaire, motif, reference_document, utilisateur_id)
  VALUES (v_produit, 'entree', p_quantite, v_prix, CONCAT('Réception bon ', v_ref), v_ref, p_utilisateur_id);

  UPDATE bons_achat_lignes SET quantite_recue = quantite_recue + p_quantite WHERE id = p_ligne_id;

  SELECT COUNT(*) INTO v_restantes FROM bons_achat_lignes
  WHERE bon_id = v_bon AND quantite_recue < quantite_commandee;
  UPDATE bons_achat
     SET statut = IF(v_restantes = 0, 'recu', 'recu_partiel'),
         date_reception = IF(v_restantes = 0, CURDATE(), date_reception)
   WHERE id = v_bon;
  COMMIT;
END$$

-- Clôture de caisse : compare le théorique et le compté, puis fige la session
CREATE PROCEDURE sp_cloturer_caisse(
  IN p_session_id INT, IN p_total_compte DECIMAL(12,2), IN p_commentaire TEXT, IN p_utilisateur_id INT)
BEGIN
  DECLARE v_fermee DATETIME;
  SELECT date_fermeture INTO v_fermee FROM sessions_caisse WHERE id = p_session_id FOR UPDATE;
  IF v_fermee IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cette caisse est déjà clôturée';
  END IF;
  UPDATE sessions_caisse
     SET total_compte = p_total_compte,
         commentaire_ecart = p_commentaire,
         date_fermeture = NOW(),
         valide_par = p_utilisateur_id,
         date_validation = NOW()
   WHERE id = p_session_id;
  -- Les espèces encaissées sont rattachées à la session par trigger ci-dessus.
END$$

DELIMITER ;


-- =====================================================================
--  VUES : indicateurs prêts à l'emploi pour le tableau de bord
-- =====================================================================

-- Solde de chaque commande (payé, remboursé, reste à payer)
CREATE OR REPLACE VIEW vue_commandes_solde AS
SELECT c.id, c.reference, c.client_id, c.statut, c.total,
       COALESCE(p.encaisse, 0) - COALESCE(r.rembourse, 0) AS paye,
       c.total - (COALESCE(p.encaisse, 0) - COALESCE(r.rembourse, 0)) AS reste_a_payer
FROM commandes c
LEFT JOIN (SELECT commande_id, SUM(montant) AS encaisse FROM paiements GROUP BY commande_id) p
       ON p.commande_id = c.id
LEFT JOIN (SELECT commande_id, SUM(montant) AS rembourse FROM remboursements GROUP BY commande_id) r
       ON r.commande_id = c.id;

-- Marge brute estimée par commande (prix de vente - coût estimé)
CREATE OR REPLACE VIEW vue_marge_commandes AS
SELECT l.commande_id,
       SUM(l.sous_total) AS ventes,
       SUM(l.quantite * l.cout_unitaire) AS couts_estimes,
       SUM(l.sous_total) - SUM(l.quantite * l.cout_unitaire) AS marge_brute
FROM commande_lignes l
GROUP BY l.commande_id;

-- État du stock avec indicateur de réapprovisionnement
CREATE OR REPLACE VIEW vue_stock_etat AS
SELECT p.id, p.libelle, p.categorie, p.unite, p.quantite_stock, p.seuil_min, p.cout_moyen,
       p.quantite_stock * p.cout_moyen AS valeur_stock,
       (p.quantite_stock <= p.seuil_min) AS a_reapprovisionner
FROM produits_stock p
WHERE p.actif = 1;

-- Solde dû à chaque fournisseur : achats reçus moins règlements
CREATE OR REPLACE VIEW vue_fournisseurs_solde AS
SELECT f.id, f.nom,
       COALESCE((SELECT SUM(bl.quantite_recue * bl.prix_unitaire)
                 FROM bons_achat_lignes bl JOIN bons_achat b ON b.id = bl.bon_id
                 WHERE b.fournisseur_id = f.id), 0)
       - COALESCE((SELECT SUM(r.montant) FROM reglements_fournisseurs r
                   WHERE r.fournisseur_id = f.id), 0) AS solde_du
FROM fournisseurs f;

-- Commandes en retard : non retirées après la date promise
CREATE OR REPLACE VIEW vue_commandes_en_retard AS
SELECT c.id, c.reference, c.statut, c.date_promise, cl.nom, cl.prenom, cl.telephone
FROM commandes c JOIN clients cl ON cl.id = c.client_id
WHERE c.statut NOT IN ('retire','annule') AND c.date_promise < CURDATE();

-- Tableau de bord du mois en cours (une seule ligne)
CREATE OR REPLACE VIEW vue_tableau_bord AS
SELECT
  (SELECT COUNT(*) FROM clients WHERE supprime = 0) AS clients_total,
  (SELECT COUNT(*) FROM commandes WHERE statut NOT IN ('retire','annule')) AS commandes_en_cours,
  (SELECT COUNT(*) FROM commandes WHERE statut = 'pret') AS commandes_pretes,
  (SELECT COUNT(*) FROM vue_commandes_en_retard) AS commandes_en_retard,
  (SELECT COALESCE(SUM(montant),0) FROM paiements
    WHERE YEAR(date_paiement) = YEAR(CURDATE()) AND MONTH(date_paiement) = MONTH(CURDATE())) AS encaissements_mois,
  (SELECT COALESCE(SUM(montant),0) FROM depenses
    WHERE YEAR(date_depense) = YEAR(CURDATE()) AND MONTH(date_depense) = MONTH(CURDATE())) AS depenses_mois,
  (SELECT COUNT(*) FROM alertes_stock WHERE etat = 'ouverte') AS alertes_stock_ouvertes;


-- =====================================================================
--  DONNÉES DE DÉPART (modifiables depuis l'application)
--  Les triggers de stock et d'alerte sont déjà créés : les alertes
--  initiales sont donc générées correctement (bug corrigé).
-- =====================================================================

INSERT INTO parametres (cle, valeur, description) VALUES
 ('nom_application',        'Pressa',              'Nom du logiciel (titres, icône, domaine)'),
 ('nom_pressing',           'Pressing de la joie', 'Nom affiché sur les reçus et les SMS'),
 ('telephone',              '',                    'Téléphone du pressing'),
 ('adresse',                'Yaoundé, Cameroun',   'Adresse du pressing'),
 ('devise',                 'FCFA',                'Devise'),
 ('surcharge_express_pct',  '30',                  'Majoration pour dépôt express (%)'),
 ('delai_defaut_jours',     '2',                   'Délai par défaut avant retrait prévu'),
 ('tva_pct',                '0',                   'TVA (0 si non assujetti)'),
 ('fuseau_horaire',         'Africa/Douala',       'Fuseau horaire de l''application');

INSERT INTO services (code, nom, description, delai_jours) VALUES
 ('LAV',  'Lavage simple',       'Lavage seul',                   2),
 ('REP',  'Repassage seul',      'Repassage seul',                1),
 ('LR',   'Lavage + repassage',  'Forfait complet',               2),
 ('NET',  'Nettoyage à sec',     'Textiles délicats et costumes', 3),
 ('DET',  'Détachage',           'Traitement des taches',         2);

INSERT INTO types_articles (nom, unite) VALUES
 ('Chemise', 'piece'), ('Pantalon', 'piece'), ('Robe', 'piece'),
 ('Costume', 'ensemble'), ('Veste', 'piece'), ('Drap', 'piece'), ('Couette', 'piece');

-- Tarifs de départ en FCFA (à adapter à vos coûts réels)
INSERT INTO tarifs (service_id, type_article_id, prix, cout_estime, date_effet)
SELECT s.id, t.id, x.prix, x.cout, '2026-01-01'
FROM (
  SELECT 'LAV' AS sc, 'Chemise' AS tn, 1500 AS prix, 650 AS cout UNION ALL
  SELECT 'LAV', 'Pantalon', 1500, 650 UNION ALL
  SELECT 'LAV', 'Drap', 3000, 1300 UNION ALL
  SELECT 'LAV', 'Couette', 6000, 2500 UNION ALL
  SELECT 'REP', 'Chemise', 1000, 350 UNION ALL
  SELECT 'REP', 'Pantalon', 1000, 350 UNION ALL
  SELECT 'LR',  'Chemise', 2500, 1050 UNION ALL
  SELECT 'LR',  'Pantalon', 2500, 1050 UNION ALL
  SELECT 'NET', 'Costume', 5000, 2400 UNION ALL
  SELECT 'NET', 'Robe', 3500, 1600 UNION ALL
  SELECT 'NET', 'Veste', 4000, 1900 UNION ALL
  SELECT 'DET', 'Chemise', 1000, 300
) x
JOIN services s ON s.code = x.sc
JOIN types_articles t ON t.nom = x.tn;

INSERT INTO produits_stock (reference, libelle, categorie, unite, seuil_min) VALUES
 ('LESS-01', 'Lessive professionnelle', 'consommable', 'kg',     5),
 ('ADOU-01', 'Adoucissant',             'consommable', 'litre',  3),
 ('DETA-01', 'Détachant',               'consommable', 'litre',  2),
 ('EMBA-01', 'Emballages plastique',    'emballage',   'paquet', 5),
 ('CINT-01', 'Cintres',                 'emballage',   'piece',  50);


-- =====================================================================
--  CONTRÔLE : ce que le script a créé
-- =====================================================================
SELECT COUNT(*) AS nombre_de_tables
FROM information_schema.tables WHERE table_schema = 'pressa' AND table_type = 'BASE TABLE';

SELECT COUNT(*) AS nombre_de_triggers FROM information_schema.triggers WHERE trigger_schema = 'pressa';

SELECT COUNT(*) AS alertes_stock_initiales FROM alertes_stock;

-- =====================================================================
--  CRÉATION DU PREMIER ADMINISTRATEUR (à faire UNE fois, depuis PHP)
--  Ne mettez jamais de mot de passe en clair dans ce fichier.
--  Dans un terminal PHP :  php -r "echo password_hash('VotreMotDePasse', PASSWORD_DEFAULT);"
--  Puis exécutez :
--    INSERT INTO utilisateurs (nom, email, mot_de_passe, role)
--    VALUES ('Administrateur', 'admin@pressa.local', '<hash-obtenu>', 'admin');
-- =====================================================================
