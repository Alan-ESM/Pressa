<?php
require_once __DIR__.'/includes/bootstrap.php';
header('Content-Type: application/json; charset=utf-8');
if($_SERVER['REQUEST_METHOD']!=='POST'){
    http_response_code(405);
    echo json_encode(['ok'=>false]);
    exit;
}
verify_csrf();
$language=(string)($_POST['language']??'');
if(!in_array($language,['fr','en','es','pt','de','it','ar','zh','ha'],true)){
    http_response_code(422);
    echo json_encode(['ok'=>false]);
    exit;
}
$_SESSION['language']=$language;
echo json_encode(['ok'=>true]);
