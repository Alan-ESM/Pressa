$ErrorActionPreference='Stop'
$mysql='C:\xampp\mysql\bin\mysql.exe'
$dumpExe='C:\xampp\mysql\bin\mysqldump.exe'
$config='C:\xampp\htdocs\Pressa\config\config.php'
$dump=Join-Path $env:TEMP 'pressa_qa_dump.sql'
$cookies=Join-Path $env:TEMP 'pressa_qa_cookies.txt'
$login=Join-Path $env:TEMP 'pressa_qa_login.html'
$page=Join-Path $env:TEMP 'pressa_qa_page.html'
$originalConfig=[IO.File]::ReadAllText($config)
$results=[System.Collections.Generic.List[string]]::new()
function Sql($query){$value=& $mysql -uroot -N -B pressa_test -e $query;if($LASTEXITCODE -ne 0){throw 'Échec de la requête SQL QA'};return (($value -join "`n").Trim())}
function Post($path,$fields){$curlArgs=@('-b',$cookies,'-c',$cookies,'-s','-o','NUL','-w','%{http_code} %{redirect_url}');foreach($field in $fields){$curlArgs+=@('--data-urlencode',$field)};$result=& curl.exe @curlArgs ("http://localhost/Pressa/"+$path);if($LASTEXITCODE -ne 0){throw "Échec curl POST $path"};return (($result -join '').Trim())}
function Record($name,$ok,$detail){$state=if($ok){'OK'}else{'ÉCHEC'};$entry="$state $name $detail";$results.Add($entry);Write-Output $entry;if(-not $ok){throw $entry}}
try{
  & $dumpExe '--user=root' '--single-transaction' '--routines' '--triggers' '--events' "--result-file=$dump" 'pressa'
  if($LASTEXITCODE -ne 0){throw 'Échec de la copie SQL temporaire'}
  & $mysql -uroot -e 'DROP DATABASE IF EXISTS pressa_test; CREATE DATABASE pressa_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'
  if($LASTEXITCODE -ne 0){throw 'Impossible de créer la base QA'}
  $source=$dump.Replace('\','/')
  & $mysql -uroot pressa_test -e "source $source"
  if($LASTEXITCODE -ne 0){throw 'Impossible de restaurer la copie SQL QA'}
  $changed=$originalConfig.Replace("define('DB_NAME', 'pressa')","define('DB_NAME', 'pressa_test')")
  if($changed -eq $originalConfig){throw 'DB_NAME pressa non trouvé pour le basculement temporaire'}
  [IO.File]::WriteAllText($config,$changed,(New-Object System.Text.UTF8Encoding($false)))
  & curl.exe -c $cookies -s 'http://localhost/Pressa/login.php' -o $login
  $match=Select-String -Path $login -Pattern 'name="csrf" value="([^"]+)"'|Select-Object -First 1
  if(-not $match){throw 'CSRF login absent en QA'}
  $csrf=[regex]::Match($match.Line,'name="csrf" value="([^"]+)"').Groups[1].Value
  $auth=& curl.exe -b $cookies -c $cookies -s -o NUL -w '%{http_code} %{redirect_url}' -d "csrf=$csrf&email=$env:PRESSA_TEST_EMAIL&password=$env:PRESSA_TEST_PASS" 'http://localhost/Pressa/login.php'
  Record 'Connexion session QA' (($auth -like '302 *dashboard.php')) $auth
  $today=Get-Date -Format 'yyyy-MM-dd'
  $r=Post 'clients.php' @("csrf=$csrf",'nom=V4 Client Temp','prenom=QA','telephone=600000001','email=','adresse=Test')
  Record 'Création client' ($r -like '302 *clients.php') $r
  $clientId=[int](Sql "SELECT id FROM clients WHERE nom='V4 Client Temp' ORDER BY id DESC LIMIT 1")
  $r=Post 'services.php' @("csrf=$csrf",'nom=Service V4 Temp','prix=1000','cout_estime=250','description=Essai fonctionnel')
  Record 'Création service' ($r -like '302 *services.php') $r
  $serviceId=[int](Sql "SELECT id FROM services WHERE nom='Service V4 Temp' ORDER BY id DESC LIMIT 1")
  $activeTypes=[int](Sql 'SELECT COUNT(*) FROM types_articles WHERE actif=1')
  $createdTariffs=[int](Sql "SELECT COUNT(*) FROM tarifs t JOIN types_articles ta ON ta.id=t.type_article_id AND ta.actif=1 WHERE t.service_id=$serviceId")
  Record 'Tarifs créés par type actif' ($createdTariffs -eq $activeTypes) "$createdTariffs/$activeTypes"
  $tariffId=[int](Sql "SELECT t.id FROM tarifs t JOIN types_articles ta ON ta.id=t.type_article_id WHERE t.service_id=$serviceId AND ta.nom='Chemise' ORDER BY t.date_effet DESC LIMIT 1")
  $r=Post 'order_new.php' @("csrf=$csrf","client_id=$clientId",'type_depot=express',"date_prevue=$today",'notes=V4 fonctionnel',"tarif_id[]=$tariffId",'quantite[]=1','description[]=Chemise QA 1',"tarif_id[]=$tariffId",'quantite[]=1','description[]=Chemise QA 2')
  Record 'Création commande express à deux lignes' ($r -like '302 *order_view.php*') $r
  $orderId=[int](Sql "SELECT id FROM commandes WHERE client_id=$clientId ORDER BY id DESC LIMIT 1")
  $orderFields=(Sql "SELECT sous_total,surcharge_express,total FROM commandes WHERE id=$orderId") -split "`t"
  $sub=[decimal]::Parse($orderFields[0],[Globalization.CultureInfo]::InvariantCulture)
  $surcharge=[decimal]::Parse($orderFields[1],[Globalization.CultureInfo]::InvariantCulture)
  $total=[decimal]::Parse($orderFields[2],[Globalization.CultureInfo]::InvariantCulture)
  $expected=[math]::Round([double]($sub*0.30),0,[MidpointRounding]::AwayFromZero)
  Record 'Total express = sous-total + 30 %' (($total -eq ($sub+$surcharge)) -and ([math]::Abs([double]$surcharge-$expected) -lt 0.01)) "sous_total=$sub surcharge=$surcharge total=$total"
  $r=Post "order_view.php?id=$orderId" @("csrf=$csrf",'pay=1','montant=100','mode=especes','reference=V4')
  Record 'Paiement partiel' ($r -like '302 *order_view.php*') $r
  $r=Post "order_view.php?id=$orderId" @("csrf=$csrf",'pay=1','montant=999999','mode=especes','reference=V4-oversolde')
  $paymentFields=(Sql "SELECT COUNT(*),COALESCE(SUM(montant),0) FROM paiements WHERE commande_id=$orderId") -split "`t"
  Record 'Paiement supérieur au solde refusé' (($r -like '302 *order_view.php*') -and [int]$paymentFields[0] -eq 1 -and [decimal]$paymentFields[1] -eq 100) $r
  $r=Post 'production.php' @("csrf=$csrf","id=$orderId",'statut=pret')
  Record 'Commande passée en prêt' ($r -like '302 *production.php') $r
  $r=Post "order_view.php?id=$orderId" @("csrf=$csrf",'retire=1')
  $status=Sql "SELECT statut FROM commandes WHERE id=$orderId"
  Record 'Retrait refusé solde impayé' (($r -like '302 *order_view.php*') -and $status -eq 'pret') $status
  $r=Post 'messages.php' @("csrf=$csrf","client_id=$clientId","order_id=$orderId",'message=Essai communication V4')
  $messageCount=[int](Sql "SELECT COUNT(*) FROM communications WHERE client_id=$clientId AND contenu='Essai communication V4'")
  Record 'Message enregistré dans communications' (($r -like '302 *messages.php') -and $messageCount -eq 1) $messageCount
  $stockId=1
  $startStock=[decimal](Sql "SELECT quantite_stock FROM produits_stock WHERE id=$stockId")
  $r=Post 'stock.php' @("csrf=$csrf",'action=movement',"product_id=$stockId",'type=entree','quantite=10','motif=V4 entrée')
  Record 'Entrée stock' ($r -like '302 *stock.php') $r
  $r=Post 'stock.php' @("csrf=$csrf",'action=movement',"product_id=$stockId",'type=sortie','quantite=4','motif=V4 sortie')
  Record 'Sortie stock' ($r -like '302 *stock.php') $r
  $r=Post 'stock.php' @("csrf=$csrf",'action=movement',"product_id=$stockId",'type=sortie','quantite=10000','motif=V4 excès')
  $midStock=[decimal](Sql "SELECT quantite_stock FROM produits_stock WHERE id=$stockId")
  Record 'Sortie supérieure au stock refusée' (($r -like '302 *stock.php') -and $midStock -eq ($startStock+6)) "$r stock=$midStock"
  $r=Post 'stock.php' @("csrf=$csrf",'action=movement',"product_id=$stockId",'type=sortie','quantite=6','motif=V4 restauration')
  $restored=[decimal](Sql "SELECT quantite_stock FROM produits_stock WHERE id=$stockId")
  Record 'Stock restauré après test' (($r -like '302 *stock.php') -and $restored -eq $startStock) $restored
  $r=Post 'suppliers.php' @("csrf=$csrf",'nom=Fournisseur V4 Temp','telephone=600000002','adresse=QA','email=')
  Record 'Création fournisseur' ($r -like '302 *suppliers.php') $r
  $supplierId=[int](Sql "SELECT id FROM fournisseurs WHERE nom='Fournisseur V4 Temp' ORDER BY id DESC LIMIT 1")
  $r=Post 'purchases.php' @("csrf=$csrf",'action=create',"supplier_id=$supplierId","product_id[]=$stockId",'product_id[]=0','product_id[]=0','product_id[]=0','quantite[]=2','quantite[]=0','quantite[]=0','quantite[]=0','prix_achat[]=100','prix_achat[]=0','prix_achat[]=0','prix_achat[]=0')
  Record 'Création bon achat' ($r -like '302 *purchases.php') $r
  $purchaseId=[int](Sql "SELECT id FROM bons_achat WHERE fournisseur_id=$supplierId ORDER BY id DESC LIMIT 1")
  $beforeReceipt=[decimal](Sql "SELECT quantite_stock FROM produits_stock WHERE id=$stockId")
  $r=Post 'purchases.php' @("csrf=$csrf",'action=receive',"id=$purchaseId")
  $received=[decimal](Sql "SELECT quantite_stock FROM produits_stock WHERE id=$stockId")
  $lineReceived=[decimal](Sql "SELECT quantite_recue FROM bons_achat_lignes WHERE bon_id=$purchaseId LIMIT 1")
  Record 'Réception bon augmente le stock une fois' (($r -like '302 *purchases.php') -and $received -eq ($beforeReceipt+2) -and $lineReceived -eq 2) "stock=$beforeReceipt->$received reçu=$lineReceived"
  $r=Post 'purchases.php' @("csrf=$csrf",'action=receive',"id=$purchaseId")
  $receivedAgain=[decimal](Sql "SELECT quantite_stock FROM produits_stock WHERE id=$stockId")
  Record 'Double réception sans double stock' (($r -like '302 *purchases.php') -and $receivedAgain -eq $received) $receivedAgain
  $r=Post 'maintenance.php' @("csrf=$csrf",'action=equipment','designation=Equipement V4 Temp','date_acquisition=','etat=en_service','fournisseur_id=')
  Record 'Création équipement' ($r -like '302 *maintenance.php') $r
  $equipmentId=[int](Sql "SELECT id FROM equipements WHERE designation='Equipement V4 Temp' ORDER BY id DESC LIMIT 1")
  $r=Post 'maintenance.php' @("csrf=$csrf",'action=intervention',"equipment_id=$equipmentId",'type=corrective',"date_intervention=$today",'duree_arret=5','cout=100','en_panne=1')
  $equipmentState=Sql "SELECT etat FROM equipements WHERE id=$equipmentId"
  $interventionCount=[int](Sql "SELECT COUNT(*) FROM interventions WHERE equipement_id=$equipmentId")
  Record 'Intervention et passage en panne' (($r -like '302 *maintenance.php') -and $equipmentState -eq 'en_panne' -and $interventionCount -eq 1) $equipmentState
  $r=Post 'expenses.php' @("csrf=$csrf","date_depense=$today",'categorie=maintenance','montant=25','justificatif=V4','commentaire=Essai V4')
  $expenseCount=[int](Sql "SELECT COUNT(*) FROM depenses WHERE categorie='maintenance' AND commentaire='Essai V4'")
  Record 'Dépense enregistrée' (($r -like '302 *expenses.php') -and $expenseCount -eq 1) $expenseCount
  $dashboardCode=& curl.exe -b $cookies -s -o $page -w '%{http_code}' 'http://localhost/Pressa/dashboard.php'
  $dashboardErrors=Select-String -Path $page -CaseSensitive -Pattern 'Fatal error|Warning|Notice|SQLSTATE|Unknown column|doesn''t exist'
  Record 'Tableau de bord après actions' (($dashboardCode -eq '200') -and -not $dashboardErrors) "HTTP $dashboardCode"
  $results | ForEach-Object { Write-Output $_ }
}
finally{
  [IO.File]::WriteAllText($config,$originalConfig,(New-Object System.Text.UTF8Encoding($false)))
  Remove-Item $cookies,$login,$page,$dump -ErrorAction SilentlyContinue
  & $mysql -uroot -e 'DROP DATABASE IF EXISTS pressa_test' 2>$null
  $env:PRESSA_TEST_EMAIL=$null
  $env:PRESSA_TEST_PASS=$null
}
