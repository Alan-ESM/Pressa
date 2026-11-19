ALTER TABLE utilisateurs MODIFY role ENUM('admin','caissier','accueil','receptionniste','production','livreur','client') NOT NULL DEFAULT 'accueil';
ALTER TABLE clients ADD COLUMN utilisateur_id INT NULL UNIQUE, ADD CONSTRAINT fk_clients_utilisateur FOREIGN KEY (utilisateur_id) REFERENCES utilisateurs(id) ON DELETE SET NULL;
ALTER TABLE communications MODIFY canal ENUM('sms','email','appel','interne') NOT NULL DEFAULT 'sms', MODIFY statut ENUM('prepare','envoye','envoye_manuellement','echec','annule') NOT NULL DEFAULT 'prepare', ADD COLUMN sens ENUM('entrant','sortant') NOT NULL DEFAULT 'sortant';
CREATE TABLE demandes_clients (
 id INT AUTO_INCREMENT PRIMARY KEY,
 client_id INT NOT NULL,
 type ENUM('depot','ramassage') NOT NULL,
 date_prevue DATE NOT NULL,
 creneau ENUM('matin','apres_midi','soir') NOT NULL DEFAULT 'matin',
 adresse VARCHAR(255) NULL,
 details VARCHAR(500) NULL,
 statut ENUM('en_attente','confirmee','refusee','terminee') NOT NULL DEFAULT 'en_attente',
 traite_par INT NULL,
 cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 modifie_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 INDEX idx_demandes_client_date (client_id,date_prevue),
 INDEX idx_demandes_statut_date (statut,date_prevue),
 CONSTRAINT fk_demandes_client FOREIGN KEY (client_id) REFERENCES clients(id),
 CONSTRAINT fk_demandes_traite_par FOREIGN KEY (traite_par) REFERENCES utilisateurs(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE avis_clients (
 id INT AUTO_INCREMENT PRIMARY KEY,
 client_id INT NOT NULL,
 commande_id INT NOT NULL,
 note TINYINT UNSIGNED NOT NULL,
 commentaire VARCHAR(1000) NULL,
 statut ENUM('nouveau','lu','traite') NOT NULL DEFAULT 'nouveau',
 cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE KEY uq_avis_client_commande (client_id,commande_id),
 INDEX idx_avis_date (cree_le),
 CONSTRAINT fk_avis_client FOREIGN KEY (client_id) REFERENCES clients(id),
 CONSTRAINT fk_avis_commande FOREIGN KEY (commande_id) REFERENCES commandes(id),
 CONSTRAINT chk_avis_note CHECK (note BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
