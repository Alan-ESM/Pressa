<?php
require_once __DIR__.'/includes/bootstrap.php';
require_role(['admin']);
$page_title='Paramètres';
$pdo=db();
if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    $name=trim((string)($_POST['nom_pressing']??''));
    $email=trim((string)($_POST['email']??''));
    $phone=trim((string)($_POST['telephone']??''));
    $address=trim((string)($_POST['adresse']??''));
    $surcharge=filter_var($_POST['surcharge_express_pct']??null,FILTER_VALIDATE_FLOAT);
    if($name===''||mb_strlen($name)>120||mb_strlen($phone)>30||mb_strlen($address)>255||($email!==''&&filter_var($email,FILTER_VALIDATE_EMAIL)===false)||$surcharge===false||$surcharge<0||$surcharge>100){flash('Vérifiez les informations et le taux express (0 à 100 %).','error');redirect('settings.php');}
    $save=$pdo->prepare('INSERT INTO parametres(cle,valeur,description) VALUES(?,?,?) ON DUPLICATE KEY UPDATE valeur=VALUES(valeur)');
    foreach(['nom_pressing'=>[$name,'Nom affiché du pressing'],'email'=>[$email,'Adresse de contact'],'telephone'=>[$phone,'Téléphone du pressing'],'adresse'=>[$address,'Adresse du pressing'],'surcharge_express_pct'=>[(string)$surcharge,'Majoration express en pourcentage']] as $key=>$setting)$save->execute([$key,$setting[0],$setting[1]]);
    audit_event('UPDATE','parametres');
    flash('Paramètres enregistrés.');
    redirect('settings.php');
}
$settings=[];
foreach($pdo->query('SELECT cle,valeur FROM parametres')->fetchAll() as $setting)$settings[$setting['cle']]=$setting['valeur'];
require 'includes/header.php';
?>
<div class="admin-page-heading"><div><p class="eyebrow">CONFIGURATION LOCALE</p><h2>Paramètres de Pressa</h2></div></div>
<div class="panel"><h2>Identité et tarifs</h2><form method="post" class="form-grid"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><div class="field"><label for="shopName">Nom du pressing</label><input id="shopName" name="nom_pressing" maxlength="120" value="<?=e($settings['nom_pressing']??'')?>" required></div><div class="field"><label for="contactEmail">E-mail de contact</label><input id="contactEmail" type="email" name="email" maxlength="160" value="<?=e($settings['email']??'')?>"></div><div class="field"><label for="phone">Téléphone</label><input id="phone" name="telephone" maxlength="30" value="<?=e($settings['telephone']??'')?>"></div><div class="field"><label for="expressRate">Majoration express (%)</label><input id="expressRate" type="number" name="surcharge_express_pct" min="0" max="100" step="0.1" value="<?=e($settings['surcharge_express_pct']??'30')?>" required></div><div class="field full"><label for="shopAddress">Adresse</label><input id="shopAddress" name="adresse" maxlength="255" value="<?=e($settings['adresse']??'')?>"></div><div class="field full"><button class="btn">Enregistrer les paramètres</button></div></form></div>
<div class="panel"><h2>Sessions de caisse ouvertes</h2><?php $sessions=$pdo->query('SELECT id,utilisateur_id,date_ouverture,total_theorique FROM sessions_caisse WHERE date_fermeture IS NULL ORDER BY id DESC LIMIT 20')->fetchAll();?><div class="table-wrap"><table><thead><tr><th>Session</th><th>Utilisateur</th><th>Ouverture</th><th>Total théorique</th></tr></thead><tbody><?php foreach($sessions as $session):?><tr><td>#<?=(int)$session['id']?></td><td><?=(int)$session['utilisateur_id']?></td><td><?=e($session['date_ouverture'])?></td><td><?=money($session['total_theorique'])?></td></tr><?php endforeach;?><?php if(!$sessions):?><tr><td colspan="4" class="empty">Aucune session de caisse ouverte.</td></tr><?php endif;?></tbody></table></div></div>
<?php require 'includes/footer.php';?>
