<?php
// Configuration locale XAMPP - Pressing de la joie
if (!defined('DB_HOST')) define('DB_HOST', '127.0.0.1');
if (!defined('DB_NAME')) define('DB_NAME', 'pressa');
if (!defined('DB_USER')) define('DB_USER', 'root');
if (!defined('DB_PASS')) define('DB_PASS', '');
if (!defined('DB_DRIVER')) define('DB_DRIVER', strtolower(getenv('PRESSA_DB_DRIVER') ?: (getenv('VERCEL') ? 'pgsql' : 'mysql')));
if (!defined('PRESSA_DATABASE_URL')) define('PRESSA_DATABASE_URL', getenv('PRESSA_DATABASE_URL') ?: getenv('DATABASE_URL') ?: '');
if (!defined('DB_PORT')) define('DB_PORT', (int)(getenv('PRESSA_DB_PORT') ?: 5432));
if (!defined('APP_NAME')) define('APP_NAME', 'Pressa');
if (!defined('APP_URL')) define('APP_URL', '/Pressa');
if (!defined('EXPRESS_SURCHARGE_PERCENT')) define('EXPRESS_SURCHARGE_PERCENT', 30);
if (!defined('CURRENCY_LABEL')) define('CURRENCY_LABEL', 'FCFA');
// Configure SMTP_PASSWORD as a Google App Password in the server environment.
if (!defined('SMTP_HOST')) define('SMTP_HOST', getenv('PRESSA_SMTP_HOST') ?: 'smtp.gmail.com');
if (!defined('SMTP_PORT')) define('SMTP_PORT', (int)(getenv('PRESSA_SMTP_PORT') ?: 587));
if (!defined('SMTP_USERNAME')) define('SMTP_USERNAME', getenv('PRESSA_SMTP_USERNAME') ?: 'codex.ess237@gmail.com');
if (!defined('SMTP_PASSWORD')) define('SMTP_PASSWORD', getenv('PRESSA_SMTP_PASSWORD') ?: '');
if (!defined('SMTP_FROM_EMAIL')) define('SMTP_FROM_EMAIL', getenv('PRESSA_SMTP_FROM') ?: SMTP_USERNAME);
if (!defined('SMTP_FROM_NAME')) define('SMTP_FROM_NAME', getenv('PRESSA_SMTP_FROM_NAME') ?: APP_NAME);
date_default_timezone_set('Africa/Douala');
