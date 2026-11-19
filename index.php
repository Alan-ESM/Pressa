<?php
require_once __DIR__.'/includes/bootstrap.php';
if(auth()) redirect(role()==='client'?'client.php':(role()==='livreur'?'livreur.php':'dashboard.php'));
redirect('login.php');
