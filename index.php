<?php
require_once __DIR__.'/includes/bootstrap.php';
if (auth()) redirect('dashboard.php');
redirect('login.php');
