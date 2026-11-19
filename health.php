<?php
header('Content-Type: application/json; charset=utf-8');
try {
    require_once __DIR__.'/includes/db.php';
    db()->query('SELECT 1');
    http_response_code(200);
    echo json_encode(['status'=>'ok','database'=>'connected']);
} catch (Throwable $e) {
    error_log('Pressa health check failed: '.$e->getMessage());
    http_response_code(503);
    echo json_encode(['status'=>'unavailable','database'=>'disconnected']);
}
