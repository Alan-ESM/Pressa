(()=>{
'use strict';
const root=document.getElementById('authLoadingRoot');
if(!root)return;
const hide=()=>{root.classList.add('is-hidden');root.setAttribute('aria-hidden','true');window.setTimeout(()=>root.remove(),400)};
// Keep sign-in usable even when the React CDN cannot be reached.
const fallback=window.setTimeout(hide,2600);
if(!window.React||!window.ReactDOM)return;
function AuthLoading(){React.useEffect(()=>{const timer=window.setTimeout(()=>{window.clearTimeout(fallback);hide()},850);return()=>window.clearTimeout(timer)},[]);return React.createElement('div',{className:'auth-loading',role:'status','aria-live':'polite'},React.createElement('span',{className:'auth-spinner','aria-hidden':'true'}),React.createElement('span',null,'Préparation de votre espace…'))}
ReactDOM.createRoot(root).render(React.createElement(AuthLoading));
})();