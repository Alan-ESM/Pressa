<?php
require_once __DIR__.'/bootstrap.php';
require_auth();
$appTitle=app_setting('nom_pressing',app_setting('nom_application',APP_NAME));
if(mb_strtolower(trim($appTitle),'UTF-8')==='pressing de la joie')$appTitle=APP_NAME;
$pageClass=role()==='admin'?'admin-shell':'';
$language=$_SESSION['language']??'fr';
?>
<!doctype html><html lang="<?=e($language)?>"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title><?=e($page_title??$appTitle)?> · <?=e($appTitle)?></title><script>try{document.documentElement.dataset.theme=localStorage.getItem('pressa-theme')||'light'}catch(e){}</script><link rel="stylesheet" href="assets/css/style.css"></head><body class="<?=$pageClass?>">
<div class="sidebar-backdrop" data-sidebar-backdrop></div>
<aside class="sidebar" id="appSidebar"><div class="brand"><img class="brand-logo" src="assets/img/Pressa%20Dragon%20Steam%20Emblem.png" alt="Pressa"><span class="brand-label"><?=e($appTitle)?></span></div><div class="userbox"><?=e($_SESSION['user']['name'])?><small><?=e(role_label(role()))?></small></div><nav>
<?php if(role()==='livreur'): ?>
<a href="livreur.php">▣ Mes livraisons</a>
<?php elseif(role()==='admin'): ?>
<a href="dashboard.php">▦ Tableau de bord</a><a href="clients.php">♙ Clients</a><a href="orders.php">▤ Commandes</a><a href="client_requests.php">⌖ Demandes clients</a><a href="production.php">◈ Production</a><a href="invoices.php">▧ Paiements</a><a href="messages.php">✉ Messages</a><a href="ratings.php">★ Évaluations</a><a href="users.php">⚙ Utilisateurs</a><a href="services.php">◆ Services & tarifs</a><a href="stock.php">▦ Stock</a><a href="suppliers.php">♧ Fournisseurs</a><a href="purchases.php">▤ Achats</a><a href="maintenance.php">⚒ Maintenance</a><a href="livreur.php">▣ Livraisons</a><a href="expenses.php">₣ Dépenses</a><a href="reports.php">▤ Rapports</a><a href="settings.php">⚙ Paramètres</a>
<?php elseif(in_array(role(),['receptionniste','accueil'],true)): ?>
<a href="dashboard.php">▦ Tableau de bord</a><a href="clients.php">♙ Clients</a><a href="orders.php">▤ Commandes & dépôts</a><a href="client_requests.php">⌖ Demandes clients</a><a href="production.php">◈ Production</a><a href="invoices.php">▧ Factures & paiements</a><a href="messages.php">✉ Messages clients</a><a href="expenses.php">₣ Dépenses</a><a href="livreur.php">▣ Livraisons</a>
<?php elseif(role()==='caissier'): ?>
<a href="dashboard.php">▦ Tableau de bord</a><a href="orders.php">▤ Commandes</a><a href="invoices.php">▧ Factures & paiements</a>
<?php elseif(role()==='production'): ?>
<a href="dashboard.php">▦ Tableau de bord</a><a href="production.php">◈ Production</a><a href="orders.php">▤ Commandes</a>
<?php endif; ?>
</nav><form class="sidebar-logout-form" action="logout.php" method="post"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><button class="logout" type="submit">↪ Déconnexion</button></form></aside>
<main class="main"><header class="topbar"><div class="topbar-heading"><button class="sidebar-toggle" type="button" aria-label="Ouvrir le menu" aria-expanded="false" data-sidebar-toggle>☰</button><div><span class="muted"><?=e(role_label(role()))?></span><h1><?=e($page_title??'Tableau de bord')?></h1></div></div><div class="top-right"><time class="date-time-pill" data-current-datetime datetime="<?=e(date(DATE_ATOM))?>"><?=e(date('d/m/Y H:i:s'))?></time><div class="ui-actions"><button class="utility-button" type="button" data-theme-toggle aria-label="Activer le thème sombre" title="Thème sombre">◐</button><label class="language-control" title="Langue"><span class="sr-only">Langue</span><select class="language-select" id="languageSelect" aria-label="Langue"><option value="fr" <?=$language==='fr'?'selected':''?>>FR</option><option value="en" <?=$language==='en'?'selected':''?>>EN</option><option value="es" <?=$language==='es'?'selected':''?>>ES</option><option value="pt" <?=$language==='pt'?'selected':''?>>PT</option><option value="de" <?=$language==='de'?'selected':''?>>DE</option><option value="it" <?=$language==='it'?'selected':''?>>IT</option><option value="ar" <?=$language==='ar'?'selected':''?>>AR</option><option value="zh" <?=$language==='zh'?'selected':''?>>ZH</option><option value="ha" <?=$language==='ha'?'selected':''?>>HA</option></select></label></div><span class="avatar"><?=e(strtoupper(substr($_SESSION['user']['name'],0,1)))?></span><form class="topbar-logout-form" action="logout.php" method="post"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><button class="logout topbar-logout" type="submit">↪ Déconnexion</button></form></div></header>
<?php if(!empty($_SESSION['flash'])): ?><div class="alert <?=e($_SESSION['flash']['type'])?>"><?=e($_SESSION['flash']['message'])?></div><?php unset($_SESSION['flash']);endif; ?>
