$ErrorActionPreference='Stop'
$mysql='C:\xampp\mysql\bin\mysql.exe'
$dumpExe='C:\xampp\mysql\bin\mysqldump.exe'
$config='C:\xampp\htdocs\Pressa\config\config.php'
$dump=Join-Path $env:TEMP 'pressa_delivery_qa_dump.sql'
$adminCookies=Join-Path $env:TEMP 'pressa_delivery_admin_cookies.txt'
$driverCookies=Join-Path $env:TEMP 'pressa_delivery_driver_cookies.txt'
$adminPage=Join-Path $env:TEMP 'pressa_delivery_admin.html'
$driverPage=Join-Path $env:TEMP 'pressa_delivery_driver.html'
$originalConfig=[IO.File]::ReadAllText($config)
$base='http://localhost/Pressa/'
$checks=[System.Collections.Generic.List[string]]::new()
$driverEmail='qa-driver-'+[Guid]::NewGuid().ToString('N')+'@example.test'
$driverPassword=[Guid]::NewGuid().ToString('N')
function Record($name,$ok,$detail){$state=if($ok){'OK'}else{'FAIL'};$line=$state+' '+$name+' '+$detail;$checks.Add($line);Write-Output $line;if(-not $ok){throw $line}}
function Sql($query){$result=& $mysql -uroot -N -B pressa_test -e $query;if($LASTEXITCODE -ne 0){throw 'SQL QA failed'};return (($result -join "`n").Trim())}
function Page($path,$jar,$out){$code=& curl.exe -b $jar -c $jar -s -o $out -w '%{http_code}' ($base+$path);if($LASTEXITCODE -ne 0){throw "GET failed: $path"};return (($code -join '').Trim())}
function Post($path,$jar,$fields){$curlArgs=@('-b',$jar,'-c',$jar,'-s','-o','NUL','-w','%{http_code}|%{redirect_url}');foreach($item in $fields){$curlArgs+=@('--data-urlencode',$item)};$answer=& curl.exe @curlArgs ($base+$path);if($LASTEXITCODE -ne 0){throw "POST failed: $path"};return (($answer -join '').Trim())}
function Csrf($file){$html=[IO.File]::ReadAllText($file);$m=[regex]::Match($html,'name="csrf"\s+value="([^"]+)"');if(!$m.Success){throw "CSRF not found in $file"};return $m.Groups[1].Value}
try{
  & $dumpExe '--user=root' '--single-transaction' '--routines' '--triggers' '--events' "--result-file=$dump" 'pressa';if($LASTEXITCODE -ne 0){throw 'Database dump failed'}
  & $mysql -uroot -e 'DROP DATABASE IF EXISTS pressa_test; CREATE DATABASE pressa_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci';if($LASTEXITCODE -ne 0){throw 'Temporary database creation failed'}
  $source=$dump.Replace('\','/');& $mysql -uroot pressa_test -e "source $source";if($LASTEXITCODE -ne 0){throw 'Temporary database restore failed'}
  $changed=$originalConfig.Replace("define('DB_NAME', 'pressa')","define('DB_NAME', 'pressa_test')");if($changed -eq $originalConfig){throw 'Could not switch config to temporary database'}
  [IO.File]::WriteAllText($config,$changed,(New-Object System.Text.UTF8Encoding($false)))
  $code=Page 'login.php' $adminCookies $adminPage;$csrf=Csrf $adminPage
  $login=Post 'login.php' $adminCookies @("csrf=$csrf","email=$env:PRESSA_TEST_EMAIL","password=$env:PRESSA_TEST_PASS")
  Record 'Admin login' ($login -like '302|*dashboard.php') $login
  foreach($path in @('dashboard.php','clients.php','orders.php','production.php','invoices.php','messages.php','users.php','services.php','stock.php','suppliers.php','purchases.php','maintenance.php','expenses.php','livreur.php','order_new.php')){$code=Page $path $adminCookies $adminPage;Record "Admin GET $path" ($code -eq '200') "HTTP $code"}
  $csrf=Csrf $adminPage
  $clientCsrf=$csrf
  $clientResult=Post 'clients.php' $adminCookies @("csrf=$clientCsrf",'nom=V4 Livraison QA','prenom=Client','telephone=600000099','email=client-qa@example.test','adresse=12 Rue de test')
  Record 'Create client with address' ($clientResult -like '302|*clients.php') $clientResult
  $clientId=[int](Sql "SELECT id FROM clients WHERE email='client-qa@example.test' ORDER BY id DESC LIMIT 1")
  $code=Page 'users.php' $adminCookies $adminPage;$csrf=Csrf $adminPage
  $userResult=Post 'users.php' $adminCookies @("csrf=$csrf",'name=QA Livreur',"email=$driverEmail","password=$driverPassword",'role=livreur')
  Record 'Create driver account' ($userResult -like '302|*users.php') $userResult
  $driverId=[int](Sql "SELECT id FROM utilisateurs WHERE email='$driverEmail' AND role='livreur' LIMIT 1")
  $employeeId=[int](Sql "SELECT id FROM employes WHERE utilisateur_id=$driverId AND poste='livreur' AND actif=1 LIMIT 1")
  Record 'Employee profile linked to account' ($driverId -gt 0 -and $employeeId -gt 0) "user=$driverId employee=$employeeId"
  $tariffId=[int](Sql 'SELECT id FROM tarifs ORDER BY id LIMIT 1')
  $date=(Get-Date).AddDays(2).ToString('yyyy-MM-dd')
  $code=Page 'order_new.php' $adminCookies $adminPage;$csrf=Csrf $adminPage
  $orderResult=Post 'order_new.php' $adminCookies @("csrf=$csrf","client_id=$clientId",'type_depot=normal','mode_remise=livraison','adresse_livraison=12 Rue de test',"date_prevue=$date",'notes=QA delivery',"tarif_id[]=$tariffId",'quantite[]=1','description[]=Article QA')
  Record 'Create delivery order and course' ($orderResult -like '302|*order_view.php*') $orderResult
  $orderId=[int](Sql "SELECT id FROM commandes WHERE client_id=$clientId ORDER BY id DESC LIMIT 1")
  $courseId=[int](Sql "SELECT id FROM courses WHERE commande_id=$orderId AND type='livraison' LIMIT 1")
  Record 'Delivery mode creates course' ($courseId -gt 0) "course=$courseId order=$orderId"
  $code=Page 'production.php' $adminCookies $adminPage;$csrf=Csrf $adminPage
  $readyResult=Post 'production.php' $adminCookies @("csrf=$csrf","id=$orderId",'statut=pret')
  Record 'Set order ready' ($readyResult -like '302|*production.php') $readyResult
  $amount=Sql "SELECT total FROM commandes WHERE id=$orderId"
  $code=Page "order_view.php?id=$orderId" $adminCookies $adminPage;$csrf=Csrf $adminPage
  $payResult=Post "order_view.php?id=$orderId" $adminCookies @("csrf=$csrf",'pay=1',"montant=$amount",'mode=especes','reference=delivery-qa')
  Record 'Pay delivery order in full' ($payResult -like '302|*order_view.php*') $payResult
  $code=Page 'livreur.php' $adminCookies $adminPage;$csrf=Csrf $adminPage
  $assignResult=Post 'livreur.php' $adminCookies @("csrf=$csrf",'action=assign',"course_id=$courseId","livreur_id=$employeeId","date_prevue=$date",'creneau=matin','adresse=12 Rue de test')
  Record 'Admin assigns course' ($assignResult -like '302|*livreur.php') $assignResult
  $code=Page 'login.php' $driverCookies $driverPage;$csrf=Csrf $driverPage
  $driverLogin=Post 'login.php' $driverCookies @("csrf=$csrf","email=$driverEmail","password=$driverPassword")
  Record 'Driver login routes to courier space' ($driverLogin -like '302|*livreur.php') $driverLogin
  $forbiddenTarget=Page 'dashboard.php' $driverCookies $driverPage
  Record 'Driver restricted from admin pages' ($forbiddenTarget -eq '302') "HTTP $forbiddenTarget"
  $code=Page 'livreur.php' $driverCookies $driverPage
  $html=[IO.File]::ReadAllText($driverPage)
  Record 'Assigned delivery visible to driver' ($code -eq '200' -and $html.Contains('12 Rue de test') -and $html.Contains('PR-')) "HTTP $code"
  $csrf=Csrf $driverPage
  $startResult=Post 'livreur.php' $driverCookies @("csrf=$csrf",'action=start',"course_id=$courseId")
  Record 'Driver starts assigned course' ($startResult -like '302|*livreur.php') $startResult
  $status=Sql "SELECT statut FROM courses WHERE id=$courseId"
  Record 'Course state becomes in progress' ($status -eq 'en_cours') $status
  $code=Page 'livreur.php' $driverCookies $driverPage;$csrf=Csrf $driverPage
  $completeResult=Post 'livreur.php' $driverCookies @("csrf=$csrf",'action=complete',"course_id=$courseId")
  Record 'Driver confirms delivery' ($completeResult -like '302|*livreur.php') $completeResult
  $courseStatus=Sql "SELECT statut FROM courses WHERE id=$courseId"
  $orderStatus=Sql "SELECT statut FROM commandes WHERE id=$orderId"
  Record 'Delivered course closes order' ($courseStatus -eq 'effectuee' -and $orderStatus -eq 'retire') "course=$courseStatus order=$orderStatus"
  Write-Output ('TOTAL checks='+$checks.Count+' all passed')
}
finally{
  [IO.File]::WriteAllText($config,$originalConfig,(New-Object System.Text.UTF8Encoding($false)))
  Remove-Item $adminCookies,$driverCookies,$adminPage,$driverPage,$dump -ErrorAction SilentlyContinue
  & $mysql -uroot -e 'DROP DATABASE IF EXISTS pressa_test' 2>$null
  $env:PRESSA_TEST_EMAIL=$null;$env:PRESSA_TEST_PASS=$null
}
