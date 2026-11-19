<?php
require_once __DIR__.'/includes/bootstrap.php';
$language=$_SESSION['language']??'fr';
if(auth())redirect(role()==='client'?'client.php':(role()==='livreur'?'livreur.php':'dashboard.php'));
$error='';
if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    $email=trim((string)($_POST['email']??''));
    $password=(string)($_POST['password']??'');
    $stmt=db()->prepare('SELECT id,nom AS name,email,mot_de_passe AS password,role,tentatives_echec,verrouille_jusqu_a FROM utilisateurs WHERE email=? AND actif=1 LIMIT 1');
    $stmt->execute([$email]);
    $user=$stmt->fetch();
    $locked=$user&&$user['verrouille_jusqu_a']&&strtotime($user['verrouille_jusqu_a'])>time();
    if($user&&!$locked&&password_verify($password,$user['password'])){
        if(password_needs_rehash($user['password'],PASSWORD_DEFAULT))db()->prepare('UPDATE utilisateurs SET mot_de_passe=? WHERE id=?')->execute([password_hash($password,PASSWORD_DEFAULT),$user['id']]);
        db()->prepare('UPDATE utilisateurs SET tentatives_echec=0,verrouille_jusqu_a=NULL,derniere_connexion=NOW() WHERE id=?')->execute([$user['id']]);
        if($user['role']==='client'){$client=db()->prepare('SELECT id FROM clients WHERE utilisateur_id=? AND supprime=0');$client->execute([$user['id']]);if(!$client->fetchColumn()){$error='Ce compte client n’est pas associé à une fiche client.';}}
        if($error===''){
            session_regenerate_id(true);
            $_SESSION['user']=['id'=>(int)$user['id'],'name'=>$user['name'],'email'=>$user['email'],'role'=>$user['role']];
            unset($_SESSION['csrf']);
            redirect($user['role']==='client'?'client.php':($user['role']==='livreur'?'livreur.php':'dashboard.php'));
        }
    }else{
        if($user&&!$locked)db()->prepare('UPDATE utilisateurs SET tentatives_echec=tentatives_echec+1,verrouille_jusqu_a=CASE WHEN tentatives_echec>=4 THEN DATE_ADD(NOW(),INTERVAL 15 MINUTE) ELSE verrouille_jusqu_a END WHERE id=?')->execute([$user['id']]);
        $error=$locked?'Compte temporairement verrouillé. Réessayez dans 15 minutes.':'Identifiants incorrects.';
    }
}
?><!doctype html><html lang="<?=e($language)?>"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>Connexion · Pressa</title><script>try{document.documentElement.dataset.theme=localStorage.getItem('pressa-theme')||'light'}catch(e){}</script><link rel="stylesheet" href="assets/css/style.css"></head><body class="login-page"><div id="authLoadingRoot" aria-hidden="false"><div class="auth-loading" role="status" aria-live="polite"><img class="auth-loading-logo" src="assets/img/Pressa%20Dragon%20Steam%20Emblem.png" alt="Pressa"><span class="auth-spinner" aria-hidden="true"></span><span>Préparation de votre espace…</span></div></div><form class="login-card" method="post" autocomplete="off"><div class="login-tools"><button class="utility-button" type="button" data-theme-toggle aria-label="Activer le thème sombre" title="Thème sombre">◐</button><label class="language-control" title="Langue"><span class="sr-only">Langue</span><select class="language-select" id="languageSelect" aria-label="Langue"><option value="fr" <?=$language==='fr'?'selected':''?>>FR</option><option value="en" <?=$language==='en'?'selected':''?>>EN</option><option value="es" <?=$language==='es'?'selected':''?>>ES</option><option value="pt" <?=$language==='pt'?'selected':''?>>PT</option><option value="de" <?=$language==='de'?'selected':''?>>DE</option><option value="it" <?=$language==='it'?'selected':''?>>IT</option><option value="ar" <?=$language==='ar'?'selected':''?>>AR</option><option value="zh" <?=$language==='zh'?'selected':''?>>ZH</option><option value="ha" <?=$language==='ha'?'selected':''?>>HA</option></select></label></div><div class="login-brand"><img src="assets/img/Pressa%20Dragon%20Steam%20Emblem.png" alt="Logo Pressa"></div><h1>Bon retour !</h1><p class="muted">Connectez-vous à votre espace de gestion.</p><?php if($error):?><div class="alert error"><?=e($error)?></div><?php endif;?><input type="hidden" name="csrf" value="<?=e(csrf())?>"><div class="field"><label for="email">Adresse e-mail</label><input id="email" type="email" name="email" required autocomplete="off" readonly data-autofill-guard></div><div class="field"><label for="password">Mot de passe</label><input id="password" type="password" name="password" required autocomplete="new-password" readonly data-autofill-guard></div><button class="btn">Se connecter</button><p class="muted login-caption">Pressa · Gestion simple et efficace</p></form><script src="assets/vendor/react.production.min.js" defer></script><script src="assets/vendor/react-dom.production.min.js" defer></script><script src="assets/js/auth-loading.js" defer></script><script src="assets/js/app.js" defer></script><script src="assets/js/locales.js" defer></script><script src="assets/js/i18n.js" defer></script></body></html>
