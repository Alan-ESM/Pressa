<?php
require_once __DIR__.'/db.php';
require_once __DIR__.'/functions.php';
if (isset($_SESSION['user'])) { db()->query('SET @app_user_id = ' . (int)$_SESSION['user']['id']); }
