<?php
if(session_status()===PHP_SESSION_NONE){
    header('X-Content-Type-Options: nosniff');
    header('X-Frame-Options: DENY');
    header('Referrer-Policy: strict-origin-when-cross-origin');
    header('Permissions-Policy: camera=(), microphone=(), geolocation=(self)');
    if(defined('DB_DRIVER')&&DB_DRIVER==='pgsql'){
        require_once __DIR__.'/db.php';
        final class PressaDatabaseSessionHandler implements SessionHandlerInterface{
            public function open(string $path,string $name):bool{return true;}
            public function close():bool{return true;}
            public function read(string $id):string|false{$q=db()->prepare('SELECT session_data FROM app_sessions WHERE session_id=? AND expires_at>?');$q->execute([$id,time()]);$value=$q->fetchColumn();return $value===false?'':(string)$value;}
            public function write(string $id,string $data):bool{$q=db()->prepare('INSERT INTO app_sessions(session_id,session_data,expires_at) VALUES(?,?,?) ON CONFLICT(session_id) DO UPDATE SET session_data=EXCLUDED.session_data,expires_at=EXCLUDED.expires_at');return $q->execute([$id,$data,time()+(int)ini_get('session.gc_maxlifetime')]);}
            public function destroy(string $id):bool{$q=db()->prepare('DELETE FROM app_sessions WHERE session_id=?');return $q->execute([$id]);}
            public function gc(int $max_lifetime):int|false{$q=db()->prepare('DELETE FROM app_sessions WHERE expires_at<?');$q->execute([time()]);return $q->rowCount();}
        }
        session_name('pressa_session');
        session_set_save_handler(new PressaDatabaseSessionHandler(),true);
    }
    ini_set('session.use_strict_mode','1');
    ini_set('session.use_only_cookies','1');
    $https=(!empty($_SERVER['HTTPS'])&&$_SERVER['HTTPS']!=='off')||($_SERVER['HTTP_X_FORWARDED_PROTO']??'')==='https';
    session_set_cookie_params(['lifetime'=>0,'path'=>'/','secure'=>$https,'httponly'=>true,'samesite'=>'Lax']);
    session_start();
}
function e($value):string{return htmlspecialchars((string)$value,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8');}
function auth():bool{return is_array($_SESSION['user']??null)&&!empty($_SESSION['user']['id']);}
function role():string{return (string)($_SESSION['user']['role']??'');}
function require_auth():void{if(!auth()){redirect('login.php');}static $validatedUser=0;$userId=(int)$_SESSION['user']['id'];if($validatedUser!==$userId){$check=db()->prepare('SELECT actif FROM utilisateurs WHERE id=?');$check->execute([$userId]);if((int)$check->fetchColumn()!==1){$_SESSION=[];session_regenerate_id(true);redirect('login.php');}$validatedUser=$userId;}if(role()==='livreur'&&!in_array(basename($_SERVER['SCRIPT_NAME']??''),['livreur.php','logout.php'],true)){redirect('livreur.php');}if(role()==='client'&&!in_array(basename($_SERVER['SCRIPT_NAME']??''),['client.php','logout.php'],true)){redirect('client.php');}}
function require_role(array $roles):void{require_auth();if(!in_array(role(),$roles,true)){http_response_code(403);exit('Accès non autorisé.');}}
function redirect(string $path):void{header('Location: '.$path);exit;}
function flash(string $message,string $type='success'):void{$_SESSION['flash']=['message'=>$message,'type'=>$type];}
function csrf():string{if(empty($_SESSION['csrf'])||!is_string($_SESSION['csrf']))$_SESSION['csrf']=bin2hex(random_bytes(32));return $_SESSION['csrf'];}
function verify_csrf():void{$token=$_POST['csrf']??null;if($_SERVER['REQUEST_METHOD']!=='POST'||!is_string($token)||!hash_equals(csrf(),$token)){http_response_code(403);exit('Requête invalide. Rechargez la page.');}}
function money($amount):string{return number_format((float)$amount,0,',',' ').' FCFA';}
function role_label(string $role):string{return ['admin'=>'Administrateur','receptionniste'=>'Réceptionniste','accueil'=>'Accueil','caissier'=>'Caissier','production'=>'Production','livreur'=>'Livreur','client'=>'Client'][$role]??$role;}
function can_manage():bool{return in_array(role(),['admin','receptionniste','accueil'],true);}
function can_handle_payments():bool{return in_array(role(),['admin','receptionniste','accueil','caissier'],true);}
function current_client_id():int{$q=db()->prepare('SELECT id FROM clients WHERE utilisateur_id=? AND supprime=0 LIMIT 1');$q->execute([(int)$_SESSION['user']['id']]);return (int)$q->fetchColumn();}
function app_setting(string $key,string $default=''):string{static $values=[];if(array_key_exists($key,$values))return $values[$key];try{$q=db()->prepare('SELECT valeur FROM parametres WHERE cle=?');$q->execute([$key]);$value=$q->fetchColumn();return $values[$key]=$value===false?$default:(string)$value;}catch(Throwable $e){return $values[$key]=$default;}}
function audit_event(string $action,string $table,?int $recordId=null):void{try{if(auth())db()->prepare('INSERT INTO journal_audit(utilisateur_id,action,table_cible,enregistrement_id) VALUES(?,?,?,?)')->execute([(int)$_SESSION['user']['id'],$action,$table,$recordId]);}catch(Throwable $e){}}
function status_label(string $status):string{return ['recu'=>'Reçu','lavage'=>'Lavage','repassage'=>'Repassage','emballage'=>'Emballage','pret'=>'Prêt','retire'=>'Retiré','annule'=>'Annulé'][$status]??$status;}
function course_status_label(string $status):string{return ['planifiee'=>'Planifiée','en_cours'=>'En cours','effectuee'=>'Effectuée','annulee'=>'Annulée'][$status]??$status;}
function delivery_slot_label(string $slot):string{return ['matin'=>'Matin','apres_midi'=>'Après-midi','soir'=>'Soir'][$slot]??$slot;}
