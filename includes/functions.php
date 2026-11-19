<?php
if (session_status()===PHP_SESSION_NONE) {
    if (defined('DB_DRIVER') && DB_DRIVER==='pgsql') {
        require_once __DIR__.'/db.php';
        final class PressaDatabaseSessionHandler implements SessionHandlerInterface {
            public function open(string $path,string $name):bool{return true;}
            public function close():bool{return true;}
            public function read(string $id):string|false {
                $q=db()->prepare('SELECT session_data FROM app_sessions WHERE session_id=? AND expires_at>?');
                $q->execute([$id,time()]);$value=$q->fetchColumn();return $value===false?'':(string)$value;
            }
            public function write(string $id,string $data):bool {
                $q=db()->prepare('INSERT INTO app_sessions(session_id,session_data,expires_at) VALUES(?,?,?) ON CONFLICT(session_id) DO UPDATE SET session_data=EXCLUDED.session_data,expires_at=EXCLUDED.expires_at');
                return $q->execute([$id,$data,time()+(int)ini_get('session.gc_maxlifetime')]);
            }
            public function destroy(string $id):bool{$q=db()->prepare('DELETE FROM app_sessions WHERE session_id=?');return $q->execute([$id]);}
            public function gc(int $max_lifetime):int|false{$q=db()->prepare('DELETE FROM app_sessions WHERE expires_at<?');$q->execute([time()]);return $q->rowCount();}
        }
        ini_set('session.use_strict_mode','1');
        ini_set('session.use_only_cookies','1');
        session_name('pressa_session');
        session_set_cookie_params(['lifetime'=>0,'path'=>'/','secure'=>!empty($_SERVER['HTTPS'])&&$_SERVER['HTTPS']!=='off' || ($_SERVER['HTTP_X_FORWARDED_PROTO']??'')==='https','httponly'=>true,'samesite'=>'Lax']);
        session_set_save_handler(new PressaDatabaseSessionHandler(),true);
    }
    session_start();
}
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
