(()=>{
'use strict';
const button=document.querySelector('[data-locate-driver]');
const mapElement=document.getElementById('courierMap');
if(!button||!mapElement||!window.L)return;
const status=document.querySelector('[data-location-status]');
const map=L.map(mapElement).setView([4.05,9.7],6);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'&copy; OpenStreetMap'}).addTo(map);
let marker;
button.addEventListener('click',()=>{
 if(!navigator.geolocation){status.textContent='La géolocalisation n’est pas disponible sur cet appareil.';return;}
 status.textContent='Recherche de votre position…';
 navigator.geolocation.getCurrentPosition(({coords})=>{
  const point=[coords.latitude,coords.longitude];map.setView(point,15);if(marker)marker.setLatLng(point);else marker=L.marker(point).addTo(map);
  marker.bindPopup('Votre position').openPopup();status.textContent='Votre position est affichée sur la carte.';
 },()=>{status.textContent='Position indisponible. Autorisez la localisation et vérifiez la connexion.';},{enableHighAccuracy:true,timeout:12000,maximumAge:60000});
});
})();
