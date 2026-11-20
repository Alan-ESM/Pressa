<?php
require_once __DIR__.'/includes/bootstrap.php';
require_role(['admin','responsable']);
$page_title='Comptes et personnel';
$pdo=db();
$isAdmin=role()==='admin';
$staffRoles=['responsable','accueil','caissier','production','livreur'];
$postForRole=['responsable'=>'gerant','accueil'=>'accueil','caissier'=>'caissier','production'=>'laveur','livreur'=>'livreur'];
$allowedByManager=['accueil','caissier','production','livreur','client'];
$notice='';
$scalarRefCount=static function(string $referencedTable,int $recordId,array $ignored=[])use($pdo):int{
    $q=$pdo->prepare('SELECT TABLE_NAME,COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=DATABASE() AND REFERENCED_TABLE_NAME=? AND REFERENCED_COLUMN_NAME=\'id\'');
    $q->execute([$referencedTable]);
    $total=0;
    foreach($q->fetchAll(PDO::FETCH_ASSOC) as $ref){
        if(in_array($ref['TABLE_NAME'].'.'.$ref['COLUMN_NAME'],$ignored,true))continue;
        if(!preg_match('/^[a-zA-Z0-9_]+$/',$ref['TABLE_NAME'])||!preg_match('/^[a-zA-Z0-9_]+$/',$ref['COLUMN_NAME']))continue;
        $count=$pdo->prepare('SELECT COUNT(*) FROM `'.$ref['TABLE_NAME'].'` WHERE `'.$ref['COLUMN_NAME'].'`=?');
        $count->execute([$recordId]);
        $total+=(int)$count->fetchColumn();
    }
    return $total;
};
$accountById=static function(int $id,bool $lock=false)use($pdo):array|false{$q=$pdo->prepare('SELECT id,nom,email,role,actif FROM utilisateurs WHERE id=?'.($lock?' FOR UPDATE':''));$q->execute([$id]);return $q->fetch();};
$actionMessage='';
if($_SERVER['REQUEST_METHOD']==='POST'){
    verify_csrf();
    $action=(string)($_POST['action']??'');
    $targetId=(int)($_POST['user_id']??0);
    $reason=trim((string)($_POST['reason']??''));
    try{
        if($action==='create'){
            if(!$isAdmin)throw new RuntimeException('Action réservée à l’administrateur.');
            $last=trim((string)($_POST['nom']??''));$first=trim((string)($_POST['prenom']??''));$name=trim($first.' '.$last);
            $email=mb_strtolower(trim((string)($_POST['email']??'')),'UTF-8');$phone=trim((string)($_POST['telephone']??''));
            $newRole=(string)($_POST['role']??'');$password=(string)($_POST['password']??'');$confirmation=(string)($_POST['confirmation']??'');
            $salary=filter_var($_POST['salaire_mensuel']??null,FILTER_VALIDATE_FLOAT);$hireDate=trim((string)($_POST['date_embauche']??''));$active=isset($_POST['actif'])?1:0;
            if($last===''||$first===''||mb_strlen($last)>120||mb_strlen($first)>120||filter_var($email,FILTER_VALIDATE_EMAIL)===false||mb_strlen($email)>160||mb_strlen($phone)>30||!in_array($newRole,$staffRoles,true)||strlen($password)<10||$password!==$confirmation||$salary===false||$salary<0||($hireDate!==''&&!preg_match('/^\d{4}-\d{2}-\d{2}$/',$hireDate)))throw new RuntimeException('Vérifiez le profil, le rôle, le salaire et les mots de passe.');
            $existing=$pdo->prepare('SELECT id FROM utilisateurs WHERE LOWER(email)=LOWER(?) LIMIT 1');$existing->execute([$email]);if($existing->fetchColumn())throw new RuntimeException('Cette adresse e-mail est déjà utilisée.');
            $pdo->beginTransaction();
            $pdo->prepare('INSERT INTO utilisateurs(nom,email,mot_de_passe,role,actif,doit_changer_mdp) VALUES(?,?,?,?,?,1)')->execute([$name,$email,password_hash($password,PASSWORD_DEFAULT),$newRole,$active]);
            $userId=db_last_insert_id($pdo,'utilisateurs');
            $pdo->prepare('INSERT INTO employes(utilisateur_id,nom,prenom,telephone,poste,date_embauche,salaire_mensuel,actif) VALUES(?,?,?,?,?,?,?,?)')->execute([$userId,$last,$first,$phone?:null,$postForRole[$newRole],$hireDate?:null,$salary,$active]);
            audit_account_action($userId,$email,'CREATION','Création du compte du personnel');
            $pdo->commit();
            flash('Compte du personnel créé. Le changement du mot de passe initial sera requis à la première connexion.');
        }elseif($action==='update_employee_salary'){
            if(!$isAdmin)throw new RuntimeException('Action réservée à l’administrateur.');
            if($reason===''||mb_strlen($reason)>500)throw new RuntimeException('Indiquez le motif de modification du salaire.');
            $salary=filter_var($_POST['salaire_mensuel']??null,FILTER_VALIDATE_FLOAT);if($salary===false||$salary<0)throw new RuntimeException('Indiquez un salaire mensuel valide en FCFA.');
            $pdo->beginTransaction();$employeeId=(int)($_POST['employee_id']??0);$employeeQuery=$pdo->prepare('SELECT e.id,e.utilisateur_id,e.nom,e.prenom,u.email FROM employes e LEFT JOIN utilisateurs u ON u.id=e.utilisateur_id WHERE e.id=? FOR UPDATE');$employeeQuery->execute([$employeeId]);$employee=$employeeQuery->fetch();if(!$employee)throw new RuntimeException('Fiche employé introuvable.');
            $pdo->prepare('UPDATE employes SET salaire_mensuel=? WHERE id=?')->execute([$salary,$employeeId]);audit_account_action((int)($employee['utilisateur_id']??0),$employee['email']?:('employe#'.$employeeId),'MODIFICATION_SALAIRE',$reason);$pdo->commit();flash('Salaire mensuel enregistré en FCFA.');
        }elseif($action==='update_profile'){
            if(!$isAdmin)throw new RuntimeException('Action réservée à l’administrateur.');
            if($reason===''||mb_strlen($reason)>500)throw new RuntimeException('Indiquez un motif de modification.');
            $account=$accountById($targetId);if(!$account||$account['role']==='admin'||$account['role']==='client')throw new RuntimeException('Fiche de personnel introuvable ou non modifiable.');
            $last=trim((string)($_POST['nom']??''));$first=trim((string)($_POST['prenom']??''));$name=trim($first.' '.$last);
            $email=mb_strtolower(trim((string)($_POST['email']??'')),'UTF-8');$phone=trim((string)($_POST['telephone']??''));$newRole=(string)($_POST['role']??'');
            $salary=filter_var($_POST['salaire_mensuel']??null,FILTER_VALIDATE_FLOAT);$hireDate=trim((string)($_POST['date_embauche']??''));
            if($last===''||$first===''||mb_strlen($last)>120||mb_strlen($first)>120||filter_var($email,FILTER_VALIDATE_EMAIL)===false||mb_strlen($email)>160||mb_strlen($phone)>30||!in_array($newRole,$staffRoles,true)||$salary===false||$salary<0||($hireDate!==''&&!preg_match('/^\d{4}-\d{2}-\d{2}$/',$hireDate)))throw new RuntimeException('Vérifiez les champs de la fiche professionnelle.');
            if(is_protected_account($account['email'])&&$newRole!==$account['role'])throw new RuntimeException('Le rôle de ce compte protégé ne peut pas être modifié ici.');
            $dupe=$pdo->prepare('SELECT id FROM utilisateurs WHERE LOWER(email)=LOWER(?) AND id<>? LIMIT 1');$dupe->execute([$email,$targetId]);if($dupe->fetchColumn())throw new RuntimeException('Cette adresse e-mail est déjà utilisée.');
            $pdo->beginTransaction();$locked=$accountById($targetId,true);if(!$locked||$locked['role']==='admin'||$locked['role']==='client'||(is_protected_account($locked['email'])&&$newRole!==$locked['role']))throw new RuntimeException('La fiche a changé ou est protégée. Rechargez la page.');
            $employeeLock=$pdo->prepare('SELECT id FROM employes WHERE utilisateur_id=? FOR UPDATE');$employeeLock->execute([$targetId]);if(!$employeeLock->fetchColumn())throw new RuntimeException('Fiche employé introuvable.');
            $pdo->prepare('UPDATE utilisateurs SET nom=?,email=?,role=? WHERE id=?')->execute([$name,$email,$newRole,$targetId]);
            $employee=$pdo->prepare('UPDATE employes SET nom=?,prenom=?,telephone=?,poste=?,date_embauche=?,salaire_mensuel=? WHERE utilisateur_id=?');$employee->execute([$last,$first,$phone?:null,$postForRole[$newRole],$hireDate?:null,$salary,$targetId]);if(!$employee->rowCount()&&$employee->errorCode()!=='00000')throw new RuntimeException('Fiche employé non mise à jour.');
            audit_account_action($targetId,$email,'MODIFICATION_FICHE',$reason);$pdo->commit();flash('Fiche professionnelle mise à jour.');
        }elseif($action==='reset_password'){
            if(!$isAdmin)throw new RuntimeException('Action réservée à l’administrateur.');
            if($reason===''||mb_strlen($reason)>500)throw new RuntimeException('Indiquez le motif de réinitialisation.');
            $password=(string)($_POST['password']??'');$confirmation=(string)($_POST['confirmation']??'');if(strlen($password)<10||$password!==$confirmation)throw new RuntimeException('Le mot de passe doit contenir 10 caractères et correspondre à sa confirmation.');
            $pdo->beginTransaction();$account=$accountById($targetId,true);if(!$account||$account['role']==='admin'||$account['role']==='client'||is_protected_account($account['email']))throw new RuntimeException('Compte du personnel introuvable, protégé ou non modifiable.');
            $pdo->prepare('UPDATE utilisateurs SET mot_de_passe=?,doit_changer_mdp=1 WHERE id=?')->execute([password_hash($password,PASSWORD_DEFAULT),$targetId]);audit_account_action($targetId,$account['email'],'REINITIALISATION_MDP',$reason);$pdo->commit();flash('Mot de passe initialisé. Le membre devra le changer à sa prochaine connexion.');
        }elseif(in_array($action,['suspend','reactivate'],true)){
            if($action==='reactivate'&&!$isAdmin)throw new RuntimeException('Seul l’administrateur peut réactiver un compte.');
            if($reason===''||mb_strlen($reason)>500)throw new RuntimeException('Indiquez un motif.');
            $pdo->beginTransaction();$account=$accountById($targetId,true);if(!$account)throw new RuntimeException('Compte introuvable.');
            $actorId=(int)$_SESSION['user']['id'];$actorRole=role();
            if($actorId===$targetId)throw new RuntimeException('Vous ne pouvez pas modifier votre propre accès.');
            if($action==='suspend'){
                if(is_protected_account($account['email']))throw new RuntimeException('Ce compte protégé ne peut pas être suspendu.');
                if($actorRole==='responsable'&&!in_array($account['role'],$allowedByManager,true))throw new RuntimeException('Le responsable ne peut suspendre que les comptes Accueil, Caissier, Production, Livreur ou Client.');
                if($account['role']==='admin'){$activeAdmins=$pdo->query("SELECT id FROM utilisateurs WHERE role='admin' AND actif=1 FOR UPDATE")->fetchAll(PDO::FETCH_COLUMN);if(count($activeAdmins)<=1)throw new RuntimeException('Impossible de suspendre le dernier administrateur actif.');}
                $pdo->prepare('UPDATE utilisateurs SET actif=0 WHERE id=? AND actif=1')->execute([$targetId]);
                $pdo->prepare('UPDATE employes SET actif=0 WHERE utilisateur_id=?')->execute([$targetId]);
                $task=$pdo->prepare("SELECT COUNT(*) FROM courses co JOIN employes e ON e.id=co.livreur_id WHERE e.utilisateur_id=? AND co.type='livraison' AND co.statut IN ('planifiee','en_cours')");$task->execute([$targetId]);$activeCourses=(int)$task->fetchColumn();
                audit_account_action($targetId,$account['email'],'SUSPENSION',$reason);$pdo->commit();
                $message='Compte suspendu; ses données métier sont conservées.';if($activeCourses>0)$message.=' '.$activeCourses.' livraison(s) à réaffecter dans le module Livraisons.';flash($message);
            }else{
                $pdo->prepare('UPDATE utilisateurs SET actif=1 WHERE id=? AND actif=0')->execute([$targetId]);
                $pdo->prepare('UPDATE employes SET actif=1 WHERE utilisateur_id=?')->execute([$targetId]);
                audit_account_action($targetId,$account['email'],'REACTIVATION',$reason);$pdo->commit();flash('Compte réactivé.');
            }
        }elseif($action==='delete'){
            if(!$isAdmin)throw new RuntimeException('Action réservée à l’administrateur.');
            if(($_POST['confirm_delete']??'')!=='yes'||$reason===''||mb_strlen($reason)>500)throw new RuntimeException('Confirmez l’opération et indiquez son motif.');
            $pdo->beginTransaction();$account=$accountById($targetId,true);if(!$account)throw new RuntimeException('Compte introuvable.');
            if($targetId===(int)$_SESSION['user']['id']||is_protected_account($account['email'])||$account['role']==='admin')throw new RuntimeException('Ce compte ne peut pas être supprimé.');
            $employeeQuery=$pdo->prepare('SELECT id FROM employes WHERE utilisateur_id=? FOR UPDATE');$employeeQuery->execute([$targetId]);$employeeId=(int)$employeeQuery->fetchColumn();
            $clientQuery=$pdo->prepare('SELECT id FROM clients WHERE utilisateur_id=? FOR UPDATE');$clientQuery->execute([$targetId]);$clientId=(int)$clientQuery->fetchColumn();
            $dependencies=$scalarRefCount('utilisateurs',$targetId,['employes.utilisateur_id','clients.utilisateur_id','gestion_comptes_audit.cible_id']);
            if($employeeId)$dependencies+=$scalarRefCount('employes',$employeeId);
            if($clientId)$dependencies+=$scalarRefCount('clients',$clientId);
            $activeCourses=0;if($employeeId){$task=$pdo->prepare("SELECT COUNT(*) FROM courses WHERE livreur_id=? AND type='livraison' AND statut IN ('planifiee','en_cours')");$task->execute([$employeeId]);$activeCourses=(int)$task->fetchColumn();}
            if($dependencies>0||$activeCourses>0){
                $pdo->prepare('UPDATE utilisateurs SET actif=0 WHERE id=?')->execute([$targetId]);$pdo->prepare('UPDATE employes SET actif=0 WHERE utilisateur_id=?')->execute([$targetId]);
                audit_account_action($targetId,$account['email'],'ARCHIVAGE',$reason);$pdo->commit();
                $message='Suppression physique bloquée par '.$dependencies.' dépendance(s) ou historique(s) : accès retiré et fiche archivée, données conservées.';if($activeCourses>0)$message.=' Réaffectez les livraisons actives.';flash($message);
            }else{
                audit_account_action($targetId,$account['email'],'SUPPRESSION_PHYSIQUE',$reason);
                if($clientId)$pdo->prepare('DELETE FROM clients WHERE id=?')->execute([$clientId]);
                if($employeeId)$pdo->prepare('DELETE FROM employes WHERE id=?')->execute([$employeeId]);
                $pdo->prepare('DELETE FROM utilisateurs WHERE id=?')->execute([$targetId]);$pdo->commit();flash('Compte supprimé physiquement; aucune dépendance métier ne le référençait.');
            }
        }else{throw new RuntimeException('Action non autorisée.');}
    }catch(Throwable $e){if($pdo->inTransaction())$pdo->rollBack();flash($e instanceof RuntimeException?$e->getMessage():'Opération impossible; aucune modification n’a été conservée.','error');}
    redirect('users.php');
}
$rows=$pdo->query('SELECT u.id,u.nom AS name,u.email,u.role,u.actif AS active,u.doit_changer_mdp,u.cree_le AS created_at,e.id AS employee_id,e.nom AS employee_last,e.prenom AS employee_first,e.telephone,e.poste,e.date_embauche,e.salaire_mensuel,c.id AS client_id,c.nom AS client_nom,c.prenom AS client_prenom FROM utilisateurs u LEFT JOIN employes e ON e.utilisateur_id=u.id LEFT JOIN clients c ON c.utilisateur_id=u.id ORDER BY u.id LIMIT 500')->fetchAll();
$employeeSalaryRows=$isAdmin?$pdo->query('SELECT e.id,e.utilisateur_id,e.nom,e.prenom,e.poste,e.salaire_mensuel,e.actif,u.email FROM employes e LEFT JOIN utilisateurs u ON u.id=e.utilisateur_id ORDER BY e.actif DESC,e.nom,e.prenom,e.id')->fetchAll():[];
if(!$isAdmin)$rows=array_values(array_filter($rows,static fn($row)=>in_array($row['role'],$allowedByManager,true)&&!is_protected_account($row['email'])));
$auditRows=$isAdmin?$pdo->query('SELECT a.*,u.nom AS auteur_nom FROM gestion_comptes_audit a LEFT JOIN utilisateurs u ON u.id=a.auteur_id ORDER BY a.id DESC LIMIT 30')->fetchAll():[];
require 'includes/header.php';
?>
<div class="admin-page-heading"><div><p class="eyebrow">ACCÈS & ÉQUIPE</p><h2><?=e($isAdmin?'Personnel et comptes':'Suspension des comptes')?></h2></div><span class="badge"><?=count($rows)?> comptes</span></div>
<?php if($isAdmin):?><div class="panel"><h2>Créer un membre du personnel</h2><form method="post" class="form-grid"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="action" value="create"><div class="field"><label for="firstName">Prénom</label><input id="firstName" name="prenom" maxlength="120" required></div><div class="field"><label for="lastName">Nom</label><input id="lastName" name="nom" maxlength="120" required></div><div class="field"><label for="staffEmail">E-mail</label><input id="staffEmail" type="email" name="email" maxlength="160" required></div><div class="field"><label for="staffPhone">Téléphone</label><input id="staffPhone" name="telephone" maxlength="30"></div><div class="field"><label for="staffRole">Rôle applicatif</label><select id="staffRole" name="role" required><option value="responsable">Responsable</option><option value="accueil">Accueil / Réception</option><option value="caissier">Caissier</option><option value="production">Production</option><option value="livreur">Livreur</option></select></div><div class="field"><label for="salary">Salaire mensuel en FCFA (XAF)</label><input id="salary" type="number" name="salaire_mensuel" min="0" step="1" placeholder="Montant mensuel" required></div><div class="field"><label for="hireDate">Date d’embauche</label><input id="hireDate" type="date" name="date_embauche"></div><div class="field"><label for="initialPassword">Mot de passe initial</label><input id="initialPassword" type="password" name="password" minlength="10" autocomplete="new-password" required></div><div class="field"><label for="initialPasswordConfirm">Confirmation</label><input id="initialPasswordConfirm" type="password" name="confirmation" minlength="10" autocomplete="new-password" required></div><div class="field"><label><input type="checkbox" name="actif" value="1" checked style="width:auto"> Compte actif</label></div><div class="field full"><button class="btn">Créer le membre</button></div></form></div><?php endif;?>
<div class="panel"><div class="panel-head"><h2>Comptes existants</h2><input class="search" data-filter="#users" placeholder="Rechercher un compte..."></div><div class="table-wrap"><table id="users"><thead><tr><th>Nom</th><th>E-mail</th><th>Rôle</th><?php if($isAdmin):?><th>Fiche / salaire mensuel</th><?php endif;?><th>État</th><th>Actions</th></tr></thead><tbody><?php foreach($rows as $row):$protected=is_protected_account($row['email']);$canSuspend=$row['active']&&!$protected&&(int)$row['id']!==(int)$_SESSION['user']['id']&&($isAdmin||($row['role']!=='admin'&&in_array($row['role'],$allowedByManager,true)));?><tr><td><?=e($row['name'])?></td><td><?=e($row['email'])?></td><td><?=e(role_label($row['role']))?></td><?php if($isAdmin):?><td><?=e(trim(($row['employee_first']??'').' '.($row['employee_last']??''))?:trim(($row['client_prenom']??'').' '.($row['client_nom']??''))?:'—')?><?php if($row['employee_id']):?><br><small><?=(float)$row['salaire_mensuel']>0?money($row['salaire_mensuel']).' / mois':'Salaire à renseigner'?></small><?php endif;?></td><?php endif;?><td><span class="badge <?=$row['active']?'pret':'annule'?>"><?=$row['active']?'Actif':'Suspendu'?></span><?=$row['doit_changer_mdp']?'<br><small>Changement du mot de passe requis</small>':''?></td><td><div class="actions"><?php if($canSuspend):?><form method="post"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="action" value="suspend"><input type="hidden" name="user_id" value="<?=(int)$row['id']?>"><input name="reason" maxlength="500" required placeholder="Motif de suspension"><button class="btn red small" data-confirm="Confirmer la suspension ?">Suspendre</button></form><?php elseif(!$row['active']&&$isAdmin):?><form method="post"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="action" value="reactivate"><input type="hidden" name="user_id" value="<?=(int)$row['id']?>"><input name="reason" maxlength="500" required placeholder="Motif de réactivation"><button class="btn green small" data-confirm="Confirmer la réactivation ?">Réactiver</button></form><?php endif;?><?php if($isAdmin&&$row['employee_id']&&$row['role']!=='admin'):?><details><summary>Gérer</summary><div class="panel"><form method="post" class="form-grid"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="action" value="update_profile"><input type="hidden" name="user_id" value="<?=(int)$row['id']?>"><div class="field"><label>Prénom</label><input name="prenom" maxlength="120" value="<?=e($row['employee_first'])?>" required></div><div class="field"><label>Nom</label><input name="nom" maxlength="120" value="<?=e($row['employee_last'])?>" required></div><div class="field"><label>E-mail</label><input type="email" name="email" maxlength="160" value="<?=e($row['email'])?>" required></div><div class="field"><label>Téléphone</label><input name="telephone" maxlength="30" value="<?=e($row['telephone'])?>"></div><div class="field"><label>Rôle applicatif</label><select name="role" required><?php foreach($staffRoles as $staffRole):?><option value="<?=e($staffRole)?>" <?=$row['role']===$staffRole?'selected':''?>><?=e(role_label($staffRole))?></option><?php endforeach;?></select></div><div class="field"><label>Salaire mensuel en FCFA (XAF)</label><input type="number" min="0" step="1" name="salaire_mensuel" value="<?=((float)$row['salaire_mensuel']>0?e($row['salaire_mensuel']):'')?>" required></div><div class="field"><label>Date d’embauche</label><input type="date" name="date_embauche" value="<?=e($row['date_embauche'])?>"></div><div class="field full"><label>Motif de modification</label><input name="reason" maxlength="500" required></div><div class="field full"><button class="btn">Enregistrer la fiche</button></div></form><?php if(!$protected):?><form method="post" class="form-grid"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="action" value="reset_password"><input type="hidden" name="user_id" value="<?=(int)$row['id']?>"><div class="field"><label>Nouveau mot de passe initial</label><input type="password" name="password" minlength="10" autocomplete="new-password" required></div><div class="field"><label>Confirmation</label><input type="password" name="confirmation" minlength="10" autocomplete="new-password" required></div><div class="field full"><label>Motif de réinitialisation</label><input name="reason" maxlength="500" required></div><div class="field full"><button class="btn light">Réinitialiser et imposer le changement</button></div></form><?php endif;?><form method="post"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="action" value="delete"><input type="hidden" name="user_id" value="<?=(int)$row['id']?>"><div class="field"><label>Motif de demande de suppression / archivage</label><input name="reason" maxlength="500" required></div><label><input type="checkbox" name="confirm_delete" value="yes" required style="width:auto"> Je confirme cette demande</label><button class="btn red" data-confirm="La fiche sera supprimée uniquement sans dépendance. Sinon l’accès sera retiré et la fiche archivée. Continuer ?">Demander la suppression</button></form></div></details><?php endif;?></div></td></tr><?php endforeach;?><?php if(!$rows):?><tr><td colspan="<?= $isAdmin ? 6 : 5 ?>" class="empty">Aucun compte enregistré.</td></tr><?php endif;?></tbody></table></div></div>
<?php if($isAdmin):?><div class="panel"><h2>Historique des actions sur les comptes</h2><div class="table-wrap"><table><thead><tr><th>Date</th><th>Auteur</th><th>Cible</th><th>Action</th><th>Motif</th></tr></thead><tbody><?php foreach($auditRows as $audit):?><tr><td><?=e($audit['date_action'])?></td><td><?=e($audit['auteur_nom']??'Compte archivé')?></td><td><?=e($audit['cible_email'])?></td><td><?=e($audit['action'])?></td><td><?=e($audit['motif'])?></td></tr><?php endforeach;?><?php if(!$auditRows):?><tr><td colspan="5" class="empty">Aucune action enregistrée.</td></tr><?php endif;?></tbody></table></div></div><?php endif;?>
<?php if($isAdmin):?><div class="panel"><h2>Salaires mensuels du personnel</h2><p>Montants en FCFA (XAF). Les fiches sans montant restent à renseigner.</p><div class="table-wrap"><table><thead><tr><th>Employé</th><th>Compte</th><th>Poste</th><th>État</th><th>Salaire mensuel</th><th>Action</th></tr></thead><tbody><?php foreach($employeeSalaryRows as $employee):?><tr><td><?=e(trim(($employee['prenom']??'').' '.$employee['nom']))?></td><td><?=e($employee['email']??'Sans compte lié')?></td><td><?=e($employee['poste'])?></td><td><?=!empty($employee['actif'])?'Actif':'Suspendu'?></td><td><?=((float)$employee['salaire_mensuel']>0?money($employee['salaire_mensuel']):'À renseigner')?></td><td><form method="post" class="actions"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="action" value="update_employee_salary"><input type="hidden" name="employee_id" value="<?=(int)$employee['id']?>"><input type="number" name="salaire_mensuel" min="0" step="1" value="<?=((float)$employee['salaire_mensuel']>0?e($employee['salaire_mensuel']):'')?>" placeholder="FCFA / mois" required><input name="reason" maxlength="500" placeholder="Motif" required><button class="btn small">Enregistrer</button></form></td></tr><?php endforeach;?><?php if(!$employeeSalaryRows):?><tr><td colspan="6" class="empty">Aucune fiche employé.</td></tr><?php endif;?></tbody></table></div></div><?php endif;?>
<?php require 'includes/footer.php';?>
