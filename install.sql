-- =====================================================================
-- PRESSING DE LA JOIE - Base MySQL 8.0 / InnoDB / utf8mb4
-- 25 tables. Devise : FCFA. Fuseau applicatif : Africa/Douala.
-- Importer ce fichier UNE SEULE FOIS dans phpMyAdmin.
-- =====================================================================
CREATE DATABASE IF NOT EXISTS pressing_de_la_joie CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE pressing_de_la_joie;
SET NAMES utf8mb4;

-- 1. UTILISATEURS (administration, accueil, production)
CREATE TABLE IF NOT EXISTS users (
 id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(120) NOT NULL,
 email VARCHAR(160) NOT NULL UNIQUE, password VARCHAR(255) NOT NULL,
 role ENUM('admin','accueil','production') NOT NULL DEFAULT 'accueil',
 active TINYINT(1) NOT NULL DEFAULT 1, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;
-- 2. CLIENTS
CREATE TABLE IF NOT EXISTS clients (
 id INT AUTO_INCREMENT PRIMARY KEY, nom VARCHAR(100) NOT NULL, prenom VARCHAR(100) NULL,
 telephone VARCHAR(30) NOT NULL, email VARCHAR(160) NULL, adresse VARCHAR(255) NULL,
 accepte_sms TINYINT(1) NOT NULL DEFAULT 1, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_client_telephone(telephone), INDEX idx_client_nom(nom,prenom)
) ENGINE=InnoDB;
-- 3. SERVICES
CREATE TABLE IF NOT EXISTS services (
 id INT AUTO_INCREMENT PRIMARY KEY, nom VARCHAR(100) NOT NULL,
 prix DECIMAL(12,2) NOT NULL DEFAULT 0, cout_estime DECIMAL(12,2) NOT NULL DEFAULT 0,
 description VARCHAR(255) NULL, active TINYINT(1) NOT NULL DEFAULT 1,
 CHECK(prix>=0), CHECK(cout_estime>=0)
) ENGINE=InnoDB;
-- 4. COMMANDES
CREATE TABLE IF NOT EXISTS orders (
 id INT AUTO_INCREMENT PRIMARY KEY, code VARCHAR(30) NOT NULL UNIQUE,
 client_id INT NOT NULL, user_id INT NOT NULL,
 type_depot ENUM('normal','express') NOT NULL DEFAULT 'normal',
 statut ENUM('recu','lavage','repassage','emballage','pret','retire','annule') NOT NULL DEFAULT 'recu',
 date_depot DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, date_prevue DATE NOT NULL,
 total DECIMAL(12,2) NOT NULL DEFAULT 0, surcharge_express DECIMAL(12,2) NOT NULL DEFAULT 0,
 notes TEXT NULL, supprimee TINYINT(1) NOT NULL DEFAULT 0,
 FOREIGN KEY(client_id) REFERENCES clients(id), FOREIGN KEY(user_id) REFERENCES users(id),
 INDEX idx_orders_statut(statut), INDEX idx_orders_date(date_depot), CHECK(total>=0), CHECK(surcharge_express>=0)
) ENGINE=InnoDB;
-- 5. LIGNES DE COMMANDE
CREATE TABLE IF NOT EXISTS order_items (
 id INT AUTO_INCREMENT PRIMARY KEY, order_id INT NOT NULL, service_id INT NOT NULL,
 description VARCHAR(160) NOT NULL, quantite INT NOT NULL DEFAULT 1,
 prix_unitaire DECIMAL(12,2) NOT NULL, cout_unitaire DECIMAL(12,2) NOT NULL DEFAULT 0,
 subtotal DECIMAL(12,2) NOT NULL,
 FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE,
 FOREIGN KEY(service_id) REFERENCES services(id), CHECK(quantite>0), CHECK(prix_unitaire>=0), CHECK(cout_unitaire>=0), CHECK(subtotal>=0)
) ENGINE=InnoDB;
-- 6. PAIEMENTS
CREATE TABLE IF NOT EXISTS payments (
 id INT AUTO_INCREMENT PRIMARY KEY, order_id INT NOT NULL, montant DECIMAL(12,2) NOT NULL,
 mode ENUM('especes','mtn_momo','orange_money','virement','carte') NOT NULL DEFAULT 'especes',
 date_paiement DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, reference VARCHAR(100) NULL,
 FOREIGN KEY(order_id) REFERENCES orders(id), CHECK(montant>0), INDEX idx_payment_date(date_paiement)
) ENGINE=InnoDB;
-- 7. MESSAGES / HISTORIQUE SMS
CREATE TABLE IF NOT EXISTS messages (
 id INT AUTO_INCREMENT PRIMARY KEY, client_id INT NOT NULL, order_id INT NULL,
 canal ENUM('interne','sms') NOT NULL DEFAULT 'sms', message TEXT NOT NULL,
 statut ENUM('prepare','envoye_manuellement','echec') NOT NULL DEFAULT 'prepare',
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(client_id) REFERENCES clients(id), FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE SET NULL
) ENGINE=InnoDB;
-- 8. PARAMETRES DU PRESSING
CREATE TABLE IF NOT EXISTS business_settings (
 id INT AUTO_INCREMENT PRIMARY KEY, nom_pressing VARCHAR(120) NOT NULL DEFAULT 'Pressing de la joie',
 telephone VARCHAR(30) NULL, adresse VARCHAR(255) NULL,
 surcharge_express_percent DECIMAL(5,2) NOT NULL DEFAULT 30,
 devise VARCHAR(10) NOT NULL DEFAULT 'FCFA', marge_cible_percent DECIMAL(5,2) NOT NULL DEFAULT 40,
 CHECK(surcharge_express_percent>=0), CHECK(marge_cible_percent>=0)
) ENGINE=InnoDB;
-- 9. TYPES D'ARTICLES
CREATE TABLE IF NOT EXISTS type_articles (
 id INT AUTO_INCREMENT PRIMARY KEY, libelle VARCHAR(100) NOT NULL, unite_mesure VARCHAR(20) NOT NULL DEFAULT 'piece', actif TINYINT(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB;
-- 10. TARIFS historisés (les commandes gardent leur prix appliqué)
CREATE TABLE IF NOT EXISTS tarifs (
 id INT AUTO_INCREMENT PRIMARY KEY, service_id INT NOT NULL, type_article_id INT NOT NULL,
 prix DECIMAL(12,2) NOT NULL, date_effet DATE NOT NULL,
 FOREIGN KEY(service_id) REFERENCES services(id), FOREIGN KEY(type_article_id) REFERENCES type_articles(id), CHECK(prix>=0), INDEX idx_tarif_date(date_effet)
) ENGINE=InnoDB;
-- 11. NOTIFICATIONS
CREATE TABLE IF NOT EXISTS notifications (
 id INT AUTO_INCREMENT PRIMARY KEY, client_id INT NOT NULL, order_id INT NULL,
 type VARCHAR(50) NOT NULL, canal ENUM('sms','appel','interne') NOT NULL DEFAULT 'sms',
 contenu TEXT NOT NULL, etat ENUM('en_attente','preparee','confirmee','echec') NOT NULL DEFAULT 'en_attente',
 date_creation DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, date_envoi DATETIME NULL,
 FOREIGN KEY(client_id) REFERENCES clients(id), FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE SET NULL
) ENGINE=InnoDB;
-- 12. RECLAMATIONS
CREATE TABLE IF NOT EXISTS reclamations (
 id INT AUTO_INCREMENT PRIMARY KEY, client_id INT NOT NULL, order_id INT NULL,
 date_reclamation DATE NOT NULL, nature VARCHAR(120) NULL, demande TEXT NULL,
 decision TEXT NULL, statut ENUM('ouverte','en_cours','cloturee') NOT NULL DEFAULT 'ouverte',
 FOREIGN KEY(client_id) REFERENCES clients(id), FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE SET NULL
) ENGINE=InnoDB;
-- 13. CLOTURES DE CAISSE
CREATE TABLE IF NOT EXISTS cash_closures (
 id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, date_cloture DATE NOT NULL,
 fond_caisse DECIMAL(12,2) NOT NULL DEFAULT 0, montant_theorique DECIMAL(12,2) NOT NULL DEFAULT 0,
 montant_compte DECIMAL(12,2) NOT NULL DEFAULT 0,
 ecart DECIMAL(12,2) GENERATED ALWAYS AS (montant_compte-montant_theorique) STORED,
 commentaire_ecart TEXT NULL, date_validation DATETIME NULL,
 FOREIGN KEY(user_id) REFERENCES users(id), CHECK(fond_caisse>=0)
) ENGINE=InnoDB;
-- 14. JOURNAL DES MODIFICATIONS
CREATE TABLE IF NOT EXISTS modifications (
 id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, order_id INT NULL,
 date_heure DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, objet VARCHAR(100) NOT NULL,
 ancienne_valeur TEXT NULL, nouvelle_valeur TEXT NULL,
 FOREIGN KEY(user_id) REFERENCES users(id), FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE SET NULL
) ENGINE=InnoDB;
-- 15. DEPENSES
CREATE TABLE IF NOT EXISTS expenses (
 id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, date_depense DATE NOT NULL,
 categorie VARCHAR(80) NOT NULL, montant DECIMAL(12,2) NOT NULL,
 justificatif VARCHAR(255) NULL, commentaire TEXT NULL,
 FOREIGN KEY(user_id) REFERENCES users(id), CHECK(montant>0)
) ENGINE=InnoDB;
-- 16. FOURNISSEURS
CREATE TABLE IF NOT EXISTS suppliers (
 id INT AUTO_INCREMENT PRIMARY KEY, nom VARCHAR(120) NOT NULL, telephone VARCHAR(30) NULL,
 adresse VARCHAR(255) NULL, email VARCHAR(160) NULL, solde_du DECIMAL(12,2) NOT NULL DEFAULT 0
) ENGINE=InnoDB;
-- 17. PRODUITS DE STOCK
CREATE TABLE IF NOT EXISTS stock_products (
 id INT AUTO_INCREMENT PRIMARY KEY, libelle VARCHAR(120) NOT NULL, unite VARCHAR(20) NOT NULL,
 quantite_stock DECIMAL(12,2) NOT NULL DEFAULT 0, seuil_min DECIMAL(12,2) NOT NULL DEFAULT 0,
 cout_moyen DECIMAL(12,2) NOT NULL DEFAULT 0, actif TINYINT(1) NOT NULL DEFAULT 1,
 CHECK(quantite_stock>=0), CHECK(seuil_min>=0), CHECK(cout_moyen>=0)
) ENGINE=InnoDB;
-- 18. BONS DE COMMANDE FOURNISSEUR
CREATE TABLE IF NOT EXISTS purchase_orders (
 id INT AUTO_INCREMENT PRIMARY KEY, supplier_id INT NOT NULL, date_bon DATE NOT NULL,
 statut ENUM('brouillon','envoye','recu_partiel','recu','annule') NOT NULL DEFAULT 'brouillon', date_reception DATE NULL,
 FOREIGN KEY(supplier_id) REFERENCES suppliers(id)
) ENGINE=InnoDB;
-- 19. LIGNES D'ACHAT
CREATE TABLE IF NOT EXISTS purchase_order_items (
 id INT AUTO_INCREMENT PRIMARY KEY, purchase_order_id INT NOT NULL, product_id INT NOT NULL,
 quantite DECIMAL(12,2) NOT NULL, prix_achat DECIMAL(12,2) NOT NULL,
 FOREIGN KEY(purchase_order_id) REFERENCES purchase_orders(id) ON DELETE CASCADE,
 FOREIGN KEY(product_id) REFERENCES stock_products(id), CHECK(quantite>0), CHECK(prix_achat>=0)
) ENGINE=InnoDB;
-- 20. EQUIPEMENTS
CREATE TABLE IF NOT EXISTS equipment (
 id INT AUTO_INCREMENT PRIMARY KEY, designation VARCHAR(120) NOT NULL,
 date_acquisition DATE NULL, etat ENUM('en_service','en_panne','hors_service') NOT NULL DEFAULT 'en_service',
 supplier_id INT NULL, FOREIGN KEY(supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL
) ENGINE=InnoDB;
-- 21. INTERVENTIONS / MAINTENANCE
CREATE TABLE IF NOT EXISTS interventions (
 id INT AUTO_INCREMENT PRIMARY KEY, equipment_id INT NOT NULL, type VARCHAR(100) NOT NULL,
 date_intervention DATE NOT NULL, duree_arret INT NOT NULL DEFAULT 0, cout DECIMAL(12,2) NOT NULL DEFAULT 0,
 FOREIGN KEY(equipment_id) REFERENCES equipment(id), CHECK(duree_arret>=0), CHECK(cout>=0)
) ENGINE=InnoDB;
-- 22. MOUVEMENTS DE STOCK
CREATE TABLE IF NOT EXISTS stock_movements (
 id INT AUTO_INCREMENT PRIMARY KEY, product_id INT NOT NULL,
 type ENUM('entree','sortie','ajustement') NOT NULL, quantite DECIMAL(12,2) NOT NULL,
 motif VARCHAR(255) NULL, date_mouvement DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 user_id INT NULL, FOREIGN KEY(product_id) REFERENCES stock_products(id),
 FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL, CHECK(quantite>0)
) ENGINE=InnoDB;
-- 23. ALERTES DE STOCK
CREATE TABLE IF NOT EXISTS stock_alerts (
 id INT AUTO_INCREMENT PRIMARY KEY, product_id INT NOT NULL, date_alerte DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 etat ENUM('ouverte','traitee') NOT NULL DEFAULT 'ouverte', FOREIGN KEY(product_id) REFERENCES stock_products(id)
) ENGINE=InnoDB;
-- 24. PRESENCES
CREATE TABLE IF NOT EXISTS attendance (
 id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, date_presence DATE NOT NULL,
 creneau_prevu VARCHAR(30) NULL, statut ENUM('present','absent','retard','conge') NOT NULL,
 FOREIGN KEY(user_id) REFERENCES users(id), UNIQUE KEY uq_presence_user_day(user_id,date_presence)
) ENGINE=InnoDB;
-- 25. COURSES DE COLLECTE / LIVRAISON
CREATE TABLE IF NOT EXISTS delivery_runs (
 id INT AUTO_INCREMENT PRIMARY KEY, order_id INT NOT NULL, type ENUM('collecte','livraison') NOT NULL,
 date_prevue DATE NOT NULL, creneau VARCHAR(30) NULL, adresse VARCHAR(255) NULL,
 statut ENUM('planifiee','en_cours','effectuee','annulee') NOT NULL DEFAULT 'planifiee',
 frais DECIMAL(12,2) NOT NULL DEFAULT 0, user_id INT NULL,
 FOREIGN KEY(order_id) REFERENCES orders(id), FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL, CHECK(frais>=0)
) ENGINE=InnoDB;

-- Données initiales : tarifs de départ en FCFA, à adapter à vos charges réelles.
INSERT INTO services(nom,prix,cout_estime,description) VALUES
('Lavage simple',1500,650,'Prix indicatif par pièce'),
('Repassage seul',1000,350,'Prix indicatif par pièce'),
('Lavage + repassage',2500,1050,'Forfait complet par pièce'),
('Nettoyage délicat',3500,1600,'Textiles délicats'),
('Costume / veste',5000,2400,'Nettoyage et finition'),
('Drap / grande pièce',3000,1300,'Linge de maison');
INSERT INTO type_articles(libelle,unite_mesure) VALUES
('Chemise','piece'),('Pantalon','piece'),('Robe','piece'),('Costume','ensemble'),('Drap','piece'),('Couette','piece');
INSERT INTO business_settings(nom_pressing,telephone,adresse,surcharge_express_percent,devise,marge_cible_percent)
VALUES('Pressing de la joie','+237','Cameroun',30,'FCFA',40);
INSERT INTO stock_products(libelle,unite,quantite_stock,seuil_min,cout_moyen) VALUES
('Lessive professionnelle','kg',0,5,0),('Adoucissant','litre',0,3,0),('Détachant','litre',0,2,0),('Emballages','paquet',0,5,0);

-- Déclencheurs : mise à jour du stock et alerte au seuil minimum.
DELIMITER $$
CREATE TRIGGER trg_stock_alert_insert AFTER INSERT ON stock_products FOR EACH ROW
BEGIN
 IF NEW.quantite_stock<=NEW.seuil_min THEN
  INSERT INTO stock_alerts(product_id,etat) VALUES(NEW.id,'ouverte');
 END IF;
END$$
CREATE TRIGGER trg_stock_movement_insert AFTER INSERT ON stock_movements FOR EACH ROW
BEGIN
 IF NEW.type='entree' THEN
  UPDATE stock_products SET quantite_stock=quantite_stock+NEW.quantite WHERE id=NEW.product_id;
 ELSEIF NEW.type='sortie' THEN
  UPDATE stock_products SET quantite_stock=GREATEST(0,quantite_stock-NEW.quantite) WHERE id=NEW.product_id;
 ELSE
  UPDATE stock_products SET quantite_stock=NEW.quantite WHERE id=NEW.product_id;
 END IF;
END$$
CREATE TRIGGER trg_stock_alert AFTER UPDATE ON stock_products FOR EACH ROW
BEGIN
 IF NEW.quantite_stock<=NEW.seuil_min AND NOT EXISTS (SELECT 1 FROM stock_alerts WHERE product_id=NEW.id AND etat='ouverte') THEN
  INSERT INTO stock_alerts(product_id,etat) VALUES(NEW.id,'ouverte');
 END IF;
END$$
DELIMITER ;
