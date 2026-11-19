<?php
require_once __DIR__.'/includes/bootstrap.php';
require_role(['admin']);
$page_title='Rapports';
$pdo=db();
$monthly=$pdo->query("SELECT DATE_FORMAT(date_paiement,'%Y-%m') mois,COUNT(*) paiements,SUM(montant) encaissements FROM paiements WHERE date_paiement>=DATE_SUB(CURRENT_DATE,INTERVAL 11 MONTH) GROUP BY DATE_FORMAT(date_paiement,'%Y-%m') ORDER BY mois DESC")->fetchAll();
$orders=$pdo->query("SELECT statut,COUNT(*) nombre,COALESCE(SUM(total),0) total FROM commandes GROUP BY statut ORDER BY FIELD(statut,'recu','lavage','repassage','emballage','pret','retire','annule')")->fetchAll();
$topClients=$pdo->query('SELECT c.id,c.nom,c.prenom,COUNT(o.id) commandes,COALESCE(SUM(o.total),0) total FROM clients c JOIN commandes o ON o.client_id=c.id GROUP BY c.id ORDER BY total DESC LIMIT 10')->fetchAll();
$expenses=(float)$pdo->query("SELECT COALESCE(SUM(montant),0) FROM depenses WHERE YEAR(date_depense)=YEAR(CURRENT_DATE) AND MONTH(date_depense)=MONTH(CURRENT_DATE)")->fetchColumn();
$revenue=(float)$pdo->query("SELECT COALESCE(SUM(montant),0) FROM paiements WHERE YEAR(date_paiement)=YEAR(CURRENT_DATE) AND MONTH(date_paiement)=MONTH(CURRENT_DATE)")->fetchColumn();
require 'includes/header.php';
?>
<div class="admin-page-heading"><div><p class="eyebrow">PILOTAGE</p><h2>Rapports d’activité</h2></div></div>
<div class="cards"><div class="stat"><span class="ico">₣</span><div class="label">Encaissements du mois</div><strong><?=money($revenue)?></strong></div><div class="stat"><span class="ico">↘</span><div class="label">Dépenses du mois</div><strong><?=money($expenses)?></strong></div><div class="stat"><span class="ico">↗</span><div class="label">Solde encaissé estimé</div><strong><?=money($revenue-$expenses)?></strong></div></div>
<div class="panel"><h2>Encaissements mensuels · 12 derniers mois</h2><div class="table-wrap"><table><thead><tr><th>Mois</th><th>Nombre de paiements</th><th>Montant</th></tr></thead><tbody><?php foreach($monthly as $row):?><tr><td><?=e($row['mois'])?></td><td><?=(int)$row['paiements']?></td><td><?=money($row['encaissements'])?></td></tr><?php endforeach;?><?php if(!$monthly):?><tr><td colspan="3" class="empty">Aucun paiement enregistré.</td></tr><?php endif;?></tbody></table></div></div>
<div class="panel"><h2>Commandes par statut</h2><div class="table-wrap"><table><thead><tr><th>État</th><th>Commandes</th><th>Total facturé</th></tr></thead><tbody><?php foreach($orders as $row):?><tr><td><?=e(status_label($row['statut']))?></td><td><?=(int)$row['nombre']?></td><td><?=money($row['total'])?></td></tr><?php endforeach;?><?php if(!$orders):?><tr><td colspan="3" class="empty">Aucune commande enregistrée.</td></tr><?php endif;?></tbody></table></div></div>
<div class="panel"><h2>Meilleurs clients par montant de commandes</h2><div class="table-wrap"><table><thead><tr><th>Client</th><th>Commandes</th><th>Total</th></tr></thead><tbody><?php foreach($topClients as $row):?><tr><td><?=e(trim(($row['prenom']??'').' '.$row['nom']))?></td><td><?=(int)$row['commandes']?></td><td><?=money($row['total'])?></td></tr><?php endforeach;?><?php if(!$topClients):?><tr><td colspan="3" class="empty">Aucun client avec commande.</td></tr><?php endif;?></tbody></table></div></div>
<?php require 'includes/footer.php';?>
