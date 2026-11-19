<?php
require_once __DIR__.'/includes/bootstrap.php';
require_auth();
$page_title='Messages clients';
$pdo=db();

if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    $cid=(int)($_POST['client_id']??0);
    $msg=trim($_POST['message']??'');
    $channel=($_POST['channel']??'sms')==='email'?'email':'sms';
    $orderId=($_POST['order_id']??'')!==''?(int)$_POST['order_id']:null;
    $clientQuery=$pdo->prepare('SELECT id,nom,prenom,telephone,email FROM clients WHERE id=?');
    $clientQuery->execute([$cid]);
    $client=$clientQuery->fetch();
    if(!$client||$msg===''){flash('Choisissez un client et saisissez un message.','error');redirect('messages.php');}
    if($channel==='email'&&filter_var($client['email'],FILTER_VALIDATE_EMAIL)===false){flash('Ce client n’a pas d’adresse e-mail valide.','error');redirect('messages.php');}
    try{
        $pdo->beginTransaction();
        $insert=$pdo->prepare("INSERT INTO communications(client_id,commande_id,canal,contenu,statut,cree_par) VALUES(?,?,?,?,?,?)");
        $insert->execute([$cid,$orderId,$channel==='email'?'email':'sms',$msg,$channel==='email'?'prepare':'prepare',$_SESSION['user']['id']]);
        $messageId=(int)db_last_insert_id($pdo,'communications');
        if($channel==='email'){
            require_once __DIR__.'/includes/mailer.php';
            send_client_email($client['email'],trim($client['prenom'].' '.$client['nom']),'Message de '.APP_NAME,$msg);
            $pdo->prepare("UPDATE communications SET statut='envoye',date_envoi=NOW() WHERE id=?")->execute([$messageId]);
        }
        $pdo->commit();
        flash($channel==='email'?'E-mail envoyé au client.':'Message enregistré dans l’historique. Cliquez sur « Ouvrir les SMS » pour l’envoyer depuis votre téléphone.');
    }catch(Throwable $e){
        if($pdo->inTransaction())$pdo->rollBack();
        $known=$e instanceof RuntimeException?$e->getMessage():'Vérifiez la configuration SMTP et réessayez.';
        flash($known,'error');
    }
    redirect('messages.php');
}
$clients=$pdo->query('SELECT id,nom,prenom,telephone,email FROM clients ORDER BY nom')->fetchAll();
$msgs=$pdo->query("SELECT m.*,m.contenu AS message,m.cree_le AS created_at,c.nom,c.prenom,c.telephone,c.email,o.reference AS code FROM communications m JOIN clients c ON c.id=m.client_id LEFT JOIN commandes o ON o.id=m.commande_id ORDER BY m.id DESC LIMIT 50")->fetchAll();
require 'includes/header.php';
?>
<div class="panel"><h2>Envoyer un SMS simple ou un e-mail</h2><p class="muted">Les SMS sont préparés dans l’application du téléphone. Les e-mails sont envoyés depuis le compte Pressa configuré sur le serveur.</p><form method="post" class="form-grid" id="messageForm"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><div class="field"><label>Client</label><select name="client_id" id="clientSelect" required><?php foreach($clients as $c):$phone=preg_replace('/\D/','',$c['telephone']);if(strlen($phone)===9)$phone='237'.$phone;?><option value="<?=$c['id']?>" data-phone="<?=e('+'.$phone)?>" data-email="<?=e($c['email']??'')?>"><?=e($c['prenom'].' '.$c['nom'].' · '.$c['telephone'])?><?=!empty($c['email'])?' · '.e($c['email']):''?></option><?php endforeach;?></select></div><div class="field"><label>Canal</label><select name="channel" id="messageChannel"><option value="sms">SMS</option><option value="email">E-mail</option></select></div><div class="field full"><label>Message</label><textarea name="message" id="messageText" rows="4" required placeholder="Bonjour, votre commande est prête à être retirée. Merci."></textarea></div><div class="field full"><button class="btn" name="submit_message" value="1">Enregistrer / envoyer</button> <button type="button" class="btn green" id="openSmsButton" onclick="openSMS()">Ouvrir les SMS</button></div></form></div>
<div class="panel"><h2>Historique récent</h2><div class="table-wrap"><table><thead><tr><th>Date</th><th>Client</th><th>Canal</th><th>Message</th><th>Commande</th></tr></thead><tbody><?php foreach($msgs as $m):?><tr><td><?=date('d/m/Y H:i',strtotime($m['created_at']))?></td><td><?=e($m['prenom'].' '.$m['nom'])?></td><td><?=e(strtoupper($m['canal']))?></td><td><?=e($m['message'])?></td><td><?=e($m['code'])?></td></tr><?php endforeach;?></tbody></table></div></div>
<script>function openSMS(){const s=document.getElementById('clientSelect'),p=s.options[s.selectedIndex]?.dataset.phone,m=document.getElementById('messageText').value.trim();if(!p||!m){alert('Choisissez un client et saisissez un message.');return;}window.location.href='sms:'+p+'?body='+encodeURIComponent(m);}const messageForm=document.getElementById('messageForm');document.getElementById('messageChannel').addEventListener('change',e=>{document.getElementById('openSmsButton').hidden=e.target.value==='email';});messageForm.addEventListener('submit',e=>{if(document.getElementById('messageChannel').value==='email'&&!confirm('Envoyer cet e-mail au client ?'))e.preventDefault();});</script>
<?php require 'includes/footer.php';?>
