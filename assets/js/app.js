(()=>{
'use strict';
document.querySelectorAll('[data-confirm]').forEach(el=>el.addEventListener('click',e=>{if(!confirm(el.dataset.confirm))e.preventDefault()}));
document.querySelectorAll('[data-filter]').forEach(input=>input.addEventListener('input',()=>{const q=input.value.toLowerCase();document.querySelectorAll(input.dataset.filter+' tbody tr').forEach(r=>r.hidden=!r.innerText.toLowerCase().includes(q))}));
const themeButton=document.querySelector('[data-theme-toggle]');
function setTheme(theme){theme=theme==='dark'?'dark':'light';document.documentElement.dataset.theme=theme;try{localStorage.setItem('pressa-theme',theme)}catch(e){}if(themeButton){const dark=theme==='dark';const english=localStorage.getItem('pressa-language')==='en';themeButton.textContent=dark?'☼':'◐';themeButton.setAttribute('aria-label',dark?(english?'Enable light theme':'Activer le thème clair'):(english?'Enable dark theme':'Activer le thème sombre'));themeButton.title=dark?(english?'Light theme':'Thème clair'):(english?'Dark theme':'Thème sombre');}}
setTheme(document.documentElement.dataset.theme||'light');
if(themeButton)themeButton.addEventListener('click',()=>setTheme(document.documentElement.dataset.theme==='dark'?'light':'dark'));
const toggle=document.querySelector('[data-sidebar-toggle]');const backdrop=document.querySelector('[data-sidebar-backdrop]');
function closeMenu(){document.body.classList.remove('nav-open');if(toggle)toggle.setAttribute('aria-expanded','false')}
if(toggle)toggle.addEventListener('click',()=>{const open=!document.body.classList.contains('nav-open');document.body.classList.toggle('nav-open',open);toggle.setAttribute('aria-expanded',String(open))});
if(backdrop)backdrop.addEventListener('click',closeMenu);
document.querySelectorAll('.sidebar nav a,.sidebar .logout').forEach(link=>link.addEventListener('click',closeMenu));
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeMenu()});
const mode=document.querySelector('[data-delivery-mode]');const addressWrap=document.querySelector('[data-delivery-address]');const addressInput=addressWrap?.querySelector('input');const clientSelect=document.querySelector('[name=client_id]');
function updateDeliveryField(){if(!mode||!addressWrap)return;const delivery=mode.value==='livraison';addressWrap.hidden=!delivery;const selected=clientSelect?.selectedOptions?.[0];if(delivery&&addressInput&&selected&&!addressInput.dataset.manual){addressInput.value=selected.dataset.address||'';}if(addressInput)addressInput.required=delivery&&!(selected?.dataset.address||addressInput.value.trim());}
if(mode){mode.addEventListener('change',updateDeliveryField);updateDeliveryField();}
if(clientSelect)clientSelect.addEventListener('change',()=>{if(addressInput)delete addressInput.dataset.manual;updateDeliveryField()});
if(addressInput)addressInput.addEventListener('input',()=>{addressInput.dataset.manual='1';if(mode?.value==='livraison')addressInput.required=!addressInput.value.trim()});
})();
