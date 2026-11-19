<?php
require_once __DIR__.'/includes/bootstrap.php';
require_role(['admin','receptionniste','accueil','caissier','production']);
$pdo=db();
$id=(int)($_GET['id']??0);
$query=$pdo->prepare('SELECT o.*,o.reference AS code,o.date_promise AS date_prevue,c.nom,c.prenom,c.telephone FROM commandes o JOIN clients c ON c.id=o.client_id WHERE o.id=?');
$query->execute([$id]);
$order=$query->fetch();
if(!$order){http_response_code(404);exit('Commande introuvable.');}
$page_title='Détail '.$order['code'];
$query=$pdo->prepare('SELECT l.*,l.sous_total AS subtotal,s.nom AS service FROM commande_lignes l JOIN tarifs t ON t.id=l.tarif_id JOIN services s ON s.id=t.service_id WHERE l.commande_id=?');
$query->execute([$id]);$items=$query->fetchAll();
$query=$pdo->prepare('SELECT COALESCE(SUM(montant),0) FROM paiements WHERE commande_id=?');
$query->execute([$id]);$paid=(float)$query->fetchColumn();
$balance=max(0,(float)$order['total']-$paid);
$payModes=['especes'=>'Espèces','mtn_momo'=>'MTN Mobile Money','orange_money'=>'Orange Money','virement'=>'Virement','carte'=>'Carte'];
if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    if(!can_handle_payments()){http_response_code(403);exit('Accès non autorisé.');}
    if(isset($_POST['pay'])){
        $amount=filter_var($_POST['montant']??null,FILTER_VALIDATE_FLOAT);
        $mode=(string)($_POST['mode']??'');
        $reference=trim((string)($_POST['reference']??''));
        if($amount===false||$amount<=0||$amount>$balance||!array_key_exists($mode,$payModes)||mb_strlen($reference)>120){flash('Vérifiez le montant et le mode de paiement.','error');redirect('order_view.php?id='.$id);}
        try{$pdo->prepare('INSERT INTO paiements(commande_id,montant,mode,reference) VALUES(?,?,?,?)')->execute([$id,$amount,$mode,$reference?:null]);audit_event('PAYMENT','paiements',(int)$pdo->lastInsertId());flash('Paiement enregistré.');}catch(Throwable $e){flash('Paiement refusé : vérifiez le montant et réessayez.','error');}
    }elseif(isset($_POST['retire'])){
        if($order['statut']!=='pret'||$balance>0){flash('La commande doit être prête et entièrement payée avant le retrait.','error');redirect('order_view.php?id='.$id);}
        try{$pdo->prepare("UPDATE commandes SET statut='retire' WHERE id=? AND statut='pret'")->execute([$id]);audit_event('PICKUP','commandes',$id);flash('Retrait confirmé.');}catch(Throwable $e){flash('Le retrait n’a pas pu être confirmé.','error');}
    }
    redirect('order_view.php?id='.$id);
}
require 'includes/header.php';
?>
<?php if(can_handle_payments()):?><div class="cards"><div class="stat"><div class="label">Montant total</div><strong><?=money($order['total'])?></strong></div><div class="stat"><div class="label">Déjà payé</div><strong><?=money($paid)?></strong></div><div class="stat"><div class="label">Reste à payer</div><strong><?=money($balance)?></strong></div><div class="stat"><div class="label">Statut</div><strong style="font-size:20px"><?=e(status_label($order['statut']))?></strong></div></div><?php else:?><div class="admin-page-heading"><div><p class="eyebrow">SUIVI DE PRODUCTION</p><h2><?=e($order['code'])?></h2></div><span class="badge <?=e($order['statut'])?>"><?=e(status_label($order['statut']))?></span></div><?php endif;?>
<div class="panel"><div class="panel-head"><h2><?=e($order['code'])?> · <?=e(trim(($order['prenom']??'').' '.$order['nom']))?></h2><?php if(role()!=='production'):?><a class="btn light" href="invoice_print.php?id=<?=$id?>" target="_blank">Imprimer le reçu</a><?php endif;?></div><p><?php if(can_manage()):?>Téléphone : <b><?=e($order['telephone'])?></b> · <?php endif;?>Dépôt <?=e($order['type_depot'])?> · Retrait prévu : <?=e($order['date_prevue'])?></p><div class="table-wrap"><table><thead><tr><th>Prestation / vêtement</th><th>Quantité</th><?php if(can_handle_payments()):?><th>Prix unitaire</th><th>Sous-total</th><?php endif;?></tr></thead><tbody><?php foreach($items as $item):?><tr><td><?=e($item['service'])?> <small>(<?=e($item['description'])?>)</small></td><td><?=(int)$item['quantite']?></td><?php if(can_handle_payments()):?><td><?=money($item['prix_unitaire'])?></td><td><?=money($item['subtotal'])?></td><?php endif;?></tr><?php endforeach;?></tbody></table></div></div>
<?php if(can_handle_payments()&&$order['statut']==='pret'):?><div class="panel"><h2>Retrait client</h2><?php if($balance<=0):?><form method="post"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><button class="btn green" name="retire" value="1" data-confirm="Confirmer la remise des vêtements au client ?">Confirmer le retrait</button></form><?php else:?><p class="notice">Le retrait sera disponible après règlement du solde de <?=money($balance)?>.</p><?php endif;?></div><?php endif;?>
<?php if(can_handle_payments()&&$balance>0):?><div class="panel"><h2>Enregistrer un paiement</h2><form method="post" class="form-grid"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="pay" value="1"><div class="field"><label for="paymentAmount">Montant (FCFA)</label><input id="paymentAmount" type="number" step="1" min="1" max="<?=$balance?>" name="montant" required></div><div class="field"><label for="paymentMode">Mode de paiement</label><select id="paymentMode" name="mode"><?php foreach($payModes as $key=>$label):?><option value="<?=e($key)?>"><?=e($label)?></option><?php endforeach;?></select></div><div class="field full"><label for="paymentReference">Référence facultative</label><input id="paymentReference" name="reference" maxlength="120"></div><div><button class="btn green">Valider le paiement</button></div></form></div><?php endif;?>
<?php if(can_manage()):?><div class="panel"><h2>Informer le client par SMS</h2><p>Un message est préparé dans l’application SMS du téléphone.</p><?php $message=($order['statut']==='pret'?'Bonjour '.$order['prenom'].', votre linge est prêt à être retiré. ':'Bonjour '.$order['prenom'].', votre commande est actuellement : '.status_label($order['statut']).'. ').'Référence : '.$order['code'].'. Merci pour votre confiance !';$phone=preg_replace('/\D/','',$order['telephone']);if(strlen($phone)===9)$phone='237'.$phone;?><a class="btn green" href="sms:+<?=e($phone)?>?body=<?=rawurlencode($message)?>">Ouvrir les SMS et envoyer</a></div><?php endif;?>
<?php require 'includes/footer.php';?>
