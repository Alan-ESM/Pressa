<?php
require_once __DIR__.'/includes/bootstrap.php';
try{
 $pdo=db();
 $count=(int)$pdo->query("SELECT COUNT(*) FROM users")->fetchColumn();
 if($count===0){
  $s=$pdo->prepare("INSERT INTO users(name,email,password,role) VALUES(?,?,?,'admin')");
  $s->execute(['Administrateur','admin@pressing.local',password_hash('Admin123!',PASSWORD_DEFAULT)]);
  echo '<h2>Installation terminée</h2><p>Compte : admin@pressing.local</p><p>Mot de passe : Admin123!</p><p><a href="login.php">Ouvrir Pressing de la joie</a></p><b>Important : supprimez setup.php après installation et changez le mot de passe.</b>';
 }else echo 'Installation déjà effectuée. <a href="login.php">Connexion</a>';
}catch(Throwable $e){http_response_code(500);echo 'Erreur : '.e($e->getMessage()).'<br>Importez install.sql dans phpMyAdmin et vérifiez config/config.php.';}
