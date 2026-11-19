<?php
require_once __DIR__.'/includes/bootstrap.php';
require_role(['admin']);
$page_title='Utilisateurs';
$pdo=db();
if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    $name=trim((string)($_POST['name']??''));
    $email=trim((string)($_POST['email']??''));
    $password=(string)($_POST['password']??'');
    $newRole=(string)($_POST['role']??'');
    $clientId=(int)($_POST['client_id']??0);
    $roles=['admin','receptionniste','accueil','caissier','production','livreur','client'];
    if($name===''||filter_var($email,FILTER_VALIDATE_EMAIL)===false||strlen($password)<10||!in_array($newRole,$roles,true)||($newRole==='client'&&$clientId<1)){
        flash('Vérifiez le nom, l’e-mail, le mot de passe et le rôle.','error');
        redirect('users.php');
    }
    try{
        $pdo->beginTransaction();
        if($newRole==='client'){$link=$pdo->prepare('SELECT id FROM clients WHERE id=? AND utilisateur_id IS NULL AND supprime=0');$link->execute([$clientId]);if(!$link->fetchColumn())throw new RuntimeException('La fiche client est déjà associée ou introuvable.');}
        $pdo->prepare('INSERT INTO utilisateurs(nom,email,mot_de_passe,role) VALUES(?,?,?,?)')->execute([$name,$email,password_hash($password,PASSWORD_DEFAULT),$newRole]);
        $userId=db_last_insert_id($pdo,'utilisateurs');
        if($newRole==='client'){$pdo->prepare('UPDATE clients SET utilisateur_id=? WHERE id=? AND utilisateur_id IS NULL')->execute([$userId,$clientId]);if($pdo->rowCount()!==1)throw new RuntimeException('Association client indisponible.');}
        else{$employeePost=['admin'=>'gerant','receptionniste'=>'accueil','accueil'=>'accueil','caissier'=>'caissier','production'=>'laveur','livreur'=>'livreur'][$newRole]??'autre';$pdo->prepare('INSERT INTO employes(utilisateur_id,nom,poste,actif) VALUES(?,?,?,1)')->execute([$userId,$name,$employeePost]);}
        $pdo->commit();
        audit_event('CREATE','utilisateurs',$userId);
        flash('Compte créé.');
    }catch(Throwable $e){if($pdo->inTransaction())$pdo->rollBack();flash($e instanceof RuntimeException?$e->getMessage():'Cette adresse e-mail est déjà utilisée.','error');}
    redirect('users.php');
}
$rows=$pdo->query('SELECT u.id,u.nom AS name,u.email,u.role,u.actif AS active,u.cree_le AS created_at,c.nom AS client_nom,c.prenom AS client_prenom FROM utilisateurs u LEFT JOIN clients c ON c.utilisateur_id=u.id ORDER BY u.id LIMIT 500')->fetchAll();
$clients=$pdo->query('SELECT id,nom,prenom,email FROM clients WHERE utilisateur_id IS NULL AND supprime=0 ORDER BY nom,prenom LIMIT 500')->fetchAll();
require 'includes/header.php';
?>
<div class="admin-page-heading"><div><p class="eyebrow">ACCÈS & ÉQUIPE</p><h2>Comptes Pressa</h2></div><span class="badge"><?=count($rows)?> comptes</span></div>
<div class="panel"><h2>Créer un compte sécurisé</h2><form method="post" class="form-grid"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><div class="field"><label for="name">Nom complet</label><input id="name" name="name" maxlength="120" required></div><div class="field"><label for="userEmail">E-mail</label><input id="userEmail" type="email" name="email" maxlength="160" required></div><div class="field"><label for="userPassword">Mot de passe temporaire</label><input id="userPassword" type="password" name="password" minlength="10" required autocomplete="new-password"></div><div class="field"><label for="userRole">Rôle</label><select id="userRole" name="role" required><option value="receptionniste">Réceptionniste</option><option value="accueil">Accueil</option><option value="caissier">Caissier</option><option value="production">Production</option><option value="livreur">Livreur</option><option value="client">Client</option><option value="admin">Administrateur</option></select></div><div class="field full" id="clientAccountField" hidden><label for="clientId">Fiche client à associer</label><select id="clientId" name="client_id"><option value="">Choisir une fiche client</option><?php foreach($clients as $client):?><option value="<?=(int)$client['id']?>"><?=e(trim(($client['prenom']??'').' '.$client['nom']).' · '.($client['email']??'Sans e-mail'))?></option><?php endforeach;?></select></div><div class="field full"><button class="btn">Créer le compte</button></div></form></div>
<div class="panel"><div class="panel-head"><h2>Comptes existants</h2><input class="search" data-filter="#users" placeholder="Rechercher un compte..."></div><div class="table-wrap"><table id="users"><thead><tr><th>Nom</th><th>E-mail</th><th>Rôle</th><th>Fiche client</th><th>État</th><th>Créé le</th></tr></thead><tbody><?php foreach($rows as $row):?><tr><td><?=e($row['name'])?></td><td><?=e($row['email'])?></td><td><?=e(role_label($row['role']))?></td><td><?=e(trim(($row['client_prenom']??'').' '.($row['client_nom']??''))?:'—')?></td><td><span class="badge <?=$row['active']?'pret':'annule'?>"><?=$row['active']?'Actif':'Inactif'?></span></td><td><?=date('d/m/Y',strtotime($row['created_at']))?></td></tr><?php endforeach;?><?php if(!$rows):?><tr><td colspan="6" class="empty">Aucun compte enregistré.</td></tr><?php endif;?></tbody></table></div></div>
<script>const userRole=document.getElementById('userRole'),clientField=document.getElementById('clientAccountField'),clientId=document.getElementById('clientId');function updateClientField(){const active=userRole.value==='client';clientField.hidden=!active;clientId.required=active;}userRole.addEventListener('change',updateClientField);updateClientField();</script>
<?php require 'includes/footer.php';?>
