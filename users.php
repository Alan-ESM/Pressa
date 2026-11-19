<?php
require_once __DIR__.'/includes/bootstrap.php';
require_auth();
if(role()!=='admin'){http_response_code(403);exit('Accès réservé à l’administrateur.');}
$page_title='Utilisateurs';
if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    $pass=$_POST['password']??'';
    $newRole=$_POST['role']??'receptionniste';
    $name=trim($_POST['name']??'');
    if(strlen($pass)<8){flash('Le mot de passe doit contenir au moins 8 caractères.','error');redirect('users.php');}
    if(!in_array($newRole,['admin','receptionniste','production','livreur'],true)){$newRole='receptionniste';}
    try{
        $pdo=db();
        $pdo->beginTransaction();
        $pdo->prepare("INSERT INTO utilisateurs(nom,email,mot_de_passe,role) VALUES(?,?,?,?)")->execute([$name,trim($_POST['email']),password_hash($pass,PASSWORD_DEFAULT),$newRole]);
        $userId=(int)db_last_insert_id($pdo,'utilisateurs');
        $employeePost=['admin'=>'gerant','receptionniste'=>'receptionniste','production'=>'laveur','livreur'=>'livreur'][$newRole];
        $pdo->prepare("INSERT INTO employes(utilisateur_id,nom,poste,actif) VALUES(?,?,?,1)")->execute([$userId,$name,$employeePost]);
        $pdo->commit();
        flash('Utilisateur créé.');
    }catch(Throwable $e){
        if(isset($pdo)&&$pdo->inTransaction())$pdo->rollBack();
        flash('Adresse e-mail déjà utilisée ou données invalides.','error');
    }
    redirect('users.php');
}
$rows=db()->query("SELECT id, nom AS name, email, role, actif AS active, cree_le AS created_at FROM utilisateurs ORDER BY id")->fetchAll();
require 'includes/header.php';?>
<div class="panel"><h2>Créer un compte</h2><form method="post" class="form-grid"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><div class="field"><label>Nom complet</label><input name="name" required></div><div class="field"><label>E-mail</label><input type="email" name="email" required></div><div class="field"><label>Mot de passe (8 caractères minimum)</label><input type="password" name="password" minlength="8" required autocomplete="new-password"></div><div class="field"><label>Rôle</label><select name="role"><option value="receptionniste">Réceptionniste (Accueil + Caissier)</option><option value="production">Production</option><option value="livreur">Livreur</option><option value="admin">Administrateur</option></select></div><div><button class="btn">Créer l'utilisateur</button></div></form></div>
<div class="panel"><h2>Comptes existants</h2><div class="table-wrap"><table><thead><tr><th>Nom</th><th>E-mail</th><th>Rôle</th><th>Créé le</th></tr></thead><tbody><?php foreach($rows as $r):?><tr><td><?=e($r['name'])?></td><td><?=e($r['email'])?></td><td><?=e(role_label($r['role']))?></td><td><?=date('d/m/Y',strtotime($r['created_at']))?></td></tr><?php endforeach;?></tbody></table></div></div>
<?php require 'includes/footer.php';?>
