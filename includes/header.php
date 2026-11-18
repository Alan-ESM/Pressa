<?php require_once __DIR__.'/bootstrap.php'; require_auth(); ?>
<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title><?= e($page_title??APP_NAME) ?> · Pressing de la joie</title><link rel="stylesheet" href="assets/css/style.css"></head><body>
<aside class="sidebar"><div class="brand">✦ Pressing <span>de la joie</span></div><div class="userbox"><?= e($_SESSION['user']['name']) ?><small><?= e(role()) ?></small></div><nav>
<a href="dashboard.php">▦ Tableau de bord</a>
<a href="clients.php">♙ Clients</a>
<a href="orders.php">▤ Commandes & dépôts</a>
<a href="production.php">◈ Production</a>
<a href="invoices.php">▧ Factures & paiements</a>
<a href="messages.php">✉ Messages clients</a>
<?php if(role()==='admin'): ?><a href="users.php">⚙ Utilisateurs</a><a href="services.php">◆ Services & tarifs</a><a href="stock.php">▦ Stock</a><a href="suppliers.php">♧ Fournisseurs</a><a href="purchases.php">▤ Achats</a><a href="maintenance.php">⚒ Maintenance</a><?php endif; ?><?php if(in_array(role(),['admin','accueil'],true)): ?><a href="expenses.php">₣ Dépenses</a><?php endif; ?>
</nav><a class="logout" href="logout.php">↪ Déconnexion</a></aside><main class="main"><header class="topbar"><div><span class="muted">ESPACE DE GESTION</span><h1><?= e($page_title??'Tableau de bord') ?></h1></div><div class="top-right"><?= date('d/m/Y') ?> <span class="avatar"><?= strtoupper(substr($_SESSION['user']['name'],0,1)) ?></span></div></header>
<?php if(!empty($_SESSION['flash'])): ?><div class="alert <?= e($_SESSION['flash']['type']) ?>"><?= e($_SESSION['flash']['message']) ?></div><?php unset($_SESSION['flash']); endif; ?>
