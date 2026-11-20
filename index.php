<?php
require_once __DIR__.'/includes/bootstrap.php';
if(auth()){require_auth();redirect(role()==='client'?'client.php':(role()==='livreur'?'livreur.php':(role()==='responsable'?'users.php':'dashboard.php')));}
redirect('login.php');
