<?php
require_once __DIR__.'/includes/bootstrap.php';
require_role(['admin','receptionniste','accueil']);
$page_title='Demandes clients';
$pdo=db();
if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    $id=(int)($_POST['id']??0);
    $status=(string)($_POST['statut']??'');
    if(!in_array($status,['confirmee','refusee','terminee'],true)){flash('Statut invalide.','error');redirect('client_requests.php');}
    $stmt=$pdo->prepare("UPDATE demandes_clients SET statut=?,traite_par=? WHERE id=? AND statut IN ('en_attente','confirmee')");
    $stmt->execute([$status,(int)$_SESSION['user']['id'],$id]);audit_event('UPDATE','demandes_clients',$id);
    flash($stmt->rowCount()?'Demande mise à jour.':'Cette demande a déjà été traitée.',$stmt->rowCount()?'success':'error');
    redirect('client_requests.php');
}
$rows=$pdo->query('SELECT d.*,c.nom,c.prenom,c.telephone,c.email FROM demandes_clients d JOIN clients c ON c.id=d.client_id ORDER BY FIELD(d.statut,"en_attente","confirmee","terminee","refusee"),d.date_prevue,d.id LIMIT 200')->fetchAll();
require 'includes/header.php';
?>
<div class="admin-page-heading"><div><p class="eyebrow">ESPACE CLIENT</p><h2>Demandes de dépôt et ramassage</h2></div><span class="badge"><?=count(array_filter($rows,fn($row)=>$row['statut']==='en_attente'))?> en attente</span></div>
<div class="panel"><div class="panel-head"><input class="search" data-filter="#requests" placeholder="Rechercher un client..."></div><div class="table-wrap"><table id="requests"><thead><tr><th>Client</th><th>Contact</th><th>Type</th><th>Date</th><th>Adresse / précisions</th><th>État</th><th>Action</th></tr></thead><tbody><?php foreach($rows as $row):?><tr><td><?=e(trim(($row['prenom']??'').' '.$row['nom']))?></td><td><?=e($row['telephone'])?><br><small><?=e($row['email']??'')?></small></td><td><?=e($row['type']==='depot'?'Dépôt':'Ramassage')?> · <?=e(delivery_slot_label($row['creneau']))?></td><td><?=e($row['date_prevue'])?></td><td><?=e($row['adresse']??'')?><?php if($row['details']):?><br><small><?=e($row['details'])?></small><?php endif;?></td><td><span class="badge <?=e($row['statut'])?>"><?=e(['en_attente'=>'En attente','confirmee'=>'Confirmée','refusee'=>'Refusée','terminee'=>'Terminée'][$row['statut']]??$row['statut'])?></span></td><td><?php if(in_array($row['statut'],['en_attente','confirmee'],true)):?><form method="post" class="actions"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="id" value="<?=(int)$row['id']?>"><select name="statut"><option value="confirmee">Confirmer</option><option value="refusee">Refuser</option><option value="terminee">Terminer</option></select><button class="btn small" data-confirm="Mettre à jour cette demande ?">Valider</button></form><?php else:?>—<?php endif;?></td></tr><?php endforeach;?><?php if(!$rows):?><tr><td colspan="7" class="empty">Aucune demande pour le moment.</td></tr><?php endif;?></tbody></table></div></div>
<?php require 'includes/footer.php';?>
