<?php
require_once __DIR__.'/includes/bootstrap.php';
if(auth()){require_auth();redirect(role()==='client'?'client.php':(role()==='livreur'?'livreur.php':(role()==='responsable'?'users.php':'dashboard.php')));}
$error='';
if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    $ip=(string)($_SERVER['REMOTE_ADDR']??'unknown');
    $key=hash('sha256',$ip);
    $limit=db()->prepare('INSERT INTO limites_inscription(cle_ip,debut_fenetre,tentatives) VALUES(?,NOW(),1) ON DUPLICATE KEY UPDATE tentatives=IF(debut_fenetre<NOW()-INTERVAL 1 HOUR,1,tentatives+1),debut_fenetre=IF(debut_fenetre<NOW()-INTERVAL 1 HOUR,NOW(),debut_fenetre)');
    $limit->execute([$key]);
    $attempts=db()->prepare('SELECT tentatives FROM limites_inscription WHERE cle_ip=?');
    $attempts->execute([$key]);
    if((int)$attempts->fetchColumn()>6){$error='Trop de tentatives. Réessayez plus tard.';}
    $last=trim((string)($_POST['nom']??''));
    $first=trim((string)($_POST['prenom']??''));
    $email=mb_strtolower(trim((string)($_POST['email']??'')),'UTF-8');
    $phone=trim((string)($_POST['telephone']??''));
    $password=(string)($_POST['password']??'');
    $confirmation=(string)($_POST['confirmation']??'');
    if($error===''&&($last===''||$first===''||mb_strlen($last)>120||mb_strlen($first)>120||filter_var($email,FILTER_VALIDATE_EMAIL)===false||mb_strlen($email)>160||mb_strlen($phone)<6||mb_strlen($phone)>30||strlen($password)<10||$password!==$confirmation))$error='Vérifiez les champs et la confirmation du mot de passe.';
    if($error===''){
        try{
            $pdo=db();
            $exists=$pdo->prepare('SELECT id FROM utilisateurs WHERE LOWER(email)=LOWER(?) LIMIT 1');
            $exists->execute([$email]);
            if($exists->fetchColumn())throw new RuntimeException('Cette adresse e-mail est déjà utilisée.');
            $pdo->beginTransaction();
            $pdo->prepare('INSERT INTO utilisateurs(nom,email,mot_de_passe,role,actif,doit_changer_mdp) VALUES(?,?,?,\'client\',1,0)')->execute([trim($first.' '.$last),$email,password_hash($password,PASSWORD_DEFAULT)]);
            $userId=db_last_insert_id($pdo,'utilisateurs');
            $pdo->prepare('INSERT INTO clients(nom,prenom,telephone,email,utilisateur_id,cree_par) VALUES(?,?,?,?,?,NULL)')->execute([$last,$first,$phone,$email,$userId]);
            $pdo->commit();
            flash('Compte client créé. Vous pouvez maintenant vous connecter.');
            redirect('login.php');
        }catch(Throwable $e){if(isset($pdo)&&$pdo->inTransaction())$pdo->rollBack();$error=$e instanceof RuntimeException?$e->getMessage():'Inscription impossible. Vérifiez les informations ou réessayez.';}
    }
}
$language=$_SESSION['language']??'fr';
?><!doctype html><html lang="<?=e($language)?>"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>Créer un compte · Pressa</title><script>try{document.documentElement.dataset.theme=localStorage.getItem('pressa-theme')||'light'}catch(e){}</script><link rel="stylesheet" href="assets/css/style.css"></head><body class="login-page"><form class="login-card" method="post" autocomplete="off"><div class="login-brand"><img src="assets/img/Pressa%20Dragon%20Steam%20Emblem.png" alt="Pressa"></div><h1>Créer un compte client</h1><p class="muted">Inscrivez-vous pour accéder à votre espace client.</p><?php if($error):?><div class="alert error"><?=e($error)?></div><?php endif;?><input type="hidden" name="csrf" value="<?=e(csrf())?>"><div class="field"><label for="firstName">Prénom</label><input id="firstName" name="prenom" maxlength="120" required autocomplete="given-name"></div><div class="field"><label for="lastName">Nom</label><input id="lastName" name="nom" maxlength="120" required autocomplete="family-name"></div><div class="field"><label for="registerEmail">Adresse e-mail</label><input id="registerEmail" name="email" type="email" maxlength="160" required autocomplete="email"></div><div class="field"><label for="phone">Téléphone</label><input id="phone" name="telephone" type="tel" maxlength="30" required autocomplete="tel"></div><div class="field"><label for="newPassword">Mot de passe</label><input id="newPassword" name="password" type="password" minlength="10" required autocomplete="new-password"></div><div class="field"><label for="confirmPassword">Confirmation du mot de passe</label><input id="confirmPassword" name="confirmation" type="password" minlength="10" required autocomplete="new-password"></div><button class="btn">Créer mon compte</button><p class="muted login-caption"><a href="login.php">Retour à la connexion</a></p></form><script src="assets/js/app.js" defer></script><script src="assets/js/locales.js" defer></script><script src="assets/js/i18n.js" defer></script></body></html>
