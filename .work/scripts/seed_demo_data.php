<?php
require_once __DIR__ . '/../../config/config.php';

$pdo = new PDO(
    'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
    DB_USER,
    DB_PASS,
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
);

function countRows(PDO $pdo, string $table): int
{
    if (!preg_match('/^[a-z_]+$/', $table)) {
        throw new RuntimeException('Nom de table invalide.');
    }
    return (int)$pdo->query("SELECT COUNT(*) FROM `$table`")->fetchColumn();
}

$expected = [
    'utilisateurs' => 1,
    'employes' => 0,
    'clients' => 0,
    'commandes' => 0,
    'commande_lignes' => 0,
    'paiements' => 0,
    'courses' => 0,
    'communications' => 0,
    'reclamations' => 0,
    'fournisseurs' => 0,
    'bons_achat' => 0,
    'bons_achat_lignes' => 0,
    'reglements_fournisseurs' => 0,
    'mouvements_stock' => 0,
    'depenses' => 0,
    'equipements' => 0,
    'interventions' => 0,
    'presences' => 0,
];
foreach ($expected as $table => $count) {
    $actual = countRows($pdo, $table);
    if ($actual !== $count) {
        throw new RuntimeException("Arrêt sans modification : `$table` contient $actual ligne(s), attendu $count pour ce jeu de démonstration initial.");
    }
}
$roleCounts = $pdo->query('SELECT role, COUNT(*) AS n FROM utilisateurs GROUP BY role')->fetchAll(PDO::FETCH_KEY_PAIR);
if (count($roleCounts) !== 1 || (int)($roleCounts['admin'] ?? 0) !== 1) {
    throw new RuntimeException('Arrêt sans modification : les comptes existants ne correspondent pas au prérequis (un seul administrateur initial).');
}
$admin = $pdo->query("SELECT id, nom FROM utilisateurs WHERE role='admin' ORDER BY id LIMIT 1")->fetch();
if (!$admin) {
    throw new RuntimeException('Compte administrateur introuvable.');
}
$tariffs = $pdo->query("SELECT t.id FROM tarifs t JOIN services s ON s.id=t.service_id JOIN types_articles ta ON ta.id=t.type_article_id WHERE s.actif=1 AND ta.actif=1 AND t.date_effet=(SELECT MAX(t2.date_effet) FROM tarifs t2 WHERE t2.service_id=t.service_id AND t2.type_article_id=t.type_article_id AND t2.date_effet<=CURDATE()) ORDER BY t.id")->fetchAll(PDO::FETCH_COLUMN);
if (!$tariffs) {
    throw new RuntimeException('Aucun tarif actif disponible pour créer les commandes de démonstration.');
}
$productIds = $pdo->query('SELECT id FROM produits_stock WHERE actif=1 ORDER BY id LIMIT 2')->fetchAll(PDO::FETCH_COLUMN);
if (count($productIds) < 2) {
    throw new RuntimeException('Deux produits actifs sont nécessaires pour le jeu de démonstration.');
}

$credentials = [];
$employeeIds = [];
$clientIds = [];
$orderIds = [];
$pdo->beginTransaction();
try {
    $pdo->exec('SET @app_user_id = ' . (int)$admin['id']);
    $employeePost = ['admin'=>'gerant','caissier'=>'caissier','accueil'=>'accueil','production'=>'laveur','livreur'=>'livreur'];
    $findEmployee = $pdo->prepare('SELECT id FROM employes WHERE utilisateur_id=? LIMIT 1');
    $insertEmployee = $pdo->prepare('INSERT INTO employes(utilisateur_id,nom,poste,actif) VALUES(?,?,?,1)');
    $findEmployee->execute([(int)$admin['id']]);
    $existingAdminEmployee = $findEmployee->fetchColumn();
    if ($existingAdminEmployee) {
        $employeeIds['admin_initial'] = (int)$existingAdminEmployee;
    } else {
        $insertEmployee->execute([(int)$admin['id'], $admin['nom'], 'gerant']);
        $employeeIds['admin_initial'] = (int)$pdo->lastInsertId();
    }

    $roleLabels = ['admin'=>'Administrateur','caissier'=>'Caissier','accueil'=>'Accueil','production'=>'Production','livreur'=>'Livreur'];
    $insertUser = $pdo->prepare('INSERT INTO utilisateurs(nom,email,mot_de_passe,role,actif) VALUES(?,?,?,?,1)');
    foreach ($roleLabels as $role => $label) {
        for ($number = 1; $number <= 2; $number++) {
            $suffix = str_pad((string)$number, 2, '0', STR_PAD_LEFT);
            $name = 'Démo ' . $label . ' ' . $suffix;
            $email = 'demo.' . $role . $suffix . '@pressa.local';
            $password = rtrim(strtr(base64_encode(random_bytes(18)), '+/', '-_'), '=');
            $insertUser->execute([$name, $email, password_hash($password, PASSWORD_DEFAULT), $role]);
            $userId = (int)$pdo->lastInsertId();
            $insertEmployee->execute([$userId, $name, $employeePost[$role]]);
            $employeeId = (int)$pdo->lastInsertId();
            $employeeIds[$role . $suffix] = $employeeId;
            $credentials[] = ['role'=>$label, 'email'=>$email, 'password'=>$password];
        }
    }

    $clients = [
        ['Amina','Démo 01','TEST-CLIENT-01','Yaoundé Centre'],
        ['Paul','Démo 02','TEST-CLIENT-02','Bastos'],
        ['Mireille','Démo 03','TEST-CLIENT-03','Mvan'],
        ['Samuel','Démo 04','TEST-CLIENT-04','Biyem-Assi'],
        ['Nadia','Démo 05','TEST-CLIENT-05','Essos'],
        ['Eric','Démo 06','TEST-CLIENT-06','Akwa, Douala'],
        ['Joëlle','Démo 07','TEST-CLIENT-07','Bonapriso, Douala'],
        ['David','Démo 08','TEST-CLIENT-08','Nlongkak'],
        ['Clarisse','Démo 09','TEST-CLIENT-09','Odza'],
        ['Benoît','Démo 10','TEST-CLIENT-10','Mendong'],
    ];
    $insertClient = $pdo->prepare("INSERT INTO clients(nom,prenom,type_client,telephone,email,adresse,quartier,canal_prefere,cree_par) VALUES(?,?,'particulier',?,?,?,?,'aucun',?)");
    foreach ($clients as $i => $client) {
        $n = $i + 1;
        $insertClient->execute([$client[1],$client[0],$client[2],'client.demo'.str_pad((string)$n,2,'0',STR_PAD_LEFT).'@example.test','Adresse de démonstration '.$n.', '.$client[3],$client[3],(int)$admin['id']]);
        $clientIds[] = (int)$pdo->lastInsertId();
    }

    $insertOrder = $pdo->prepare("INSERT INTO commandes(reference,client_id,depose_par,type_depot,mode_remise,date_promise,notes) VALUES(?,?,?,?,?,?,?)");
    $insertLine = $pdo->prepare('INSERT INTO commande_lignes(commande_id,tarif_id,description,quantite) VALUES(?,?,?,?)');
    $today = new DateTimeImmutable('today');
    for ($i = 0; $i < 10; $i++) {
        $n = $i + 1;
        $reference = 'DEMO-' . date('ymd') . '-' . str_pad((string)$n,2,'0',STR_PAD_LEFT);
        $depotType = in_array($n,[3,8],true) ? 'express' : 'normal';
        $mode = $n === 6 ? 'livraison' : 'retrait';
        $due = $today->modify('+' . (1 + ($i % 8)) . ' days')->format('Y-m-d');
        $insertOrder->execute([$reference,$clientIds[$i],(int)$admin['id'],$depotType,$mode,$due,'DONNEE DEMO Pressa — jeu de démonstration']);
        $orderId = (int)$pdo->lastInsertId();
        $orderIds[$n] = $orderId;
        $tariffId = (int)$tariffs[$i % count($tariffs)];
        $quantity = 1 + ($i % 3);
        $insertLine->execute([$orderId,$tariffId,'Article de démonstration ' . str_pad((string)$n,2,'0',STR_PAD_LEFT),$quantity]);
    }

    $paymentShare = [2=>0.25,4=>0.50,5=>1.0,6=>1.0,7=>1.0,10=>1.0];
    $paymentModes = ['especes','mtn_momo','orange_money','virement','carte','especes'];
    $insertPayment = $pdo->prepare('INSERT INTO paiements(commande_id,montant,mode,reference,enregistre_par) VALUES(?,?,?,?,?)');
    foreach ($paymentShare as $orderNumber => $share) {
        $s = $pdo->prepare('SELECT total FROM commandes WHERE id=?');
        $s->execute([$orderIds[$orderNumber]]);
        $total = (float)$s->fetchColumn();
        $amount = number_format($total * $share, 2, '.', '');
        $mode = [2=>'especes',4=>'mtn_momo',5=>'orange_money',6=>'virement',7=>'carte',10=>'especes'][$orderNumber];
        $insertPayment->execute([$orderIds[$orderNumber],$amount,$mode,sprintf('DEMO-PAY-%02d',$orderNumber),(int)$admin['id']]);
    }

    $targetStatuses = [2=>'lavage',3=>'repassage',4=>'emballage',5=>'pret',6=>'pret',7=>'pret',8=>'lavage',10=>'pret'];
    $updateStatus = $pdo->prepare('UPDATE commandes SET statut=? WHERE id=?');
    foreach ($targetStatuses as $orderNumber => $status) {
        $updateStatus->execute([$status,$orderIds[$orderNumber]]);
    }
    foreach ([7,10] as $orderNumber) {
        $updateStatus->execute(['retire',$orderIds[$orderNumber]]);
    }

    $driverEmployeeId = $employeeIds['livreur01'];
    $insertCourse = $pdo->prepare("INSERT INTO courses(commande_id,type,date_prevue,creneau,adresse,statut,livreur_id,notes) VALUES(?,'livraison',?,'matin','Adresse de démonstration 6, Akwa, Douala','planifiee',?,'DEMO — course à attribuer et tester')");
    $insertCourse->execute([$orderIds[6],$today->modify('+1 day')->format('Y-m-d'),$driverEmployeeId]);

    $insertMessage = $pdo->prepare("INSERT INTO communications(client_id,commande_id,canal,type,contenu,statut,cree_par) VALUES(?,?,'interne','autre',?,'prepare',?)");
    foreach ([1,2,5,6] as $n) {
        $insertMessage->execute([$clientIds[$n-1],$orderIds[$n],'DEMO — note interne de démonstration ; aucun SMS envoyé.',(int)$admin['id']]);
    }
    $insertComplaint = $pdo->prepare('INSERT INTO reclamations(client_id,commande_id,date_reclamation,nature,demande,decision,statut,traite_par,date_info_client,date_cloture) VALUES(?,?,?,?,?,?,?,?,?,?)');
    $insertComplaint->execute([$clientIds[2],$orderIds[3],$today->format('Y-m-d'),'DEMO — délai de traitement','Exemple fictif de réclamation.','Suivi de démonstration.','en_cours',(int)$admin['id'],null,null]);
    $insertComplaint->execute([$clientIds[6],$orderIds[7],$today->modify('-1 day')->format('Y-m-d'),'DEMO — article à vérifier','Exemple fictif de demande client.','Dossier démo clôturé.','cloturee',(int)$admin['id'],$today->format('Y-m-d'),$today->format('Y-m-d H:i:s')]);

    $suppliers = [
        ['DEMO Fournitures Pressing','TEST-FOURN-01','fournisseur.demo01@example.test','Adresse fournisseur démo 01'],
        ['DEMO Produits & Emballages','TEST-FOURN-02','fournisseur.demo02@example.test','Adresse fournisseur démo 02'],
        ['DEMO Équipements','TEST-FOURN-03','fournisseur.demo03@example.test','Adresse fournisseur démo 03'],
    ];
    $insertSupplier = $pdo->prepare('INSERT INTO fournisseurs(nom,telephone,email,adresse,notes) VALUES(?,?,?,?,?)');
    $supplierIds=[];
    foreach ($suppliers as $supplier) {
        $insertSupplier->execute([$supplier[0],$supplier[1],$supplier[2],$supplier[3],'Données fictives de démonstration Pressa']);
        $supplierIds[]=(int)$pdo->lastInsertId();
    }
    $insertPurchase = $pdo->prepare('INSERT INTO bons_achat(reference,fournisseur_id,date_bon,statut,cree_par,notes) VALUES(?,?,CURDATE(),?,?,?)');
    $insertPurchase->execute(['DEMO-ACHAT-001',$supplierIds[0],'envoye',(int)$admin['id'],'Bon démo envoyé — réception simulée séparément dans le stock.']);
    $purchase1=(int)$pdo->lastInsertId();
    $insertPurchase->execute(['DEMO-ACHAT-002',$supplierIds[1],'brouillon',(int)$admin['id'],'Bon démo en brouillon.']);
    $purchase2=(int)$pdo->lastInsertId();
    $insertPurchaseLine=$pdo->prepare('INSERT INTO bons_achat_lignes(bon_id,produit_id,quantite_commandee,quantite_recue,prix_unitaire) VALUES(?,?,?,?,?)');
    $insertPurchaseLine->execute([$purchase1,(int)$productIds[0],20,0,2500]);
    $insertPurchaseLine->execute([$purchase1,(int)$productIds[1],10,0,1800]);
    $insertPurchaseLine->execute([$purchase2,(int)$productIds[0],5,0,2500]);
    $pdo->prepare("INSERT INTO reglements_fournisseurs(fournisseur_id,bon_id,montant,mode,reference,enregistre_par) VALUES(?,?,5000,'virement','DEMO-REG-001',?)")->execute([$supplierIds[0],$purchase1,(int)$admin['id']]);

    $pdo->prepare("INSERT INTO mouvements_stock(produit_id,type,quantite,prix_unitaire,motif,reference_document,utilisateur_id) VALUES(?,'entree',12,2500,'DEMO — stock initial de démonstration','DEMO-STOCK-001',?)")->execute([(int)$productIds[0],(int)$admin['id']]);
    $pdo->prepare("UPDATE alertes_stock SET etat='traitee',traitee_par=?,date_traitement=NOW() WHERE produit_id=? AND etat='ouverte'")->execute([(int)$admin['id'],(int)$productIds[0]]);

    $insertEquipment=$pdo->prepare('INSERT INTO equipements(designation,numero_serie,categorie,date_acquisition,valeur_acquisition,fournisseur_id,etat,actif) VALUES(?,?,?,?,?,?,?,1)');
    $insertEquipment->execute(['DEMO — Machine à laver','DEMO-MACH-001','machine_laver',$today->modify('-1 year')->format('Y-m-d'),850000,$supplierIds[2],'en_service']);
    $equipment1=(int)$pdo->lastInsertId();
    $insertEquipment->execute(['DEMO — Sécheuse','DEMO-SEC-001','secheuse',$today->modify('-8 months')->format('Y-m-d'),620000,$supplierIds[2],'en_panne']);
    $equipment2=(int)$pdo->lastInsertId();
    $insertIntervention=$pdo->prepare('INSERT INTO interventions(equipement_id,date_intervention,type,description,technicien,duree_arret_min,cout) VALUES(?,?,?,?,?,?,?)');
    $insertIntervention->execute([$equipment1,$today->modify('-14 days')->format('Y-m-d'),'preventive','DEMO — entretien périodique fictif','Technicien démo',30,12000]);
    $intervention1=(int)$pdo->lastInsertId();
    $insertIntervention->execute([$equipment2,$today->modify('-2 days')->format('Y-m-d'),'corrective','DEMO — diagnostic fictif, intervention à planifier','Technicien démo',90,25000]);
    $intervention2=(int)$pdo->lastInsertId();

    $insertExpense=$pdo->prepare('INSERT INTO depenses(date_depense,categorie,libelle,montant,mode_paiement,justificatif,commentaire,fournisseur_id,intervention_id,enregistre_par) VALUES(CURDATE(),?,?,?,?,?,?,?,?,?)');
    $expenseRows=[
        ['loyer','DEMO — loyer mensuel',250000,'virement','DEMO-JUST-001',null,null],
        ['electricite_eau','DEMO — eau et électricité',68000,'especes','DEMO-JUST-002',null,null],
        ['produits_lavage','DEMO — réapprovisionnement démo',42000,'virement','DEMO-JUST-003',$supplierIds[1],null],
        ['maintenance','DEMO — intervention sécheuse',25000,'virement','DEMO-JUST-004',$supplierIds[2],$intervention2],
    ];
    foreach ($expenseRows as $expense) {
        $insertExpense->execute([$expense[0],$expense[1],$expense[2],$expense[3],$expense[4],'Montant et justificatif fictifs de démonstration.',$expense[5],$expense[6],(int)$admin['id']]);
    }

    $insertPresence=$pdo->prepare('INSERT INTO presences(employe_id,date_presence,creneau,statut) VALUES(?,CURDATE(),?,?)');
    $allEmployees=$pdo->query('SELECT id FROM employes ORDER BY id')->fetchAll(PDO::FETCH_COLUMN);
    foreach ($allEmployees as $i=>$employeeId) {
        $insertPresence->execute([(int)$employeeId,$i===0?'journee':($i%2?'matin':'apres_midi'),$i===3?'retard':'present']);
    }
    $pdo->commit();
} catch (Throwable $error) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    fwrite(STDERR, 'Aucune insertion conservée (transaction annulée) : ' . $error->getMessage() . PHP_EOL);
    exit(1);
}

$counts = [
    'utilisateurs' => countRows($pdo,'utilisateurs'),
    'employes' => countRows($pdo,'employes'),
    'clients' => countRows($pdo,'clients'),
    'commandes' => countRows($pdo,'commandes'),
    'commande_lignes' => countRows($pdo,'commande_lignes'),
    'paiements' => countRows($pdo,'paiements'),
    'courses' => countRows($pdo,'courses'),
    'communications' => countRows($pdo,'communications'),
    'reclamations' => countRows($pdo,'reclamations'),
    'fournisseurs' => countRows($pdo,'fournisseurs'),
    'bons_achat' => countRows($pdo,'bons_achat'),
    'bons_achat_lignes' => countRows($pdo,'bons_achat_lignes'),
    'reglements_fournisseurs' => countRows($pdo,'reglements_fournisseurs'),
    'mouvements_stock' => countRows($pdo,'mouvements_stock'),
    'alertes_stock' => countRows($pdo,'alertes_stock'),
    'depenses' => countRows($pdo,'depenses'),
    'equipements' => countRows($pdo,'equipements'),
    'interventions' => countRows($pdo,'interventions'),
    'presences' => countRows($pdo,'presences'),
    'historique_statuts' => countRows($pdo,'historique_statuts'),
    'journal_audit' => countRows($pdo,'journal_audit'),
];
echo "DONNEES DE DEMONSTRATION AJOUTEES\n";
echo "Comptes actifs par rôle (compte administrateur initial inclus) :\n";
foreach ($pdo->query('SELECT role,COUNT(*) AS n FROM utilisateurs WHERE actif=1 GROUP BY role ORDER BY role') as $row) {
    echo '  ' . $row['role'] . ': ' . $row['n'] . PHP_EOL;
}
echo "Lignes présentes après insertion :\n";
foreach ($counts as $table=>$count) {
    echo '  ' . $table . ': ' . $count . PHP_EOL;
}
echo "NOUVEAUX IDENTIFIANTS DEMO — mots de passe uniques générés\n";
foreach ($credentials as $account) {
    echo $account['role'] . ' | ' . $account['email'] . ' | ' . $account['password'] . PHP_EOL;
}
echo "Compte administrateur préexistant conservé : " . $admin['nom'] . ' (mot de passe inchangé).' . PHP_EOL;
