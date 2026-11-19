<?php
require_once __DIR__ . '/../../config/config.php';
$commonPassword = getenv('PRESSA_COMMON_PASSWORD') ?: '';
if (strlen($commonPassword) < 8) {
    fwrite(STDERR, "Mot de passe commun absent ou trop court; aucune modification effectuée.\n");
    exit(2);
}
$pdo = new PDO(
    'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
    DB_USER,
    DB_PASS,
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
);
$counts = $pdo->query('SELECT role,COUNT(*) AS n FROM utilisateurs WHERE actif=1 GROUP BY role')->fetchAll(PDO::FETCH_KEY_PAIR);
foreach ($counts as $role=>$count) {
    $counts[$role]=(int)$count;
}
$expected = ['admin'=>2,'caissier'=>2,'accueil'=>2,'production'=>2,'livreur'=>2];
ksort($counts);ksort($expected);
if ($counts !== $expected) {
    fwrite(STDERR, "Préconditions de rôles inattendues; aucune modification effectuée.\n");
    exit(3);
}
$demoAdmin = $pdo->query("SELECT id FROM utilisateurs WHERE email='pressa.demo.admin01@gmail.com' AND role='admin' LIMIT 1")->fetchColumn();
$initialAdmin = $pdo->query("SELECT id FROM utilisateurs WHERE email='pressa.admin.initial@gmail.com' AND role='admin' LIMIT 1")->fetchColumn();
if (!$demoAdmin || !$initialAdmin) {
    fwrite(STDERR, "Les deux comptes administrateur attendus ne sont pas présents; aucune modification effectuée.\n");
    exit(4);
}
$employeeQuery = $pdo->prepare('SELECT id FROM employes WHERE utilisateur_id=? LIMIT 1');
$employeeQuery->execute([(int)$demoAdmin]);
$demoAdminEmployee = $employeeQuery->fetchColumn();
if (!$demoAdminEmployee) {
    fwrite(STDERR, "La fiche employé du compte à retirer est introuvable; aucune modification effectuée.\n");
    exit(5);
}
function assertOnlyAllowedReferences(PDO $pdo, string $referencedTable, int $id, array $allowed): void
{
    $stmt = $pdo->prepare('SELECT TABLE_NAME,COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=DATABASE() AND REFERENCED_TABLE_NAME=? AND REFERENCED_COLUMN_NAME=\'id\'');
    $stmt->execute([$referencedTable]);
    foreach ($stmt->fetchAll() as $reference) {
        $table = $reference['TABLE_NAME'];
        $column = $reference['COLUMN_NAME'];
        if (!preg_match('/^[a-z_]+$/', $table) || !preg_match('/^[a-z_]+$/', $column)) {
            throw new RuntimeException('Référence SQL inattendue; annulation.');
        }
        $q = $pdo->prepare("SELECT COUNT(*) FROM `$table` WHERE `$column`=?");
        $q->execute([$id]);
        $n = (int)$q->fetchColumn();
        $allowedCount = (int)($allowed[$table . '.' . $column] ?? 0);
        if ($n !== $allowedCount) {
            throw new RuntimeException("Le compte à retirer est utilisé dans `$table.$column` ($n référence(s)); annulation de sécurité.");
        }
    }
}
try {
    assertOnlyAllowedReferences($pdo, 'utilisateurs', (int)$demoAdmin, ['employes.utilisateur_id'=>1]);
    assertOnlyAllowedReferences($pdo, 'employes', (int)$demoAdminEmployee, ['presences.employe_id'=>1]);
    $pdo->beginTransaction();
    $pdo->exec('SET @app_user_id = ' . (int)$initialAdmin);
    $pdo->prepare("UPDATE utilisateurs SET role='receptionniste' WHERE role IN ('accueil','caissier')")->execute();
    $convertedUsers = $pdo->query("SELECT COUNT(*) FROM utilisateurs WHERE role='receptionniste'")->fetchColumn();
    if ((int)$convertedUsers !== 4) {
        throw new RuntimeException('Le nombre de comptes réceptionniste n’est pas celui attendu.');
    }
    $pdo->prepare("UPDATE employes SET poste='receptionniste' WHERE poste IN ('accueil','caissier')")->execute();
    $presence = $pdo->prepare('DELETE FROM presences WHERE employe_id=?');
    $presence->execute([(int)$demoAdminEmployee]);
    if ($presence->rowCount() !== 1) {
        throw new RuntimeException('La présence du second administrateur n’a pas pu être isolée.');
    }
    $employee = $pdo->prepare('DELETE FROM employes WHERE id=? AND utilisateur_id=?');
    $employee->execute([(int)$demoAdminEmployee,(int)$demoAdmin]);
    if ($employee->rowCount() !== 1) {
        throw new RuntimeException('La fiche employé du second administrateur n’a pas pu être supprimée.');
    }
    $user = $pdo->prepare('DELETE FROM utilisateurs WHERE id=? AND email=\'pressa.demo.admin01@gmail.com\'');
    $user->execute([(int)$demoAdmin]);
    if ($user->rowCount() !== 1) {
        throw new RuntimeException('Le second administrateur n’a pas pu être supprimé.');
    }
    $accounts = $pdo->query('SELECT id FROM utilisateurs')->fetchAll(PDO::FETCH_COLUMN);
    $passwordUpdate = $pdo->prepare('UPDATE utilisateurs SET mot_de_passe=? WHERE id=?');
    foreach ($accounts as $accountId) {
        $passwordUpdate->execute([password_hash($commonPassword, PASSWORD_DEFAULT),(int)$accountId]);
    }
    $pdo->commit();
} catch (Throwable $error) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    fwrite(STDERR, 'Migration annulée : ' . $error->getMessage() . PHP_EOL);
    exit(1);
}
$finalCounts = $pdo->query('SELECT role,COUNT(*) AS n FROM utilisateurs WHERE actif=1 GROUP BY role ORDER BY role')->fetchAll(PDO::FETCH_KEY_PAIR);
echo "MIGRATION TERMINÉE\n";
echo "Comptes actifs par rôle :\n";
foreach ($finalCounts as $role=>$n) {
    echo '  ' . $role . ': ' . $n . PHP_EOL;
}
echo 'Comptes restants: ' . count($accounts) . PHP_EOL;
echo 'Mot de passe commun vérifié et haché dans chaque compte: ' . count($accounts) . PHP_EOL;
echo 'Second administrateur de démonstration supprimé; compte initial conservé.\n';
