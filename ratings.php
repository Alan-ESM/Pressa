<?php
require_once __DIR__.'/includes/bootstrap.php';
require_role(['admin']);
$page_title='Évaluations';
$pdo=db();
if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    $id=(int)($_POST['id']??0);
    $status=(string)($_POST['statut']??'');
    if(!in_array($status,['nouveau','lu','traite'],true)){flash('Statut invalide.','error');redirect('ratings.php');}
    $pdo->prepare('UPDATE avis_clients SET statut=? WHERE id=?')->execute([$status,$id]);audit_event('UPDATE','avis_clients',$id);
    flash('Évaluation mise à jour.');
    redirect('ratings.php');
}
$summary=$pdo->query('SELECT COUNT(*) total,COALESCE(AVG(note),0) moyenne FROM avis_clients')->fetch();
$rows=$pdo->query('SELECT a.*,c.nom,c.prenom,o.reference FROM avis_clients a JOIN clients c ON c.id=a.client_id JOIN commandes o ON o.id=a.commande_id ORDER BY a.id DESC LIMIT 200')->fetchAll();
require 'includes/header.php';
?>
<div class="admin-page-heading"><div><p class="eyebrow">RETOURS CLIENTS</p><h2>Évaluations du service</h2></div><span class="badge"><?=number_format((float)$summary['moyenne'],1,',',' ')?> / 5 · <?=(int)$summary['total']?> avis</span></div>
<div class="panel"><div class="panel-head"><h2>Avis reçus</h2><input class="search" data-filter="#ratings" placeholder="Rechercher un client ou une commande..."></div><div class="table-wrap"><table id="ratings"><thead><tr><th>Date</th><th>Client</th><th>Commande</th><th>Note</th><th>Commentaire</th><th>État</th><th>Action</th></tr></thead><tbody><?php foreach($rows as $row):?><tr><td><?=date('d/m/Y',strtotime($row['cree_le']))?></td><td><?=e(trim(($row['prenom']??'').' '.$row['nom']))?></td><td><?=e($row['reference'])?></td><td><span class="rating-stars"><?=str_repeat('★',(int)$row['note'])?><?=str_repeat('☆',5-(int)$row['note'])?></span></td><td><?=e($row['commentaire']??'—')?></td><td><?=e(['nouveau'=>'Nouveau','lu'=>'Lu','traite'=>'Traité'][$row['statut']]??$row['statut'])?></td><td><form method="post" class="actions"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="id" value="<?=(int)$row['id']?>"><select name="statut"><option value="nouveau" <?=$row['statut']==='nouveau'?'selected':''?>>Nouveau</option><option value="lu" <?=$row['statut']==='lu'?'selected':''?>>Lu</option><option value="traite" <?=$row['statut']==='traite'?'selected':''?>>Traité</option></select><button class="btn small">Enregistrer</button></form></td></tr><?php endforeach;?><?php if(!$rows):?><tr><td colspan="7" class="empty">Aucune évaluation reçue.</td></tr><?php endif;?></tbody></table></div></div>
<?php require 'includes/footer.php';?>
