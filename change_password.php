<?php
require_once __DIR__.'/includes/bootstrap.php';
require_auth();
$error='';
if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    $current=(string)($_POST['current_password']??'');
    $password=(string)($_POST['password']??'');
    $confirmation=(string)($_POST['confirmation']??'');
    $q=db()->prepare('SELECT mot_de_passe FROM utilisateurs WHERE id=? AND actif=1');
    $q->execute([(int)$_SESSION['user']['id']]);
    $hash=$q->fetchColumn();
    if(!$hash||!password_verify($current,(string)$hash))$error='Mot de passe actuel incorrect.';
    elseif(strlen($password)<10||$password!==$confirmation)$error='Le nouveau mot de passe doit contenir au moins 10 caractères et correspondre à sa confirmation.';
    else{db()->prepare('UPDATE utilisateurs SET mot_de_passe=?,doit_changer_mdp=0 WHERE id=? AND actif=1')->execute([password_hash($password,PASSWORD_DEFAULT),(int)$_SESSION['user']['id']]);audit_event('CHANGE_PASSWORD','utilisateurs',(int)$_SESSION['user']['id']);redirect(role()==='client'?'client.php':(role()==='livreur'?'livreur.php':(role()==='responsable'?'users.php':'dashboard.php')));}
}
$page_title='Changer le mot de passe';
require 'includes/header.php';
?><div class="panel"><h2>Définir votre mot de passe personnel</h2><p class="muted">Changez le mot de passe initial avant de continuer.</p><?php if($error):?><div class="alert error"><?=e($error)?></div><?php endif;?><form method="post" class="form-grid"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><div class="field full"><label for="currentPassword">Mot de passe initial</label><input id="currentPassword" type="password" name="current_password" autocomplete="current-password" required></div><div class="field"><label for="newPassword">Nouveau mot de passe</label><input id="newPassword" type="password" name="password" minlength="10" autocomplete="new-password" required></div><div class="field"><label for="confirmPassword">Confirmation</label><input id="confirmPassword" type="password" name="confirmation" minlength="10" autocomplete="new-password" required></div><div class="field full"><button class="btn">Enregistrer le nouveau mot de passe</button></div></form></div><?php require 'includes/footer.php';?>
