-- Adds email as a communications channel and records successful delivery.
-- Back up the database before applying this migration. Safe to apply once.
USE pressa;
ALTER TABLE communications
  MODIFY canal ENUM('sms','email','appel','interne') NOT NULL DEFAULT 'sms',
  MODIFY statut ENUM('prepare','envoye','envoye_manuellement','echec','annule') NOT NULL DEFAULT 'prepare';
