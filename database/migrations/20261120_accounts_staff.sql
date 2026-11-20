ALTER TABLE utilisateurs MODIFY role ENUM('admin','responsable','caissier','accueil','receptionniste','production','livreur','client') NOT NULL DEFAULT 'accueil';
UPDATE utilisateurs SET role='accueil' WHERE role='receptionniste';
ALTER TABLE utilisateurs MODIFY role ENUM('admin','responsable','caissier','accueil','production','livreur','client') NOT NULL DEFAULT 'accueil';
ALTER TABLE utilisateurs ADD COLUMN doit_changer_mdp TINYINT(1) NOT NULL DEFAULT 0 AFTER actif;
CREATE TABLE limites_inscription (
  cle_ip CHAR(64) NOT NULL,
  debut_fenetre DATETIME NOT NULL,
  tentatives INT NOT NULL DEFAULT 0,
  PRIMARY KEY (cle_ip)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE gestion_comptes_audit (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  auteur_id INT(11) NOT NULL,
  cible_id INT(11) DEFAULT NULL,
  cible_email VARCHAR(160) NOT NULL,
  action VARCHAR(30) NOT NULL,
  motif VARCHAR(500) NOT NULL,
  date_action DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_gestion_comptes_cible (cible_id),
  KEY idx_gestion_comptes_auteur (auteur_id),
  CONSTRAINT fk_gestion_comptes_auteur FOREIGN KEY (auteur_id) REFERENCES utilisateurs(id),
  CONSTRAINT fk_gestion_comptes_cible FOREIGN KEY (cible_id) REFERENCES utilisateurs(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
