<?php
if (session_status()===PHP_SESSION_NONE) session_start();
function e($v){return htmlspecialchars((string)$v,ENT_QUOTES,'UTF-8');}
function auth(){return !empty($_SESSION['user']);}
function require_auth(){if(!auth()){header('Location: login.php');exit;}}
function redirect($p){header('Location: '.$p);exit;}
function flash($m,$type='success'){$_SESSION['flash']=['message'=>$m,'type'=>$type];}
function csrf(){if(empty($_SESSION['csrf']))$_SESSION['csrf']=bin2hex(random_bytes(32));return $_SESSION['csrf'];}
function verify_csrf(){if($_SERVER['REQUEST_METHOD']==='POST' && !hash_equals($_SESSION['csrf']??'',$_POST['csrf']??'')){http_response_code(403);exit('Requête invalide. Rechargez la page.');}}
function money($n){return number_format((float)$n,0,',',' ').' FCFA';}
function role(){return $_SESSION['user']['role']??'';}
function can_manage(){return in_array(role(),['admin','accueil'],true);}
function status_label($s){$map=['recu'=>'Reçu','lavage'=>'Lavage','repassage'=>'Repassage','emballage'=>'Emballage','pret'=>'Prêt','retire'=>'Retiré'];return $map[$s]??$s;}
