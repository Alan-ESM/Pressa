<?php
require_once __DIR__.'/includes/bootstrap.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: '.(auth() ? (role()==='livreur' ? 'livreur.php' : 'dashboard.php') : 'login.php'));
    exit;
}
verify_csrf();
$_SESSION = [];
$params = session_get_cookie_params();
if (ini_get('session.use_cookies')) {
    setcookie(session_name(), '', time()-42000, $params['path'], $params['domain'], $params['secure'], $params['httponly']);
}
session_destroy();
header('Location: login.php');
exit;