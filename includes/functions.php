<?php
if (session_status()===PHP_SESSION_NONE) session_start();
function e($v){return htmlspecialchars((string)$v,ENT_QUOTES,'UTF-8');}
function auth(){return !empty($_SESSION['user']);}
function require_auth(){if(!auth()){header('Location: login.php');exit;}if(role()==='livreur'&&!in_array(basename($_SERVER['SCRIPT_NAME']??''),['livreur.php','logout.php'],true)){header('Location: livreur.php');exit;}}
function redirect($p){header('Location: '.$p);exit;}
function flash($m,$type='success'){$_SESSION['flash']=['message'=>$m,'type'=>$type];}
function csrf(){if(empty($_SESSION['csrf']))$_SESSION['csrf']=bin2hex(random_bytes(32));return $_SESSION['csrf'];}
function verify_csrf(){if($_SERVER['REQUEST_METHOD']==='POST' && !hash_equals($_SESSION['csrf']??'',$_POST['csrf']??'')){http_response_code(403);exit('Requête invalide. Rechargez la page.');}}
function money($n){return number_format((float)$n,0,',',' ').' FCFA';}
function role(){return $_SESSION['user']['role']??'';}
function role_label($r){$map=['admin'=>'Administrateur','receptionniste'=>'Réceptionniste','production'=>'Production','livreur'=>'Livreur'];return $map[$r]??$r;}
function can_manage(){return in_array(role(),['admin','receptionniste'],true);}
function status_label($s){$map=['recu'=>'Reçu','lavage'=>'Lavage','repassage'=>'Repassage','emballage'=>'Emballage','pret'=>'Prêt','retire'=>'Retiré','annule'=>'Annulé'];return $map[$s]??$s;}
function course_status_label($s){$map=['planifiee'=>'Planifiée','en_cours'=>'En cours','effectuee'=>'Effectuée','annulee'=>'Annulée'];return $map[$s]??$s;}
function delivery_slot_label($s){$map=['matin'=>'Matin','apres_midi'=>'Après-midi','soir'=>'Soir'];return $map[$s]??$s;}
