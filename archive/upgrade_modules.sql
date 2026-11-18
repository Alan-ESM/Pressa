-- Mise à jour de la gestion du stock pour une installation existante.
-- À importer dans phpMyAdmin si la base pressing_de_la_joie existe déjà.
USE pressing_de_la_joie;

DROP TRIGGER IF EXISTS trg_stock_alert_insert;
DROP TRIGGER IF EXISTS trg_stock_alert;

DELIMITER $$
CREATE TRIGGER trg_stock_alert_insert AFTER INSERT ON stock_products FOR EACH ROW
BEGIN
 IF NEW.quantite_stock<=NEW.seuil_min THEN
  INSERT INTO stock_alerts(product_id,etat) VALUES(NEW.id,'ouverte');
 END IF;
END$$

CREATE TRIGGER trg_stock_alert AFTER UPDATE ON stock_products FOR EACH ROW
BEGIN
 IF NEW.quantite_stock<=NEW.seuil_min AND NOT EXISTS (
   SELECT 1 FROM stock_alerts WHERE product_id=NEW.id AND etat='ouverte'
 ) THEN
  INSERT INTO stock_alerts(product_id,etat) VALUES(NEW.id,'ouverte');
 END IF;
END$$
DELIMITER ;

-- Créer les alertes qui auraient dû exister avant la mise à jour.
INSERT INTO stock_alerts(product_id,etat)
SELECT p.id,'ouverte'
FROM stock_products p
WHERE p.quantite_stock<=p.seuil_min
  AND NOT EXISTS (SELECT 1 FROM stock_alerts a WHERE a.product_id=p.id AND a.etat='ouverte');
