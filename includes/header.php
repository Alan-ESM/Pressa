<?php require_once __DIR__.'/bootstrap.php'; require_auth(); ?>
<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title><?= e($page_title??APP_NAME) ?> · <?= e(APP_NAME) ?></title><script>try{document.documentElement.dataset.theme=localStorage.getItem('pressa-theme')||'light'}catch(e){}</script><link rel="stylesheet" href="assets/css/style.css"></head><body>
<div class="sidebar-backdrop" data-sidebar-backdrop></div>
<aside class="sidebar" id="appSidebar"><div class="brand"><img class="brand-logo" src="assets/img/Pressa%20Dragon%20Steam%20Emblem.png" alt="Pressa"><span class="brand-label">Pressa</span></div><div class="userbox"><?= e($_SESSION['user']['name']) ?><small><?= e(role_label(role())) ?></small></div><nav>
<?php if(role()==='livreur'): ?><a href="livreur.php">▣ Mes livraisons</a><?php else: ?>
<a href="dashboard.php">▦ Tableau de bord</a>
<a href="clients.php">♙ Clients</a>
<a href="orders.php">▤ Commandes & dépôts</a>
<a href="production.php">◈ Production</a>
<a href="invoices.php">▧ Factures & paiements</a>
<a href="messages.php">✉ Messages clients</a>
<?php if(role()==='admin'): ?><a href="users.php">⚙ Utilisateurs</a><a href="services.php">◆ Services & tarifs</a><a href="stock.php">▦ Stock</a><a href="suppliers.php">♧ Fournisseurs</a><a href="purchases.php">▤ Achats</a><a href="maintenance.php">⚒ Maintenance</a><a href="livreur.php">▣ Livraisons</a><?php endif; ?><?php if(in_array(role(),['admin','receptionniste'],true)): ?><a href="expenses.php">₣ Dépenses</a><?php endif; ?><?php endif; ?>
</nav><a class="logout" href="logout.php">↪ Déconnexion</a></aside>
<main class="main"><header class="topbar"><div class="topbar-heading"><button class="sidebar-toggle" type="button" aria-label="Ouvrir le menu" aria-expanded="false" data-sidebar-toggle>☰</button><div><span class="muted">ESPACE DE GESTION</span><h1><?= e($page_title??'Tableau de bord') ?></h1></div></div><div class="top-right"><span class="top-date"><?= date('d/m/Y') ?></span><div class="ui-actions"><button class="utility-button" type="button" data-theme-toggle aria-label="Activer le thème sombre" title="Thème sombre">◐</button><label class="language-label" for="languageSelect">Langue</label><select class="language-select" id="languageSelect" aria-label="Langue"><option value="fr">FR</option><option value="en">EN</option></select></div><span class="avatar"><?= strtoupper(substr($_SESSION['user']['name'],0,1)) ?></span></div></header>
<?php if(!empty($_SESSION['flash'])): ?><div class="alert <?= e($_SESSION['flash']['type']) ?>"><?= e($_SESSION['flash']['message']) ?></div><?php unset($_SESSION['flash']); endif; ?>
