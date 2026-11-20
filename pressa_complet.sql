-- phpMyAdmin SQL Dump
-- version 5.2.3
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Nov 19, 2026 at 10:16 PM
-- Server version: 10.11.16-MariaDB
-- PHP Version: 8.3.36

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `pressa`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_cloturer_caisse` (IN `p_session_id` INT, IN `p_total_compte` DECIMAL(12,2), IN `p_commentaire` TEXT, IN `p_utilisateur_id` INT)   BEGIN
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_enregistrer_paiement` (IN `p_commande_id` INT, IN `p_montant` DECIMAL(12,2), IN `p_mode` VARCHAR(20), IN `p_reference` VARCHAR(100), IN `p_utilisateur_id` INT, IN `p_session_id` INT)   BEGIN
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_receptionner_ligne` (IN `p_ligne_id` INT, IN `p_quantite` DECIMAL(12,3), IN `p_utilisateur_id` INT)   BEGIN
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

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `alertes_stock`
--

CREATE TABLE `alertes_stock` (
  `id` int(11) NOT NULL,
  `produit_id` int(11) NOT NULL,
  `date_alerte` datetime NOT NULL DEFAULT current_timestamp(),
  `etat` enum('ouverte','traitee') NOT NULL DEFAULT 'ouverte',
  `traitee_par` int(11) DEFAULT NULL,
  `date_traitement` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `alertes_stock`
--

INSERT INTO `alertes_stock` (`id`, `produit_id`, `date_alerte`, `etat`, `traitee_par`, `date_traitement`) VALUES
(1, 1, '2026-11-19 00:08:16', 'traitee', 1, '2026-11-19 02:05:09'),
(2, 2, '2026-11-19 00:08:16', 'ouverte', NULL, NULL),
(3, 3, '2026-11-19 00:08:16', 'ouverte', NULL, NULL),
(4, 4, '2026-11-19 00:08:16', 'ouverte', NULL, NULL),
(5, 5, '2026-11-19 00:08:16', 'ouverte', NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `appareils`
--

CREATE TABLE `appareils` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `nom` varchar(100) NOT NULL,
  `type` enum('caisse','tablette','telephone','serveur') NOT NULL DEFAULT 'caisse',
  `actif` tinyint(1) NOT NULL DEFAULT 1,
  `derniere_synchro` datetime DEFAULT NULL,
  `cree_le` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `avis_clients`
--

CREATE TABLE `avis_clients` (
  `id` int(11) NOT NULL,
  `client_id` int(11) NOT NULL,
  `commande_id` int(11) NOT NULL,
  `note` tinyint(3) UNSIGNED NOT NULL,
  `commentaire` varchar(1000) DEFAULT NULL,
  `statut` enum('nouveau','lu','traite') NOT NULL DEFAULT 'nouveau',
  `cree_le` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Table structure for table `bons_achat`
--

CREATE TABLE `bons_achat` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `reference` varchar(30) NOT NULL,
  `fournisseur_id` int(11) NOT NULL,
  `date_bon` date NOT NULL,
  `statut` enum('brouillon','envoye','recu_partiel','recu','annule') NOT NULL DEFAULT 'brouillon',
  `date_reception` date DEFAULT NULL,
  `cree_par` int(11) DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `bons_achat`
--

INSERT INTO `bons_achat` (`id`, `uuid`, `reference`, `fournisseur_id`, `date_bon`, `statut`, `date_reception`, `cree_par`, `notes`) VALUES
(1, '44175afb-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-ACHAT-001', 1, '2026-11-19', 'envoye', NULL, 1, 'Bon démo envoyé — réception simulée séparément dans le stock.'),
(2, '44182e66-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-ACHAT-002', 2, '2026-11-19', 'brouillon', NULL, 1, 'Bon démo en brouillon.');

-- --------------------------------------------------------

--
-- Table structure for table `bons_achat_lignes`
--

CREATE TABLE `bons_achat_lignes` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `bon_id` int(11) NOT NULL,
  `produit_id` int(11) NOT NULL,
  `quantite_commandee` decimal(12,3) NOT NULL,
  `quantite_recue` decimal(12,3) NOT NULL DEFAULT 0.000,
  `prix_unitaire` decimal(12,2) NOT NULL
) ;

--
-- Dumping data for table `bons_achat_lignes`
--

INSERT INTO `bons_achat_lignes` (`id`, `uuid`, `bon_id`, `produit_id`, `quantite_commandee`, `quantite_recue`, `prix_unitaire`) VALUES
(1, '441999b5-e3b5-11f1-b0c7-0c5415f01e22', 1, 1, 20.000, 0.000, 2500.00),
(2, '4419def6-e3b5-11f1-b0c7-0c5415f01e22', 1, 2, 10.000, 0.000, 1800.00),
(3, '4419eae0-e3b5-11f1-b0c7-0c5415f01e22', 2, 1, 5.000, 0.000, 2500.00);

-- --------------------------------------------------------

--
-- Table structure for table `clients`
--

CREATE TABLE `clients` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `nom` varchar(120) NOT NULL,
  `prenom` varchar(120) DEFAULT NULL,
  `type_client` enum('particulier','entreprise') NOT NULL DEFAULT 'particulier',
  `telephone` varchar(30) NOT NULL,
  `telephone_secondaire` varchar(30) DEFAULT NULL,
  `email` varchar(160) DEFAULT NULL,
  `adresse` varchar(255) DEFAULT NULL,
  `quartier` varchar(120) DEFAULT NULL,
  `canal_prefere` enum('sms','appel','aucun') NOT NULL DEFAULT 'sms',
  `accepte_sms` tinyint(1) NOT NULL DEFAULT 0,
  `accepte_promotions` tinyint(1) NOT NULL DEFAULT 0,
  `date_consentement` datetime DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `supprime` tinyint(1) NOT NULL DEFAULT 0,
  `version` int(11) NOT NULL DEFAULT 1,
  `cree_par` int(11) DEFAULT NULL,
  `cree_le` datetime NOT NULL DEFAULT current_timestamp(),
  `modifie_le` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `utilisateur_id` int(11) DEFAULT NULL
) ;

--
-- Dumping data for table `clients`
--

INSERT INTO `clients` (`id`, `uuid`, `nom`, `prenom`, `type_client`, `telephone`, `telephone_secondaire`, `email`, `adresse`, `quartier`, `canal_prefere`, `accepte_sms`, `accepte_promotions`, `date_consentement`, `notes`, `supprime`, `version`, `cree_par`, `cree_le`, `modifie_le`, `utilisateur_id`) VALUES
(11, '43f134bc-e3b5-11f1-b0c7-0c5415f01e22', 'Démo 01', 'Amina', 'particulier', 'TEST-CLIENT-01', NULL, 'client.demo01@example.test', 'Adresse de démonstration 1, Yaoundé Centre', 'Yaoundé Centre', 'aucun', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL),
(12, '43f54fb9-e3b5-11f1-b0c7-0c5415f01e22', 'Démo 02', 'Paul', 'particulier', 'TEST-CLIENT-02', NULL, 'client.demo02@example.test', 'Adresse de démonstration 2, Bastos', 'Bastos', 'aucun', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL),
(13, '43fb7bb3-e3b5-11f1-b0c7-0c5415f01e22', 'Démo 03', 'Mireille', 'particulier', 'TEST-CLIENT-03', NULL, 'client.demo03@example.test', 'Adresse de démonstration 3, Mvan', 'Mvan', 'aucun', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL),
(14, '43fdcd19-e3b5-11f1-b0c7-0c5415f01e22', 'Démo 04', 'Samuel', 'particulier', 'TEST-CLIENT-04', NULL, 'client.demo04@example.test', 'Adresse de démonstration 4, Biyem-Assi', 'Biyem-Assi', 'aucun', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL),
(15, '43fdecca-e3b5-11f1-b0c7-0c5415f01e22', 'Démo 05', 'Nadia', 'particulier', 'TEST-CLIENT-05', NULL, 'client.demo05@example.test', 'Adresse de démonstration 5, Essos', 'Essos', 'aucun', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL),
(16, '43fe05c1-e3b5-11f1-b0c7-0c5415f01e22', 'Démo 06', 'Eric', 'particulier', 'TEST-CLIENT-06', NULL, 'client.demo06@example.test', 'Adresse de démonstration 6, Akwa, Douala', 'Akwa, Douala', 'aucun', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL),
(17, '43fe1495-e3b5-11f1-b0c7-0c5415f01e22', 'Démo 07', 'Joëlle', 'particulier', 'TEST-CLIENT-07', NULL, 'client.demo07@example.test', 'Adresse de démonstration 7, Bonapriso, Douala', 'Bonapriso, Douala', 'aucun', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL),
(18, '43fe2114-e3b5-11f1-b0c7-0c5415f01e22', 'Démo 08', 'David', 'particulier', 'TEST-CLIENT-08', NULL, 'client.demo08@example.test', 'Adresse de démonstration 8, Nlongkak', 'Nlongkak', 'aucun', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL),
(19, '43fe2cc8-e3b5-11f1-b0c7-0c5415f01e22', 'Démo 09', 'Clarisse', 'particulier', 'TEST-CLIENT-09', NULL, 'client.demo09@example.test', 'Adresse de démonstration 9, Odza', 'Odza', 'aucun', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL),
(20, '43fe3977-e3b5-11f1-b0c7-0c5415f01e22', 'Démo 10', 'Benoît', 'particulier', 'TEST-CLIENT-10', NULL, 'client.demo10@example.test', 'Adresse de démonstration 10, Mendong', 'Mendong', 'aucun', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL),
(22, 'a689282b-e45b-11f1-b0c7-0c5415f01e22', 'Valdeshack', 'Client', 'particulier', '+237699999999', NULL, 'Valdeshack@gmail.com', 'Adresse client démo', NULL, 'sms', 0, 0, NULL, NULL, 0, 1, 1, '2026-11-19 21:56:11', '2026-11-19 21:56:11', 34);

-- --------------------------------------------------------

--
-- Table structure for table `commandes`
--

CREATE TABLE `commandes` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `reference` varchar(30) NOT NULL,
  `client_id` int(11) NOT NULL,
  `depose_par` int(11) DEFAULT NULL,
  `type_depot` enum('normal','express') NOT NULL DEFAULT 'normal',
  `mode_remise` enum('retrait','livraison') NOT NULL DEFAULT 'retrait',
  `statut` enum('recu','lavage','repassage','emballage','pret','retire','annule') NOT NULL DEFAULT 'recu',
  `date_depot` datetime NOT NULL DEFAULT current_timestamp(),
  `date_promise` date NOT NULL,
  `date_pret` datetime DEFAULT NULL,
  `date_retrait` datetime DEFAULT NULL,
  `emplacement` varchar(30) DEFAULT NULL,
  `sous_total` decimal(12,2) NOT NULL DEFAULT 0.00,
  `remise_montant` decimal(12,2) NOT NULL DEFAULT 0.00,
  `motif_remise` varchar(255) DEFAULT NULL,
  `surcharge_express` decimal(12,2) NOT NULL DEFAULT 0.00,
  `total` decimal(12,2) NOT NULL DEFAULT 0.00,
  `notes` text DEFAULT NULL,
  `motif_annulation` varchar(255) DEFAULT NULL,
  `version` int(11) NOT NULL DEFAULT 1,
  `cree_le` datetime NOT NULL DEFAULT current_timestamp(),
  `modifie_le` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ;

--
-- Dumping data for table `commandes`
--

INSERT INTO `commandes` (`id`, `uuid`, `reference`, `client_id`, `depose_par`, `type_depot`, `mode_remise`, `statut`, `date_depot`, `date_promise`, `date_pret`, `date_retrait`, `emplacement`, `sous_total`, `remise_montant`, `motif_remise`, `surcharge_express`, `total`, `notes`, `motif_annulation`, `version`, `cree_le`, `modifie_le`) VALUES
(11, '43ff6106-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-261119-01', 11, 1, 'normal', 'retrait', 'recu', '2026-11-19 02:05:09', '2026-11-20', NULL, NULL, NULL, 1500.00, 0.00, NULL, 0.00, 1500.00, 'DONNEE DEMO Pressa — jeu de démonstration', NULL, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09'),
(12, '43ffd8d8-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-261119-02', 12, 1, 'normal', 'retrait', 'lavage', '2026-11-19 02:05:09', '2026-11-21', NULL, NULL, NULL, 3000.00, 0.00, NULL, 0.00, 3000.00, 'DONNEE DEMO Pressa — jeu de démonstration', NULL, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09'),
(13, '44003ca6-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-261119-03', 13, 1, 'express', 'retrait', 'repassage', '2026-11-19 02:05:09', '2026-11-22', NULL, NULL, NULL, 9000.00, 0.00, NULL, 2700.00, 11700.00, 'DONNEE DEMO Pressa — jeu de démonstration', NULL, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09'),
(14, '44008e85-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-261119-04', 14, 1, 'normal', 'retrait', 'emballage', '2026-11-19 02:05:09', '2026-11-23', NULL, NULL, NULL, 6000.00, 0.00, NULL, 0.00, 6000.00, 'DONNEE DEMO Pressa — jeu de démonstration', NULL, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09'),
(15, '44021cac-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-261119-05', 15, 1, 'normal', 'retrait', 'pret', '2026-11-19 02:05:09', '2026-11-24', '2026-11-19 02:05:09', NULL, NULL, 2000.00, 0.00, NULL, 0.00, 2000.00, 'DONNEE DEMO Pressa — jeu de démonstration', NULL, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09'),
(16, '44075757-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-261119-06', 16, 1, 'normal', 'livraison', 'pret', '2026-11-19 02:05:09', '2026-11-25', '2026-11-19 02:05:09', NULL, NULL, 3000.00, 0.00, NULL, 0.00, 3000.00, 'DONNEE DEMO Pressa — jeu de démonstration', NULL, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09'),
(17, '4407af72-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-261119-07', 17, 1, 'normal', 'retrait', 'retire', '2026-11-19 02:05:09', '2026-11-26', '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL, 2500.00, 0.00, NULL, 0.00, 2500.00, 'DONNEE DEMO Pressa — jeu de démonstration', NULL, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09'),
(18, '4407ec48-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-261119-08', 18, 1, 'express', 'retrait', 'lavage', '2026-11-19 02:05:09', '2026-11-27', NULL, NULL, NULL, 5000.00, 0.00, NULL, 1500.00, 6500.00, 'DONNEE DEMO Pressa — jeu de démonstration', NULL, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09'),
(19, '4408249d-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-261119-09', 19, 1, 'normal', 'retrait', 'recu', '2026-11-19 02:05:09', '2026-11-20', NULL, NULL, NULL, 15000.00, 0.00, NULL, 0.00, 15000.00, 'DONNEE DEMO Pressa — jeu de démonstration', NULL, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09'),
(20, '44085d69-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO-261119-10', 20, 1, 'normal', 'retrait', 'retire', '2026-11-19 02:05:09', '2026-11-21', '2026-11-19 02:05:09', '2026-11-19 02:05:09', NULL, 3500.00, 0.00, NULL, 0.00, 3500.00, 'DONNEE DEMO Pressa — jeu de démonstration', NULL, 1, '2026-11-19 02:05:09', '2026-11-19 02:05:09');

--
-- Triggers `commandes`
--
DELIMITER $$
CREATE TRIGGER `trg_commande_apres_maj` AFTER UPDATE ON `commandes` FOR EACH ROW BEGIN
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
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_commande_avant_maj` BEFORE UPDATE ON `commandes` FOR EACH ROW BEGIN
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
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `commande_lignes`
--

CREATE TABLE `commande_lignes` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `commande_id` int(11) NOT NULL,
  `tarif_id` int(11) NOT NULL,
  `description` varchar(160) NOT NULL,
  `quantite` int(11) NOT NULL DEFAULT 1,
  `prix_unitaire` decimal(12,2) NOT NULL DEFAULT 0.00,
  `cout_unitaire` decimal(12,2) NOT NULL DEFAULT 0.00,
  `remise_pct` decimal(5,2) NOT NULL DEFAULT 0.00,
  `sous_total` decimal(12,2) GENERATED ALWAYS AS (round(`quantite` * `prix_unitaire` * (1 - `remise_pct` / 100),0)) STORED
) ;

--
-- Dumping data for table `commande_lignes`
--

INSERT INTO `commande_lignes` (`id`, `uuid`, `commande_id`, `tarif_id`, `description`, `quantite`, `prix_unitaire`, `cout_unitaire`, `remise_pct`) VALUES
(11, '43ff7b61-e3b5-11f1-b0c7-0c5415f01e22', 11, 1, 'Article de démonstration 01', 1, 1500.00, 650.00, 0.00),
(12, '44000b17-e3b5-11f1-b0c7-0c5415f01e22', 12, 2, 'Article de démonstration 02', 2, 1500.00, 650.00, 0.00),
(13, '4400539a-e3b5-11f1-b0c7-0c5415f01e22', 13, 3, 'Article de démonstration 03', 3, 3000.00, 1300.00, 0.00),
(14, '4400a1aa-e3b5-11f1-b0c7-0c5415f01e22', 14, 4, 'Article de démonstration 04', 1, 6000.00, 2500.00, 0.00),
(15, '440501a1-e3b5-11f1-b0c7-0c5415f01e22', 15, 5, 'Article de démonstration 05', 2, 1000.00, 350.00, 0.00),
(16, '44076fe1-e3b5-11f1-b0c7-0c5415f01e22', 16, 6, 'Article de démonstration 06', 3, 1000.00, 350.00, 0.00),
(17, '4407c020-e3b5-11f1-b0c7-0c5415f01e22', 17, 7, 'Article de démonstration 07', 1, 2500.00, 1050.00, 0.00),
(18, '4407fb52-e3b5-11f1-b0c7-0c5415f01e22', 18, 8, 'Article de démonstration 08', 2, 2500.00, 1050.00, 0.00),
(19, '44083323-e3b5-11f1-b0c7-0c5415f01e22', 19, 9, 'Article de démonstration 09', 3, 5000.00, 2400.00, 0.00),
(20, '44086c24-e3b5-11f1-b0c7-0c5415f01e22', 20, 10, 'Article de démonstration 10', 1, 3500.00, 1600.00, 0.00);

--
-- Triggers `commande_lignes`
--
DELIMITER $$
CREATE TRIGGER `trg_lignes_apres_insert` AFTER INSERT ON `commande_lignes` FOR EACH ROW BEGIN
  UPDATE commandes SET sous_total = sous_total WHERE id = NEW.commande_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_lignes_apres_maj` AFTER UPDATE ON `commande_lignes` FOR EACH ROW BEGIN
  UPDATE commandes SET sous_total = sous_total WHERE id = NEW.commande_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_lignes_apres_suppr` AFTER DELETE ON `commande_lignes` FOR EACH ROW BEGIN
  UPDATE commandes SET sous_total = sous_total WHERE id = OLD.commande_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_lignes_avant_insert` BEFORE INSERT ON `commande_lignes` FOR EACH ROW BEGIN
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
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_lignes_avant_maj` BEFORE UPDATE ON `commande_lignes` FOR EACH ROW BEGIN
  SET NEW.prix_unitaire = OLD.prix_unitaire;
  SET NEW.cout_unitaire = OLD.cout_unitaire;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `communications`
--

CREATE TABLE `communications` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `client_id` int(11) NOT NULL,
  `commande_id` int(11) DEFAULT NULL,
  `canal` enum('sms','email','appel','interne') NOT NULL DEFAULT 'sms',
  `type` enum('commande_recue','commande_prete','rappel_retrait','relance_impaye','promotion','autre') NOT NULL DEFAULT 'autre',
  `contenu` text NOT NULL,
  `statut` enum('prepare','envoye','envoye_manuellement','echec','annule') NOT NULL DEFAULT 'prepare',
  `date_programmee` datetime DEFAULT NULL,
  `date_envoi` datetime DEFAULT NULL,
  `cree_par` int(11) DEFAULT NULL,
  `cree_le` datetime NOT NULL DEFAULT current_timestamp(),
  `sens` enum('entrant','sortant') NOT NULL DEFAULT 'sortant'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `communications`
--

INSERT INTO `communications` (`id`, `uuid`, `client_id`, `commande_id`, `canal`, `type`, `contenu`, `statut`, `date_programmee`, `date_envoi`, `cree_par`, `cree_le`, `sens`) VALUES
(5, '44167113-e3b5-11f1-b0c7-0c5415f01e22', 11, 11, 'interne', 'autre', 'DEMO — note interne de démonstration ; aucun SMS envoyé.', 'prepare', NULL, NULL, 1, '2026-11-19 02:05:09', 'sortant'),
(6, '4416865b-e3b5-11f1-b0c7-0c5415f01e22', 12, 12, 'interne', 'autre', 'DEMO — note interne de démonstration ; aucun SMS envoyé.', 'prepare', NULL, NULL, 1, '2026-11-19 02:05:09', 'sortant'),
(7, '44169438-e3b5-11f1-b0c7-0c5415f01e22', 15, 15, 'interne', 'autre', 'DEMO — note interne de démonstration ; aucun SMS envoyé.', 'prepare', NULL, NULL, 1, '2026-11-19 02:05:09', 'sortant'),
(8, '4416a002-e3b5-11f1-b0c7-0c5415f01e22', 16, 16, 'interne', 'autre', 'DEMO — note interne de démonstration ; aucun SMS envoyé.', 'prepare', NULL, NULL, 1, '2026-11-19 02:05:09', 'sortant');

-- --------------------------------------------------------

--
-- Table structure for table `courses`
--

CREATE TABLE `courses` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `commande_id` int(11) NOT NULL,
  `type` enum('collecte','livraison') NOT NULL,
  `date_prevue` date NOT NULL,
  `creneau` enum('matin','apres_midi','soir') NOT NULL DEFAULT 'matin',
  `adresse` varchar(255) DEFAULT NULL,
  `statut` enum('planifiee','en_cours','effectuee','annulee') NOT NULL DEFAULT 'planifiee',
  `frais` decimal(12,2) NOT NULL DEFAULT 0.00,
  `livreur_id` int(11) DEFAULT NULL,
  `date_realisation` datetime DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL
) ;

--
-- Dumping data for table `courses`
--

INSERT INTO `courses` (`id`, `uuid`, `commande_id`, `type`, `date_prevue`, `creneau`, `adresse`, `statut`, `frais`, `livreur_id`, `date_realisation`, `notes`) VALUES
(2, '44164d0a-e3b5-11f1-b0c7-0c5415f01e22', 16, 'livraison', '2026-11-20', 'matin', 'Adresse de démonstration 6, Akwa, Douala', 'planifiee', 0.00, 21, NULL, 'DEMO — course à attribuer et tester');

-- --------------------------------------------------------

--
-- Table structure for table `demandes_clients`
--

CREATE TABLE `demandes_clients` (
  `id` int(11) NOT NULL,
  `client_id` int(11) NOT NULL,
  `type` enum('depot','ramassage') NOT NULL,
  `date_prevue` date NOT NULL,
  `creneau` enum('matin','apres_midi','soir') NOT NULL DEFAULT 'matin',
  `adresse` varchar(255) DEFAULT NULL,
  `details` varchar(500) DEFAULT NULL,
  `statut` enum('en_attente','confirmee','refusee','terminee') NOT NULL DEFAULT 'en_attente',
  `traite_par` int(11) DEFAULT NULL,
  `cree_le` datetime NOT NULL DEFAULT current_timestamp(),
  `modifie_le` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `depenses`
--

CREATE TABLE `depenses` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `date_depense` date NOT NULL,
  `categorie` enum('loyer','electricite_eau','produits_lavage','transport','maintenance','internet_telephone','impots_taxes','fournitures','publicite','autre') NOT NULL,
  `libelle` varchar(160) DEFAULT NULL,
  `montant` decimal(12,2) NOT NULL,
  `mode_paiement` enum('especes','mtn_momo','orange_money','virement','carte','cheque') NOT NULL DEFAULT 'especes',
  `justificatif` varchar(100) DEFAULT NULL,
  `commentaire` text DEFAULT NULL,
  `fournisseur_id` int(11) DEFAULT NULL,
  `intervention_id` int(11) DEFAULT NULL,
  `session_id` int(11) DEFAULT NULL,
  `enregistre_par` int(11) DEFAULT NULL,
  `cree_le` datetime NOT NULL DEFAULT current_timestamp()
) ;

--
-- Dumping data for table `depenses`
--

INSERT INTO `depenses` (`id`, `uuid`, `date_depense`, `categorie`, `libelle`, `montant`, `mode_paiement`, `justificatif`, `commentaire`, `fournisseur_id`, `intervention_id`, `session_id`, `enregistre_par`, `cree_le`) VALUES
(1, '441f0e12-e3b5-11f1-b0c7-0c5415f01e22', '2026-11-19', 'loyer', 'DEMO — loyer mensuel', 250000.00, 'virement', 'DEMO-JUST-001', 'Montant et justificatif fictifs de démonstration.', NULL, NULL, NULL, 1, '2026-11-19 02:05:09'),
(2, '44205fe9-e3b5-11f1-b0c7-0c5415f01e22', '2026-11-19', 'electricite_eau', 'DEMO — eau et électricité', 68000.00, 'especes', 'DEMO-JUST-002', 'Montant et justificatif fictifs de démonstration.', NULL, NULL, NULL, 1, '2026-11-19 02:05:09'),
(3, '4420b5a6-e3b5-11f1-b0c7-0c5415f01e22', '2026-11-19', 'produits_lavage', 'DEMO — réapprovisionnement démo', 42000.00, 'virement', 'DEMO-JUST-003', 'Montant et justificatif fictifs de démonstration.', 2, NULL, NULL, 1, '2026-11-19 02:05:09'),
(4, '4420da0b-e3b5-11f1-b0c7-0c5415f01e22', '2026-11-19', 'maintenance', 'DEMO — intervention sécheuse', 25000.00, 'virement', 'DEMO-JUST-004', 'Montant et justificatif fictifs de démonstration.', 3, 2, NULL, 1, '2026-11-19 02:05:09');

--
-- Triggers `depenses`
--
DELIMITER $$
CREATE TRIGGER `trg_depense_apres_insert` AFTER INSERT ON `depenses` FOR EACH ROW BEGIN
  IF NEW.session_id IS NOT NULL AND NEW.mode_paiement = 'especes' THEN
    UPDATE sessions_caisse SET total_theorique = total_theorique - NEW.montant WHERE id = NEW.session_id;
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `employes`
--

CREATE TABLE `employes` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `utilisateur_id` int(11) DEFAULT NULL,
  `nom` varchar(120) NOT NULL,
  `prenom` varchar(120) DEFAULT NULL,
  `telephone` varchar(30) DEFAULT NULL,
  `poste` enum('gerant','caissier','accueil','laveur','repasseur','detacheur','emballeur','livreur','comptable','autre') NOT NULL,
  `date_embauche` date DEFAULT NULL,
  `salaire_mensuel` decimal(12,2) NOT NULL DEFAULT 0.00,
  `actif` tinyint(1) NOT NULL DEFAULT 1,
  `notes` text DEFAULT NULL
) ;

--
-- Dumping data for table `employes`
--

INSERT INTO `employes` (`id`, `uuid`, `utilisateur_id`, `nom`, `prenom`, `telephone`, `poste`, `date_embauche`, `salaire_mensuel`, `actif`, `notes`) VALUES
(12, '428d5fac-e3b5-11f1-b0c7-0c5415f01e22', 1, 'Administrateur', NULL, NULL, 'gerant', NULL, 0.00, 1, NULL),
(13, '42a8851e-e3b5-11f1-b0c7-0c5415f01e22', NULL, 'Démo Administrateur 01', NULL, NULL, 'gerant', NULL, 0.00, 0, NULL),
(15, '42e184ff-e3b5-11f1-b0c7-0c5415f01e22', NULL, 'Démo Caissier 01', NULL, NULL, 'caissier', NULL, 0.00, 0, NULL),
(16, '42fcea67-e3b5-11f1-b0c7-0c5415f01e22', NULL, 'Démo Caissier 02', NULL, NULL, 'caissier', NULL, 0.00, 0, NULL),
(17, '43255c41-e3b5-11f1-b0c7-0c5415f01e22', NULL, 'Démo Accueil 01', NULL, NULL, 'accueil', NULL, 0.00, 0, NULL),
(18, '434e4533-e3b5-11f1-b0c7-0c5415f01e22', NULL, 'Démo Accueil 02', NULL, NULL, 'accueil', NULL, 0.00, 0, NULL),
(19, '43719ea2-e3b5-11f1-b0c7-0c5415f01e22', NULL, 'Démo Production 01', NULL, NULL, 'laveur', NULL, 0.00, 0, NULL),
(20, '4395a609-e3b5-11f1-b0c7-0c5415f01e22', NULL, 'Démo Production 02', NULL, NULL, 'laveur', NULL, 0.00, 0, NULL),
(21, '43badc3f-e3b5-11f1-b0c7-0c5415f01e22', NULL, 'Démo Livreur 01', NULL, NULL, 'livreur', NULL, 0.00, 0, NULL),
(22, '43eeddc0-e3b5-11f1-b0c7-0c5415f01e22', NULL, 'Démo Livreur 02', NULL, NULL, 'livreur', NULL, 0.00, 0, NULL),
(23, 'dae4eae1-e458-11f1-b0c7-0c5415f01e22', NULL, 'Administrateur Démo', NULL, NULL, 'gerant', NULL, 0.00, 0, NULL),
(24, 'daeed58e-e458-11f1-b0c7-0c5415f01e22', NULL, 'Réceptionniste Démo', NULL, NULL, 'accueil', NULL, 0.00, 0, NULL),
(25, 'daf91ede-e458-11f1-b0c7-0c5415f01e22', NULL, 'Accueil Démo', NULL, NULL, 'accueil', NULL, 0.00, 0, NULL),
(26, 'db036062-e458-11f1-b0c7-0c5415f01e22', NULL, 'Caissier Démo', NULL, NULL, 'caissier', NULL, 0.00, 0, NULL),
(27, 'db0d6aa1-e458-11f1-b0c7-0c5415f01e22', NULL, 'Production Démo', NULL, NULL, 'laveur', NULL, 0.00, 0, NULL),
(28, 'db174d6c-e458-11f1-b0c7-0c5415f01e22', NULL, 'Livreur Démo', NULL, NULL, 'livreur', NULL, 0.00, 0, NULL),
(29, 'a6578058-e45b-11f1-b0c7-0c5415f01e22', 29, 'Réceptionniste 67prime', NULL, NULL, 'accueil', NULL, 0.00, 1, NULL),
(30, 'a66137a8-e45b-11f1-b0c7-0c5415f01e22', 30, 'Daniel Accueil', NULL, NULL, 'accueil', NULL, 0.00, 1, NULL),
(31, 'a66af0ba-e45b-11f1-b0c7-0c5415f01e22', 31, 'Jojo Mel', NULL, NULL, 'caissier', NULL, 0.00, 1, NULL),
(32, 'a675384c-e45b-11f1-b0c7-0c5415f01e22', 32, 'Tafu Gw', NULL, NULL, 'laveur', NULL, 0.00, 1, NULL),
(33, 'a67f37f8-e45b-11f1-b0c7-0c5415f01e22', 33, 'Cris', NULL, NULL, 'livreur', NULL, 0.00, 1, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `equipements`
--

CREATE TABLE `equipements` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `designation` varchar(150) NOT NULL,
  `numero_serie` varchar(100) DEFAULT NULL,
  `categorie` enum('machine_laver','presse','secheuse','table_repassage','generateur','autre') NOT NULL DEFAULT 'autre',
  `date_acquisition` date DEFAULT NULL,
  `valeur_acquisition` decimal(12,2) NOT NULL DEFAULT 0.00,
  `fournisseur_id` int(11) DEFAULT NULL,
  `etat` enum('en_service','en_panne','hors_service') NOT NULL DEFAULT 'en_service',
  `actif` tinyint(1) NOT NULL DEFAULT 1
) ;

--
-- Dumping data for table `equipements`
--

INSERT INTO `equipements` (`id`, `uuid`, `designation`, `numero_serie`, `categorie`, `date_acquisition`, `valeur_acquisition`, `fournisseur_id`, `etat`, `actif`) VALUES
(1, '441c1096-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO — Machine à laver', 'DEMO-MACH-001', 'machine_laver', '2025-11-19', 850000.00, 3, 'en_service', 1),
(2, '441c5c40-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO — Sécheuse', 'DEMO-SEC-001', 'secheuse', '2026-03-19', 620000.00, 3, 'en_panne', 1);

-- --------------------------------------------------------

--
-- Table structure for table `file_synchro`
--

CREATE TABLE `file_synchro` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL,
  `appareil_uuid` char(36) NOT NULL,
  `table_cible` varchar(60) NOT NULL,
  `enregistrement_uuid` char(36) NOT NULL,
  `operation` enum('insert','update','delete') NOT NULL,
  `contenu` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL CHECK (json_valid(`contenu`)),
  `date_locale` datetime(6) NOT NULL,
  `recu_le` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `statut` enum('en_attente','appliquee','conflit','rejetee') NOT NULL DEFAULT 'en_attente',
  `message_erreur` text DEFAULT NULL,
  `traitee_le` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `fournisseurs`
--

CREATE TABLE `fournisseurs` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `nom` varchar(150) NOT NULL,
  `telephone` varchar(30) DEFAULT NULL,
  `email` varchar(160) DEFAULT NULL,
  `adresse` varchar(255) DEFAULT NULL,
  `actif` tinyint(1) NOT NULL DEFAULT 1,
  `notes` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `fournisseurs`
--

INSERT INTO `fournisseurs` (`id`, `uuid`, `nom`, `telephone`, `email`, `adresse`, `actif`, `notes`) VALUES
(1, '44172a90-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO Fournitures Pressing', 'TEST-FOURN-01', 'fournisseur.demo01@example.test', 'Adresse fournisseur démo 01', 1, 'Données fictives de démonstration Pressa'),
(2, '44174706-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO Produits & Emballages', 'TEST-FOURN-02', 'fournisseur.demo02@example.test', 'Adresse fournisseur démo 02', 1, 'Données fictives de démonstration Pressa'),
(3, '4417507d-e3b5-11f1-b0c7-0c5415f01e22', 'DEMO Équipements', 'TEST-FOURN-03', 'fournisseur.demo03@example.test', 'Adresse fournisseur démo 03', 1, 'Données fictives de démonstration Pressa');

-- --------------------------------------------------------

--
-- Table structure for table `historique_statuts`
--

CREATE TABLE `historique_statuts` (
  `id` int(11) NOT NULL,
  `commande_id` int(11) NOT NULL,
  `ancien_statut` varchar(20) DEFAULT NULL,
  `nouveau_statut` varchar(20) NOT NULL,
  `utilisateur_id` int(11) DEFAULT NULL,
  `date_changement` datetime(6) NOT NULL DEFAULT current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `historique_statuts`
--

INSERT INTO `historique_statuts` (`id`, `commande_id`, `ancien_statut`, `nouveau_statut`, `utilisateur_id`, `date_changement`) VALUES
(11, 12, 'recu', 'lavage', 1, '2026-11-19 02:05:09.550358'),
(12, 13, 'recu', 'repassage', 1, '2026-11-19 02:05:09.559019'),
(13, 14, 'recu', 'emballage', 1, '2026-11-19 02:05:09.561478'),
(14, 15, 'recu', 'pret', 1, '2026-11-19 02:05:09.562740'),
(15, 16, 'recu', 'pret', 1, '2026-11-19 02:05:09.563981'),
(16, 17, 'recu', 'pret', 1, '2026-11-19 02:05:09.565300'),
(17, 18, 'recu', 'lavage', 1, '2026-11-19 02:05:09.566625'),
(18, 20, 'recu', 'pret', 1, '2026-11-19 02:05:09.568535'),
(19, 17, 'pret', 'retire', 1, '2026-11-19 02:05:09.577552'),
(20, 20, 'pret', 'retire', 1, '2026-11-19 02:05:09.582050');

-- --------------------------------------------------------

--
-- Table structure for table `interventions`
--

CREATE TABLE `interventions` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `equipement_id` int(11) NOT NULL,
  `date_intervention` date NOT NULL,
  `type` enum('preventive','corrective','nettoyage','autre') NOT NULL DEFAULT 'corrective',
  `description` text DEFAULT NULL,
  `technicien` varchar(120) DEFAULT NULL,
  `duree_arret_min` int(11) NOT NULL DEFAULT 0,
  `cout` decimal(12,2) NOT NULL DEFAULT 0.00
) ;

--
-- Dumping data for table `interventions`
--

INSERT INTO `interventions` (`id`, `uuid`, `equipement_id`, `date_intervention`, `type`, `description`, `technicien`, `duree_arret_min`, `cout`) VALUES
(1, '441ecaaf-e3b5-11f1-b0c7-0c5415f01e22', 1, '2026-11-05', 'preventive', 'DEMO — entretien périodique fictif', 'Technicien démo', 30, 12000.00),
(2, '441efbbf-e3b5-11f1-b0c7-0c5415f01e22', 2, '2026-11-17', 'corrective', 'DEMO — diagnostic fictif, intervention à planifier', 'Technicien démo', 90, 25000.00);

-- --------------------------------------------------------

--
-- Table structure for table `journal_audit`
--

CREATE TABLE `journal_audit` (
  `id` int(11) NOT NULL,
  `date_heure` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `utilisateur_id` int(11) DEFAULT NULL,
  `action` varchar(60) NOT NULL,
  `table_cible` varchar(60) NOT NULL,
  `enregistrement_id` int(11) DEFAULT NULL,
  `ancienne_valeur` text DEFAULT NULL,
  `nouvelle_valeur` text DEFAULT NULL,
  `appareil_uuid` char(36) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `journal_audit`
--

INSERT INTO `journal_audit` (`id`, `date_heure`, `utilisateur_id`, `action`, `table_cible`, `enregistrement_id`, `ancienne_valeur`, `nouvelle_valeur`, `appareil_uuid`) VALUES
(17, '2026-11-19 02:05:09.529311', 1, 'PAIEMENT', 'paiements', 7, NULL, '750.00 FCFA especes', NULL),
(18, '2026-11-19 02:05:09.533648', 1, 'PAIEMENT', 'paiements', 8, NULL, '3000.00 FCFA mtn_momo', NULL),
(19, '2026-11-19 02:05:09.534997', 1, 'PAIEMENT', 'paiements', 9, NULL, '2000.00 FCFA orange_money', NULL),
(20, '2026-11-19 02:05:09.545786', 1, 'PAIEMENT', 'paiements', 10, NULL, '3000.00 FCFA virement', NULL),
(21, '2026-11-19 02:05:09.548389', 1, 'PAIEMENT', 'paiements', 11, NULL, '2500.00 FCFA carte', NULL),
(22, '2026-11-19 02:05:09.549618', 1, 'PAIEMENT', 'paiements', 12, NULL, '3500.00 FCFA especes', NULL),
(23, '2026-11-19 02:05:09.550358', 1, 'CHANGEMENT_STATUT', 'commandes', 12, 'recu', 'lavage', NULL),
(24, '2026-11-19 02:05:09.559019', 1, 'CHANGEMENT_STATUT', 'commandes', 13, 'recu', 'repassage', NULL),
(25, '2026-11-19 02:05:09.561478', 1, 'CHANGEMENT_STATUT', 'commandes', 14, 'recu', 'emballage', NULL),
(26, '2026-11-19 02:05:09.562740', 1, 'CHANGEMENT_STATUT', 'commandes', 15, 'recu', 'pret', NULL),
(27, '2026-11-19 02:05:09.563981', 1, 'CHANGEMENT_STATUT', 'commandes', 16, 'recu', 'pret', NULL),
(28, '2026-11-19 02:05:09.565300', 1, 'CHANGEMENT_STATUT', 'commandes', 17, 'recu', 'pret', NULL),
(29, '2026-11-19 02:05:09.566625', 1, 'CHANGEMENT_STATUT', 'commandes', 18, 'recu', 'lavage', NULL),
(30, '2026-11-19 02:05:09.568535', 1, 'CHANGEMENT_STATUT', 'commandes', 20, 'recu', 'pret', NULL),
(31, '2026-11-19 02:05:09.577552', 1, 'CHANGEMENT_STATUT', 'commandes', 17, 'pret', 'retire', NULL),
(32, '2026-11-19 02:05:09.582050', 1, 'CHANGEMENT_STATUT', 'commandes', 20, 'pret', 'retire', NULL);

--
-- Triggers `journal_audit`
--
DELIMITER $$
CREATE TRIGGER `trg_journal_avant_maj` BEFORE UPDATE ON `journal_audit` FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Journal d''audit en lecture seule';
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_journal_avant_suppr` BEFORE DELETE ON `journal_audit` FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Journal d''audit en lecture seule';
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `mouvements_stock`
--

CREATE TABLE `mouvements_stock` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `produit_id` int(11) NOT NULL,
  `type` enum('entree','sortie','ajustement') NOT NULL,
  `quantite` decimal(12,3) NOT NULL,
  `prix_unitaire` decimal(12,2) DEFAULT NULL,
  `quantite_avant` decimal(12,3) NOT NULL DEFAULT 0.000,
  `quantite_apres` decimal(12,3) NOT NULL DEFAULT 0.000,
  `cout_moyen_apres` decimal(12,2) NOT NULL DEFAULT 0.00,
  `motif` varchar(255) DEFAULT NULL,
  `reference_document` varchar(50) DEFAULT NULL,
  `utilisateur_id` int(11) DEFAULT NULL,
  `date_mouvement` datetime(6) NOT NULL DEFAULT current_timestamp(6)
) ;

--
-- Dumping data for table `mouvements_stock`
--

INSERT INTO `mouvements_stock` (`id`, `uuid`, `produit_id`, `type`, `quantite`, `prix_unitaire`, `quantite_avant`, `quantite_apres`, `cout_moyen_apres`, `motif`, `reference_document`, `utilisateur_id`, `date_mouvement`) VALUES
(1, '441b8c9f-e3b5-11f1-b0c7-0c5415f01e22', 1, 'entree', 12.000, 2500.00, 0.000, 12.000, 2500.00, 'DEMO — stock initial de démonstration', 'DEMO-STOCK-001', 1, '2026-11-19 02:05:09.641917');

--
-- Triggers `mouvements_stock`
--
DELIMITER $$
CREATE TRIGGER `trg_mvt_apres_insert` AFTER INSERT ON `mouvements_stock` FOR EACH ROW BEGIN
  UPDATE produits_stock
     SET quantite_stock = NEW.quantite_apres,
         cout_moyen = NEW.cout_moyen_apres,
         version = version + 1
   WHERE id = NEW.produit_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_mvt_avant_insert` BEFORE INSERT ON `mouvements_stock` FOR EACH ROW BEGIN
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
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_mvt_avant_maj` BEFORE UPDATE ON `mouvements_stock` FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Mouvement de stock non modifiable : faire une contre-écriture';
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_mvt_avant_suppr` BEFORE DELETE ON `mouvements_stock` FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Mouvement de stock non supprimable';
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `paiements`
--

CREATE TABLE `paiements` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `commande_id` int(11) NOT NULL,
  `session_id` int(11) DEFAULT NULL,
  `montant` decimal(12,2) NOT NULL,
  `mode` enum('especes','mtn_momo','orange_money','virement','carte','cheque') NOT NULL,
  `reference` varchar(100) DEFAULT NULL,
  `enregistre_par` int(11) DEFAULT NULL,
  `date_paiement` datetime(6) NOT NULL DEFAULT current_timestamp(6)
) ;

--
-- Dumping data for table `paiements`
--

INSERT INTO `paiements` (`id`, `uuid`, `commande_id`, `session_id`, `montant`, `mode`, `reference`, `enregistre_par`, `date_paiement`) VALUES
(7, '440a1bb2-e3b5-11f1-b0c7-0c5415f01e22', 12, NULL, 750.00, 'especes', 'DEMO-PAY-02', 1, '2026-11-19 02:05:09.529311'),
(8, '440ac4b8-e3b5-11f1-b0c7-0c5415f01e22', 14, NULL, 3000.00, 'mtn_momo', 'DEMO-PAY-04', 1, '2026-11-19 02:05:09.533648'),
(9, '440af80d-e3b5-11f1-b0c7-0c5415f01e22', 15, NULL, 2000.00, 'orange_money', 'DEMO-PAY-05', 1, '2026-11-19 02:05:09.534997'),
(10, '440ccbcc-e3b5-11f1-b0c7-0c5415f01e22', 16, NULL, 3000.00, 'virement', 'DEMO-PAY-06', 1, '2026-11-19 02:05:09.545786'),
(11, '440d031b-e3b5-11f1-b0c7-0c5415f01e22', 17, NULL, 2500.00, 'carte', 'DEMO-PAY-07', 1, '2026-11-19 02:05:09.548389'),
(12, '440d3280-e3b5-11f1-b0c7-0c5415f01e22', 20, NULL, 3500.00, 'especes', 'DEMO-PAY-10', 1, '2026-11-19 02:05:09.549618');

--
-- Triggers `paiements`
--
DELIMITER $$
CREATE TRIGGER `trg_paiement_apres_insert` AFTER INSERT ON `paiements` FOR EACH ROW BEGIN
  INSERT INTO journal_audit(utilisateur_id, action, table_cible, enregistrement_id, nouvelle_valeur)
  VALUES (NEW.enregistre_par, 'PAIEMENT', 'paiements', NEW.id, CONCAT(NEW.montant, ' FCFA ', NEW.mode));
  IF NEW.session_id IS NOT NULL AND NEW.mode = 'especes' THEN
    UPDATE sessions_caisse SET total_theorique = total_theorique + NEW.montant WHERE id = NEW.session_id;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_paiement_avant_insert` BEFORE INSERT ON `paiements` FOR EACH ROW BEGIN
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
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_paiement_avant_maj` BEFORE UPDATE ON `paiements` FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Paiement non modifiable : utiliser un remboursement';
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_paiement_avant_suppr` BEFORE DELETE ON `paiements` FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Paiement non supprimable : utiliser un remboursement';
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `parametres`
--

CREATE TABLE `parametres` (
  `cle` varchar(60) NOT NULL,
  `valeur` varchar(255) NOT NULL,
  `description` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `parametres`
--

INSERT INTO `parametres` (`cle`, `valeur`, `description`) VALUES
('adresse', 'Yaoundé, Cameroun', 'Adresse du pressing'),
('delai_defaut_jours', '2', 'Délai par défaut avant retrait prévu'),
('devise', 'FCFA (XAF)', 'Devise'),
('fuseau_horaire', 'Africa/Douala', 'Fuseau horaire de l\'application'),
('nom_application', 'Pressa', 'Nom du logiciel (titres, icône, domaine)'),
('nom_pressing', 'Pressa', 'Nom affiché sur les reçus et les SMS'),
('surcharge_express_pct', '30', 'Majoration pour dépôt express (%)'),
('telephone', '', 'Téléphone du pressing'),
('tva_pct', '0', 'TVA (0 si non assujetti)');

-- --------------------------------------------------------

--
-- Table structure for table `presences`
--

CREATE TABLE `presences` (
  `id` int(11) NOT NULL,
  `employe_id` int(11) NOT NULL,
  `date_presence` date NOT NULL,
  `creneau` enum('matin','apres_midi','journee') NOT NULL DEFAULT 'journee',
  `statut` enum('present','absent','retard','conge','repos') NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `presences`
--

INSERT INTO `presences` (`id`, `employe_id`, `date_presence`, `creneau`, `statut`) VALUES
(1, 12, '2026-11-19', 'journee', 'present'),
(2, 13, '2026-11-19', 'matin', 'present'),
(4, 15, '2026-11-19', 'matin', 'retard'),
(5, 16, '2026-11-19', 'apres_midi', 'present'),
(6, 17, '2026-11-19', 'matin', 'present'),
(7, 18, '2026-11-19', 'apres_midi', 'present'),
(8, 19, '2026-11-19', 'matin', 'present'),
(9, 20, '2026-11-19', 'apres_midi', 'present'),
(10, 21, '2026-11-19', 'matin', 'present'),
(11, 22, '2026-11-19', 'apres_midi', 'present');

-- --------------------------------------------------------

--
-- Table structure for table `produits_stock`
--

CREATE TABLE `produits_stock` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `reference` varchar(30) DEFAULT NULL,
  `libelle` varchar(150) NOT NULL,
  `categorie` enum('consommable','emballage','outillage','autre') NOT NULL DEFAULT 'consommable',
  `unite` enum('kg','litre','paquet','piece','bidon') NOT NULL DEFAULT 'piece',
  `quantite_stock` decimal(12,3) NOT NULL DEFAULT 0.000,
  `seuil_min` decimal(12,3) NOT NULL DEFAULT 0.000,
  `cout_moyen` decimal(12,2) NOT NULL DEFAULT 0.00,
  `actif` tinyint(1) NOT NULL DEFAULT 1,
  `version` int(11) NOT NULL DEFAULT 1
) ;

--
-- Dumping data for table `produits_stock`
--

INSERT INTO `produits_stock` (`id`, `uuid`, `reference`, `libelle`, `categorie`, `unite`, `quantite_stock`, `seuil_min`, `cout_moyen`, `actif`, `version`) VALUES
(1, 'efec4763-e3a4-11f1-b0c7-0c5415f01e22', 'LESS-01', 'Lessive professionnelle', 'consommable', 'kg', 12.000, 5.000, 2500.00, 1, 2),
(2, 'efecc121-e3a4-11f1-b0c7-0c5415f01e22', 'ADOU-01', 'Adoucissant', 'consommable', 'litre', 0.000, 3.000, 0.00, 1, 1),
(3, 'efecc38b-e3a4-11f1-b0c7-0c5415f01e22', 'DETA-01', 'Détachant', 'consommable', 'litre', 0.000, 2.000, 0.00, 1, 1),
(4, 'efecc592-e3a4-11f1-b0c7-0c5415f01e22', 'EMBA-01', 'Emballages plastique', 'emballage', 'paquet', 0.000, 5.000, 0.00, 1, 1),
(5, 'efecc6c3-e3a4-11f1-b0c7-0c5415f01e22', 'CINT-01', 'Cintres', 'emballage', 'piece', 0.000, 50.000, 0.00, 1, 1);

--
-- Triggers `produits_stock`
--
DELIMITER $$
CREATE TRIGGER `trg_produit_apres_insert` AFTER INSERT ON `produits_stock` FOR EACH ROW BEGIN
  IF NEW.quantite_stock <= NEW.seuil_min THEN
    INSERT INTO alertes_stock(produit_id, etat) VALUES (NEW.id, 'ouverte');
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_produit_apres_maj` AFTER UPDATE ON `produits_stock` FOR EACH ROW BEGIN
  IF NEW.quantite_stock <= NEW.seuil_min AND NOT EXISTS (
       SELECT 1 FROM alertes_stock WHERE produit_id = NEW.id AND etat = 'ouverte') THEN
    INSERT INTO alertes_stock(produit_id, etat) VALUES (NEW.id, 'ouverte');
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `reclamations`
--

CREATE TABLE `reclamations` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `client_id` int(11) NOT NULL,
  `commande_id` int(11) DEFAULT NULL,
  `date_reclamation` date NOT NULL,
  `nature` varchar(120) NOT NULL,
  `demande` text DEFAULT NULL,
  `decision` text DEFAULT NULL,
  `statut` enum('ouverte','en_cours','cloturee') NOT NULL DEFAULT 'ouverte',
  `traite_par` int(11) DEFAULT NULL,
  `date_info_client` date DEFAULT NULL,
  `date_cloture` datetime DEFAULT NULL
) ;

--
-- Dumping data for table `reclamations`
--

INSERT INTO `reclamations` (`id`, `uuid`, `client_id`, `commande_id`, `date_reclamation`, `nature`, `demande`, `decision`, `statut`, `traite_par`, `date_info_client`, `date_cloture`) VALUES
(1, '4416c1e0-e3b5-11f1-b0c7-0c5415f01e22', 13, 13, '2026-11-19', 'DEMO — délai de traitement', 'Exemple fictif de réclamation.', 'Suivi de démonstration.', 'en_cours', 1, NULL, NULL),
(2, '44171220-e3b5-11f1-b0c7-0c5415f01e22', 17, 17, '2026-11-18', 'DEMO — article à vérifier', 'Exemple fictif de demande client.', 'Dossier démo clôturé.', 'cloturee', 1, '2026-11-19', '2026-11-19 00:00:00');

-- --------------------------------------------------------

--
-- Table structure for table `reglements_fournisseurs`
--

CREATE TABLE `reglements_fournisseurs` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `fournisseur_id` int(11) NOT NULL,
  `bon_id` int(11) DEFAULT NULL,
  `session_id` int(11) DEFAULT NULL,
  `montant` decimal(12,2) NOT NULL,
  `mode` enum('especes','mtn_momo','orange_money','virement','cheque') NOT NULL DEFAULT 'virement',
  `reference` varchar(100) DEFAULT NULL,
  `enregistre_par` int(11) DEFAULT NULL,
  `date_reglement` datetime(6) NOT NULL DEFAULT current_timestamp(6)
) ;

--
-- Dumping data for table `reglements_fournisseurs`
--

INSERT INTO `reglements_fournisseurs` (`id`, `uuid`, `fournisseur_id`, `bon_id`, `session_id`, `montant`, `mode`, `reference`, `enregistre_par`, `date_reglement`) VALUES
(1, '4419f905-e3b5-11f1-b0c7-0c5415f01e22', 1, 1, NULL, 5000.00, 'virement', 'DEMO-REG-001', 1, '2026-11-19 02:05:09.633298');

--
-- Triggers `reglements_fournisseurs`
--
DELIMITER $$
CREATE TRIGGER `trg_reglement_fournisseur_apres_insert` AFTER INSERT ON `reglements_fournisseurs` FOR EACH ROW BEGIN
  IF NEW.session_id IS NOT NULL AND NEW.mode = 'especes' THEN
    UPDATE sessions_caisse SET total_theorique = total_theorique - NEW.montant WHERE id = NEW.session_id;
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `remboursements`
--

CREATE TABLE `remboursements` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `commande_id` int(11) NOT NULL,
  `session_id` int(11) DEFAULT NULL,
  `montant` decimal(12,2) NOT NULL,
  `mode` enum('especes','mtn_momo','orange_money','virement','carte','cheque') NOT NULL DEFAULT 'especes',
  `motif` varchar(255) NOT NULL,
  `enregistre_par` int(11) DEFAULT NULL,
  `date_remboursement` datetime(6) NOT NULL DEFAULT current_timestamp(6)
) ;

--
-- Triggers `remboursements`
--
DELIMITER $$
CREATE TRIGGER `trg_remboursement_apres_insert` AFTER INSERT ON `remboursements` FOR EACH ROW BEGIN
  INSERT INTO journal_audit(utilisateur_id, action, table_cible, enregistrement_id, nouvelle_valeur)
  VALUES (NEW.enregistre_par, 'REMBOURSEMENT', 'remboursements', NEW.id,
          CONCAT(NEW.montant, ' FCFA - ', NEW.motif));
  IF NEW.session_id IS NOT NULL AND NEW.mode = 'especes' THEN
    UPDATE sessions_caisse SET total_theorique = total_theorique - NEW.montant WHERE id = NEW.session_id;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_remboursement_avant_insert` BEFORE INSERT ON `remboursements` FOR EACH ROW BEGIN
  DECLARE v_solde_encaisse DECIMAL(12,2);
  SELECT COALESCE((SELECT SUM(montant) FROM paiements WHERE commande_id = NEW.commande_id), 0)
       - COALESCE((SELECT SUM(montant) FROM remboursements WHERE commande_id = NEW.commande_id), 0)
  INTO v_solde_encaisse;
  IF NEW.montant > v_solde_encaisse THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Remboursement supérieur aux sommes encaissées';
  END IF;
  IF NEW.enregistre_par IS NULL THEN SET NEW.enregistre_par = @app_user_id; END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `salaires`
--

CREATE TABLE `salaires` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `employe_id` int(11) NOT NULL,
  `periode` char(7) NOT NULL,
  `montant` decimal(12,2) NOT NULL,
  `date_paiement` date NOT NULL,
  `mode_paiement` enum('especes','mtn_momo','orange_money','virement') NOT NULL DEFAULT 'especes',
  `session_id` int(11) DEFAULT NULL,
  `enregistre_par` int(11) DEFAULT NULL
) ;

--
-- Triggers `salaires`
--
DELIMITER $$
CREATE TRIGGER `trg_salaire_apres_insert` AFTER INSERT ON `salaires` FOR EACH ROW BEGIN
  IF NEW.session_id IS NOT NULL AND NEW.mode_paiement = 'especes' THEN
    UPDATE sessions_caisse SET total_theorique = total_theorique - NEW.montant WHERE id = NEW.session_id;
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `services`
--

CREATE TABLE `services` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `code` varchar(20) NOT NULL,
  `nom` varchar(100) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `delai_jours` int(11) NOT NULL DEFAULT 2,
  `actif` tinyint(1) NOT NULL DEFAULT 1
) ;

--
-- Dumping data for table `services`
--

INSERT INTO `services` (`id`, `uuid`, `code`, `nom`, `description`, `delai_jours`, `actif`) VALUES
(1, 'efeab525-e3a4-11f1-b0c7-0c5415f01e22', 'LAV', 'Lavage simple', 'Lavage seul', 2, 1),
(2, 'efeaeed2-e3a4-11f1-b0c7-0c5415f01e22', 'REP', 'Repassage seul', 'Repassage seul', 1, 1),
(3, 'efeaf18d-e3a4-11f1-b0c7-0c5415f01e22', 'LR', 'Lavage + repassage', 'Forfait complet', 2, 1),
(4, 'efeaf200-e3a4-11f1-b0c7-0c5415f01e22', 'NET', 'Nettoyage à sec', 'Textiles délicats et costumes', 3, 1),
(5, 'efeaf263-e3a4-11f1-b0c7-0c5415f01e22', 'DET', 'Détachage', 'Traitement des taches', 2, 1);

-- --------------------------------------------------------

--
-- Table structure for table `sessions_caisse`
--

CREATE TABLE `sessions_caisse` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `utilisateur_id` int(11) NOT NULL,
  `date_ouverture` datetime NOT NULL DEFAULT current_timestamp(),
  `fond_ouverture` decimal(12,2) NOT NULL DEFAULT 0.00,
  `date_fermeture` datetime DEFAULT NULL,
  `total_theorique` decimal(12,2) NOT NULL DEFAULT 0.00,
  `total_compte` decimal(12,2) DEFAULT NULL,
  `ecart` decimal(12,2) GENERATED ALWAYS AS (`total_compte` - (`fond_ouverture` + `total_theorique`)) STORED,
  `commentaire_ecart` text DEFAULT NULL,
  `valide_par` int(11) DEFAULT NULL,
  `date_validation` datetime DEFAULT NULL
) ;

--
-- Triggers `sessions_caisse`
--
DELIMITER $$
CREATE TRIGGER `trg_session_avant_maj` BEFORE UPDATE ON `sessions_caisse` FOR EACH ROW BEGIN
  IF OLD.date_fermeture IS NOT NULL AND (NEW.total_compte <> OLD.total_compte
     OR NEW.total_theorique <> OLD.total_theorique) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Caisse déjà clôturée : montants figés';
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `tarifs`
--

CREATE TABLE `tarifs` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `service_id` int(11) NOT NULL,
  `type_article_id` int(11) NOT NULL,
  `prix` decimal(12,2) NOT NULL,
  `cout_estime` decimal(12,2) NOT NULL DEFAULT 0.00,
  `date_effet` date NOT NULL
) ;

--
-- Dumping data for table `tarifs`
--

INSERT INTO `tarifs` (`id`, `uuid`, `service_id`, `type_article_id`, `prix`, `cout_estime`, `date_effet`) VALUES
(1, 'efebcab8-e3a4-11f1-b0c7-0c5415f01e22', 1, 1, 1500.00, 650.00, '2026-01-01'),
(2, 'efebf0a4-e3a4-11f1-b0c7-0c5415f01e22', 1, 2, 1500.00, 650.00, '2026-01-01'),
(3, 'efebf2df-e3a4-11f1-b0c7-0c5415f01e22', 1, 6, 3000.00, 1300.00, '2026-01-01'),
(4, 'efebf3d6-e3a4-11f1-b0c7-0c5415f01e22', 1, 7, 6000.00, 2500.00, '2026-01-01'),
(5, 'efebf4c0-e3a4-11f1-b0c7-0c5415f01e22', 2, 1, 1000.00, 350.00, '2026-01-01'),
(6, 'efebf589-e3a4-11f1-b0c7-0c5415f01e22', 2, 2, 1000.00, 350.00, '2026-01-01'),
(7, 'efebf64f-e3a4-11f1-b0c7-0c5415f01e22', 3, 1, 2500.00, 1050.00, '2026-01-01'),
(8, 'efebf702-e3a4-11f1-b0c7-0c5415f01e22', 3, 2, 2500.00, 1050.00, '2026-01-01'),
(9, 'efebf7d0-e3a4-11f1-b0c7-0c5415f01e22', 4, 4, 5000.00, 2400.00, '2026-01-01'),
(10, 'efebf888-e3a4-11f1-b0c7-0c5415f01e22', 4, 3, 3500.00, 1600.00, '2026-01-01'),
(11, 'efebf945-e3a4-11f1-b0c7-0c5415f01e22', 4, 5, 4000.00, 1900.00, '2026-01-01'),
(12, 'efebfa0d-e3a4-11f1-b0c7-0c5415f01e22', 5, 1, 1000.00, 300.00, '2026-01-01');

--
-- Triggers `tarifs`
--
DELIMITER $$
CREATE TRIGGER `trg_tarif_avant_maj` BEFORE UPDATE ON `tarifs` FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tarif historisé : créer un nouveau tarif avec une nouvelle date d''effet';
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `types_articles`
--

CREATE TABLE `types_articles` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `nom` varchar(100) NOT NULL,
  `unite` enum('piece','ensemble','kg') NOT NULL DEFAULT 'piece',
  `actif` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `types_articles`
--

INSERT INTO `types_articles` (`id`, `uuid`, `nom`, `unite`, `actif`) VALUES
(1, 'efeb508a-e3a4-11f1-b0c7-0c5415f01e22', 'Chemise', 'piece', 1),
(2, 'efeb6420-e3a4-11f1-b0c7-0c5415f01e22', 'Pantalon', 'piece', 1),
(3, 'efeb6575-e3a4-11f1-b0c7-0c5415f01e22', 'Robe', 'piece', 1),
(4, 'efeb65be-e3a4-11f1-b0c7-0c5415f01e22', 'Costume', 'ensemble', 1),
(5, 'efeb65fb-e3a4-11f1-b0c7-0c5415f01e22', 'Veste', 'piece', 1),
(6, 'efeb6637-e3a4-11f1-b0c7-0c5415f01e22', 'Drap', 'piece', 1),
(7, 'efeb666b-e3a4-11f1-b0c7-0c5415f01e22', 'Couette', 'piece', 1);

-- --------------------------------------------------------

--
-- Table structure for table `utilisateurs`
--

CREATE TABLE `utilisateurs` (
  `id` int(11) NOT NULL,
  `uuid` char(36) NOT NULL DEFAULT uuid(),
  `nom` varchar(120) NOT NULL,
  `email` varchar(160) NOT NULL,
  `mot_de_passe` varchar(255) NOT NULL,
  `role` enum('admin','responsable','caissier','accueil','production','livreur','client') NOT NULL DEFAULT 'accueil',
  `actif` tinyint(1) NOT NULL DEFAULT 1,
  `doit_changer_mdp` tinyint(1) NOT NULL DEFAULT 0,
  `tentatives_echec` int(11) NOT NULL DEFAULT 0,
  `verrouille_jusqu_a` datetime DEFAULT NULL,
  `derniere_connexion` datetime DEFAULT NULL,
  `cree_le` datetime NOT NULL DEFAULT current_timestamp(),
  `modifie_le` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `utilisateurs`
--

INSERT INTO `utilisateurs` (`id`, `uuid`, `nom`, `email`, `mot_de_passe`, `role`, `actif`, `doit_changer_mdp`, `tentatives_echec`, `verrouille_jusqu_a`, `derniere_connexion`, `cree_le`, `modifie_le`) VALUES
(1, '123', 'Administrateur', 'pressa.admin.initial@gmail.com', '$2y$10$QkRGTvXltDFwe6ghTKccOuhywtZkV0iDtoTw/rb4FlWIfR6BrEeK.', 'admin', 1, 0, NULL, '2026-11-19 22:00:20', '2026-11-19 00:34:59', '2026-11-19 22:00:20'),
(29, 'a6576dad-e45b-11f1-b0c7-0c5415f01e22', 'Réceptionniste 67prime', '67prime.ess@gmail.com', '$2y$10$21IiLRWkdCoTDn3A7EG/6OfJLcuOrVBrNbuc4Oj8ylifAK.o092iu', 'accueil', 1, 0, 0, NULL, '2026-11-19 22:13:27', '2026-11-19 21:56:10', '2026-11-19 22:13:27'),
(30, 'a6612577-e45b-11f1-b0c7-0c5415f01e22', 'Daniel Accueil', 'Daniel@gmail.com', '$2y$10$zw2m55egIWe.eI9C30c05uNvABuf/PoL2ban36dC/bxj4u28utX0O', 'accueil', 1, 0, 0, NULL, NULL, '2026-11-19 21:56:10', '2026-11-19 21:56:10'),
(31, 'a66adddc-e45b-11f1-b0c7-0c5415f01e22', 'Jojo Mel', 'jojomel@gmail.com', '$2y$10$ry9k6FbSyXsg0LzAZJZfzOhCILQkfFQw9qPcYavJ2flpHlMo5pgdC', 'caissier', 1, 0, 0, NULL, NULL, '2026-11-19 21:56:10', '2026-11-19 21:56:10'),
(32, 'a6752742-e45b-11f1-b0c7-0c5415f01e22', 'Tafu Gw', 'tafugw@gmail.com', '$2y$10$zJzj/ESbKfrk4/lW2jcZrOTtk/MW1wim2.1EVSBxgWsVMQao58UL6', 'production', 1, 0, 0, NULL, NULL, '2026-11-19 21:56:11', '2026-11-19 21:56:11'),
(33, 'a67f269f-e45b-11f1-b0c7-0c5415f01e22', 'Cris', 'Cris@gmail.com', '$2y$10$JsITTun0Xedsn4.4FhZlmesJkO405lmSP1FWmU7c61VvKsVAo2sqe', 'livreur', 1, 0, 0, NULL, '2026-11-19 22:01:57', '2026-11-19 21:56:11', '2026-11-19 22:01:57'),
(34, 'a688e856-e45b-11f1-b0c7-0c5415f01e22', 'Valdeshack', 'Valdeshack@gmail.com', '$2y$10$Fjw6vGyP8YnQ1ppdnzawEuyl61Rpr3NYOWhcR2DdFryOTF1fIkogu', 'client', 1, 0, 0, NULL, NULL, '2026-11-19 21:56:11', '2026-11-19 21:56:11');

--
-- Triggers `utilisateurs`
--
DELIMITER $$
CREATE TRIGGER `trg_utilisateur_apres_maj` AFTER UPDATE ON `utilisateurs` FOR EACH ROW BEGIN
  IF OLD.role <> NEW.role THEN
    INSERT INTO journal_audit(utilisateur_id, action, table_cible, enregistrement_id, ancienne_valeur, nouvelle_valeur)
    VALUES (@app_user_id, 'CHANGEMENT_ROLE', 'utilisateurs', NEW.id, OLD.role, NEW.role);
  END IF;
  IF OLD.actif <> NEW.actif THEN
    INSERT INTO journal_audit(utilisateur_id, action, table_cible, enregistrement_id, ancienne_valeur, nouvelle_valeur)
    VALUES (@app_user_id, 'ACTIVATION', 'utilisateurs', NEW.id, OLD.actif, NEW.actif);
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
CREATE TABLE `limites_inscription` (
  `cle_ip` char(64) NOT NULL,
  `debut_fenetre` datetime NOT NULL,
  `tentatives` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`cle_ip`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `gestion_comptes_audit` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `auteur_id` int(11) NOT NULL,
  `cible_id` int(11) DEFAULT NULL,
  `cible_email` varchar(160) NOT NULL,
  `action` varchar(30) NOT NULL,
  `motif` varchar(500) NOT NULL,
  `date_action` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_gestion_comptes_cible` (`cible_id`),
  KEY `idx_gestion_comptes_auteur` (`auteur_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Stand-in structure for view `vue_commandes_en_retard`
-- (See below for the actual view)
--
CREATE TABLE `vue_commandes_en_retard` (
`id` int(11)
,`reference` varchar(30)
,`statut` enum('recu','lavage','repassage','emballage','pret','retire','annule')
,`date_promise` date
,`nom` varchar(120)
,`prenom` varchar(120)
,`telephone` varchar(30)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vue_commandes_solde`
-- (See below for the actual view)
--
CREATE TABLE `vue_commandes_solde` (
`id` int(11)
,`reference` varchar(30)
,`client_id` int(11)
,`statut` enum('recu','lavage','repassage','emballage','pret','retire','annule')
,`total` decimal(12,2)
,`paye` decimal(35,2)
,`reste_a_payer` decimal(36,2)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vue_fournisseurs_solde`
-- (See below for the actual view)
--
CREATE TABLE `vue_fournisseurs_solde` (
`id` int(11)
,`nom` varchar(150)
,`solde_du` decimal(47,5)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vue_marge_commandes`
-- (See below for the actual view)
--
CREATE TABLE `vue_marge_commandes` (
`commande_id` int(11)
,`ventes` decimal(34,2)
,`couts_estimes` decimal(44,2)
,`marge_brute` decimal(45,2)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vue_stock_etat`
-- (See below for the actual view)
--
CREATE TABLE `vue_stock_etat` (
`id` int(11)
,`libelle` varchar(150)
,`categorie` enum('consommable','emballage','outillage','autre')
,`unite` enum('kg','litre','paquet','piece','bidon')
,`quantite_stock` decimal(12,3)
,`seuil_min` decimal(12,3)
,`cout_moyen` decimal(12,2)
,`valeur_stock` decimal(24,5)
,`a_reapprovisionner` int(1)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vue_tableau_bord`
-- (See below for the actual view)
--
CREATE TABLE `vue_tableau_bord` (
`clients_total` bigint(21)
,`commandes_en_cours` bigint(21)
,`commandes_pretes` bigint(21)
,`commandes_en_retard` bigint(21)
,`encaissements_mois` decimal(34,2)
,`depenses_mois` decimal(34,2)
,`alertes_stock_ouvertes` bigint(21)
);

--
-- Indexes for dumped tables
--

--
-- Indexes for table `alertes_stock`
--
ALTER TABLE `alertes_stock`
  ADD PRIMARY KEY (`id`),
  ADD KEY `produit_id` (`produit_id`),
  ADD KEY `traitee_par` (`traitee_par`);

--
-- Indexes for table `appareils`
--
ALTER TABLE `appareils`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`);

--
-- Indexes for table `avis_clients`
--
ALTER TABLE `avis_clients`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_avis_client_commande` (`client_id`,`commande_id`),
  ADD KEY `idx_avis_date` (`cree_le`),
  ADD KEY `fk_avis_commande` (`commande_id`);

--
-- Indexes for table `bons_achat`
--
ALTER TABLE `bons_achat`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `reference` (`reference`),
  ADD KEY `fournisseur_id` (`fournisseur_id`),
  ADD KEY `cree_par` (`cree_par`);

--
-- Indexes for table `bons_achat_lignes`
--
ALTER TABLE `bons_achat_lignes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `bon_id` (`bon_id`),
  ADD KEY `produit_id` (`produit_id`);

--
-- Indexes for table `clients`
--
ALTER TABLE `clients`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `utilisateur_id` (`utilisateur_id`),
  ADD KEY `idx_client_tel` (`telephone`),
  ADD KEY `idx_client_nom` (`nom`,`prenom`),
  ADD KEY `cree_par` (`cree_par`);

--
-- Indexes for table `commandes`
--
ALTER TABLE `commandes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `reference` (`reference`),
  ADD KEY `idx_cmd_statut` (`statut`),
  ADD KEY `idx_cmd_date` (`date_depot`),
  ADD KEY `client_id` (`client_id`),
  ADD KEY `depose_par` (`depose_par`);

--
-- Indexes for table `commande_lignes`
--
ALTER TABLE `commande_lignes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `commande_id` (`commande_id`),
  ADD KEY `tarif_id` (`tarif_id`);

--
-- Indexes for table `communications`
--
ALTER TABLE `communications`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `client_id` (`client_id`),
  ADD KEY `commande_id` (`commande_id`),
  ADD KEY `cree_par` (`cree_par`);

--
-- Indexes for table `courses`
--
ALTER TABLE `courses`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `commande_id` (`commande_id`),
  ADD KEY `livreur_id` (`livreur_id`);

--
-- Indexes for table `demandes_clients`
--
ALTER TABLE `demandes_clients`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_demandes_client_date` (`client_id`,`date_prevue`),
  ADD KEY `idx_demandes_statut_date` (`statut`,`date_prevue`),
  ADD KEY `fk_demandes_traite_par` (`traite_par`);

--
-- Indexes for table `depenses`
--
ALTER TABLE `depenses`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `fournisseur_id` (`fournisseur_id`),
  ADD KEY `intervention_id` (`intervention_id`),
  ADD KEY `session_id` (`session_id`),
  ADD KEY `enregistre_par` (`enregistre_par`);

--
-- Indexes for table `employes`
--
ALTER TABLE `employes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `utilisateur_id` (`utilisateur_id`);

--
-- Indexes for table `equipements`
--
ALTER TABLE `equipements`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `fournisseur_id` (`fournisseur_id`);

--
-- Indexes for table `file_synchro`
--
ALTER TABLE `file_synchro`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `idx_sync_statut` (`statut`);

--
-- Indexes for table `fournisseurs`
--
ALTER TABLE `fournisseurs`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`);

--
-- Indexes for table `historique_statuts`
--
ALTER TABLE `historique_statuts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `commande_id` (`commande_id`),
  ADD KEY `utilisateur_id` (`utilisateur_id`);

--
-- Indexes for table `interventions`
--
ALTER TABLE `interventions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `equipement_id` (`equipement_id`);

--
-- Indexes for table `journal_audit`
--
ALTER TABLE `journal_audit`
  ADD PRIMARY KEY (`id`),
  ADD KEY `utilisateur_id` (`utilisateur_id`);

--
-- Indexes for table `mouvements_stock`
--
ALTER TABLE `mouvements_stock`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `produit_id` (`produit_id`),
  ADD KEY `utilisateur_id` (`utilisateur_id`);

--
-- Indexes for table `paiements`
--
ALTER TABLE `paiements`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `idx_paie_commande` (`commande_id`),
  ADD KEY `session_id` (`session_id`),
  ADD KEY `enregistre_par` (`enregistre_par`);

--
-- Indexes for table `parametres`
--
ALTER TABLE `parametres`
  ADD PRIMARY KEY (`cle`);

--
-- Indexes for table `presences`
--
ALTER TABLE `presences`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_presence` (`employe_id`,`date_presence`);

--
-- Indexes for table `produits_stock`
--
ALTER TABLE `produits_stock`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `reference` (`reference`);

--
-- Indexes for table `reclamations`
--
ALTER TABLE `reclamations`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `client_id` (`client_id`),
  ADD KEY `commande_id` (`commande_id`),
  ADD KEY `traite_par` (`traite_par`);

--
-- Indexes for table `reglements_fournisseurs`
--
ALTER TABLE `reglements_fournisseurs`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `fournisseur_id` (`fournisseur_id`),
  ADD KEY `bon_id` (`bon_id`),
  ADD KEY `session_id` (`session_id`),
  ADD KEY `enregistre_par` (`enregistre_par`);

--
-- Indexes for table `remboursements`
--
ALTER TABLE `remboursements`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `commande_id` (`commande_id`),
  ADD KEY `session_id` (`session_id`),
  ADD KEY `enregistre_par` (`enregistre_par`);

--
-- Indexes for table `salaires`
--
ALTER TABLE `salaires`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `employe_id` (`employe_id`),
  ADD KEY `enregistre_par` (`enregistre_par`),
  ADD KEY `fk_salaire_session` (`session_id`);

--
-- Indexes for table `services`
--
ALTER TABLE `services`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `code` (`code`);

--
-- Indexes for table `sessions_caisse`
--
ALTER TABLE `sessions_caisse`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD KEY `utilisateur_id` (`utilisateur_id`),
  ADD KEY `valide_par` (`valide_par`);

--
-- Indexes for table `tarifs`
--
ALTER TABLE `tarifs`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `uq_tarif` (`service_id`,`type_article_id`,`date_effet`),
  ADD KEY `type_article_id` (`type_article_id`);

--
-- Indexes for table `types_articles`
--
ALTER TABLE `types_articles`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `nom` (`nom`);

--
-- Indexes for table `utilisateurs`
--
ALTER TABLE `utilisateurs`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `email` (`email`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `alertes_stock`
--
ALTER TABLE `alertes_stock`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `appareils`
--
ALTER TABLE `appareils`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `avis_clients`
--
ALTER TABLE `avis_clients`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `bons_achat`
--
ALTER TABLE `bons_achat`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `bons_achat_lignes`
--
ALTER TABLE `bons_achat_lignes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `clients`
--
ALTER TABLE `clients`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `commandes`
--
ALTER TABLE `commandes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `commande_lignes`
--
ALTER TABLE `commande_lignes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `communications`
--
ALTER TABLE `communications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `courses`
--
ALTER TABLE `courses`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `demandes_clients`
--
ALTER TABLE `demandes_clients`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `depenses`
--
ALTER TABLE `depenses`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `employes`
--
ALTER TABLE `employes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `equipements`
--
ALTER TABLE `equipements`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `file_synchro`
--
ALTER TABLE `file_synchro`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `fournisseurs`
--
ALTER TABLE `fournisseurs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `historique_statuts`
--
ALTER TABLE `historique_statuts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=21;

--
-- AUTO_INCREMENT for table `interventions`
--
ALTER TABLE `interventions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `journal_audit`
--
ALTER TABLE `journal_audit`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=33;

--
-- AUTO_INCREMENT for table `mouvements_stock`
--
ALTER TABLE `mouvements_stock`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `paiements`
--
ALTER TABLE `paiements`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `presences`
--
ALTER TABLE `presences`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT for table `produits_stock`
--
ALTER TABLE `produits_stock`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `reclamations`
--
ALTER TABLE `reclamations`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `reglements_fournisseurs`
--
ALTER TABLE `reglements_fournisseurs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `remboursements`
--
ALTER TABLE `remboursements`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `salaires`
--
ALTER TABLE `salaires`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `services`
--
ALTER TABLE `services`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `sessions_caisse`
--
ALTER TABLE `sessions_caisse`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `tarifs`
--
ALTER TABLE `tarifs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `types_articles`
--
ALTER TABLE `types_articles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `utilisateurs`
--
ALTER TABLE `utilisateurs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=35;

-- --------------------------------------------------------

--
-- Structure for view `vue_commandes_en_retard`
--
DROP TABLE IF EXISTS `vue_commandes_en_retard`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vue_commandes_en_retard`  AS SELECT `c`.`id` AS `id`, `c`.`reference` AS `reference`, `c`.`statut` AS `statut`, `c`.`date_promise` AS `date_promise`, `cl`.`nom` AS `nom`, `cl`.`prenom` AS `prenom`, `cl`.`telephone` AS `telephone` FROM (`commandes` `c` join `clients` `cl` on(`cl`.`id` = `c`.`client_id`)) WHERE `c`.`statut` not in ('retire','annule') AND `c`.`date_promise` < curdate() ;

-- --------------------------------------------------------

--
-- Structure for view `vue_commandes_solde`
--
DROP TABLE IF EXISTS `vue_commandes_solde`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vue_commandes_solde`  AS SELECT `c`.`id` AS `id`, `c`.`reference` AS `reference`, `c`.`client_id` AS `client_id`, `c`.`statut` AS `statut`, `c`.`total` AS `total`, coalesce(`p`.`encaisse`,0) - coalesce(`r`.`rembourse`,0) AS `paye`, `c`.`total`- (coalesce(`p`.`encaisse`,0) - coalesce(`r`.`rembourse`,0)) AS `reste_a_payer` FROM ((`commandes` `c` left join (select `paiements`.`commande_id` AS `commande_id`,sum(`paiements`.`montant`) AS `encaisse` from `paiements` group by `paiements`.`commande_id`) `p` on(`p`.`commande_id` = `c`.`id`)) left join (select `remboursements`.`commande_id` AS `commande_id`,sum(`remboursements`.`montant`) AS `rembourse` from `remboursements` group by `remboursements`.`commande_id`) `r` on(`r`.`commande_id` = `c`.`id`)) ;

-- --------------------------------------------------------

--
-- Structure for view `vue_fournisseurs_solde`
--
DROP TABLE IF EXISTS `vue_fournisseurs_solde`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vue_fournisseurs_solde`  AS SELECT `f`.`id` AS `id`, `f`.`nom` AS `nom`, coalesce((select sum(`bl`.`quantite_recue` * `bl`.`prix_unitaire`) from (`bons_achat_lignes` `bl` join `bons_achat` `b` on(`b`.`id` = `bl`.`bon_id`)) where `b`.`fournisseur_id` = `f`.`id`),0) - coalesce((select sum(`r`.`montant`) from `reglements_fournisseurs` `r` where `r`.`fournisseur_id` = `f`.`id`),0) AS `solde_du` FROM `fournisseurs` AS `f` ;

-- --------------------------------------------------------

--
-- Structure for view `vue_marge_commandes`
--
DROP TABLE IF EXISTS `vue_marge_commandes`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vue_marge_commandes`  AS SELECT `l`.`commande_id` AS `commande_id`, sum(`l`.`sous_total`) AS `ventes`, sum(`l`.`quantite` * `l`.`cout_unitaire`) AS `couts_estimes`, sum(`l`.`sous_total`) - sum(`l`.`quantite` * `l`.`cout_unitaire`) AS `marge_brute` FROM `commande_lignes` AS `l` GROUP BY `l`.`commande_id` ;

-- --------------------------------------------------------

--
-- Structure for view `vue_stock_etat`
--
DROP TABLE IF EXISTS `vue_stock_etat`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vue_stock_etat`  AS SELECT `p`.`id` AS `id`, `p`.`libelle` AS `libelle`, `p`.`categorie` AS `categorie`, `p`.`unite` AS `unite`, `p`.`quantite_stock` AS `quantite_stock`, `p`.`seuil_min` AS `seuil_min`, `p`.`cout_moyen` AS `cout_moyen`, `p`.`quantite_stock`* `p`.`cout_moyen` AS `valeur_stock`, `p`.`quantite_stock`<= `p`.`seuil_min` AS `a_reapprovisionner` FROM `produits_stock` AS `p` WHERE `p`.`actif` = 1 ;

-- --------------------------------------------------------

--
-- Structure for view `vue_tableau_bord`
--
DROP TABLE IF EXISTS `vue_tableau_bord`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vue_tableau_bord`  AS SELECT (select count(0) from `clients` where `clients`.`supprime` = 0) AS `clients_total`, (select count(0) from `commandes` where `commandes`.`statut` not in ('retire','annule')) AS `commandes_en_cours`, (select count(0) from `commandes` where `commandes`.`statut` = 'pret') AS `commandes_pretes`, (select count(0) from `vue_commandes_en_retard`) AS `commandes_en_retard`, (select coalesce(sum(`paiements`.`montant`),0) from `paiements` where year(`paiements`.`date_paiement`) = year(curdate()) and month(`paiements`.`date_paiement`) = month(curdate())) AS `encaissements_mois`, (select coalesce(sum(`depenses`.`montant`),0) from `depenses` where year(`depenses`.`date_depense`) = year(curdate()) and month(`depenses`.`date_depense`) = month(curdate())) AS `depenses_mois`, (select count(0) from `alertes_stock` where `alertes_stock`.`etat` = 'ouverte') AS `alertes_stock_ouvertes` ;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `alertes_stock`
--
ALTER TABLE `alertes_stock`
  ADD CONSTRAINT `alertes_stock_ibfk_1` FOREIGN KEY (`produit_id`) REFERENCES `produits_stock` (`id`),
  ADD CONSTRAINT `alertes_stock_ibfk_2` FOREIGN KEY (`traitee_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `avis_clients`
--
ALTER TABLE `avis_clients`
  ADD CONSTRAINT `fk_avis_client` FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`),
  ADD CONSTRAINT `fk_avis_commande` FOREIGN KEY (`commande_id`) REFERENCES `commandes` (`id`);

--
-- Constraints for table `bons_achat`
--
ALTER TABLE `bons_achat`
  ADD CONSTRAINT `bons_achat_ibfk_1` FOREIGN KEY (`fournisseur_id`) REFERENCES `fournisseurs` (`id`),
  ADD CONSTRAINT `bons_achat_ibfk_2` FOREIGN KEY (`cree_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `bons_achat_lignes`
--
ALTER TABLE `bons_achat_lignes`
  ADD CONSTRAINT `bons_achat_lignes_ibfk_1` FOREIGN KEY (`bon_id`) REFERENCES `bons_achat` (`id`),
  ADD CONSTRAINT `bons_achat_lignes_ibfk_2` FOREIGN KEY (`produit_id`) REFERENCES `produits_stock` (`id`);

--
-- Constraints for table `clients`
--
ALTER TABLE `clients`
  ADD CONSTRAINT `clients_ibfk_1` FOREIGN KEY (`cree_par`) REFERENCES `utilisateurs` (`id`),
  ADD CONSTRAINT `fk_clients_utilisateur` FOREIGN KEY (`utilisateur_id`) REFERENCES `utilisateurs` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `commandes`
--
ALTER TABLE `commandes`
  ADD CONSTRAINT `commandes_ibfk_1` FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`),
  ADD CONSTRAINT `commandes_ibfk_2` FOREIGN KEY (`depose_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `commande_lignes`
--
ALTER TABLE `commande_lignes`
  ADD CONSTRAINT `commande_lignes_ibfk_1` FOREIGN KEY (`commande_id`) REFERENCES `commandes` (`id`),
  ADD CONSTRAINT `commande_lignes_ibfk_2` FOREIGN KEY (`tarif_id`) REFERENCES `tarifs` (`id`);

--
-- Constraints for table `communications`
--
ALTER TABLE `communications`
  ADD CONSTRAINT `communications_ibfk_1` FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`),
  ADD CONSTRAINT `communications_ibfk_2` FOREIGN KEY (`commande_id`) REFERENCES `commandes` (`id`),
  ADD CONSTRAINT `communications_ibfk_3` FOREIGN KEY (`cree_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `courses`
--
ALTER TABLE `courses`
  ADD CONSTRAINT `courses_ibfk_1` FOREIGN KEY (`commande_id`) REFERENCES `commandes` (`id`),
  ADD CONSTRAINT `courses_ibfk_2` FOREIGN KEY (`livreur_id`) REFERENCES `employes` (`id`);

--
-- Constraints for table `demandes_clients`
--
ALTER TABLE `demandes_clients`
  ADD CONSTRAINT `fk_demandes_client` FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`),
  ADD CONSTRAINT `fk_demandes_traite_par` FOREIGN KEY (`traite_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `depenses`
--
ALTER TABLE `depenses`
  ADD CONSTRAINT `depenses_ibfk_1` FOREIGN KEY (`fournisseur_id`) REFERENCES `fournisseurs` (`id`),
  ADD CONSTRAINT `depenses_ibfk_2` FOREIGN KEY (`intervention_id`) REFERENCES `interventions` (`id`),
  ADD CONSTRAINT `depenses_ibfk_3` FOREIGN KEY (`session_id`) REFERENCES `sessions_caisse` (`id`),
  ADD CONSTRAINT `depenses_ibfk_4` FOREIGN KEY (`enregistre_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `employes`
--
ALTER TABLE `employes`
  ADD CONSTRAINT `employes_ibfk_1` FOREIGN KEY (`utilisateur_id`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `equipements`
--
ALTER TABLE `equipements`
  ADD CONSTRAINT `equipements_ibfk_1` FOREIGN KEY (`fournisseur_id`) REFERENCES `fournisseurs` (`id`);

--
-- Constraints for table `historique_statuts`
--
ALTER TABLE `historique_statuts`
  ADD CONSTRAINT `historique_statuts_ibfk_1` FOREIGN KEY (`commande_id`) REFERENCES `commandes` (`id`),
  ADD CONSTRAINT `historique_statuts_ibfk_2` FOREIGN KEY (`utilisateur_id`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `interventions`
--
ALTER TABLE `interventions`
  ADD CONSTRAINT `interventions_ibfk_1` FOREIGN KEY (`equipement_id`) REFERENCES `equipements` (`id`);

--
-- Constraints for table `journal_audit`
--
ALTER TABLE `journal_audit`
  ADD CONSTRAINT `journal_audit_ibfk_1` FOREIGN KEY (`utilisateur_id`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `mouvements_stock`
--
ALTER TABLE `mouvements_stock`
  ADD CONSTRAINT `mouvements_stock_ibfk_1` FOREIGN KEY (`produit_id`) REFERENCES `produits_stock` (`id`),
  ADD CONSTRAINT `mouvements_stock_ibfk_2` FOREIGN KEY (`utilisateur_id`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `paiements`
--
ALTER TABLE `paiements`
  ADD CONSTRAINT `paiements_ibfk_1` FOREIGN KEY (`commande_id`) REFERENCES `commandes` (`id`),
  ADD CONSTRAINT `paiements_ibfk_2` FOREIGN KEY (`session_id`) REFERENCES `sessions_caisse` (`id`),
  ADD CONSTRAINT `paiements_ibfk_3` FOREIGN KEY (`enregistre_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `presences`
--
ALTER TABLE `presences`
  ADD CONSTRAINT `presences_ibfk_1` FOREIGN KEY (`employe_id`) REFERENCES `employes` (`id`);

--
-- Constraints for table `reclamations`
--
ALTER TABLE `reclamations`
  ADD CONSTRAINT `reclamations_ibfk_1` FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`),
  ADD CONSTRAINT `reclamations_ibfk_2` FOREIGN KEY (`commande_id`) REFERENCES `commandes` (`id`),
  ADD CONSTRAINT `reclamations_ibfk_3` FOREIGN KEY (`traite_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `reglements_fournisseurs`
--
ALTER TABLE `reglements_fournisseurs`
  ADD CONSTRAINT `reglements_fournisseurs_ibfk_1` FOREIGN KEY (`fournisseur_id`) REFERENCES `fournisseurs` (`id`),
  ADD CONSTRAINT `reglements_fournisseurs_ibfk_2` FOREIGN KEY (`bon_id`) REFERENCES `bons_achat` (`id`),
  ADD CONSTRAINT `reglements_fournisseurs_ibfk_3` FOREIGN KEY (`session_id`) REFERENCES `sessions_caisse` (`id`),
  ADD CONSTRAINT `reglements_fournisseurs_ibfk_4` FOREIGN KEY (`enregistre_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `remboursements`
--
ALTER TABLE `remboursements`
  ADD CONSTRAINT `remboursements_ibfk_1` FOREIGN KEY (`commande_id`) REFERENCES `commandes` (`id`),
  ADD CONSTRAINT `remboursements_ibfk_2` FOREIGN KEY (`session_id`) REFERENCES `sessions_caisse` (`id`),
  ADD CONSTRAINT `remboursements_ibfk_3` FOREIGN KEY (`enregistre_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `salaires`
--
ALTER TABLE `salaires`
  ADD CONSTRAINT `fk_salaire_session` FOREIGN KEY (`session_id`) REFERENCES `sessions_caisse` (`id`),
  ADD CONSTRAINT `salaires_ibfk_1` FOREIGN KEY (`employe_id`) REFERENCES `employes` (`id`),
  ADD CONSTRAINT `salaires_ibfk_2` FOREIGN KEY (`enregistre_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `sessions_caisse`
--
ALTER TABLE `sessions_caisse`
  ADD CONSTRAINT `sessions_caisse_ibfk_1` FOREIGN KEY (`utilisateur_id`) REFERENCES `utilisateurs` (`id`),
  ADD CONSTRAINT `sessions_caisse_ibfk_2` FOREIGN KEY (`valide_par`) REFERENCES `utilisateurs` (`id`);

--
-- Constraints for table `tarifs`
--
ALTER TABLE `tarifs`
  ADD CONSTRAINT `tarifs_ibfk_1` FOREIGN KEY (`service_id`) REFERENCES `services` (`id`),
  ADD CONSTRAINT `tarifs_ibfk_2` FOREIGN KEY (`type_article_id`) REFERENCES `types_articles` (`id`);

ALTER TABLE `gestion_comptes_audit`
  ADD CONSTRAINT `fk_gestion_comptes_auteur` FOREIGN KEY (`auteur_id`) REFERENCES `utilisateurs` (`id`),
  ADD CONSTRAINT `fk_gestion_comptes_cible` FOREIGN KEY (`cible_id`) REFERENCES `utilisateurs` (`id`) ON DELETE SET NULL;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
