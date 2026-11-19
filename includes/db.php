<?php
require_once __DIR__.'/../config/config.php';
function db(): PDO {
 static $pdo=null;
 if (!$pdo) {
  if(DB_DRIVER==='pgsql'){
   $url=PRESSA_DATABASE_URL;
   if($url===''&&getenv('VERCEL')){
    http_response_code(503);
    header('Content-Type: text/plain; charset=utf-8');
    exit('Pressa est en cours de configuration. La connexion à la base de données est temporairement indisponible.');
   }
   if($url!==''){
    $parts=parse_url($url);
    if(!$parts||empty($parts['host'])||empty($parts['path']))throw new RuntimeException('PRESSA_DATABASE_URL is invalid.');
    parse_str($parts['query']??'',$query);
    $host=$parts['host'];$port=$parts['port']??DB_PORT;$name=ltrim($parts['path'],'/');
    $user=urldecode($parts['user']??'');$pass=urldecode($parts['pass']??'');$ssl=$query['sslmode']??'require';
   }else{$host=DB_HOST;$port=DB_PORT;$name=DB_NAME;$user=DB_USER;$pass=DB_PASS;$ssl='require';}
   $dsn='pgsql:host='.$host.';port='.$port.';dbname='.$name.';sslmode='.$ssl;
  }elseif(DB_DRIVER==='mysql'){$user=DB_USER;$pass=DB_PASS;$dsn='mysql:host='.DB_HOST.';dbname='.DB_NAME.';charset=utf8mb4';}
  else{throw new RuntimeException('PRESSA_DB_DRIVER must be mysql or pgsql.');}
  $pdo=new PDO($dsn,$user,$pass,[
   PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
   PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,
   PDO::ATTR_EMULATE_PREPARES=>false
  ]);
 }
 return $pdo;
}
function db_last_insert_id(PDO $pdo,string $table): int {
 if($pdo->getAttribute(PDO::ATTR_DRIVER_NAME)!=='pgsql')return (int)$pdo->lastInsertId();
 $q=$pdo->prepare("SELECT currval(pg_get_serial_sequence(?, 'id'))");$q->execute([$table]);
 return (int)$q->fetchColumn();
}
