<?php
require_once __DIR__.'/db.php';
require_once __DIR__.'/functions.php';
$userId=(int)($_SESSION['user']['id']??0);
if(DB_DRIVER==='pgsql'){
    $stmt=db()->prepare("SELECT set_config('app.user_id', ?, false)");
    $stmt->execute([$userId>0?(string)$userId:'']);
}elseif($userId>0){
    db()->query('SET @app_user_id = '.$userId);
}
