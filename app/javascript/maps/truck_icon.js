// app/javascript/maps/truck_icon.js
// Camioncito (vista lateral) en círculo de marca — mismo ícono del enlace
// público de tracking, reemplaza flechas/símbolos por defecto de Google Maps
// en los mapas de seguimiento en vivo (admin y flota).
export const TRUCK_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 44 44"><circle cx="22" cy="22" r="20" fill="#43322a" stroke="#fff" stroke-width="3"/><path fill="#fdf5ea" d="M10 15h14v11H10zM25 19h5l3 4v3h-8z"/><circle cx="15" cy="27" r="2.5" fill="#fdf5ea" stroke="#43322a"/><circle cx="29" cy="27" r="2.5" fill="#fdf5ea" stroke="#43322a"/></svg>`;

export function truckIcon(sizePx = 40) {
  return {
    url: "data:image/svg+xml;utf8," + encodeURIComponent(TRUCK_SVG),
    scaledSize: new google.maps.Size(sizePx, sizePx),
    anchor: new google.maps.Point(sizePx / 2, sizePx / 2),
  };
}
