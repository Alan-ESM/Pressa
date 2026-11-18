document.querySelectorAll('[data-confirm]').forEach(el=>el.addEventListener('click',e=>{if(!confirm(el.dataset.confirm))e.preventDefault()}));
document.querySelectorAll('[data-filter]').forEach(input=>input.addEventListener('input',()=>{const q=input.value.toLowerCase();document.querySelectorAll(input.dataset.filter+' tbody tr').forEach(r=>r.hidden=!r.innerText.toLowerCase().includes(q));}));
