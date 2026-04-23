// app/javascript/controllers/address_autocomplete_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "input",
    "map",
    "lat",
    "lng",
    "plus",
    "addressName",
    "addressSelect",
    "description",
    "latDisplay",
    "lngDisplay",
    "plusDisplay",
    "addressDisplay",
    "statusBadge",
    "coordsStatus",
    "descStatus",
    "geoDetails",
  ];

  static values = { apiKey: String };

  connect() {
    this._initialized = false;
    this._initAttempts = 0;
    this._descriptionWasManuallyEdited = false;
    this._lastInputSource = null;
    this._pacObserver = null;

    if (this.hasDescriptionTarget) {
      this.descriptionTarget.addEventListener("input", () => {
        this._descriptionWasManuallyEdited = true;
      });
    }

    this.loadGoogleMapsAPI().then(() => this.tryInitializeAutocomplete());
  }

  disconnect() {
    if (this._pacObserver) {
      this._pacObserver.disconnect();
      this._pacObserver = null;
    }
    if (this._repositionPac) {
      const modalBody =
        this.element.closest(".modal-body") || this.element.closest(".modal");
      if (modalBody)
        modalBody.removeEventListener("scroll", this._repositionPac);
      window.removeEventListener("resize", this._repositionPac);
    }
    if (this.autocomplete)
      google.maps.event.clearInstanceListeners(this.autocomplete);
    if (this.marker) google.maps.event.clearInstanceListeners(this.marker);
    if (this.map) google.maps.event.clearInstanceListeners(this.map);
  }

  // ─── CARGA DE API ────────────────────────────────────────────────────────────

  async loadGoogleMapsAPI() {
    if (window.google?.maps) return Promise.resolve();
    if (window.__googleMapsLoadingPromise)
      return window.__googleMapsLoadingPromise;

    window.__googleMapsLoadingPromise = new Promise((resolve, reject) => {
      const existing = document.querySelector(
        "script[data-google-maps-loader='true']",
      );
      if (existing) {
        existing.addEventListener("load", resolve);
        existing.addEventListener("error", () =>
          reject(new Error("Google Maps script load failed")),
        );
        return;
      }

      const script = document.createElement("script");
      script.dataset.googleMapsLoader = "true";
      script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}&libraries=places,marker&loading=async`;
      script.async = true;
      script.defer = true;
      script.onload = resolve;
      script.onerror = () =>
        reject(new Error("Google Maps script load failed"));
      document.head.appendChild(script);
    });

    return window.__googleMapsLoadingPromise;
  }

  // ─── INICIALIZACIÓN ──────────────────────────────────────────────────────────

  async tryInitializeAutocomplete() {
    if (this._initialized) return;

    if (!this.hasMapTarget) {
      this._initAttempts += 1;
      if (this._initAttempts <= 10)
        setTimeout(() => this.tryInitializeAutocomplete(), 200);
      return;
    }

    try {
      const { Map } = await google.maps.importLibrary("maps");
      const { AdvancedMarkerElement } =
        await google.maps.importLibrary("marker");
      await google.maps.importLibrary("places");

      const initialLat = parseFloat(this.latTarget?.value) || 9.9281;
      const initialLng = parseFloat(this.lngTarget?.value) || -84.0907;
      const hasExisting = initialLat !== 9.9281 || initialLng !== -84.0907;

      this.map = new Map(this.mapTarget, {
        center: { lat: initialLat, lng: initialLng },
        zoom: hasExisting ? 17 : 8,
        mapId: "DELIVERY_ADDRESS_MAP_ID",
        mapTypeControl: false,
        streetViewControl: false,
        fullscreenControl: true,
      });

      this.marker = new AdvancedMarkerElement({
        map: this.map,
        position: { lat: initialLat, lng: initialLng },
        gmpDraggable: true,
        title: "Ubicación de entrega",
      });

      this.geocoder = new google.maps.Geocoder();

      this.marker.addListener("dragend", async (event) => {
        this._lastInputSource = "map_drag";
        const lat = event.latLng.lat();
        const lng = event.latLng.lng();
        this.updateFromCoords(lat, lng);
        await this.reverseGeocode({ lat, lng });
      });

      this.map.addListener("click", async (event) => {
        this._lastInputSource = "map_click";
        const lat = event.latLng.lat();
        const lng = event.latLng.lng();
        this.marker.position = event.latLng;
        this.updateFromCoords(lat, lng);
        await this.reverseGeocode({ lat, lng });
      });

      if (this.hasInputTarget) this._initLegacyAutocomplete();
      if (hasExisting) {
        this.updateDisplays(initialLat, initialLng);
        this.validateStatus();
      }

      this._initialized = true;
      console.log("✅ AddressAutocompleteController inicializado");
    } catch (error) {
      console.error("❌ Error inicializando address autocomplete:", error);
    }
  }

  // ─── AUTOCOMPLETE LEGACY ─────────────────────────────────────────────────────

  _initLegacyAutocomplete() {
    this.autocomplete = new google.maps.places.Autocomplete(this.inputTarget, {
      componentRestrictions: { country: "cr" },
      fields: [
        "address_components",
        "formatted_address",
        "geometry",
        "name",
        "place_id",
        "plus_code",
        "types",
        "vicinity",
        "url",
      ],
      types: [],
    });

    // ✅ FIX: Evitar que el input pierda foco al hacer click en sugerencia
    this._preventBlur = (e) => e.preventDefault();

    // ✅ FIX DEFINITIVO pac-container: mover al body + position fixed + z-index
    this._pacObserver = new MutationObserver(() => {
      const pac = document.querySelector(".pac-container");
      if (!pac) return;

      if (pac.parentElement !== document.body) {
        document.body.appendChild(pac);
        // Prevenir que el click en sugerencias quite el foco del input
        pac.addEventListener("mousedown", this._preventBlur);
      }

      pac.style.setProperty("z-index", "9999", "important");
      pac.style.setProperty("position", "fixed", "important");

      const inputRect = this.inputTarget.getBoundingClientRect();
      pac.style.setProperty("top", `${inputRect.bottom}px`, "important");
      pac.style.setProperty("left", `${inputRect.left}px`, "important");
      pac.style.setProperty("width", `${inputRect.width}px`, "important");
    });

    this._pacObserver.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["style"],
    });

    this._repositionPac = () => {
      const pac = document.querySelector(".pac-container");
      if (!pac || pac.style.display === "none") return;
      const inputRect = this.inputTarget.getBoundingClientRect();
      pac.style.setProperty("top", `${inputRect.bottom}px`, "important");
      pac.style.setProperty("left", `${inputRect.left}px`, "important");
      pac.style.setProperty("width", `${inputRect.width}px`, "important");
    };

    const modalBody =
      this.element.closest(".modal-body") || this.element.closest(".modal");
    if (modalBody) modalBody.addEventListener("scroll", this._repositionPac);
    window.addEventListener("resize", this._repositionPac);

    this.autocomplete.addListener("place_changed", () => {
      const place = this.autocomplete.getPlace();
      if (!place?.geometry?.location) {
        console.warn("⚠️ El autocomplete no devolvió geometry.location");
        return;
      }
      this._lastInputSource = "autocomplete";
      this._handlePlaceResult(place);
    });
  }

  // ─── MANEJO DE RESULTADO DE PLACE ────────────────────────────────────────────

  async _handlePlaceResult(place) {
    const lat = place.geometry.location.lat();
    const lng = place.geometry.location.lng();

    const placeName = place.name || "";
    const formattedAddress = place.formatted_address || "";
    const vicinity = place.vicinity || "";
    const placeId = place.place_id || "";
    const placeUrl = place.url || "";
    const placeTypes = place.types || [];
    const plusCode =
      place.plus_code?.global_code || place.plus_code?.compound_code || "";
    const components = this._extractComponents(place.address_components || []);

    this.updateFromCoords(lat, lng);

    if (plusCode && this.hasPlusTarget) {
      this.plusTarget.value = plusCode;
      if (this.hasPlusDisplayTarget)
        this.plusDisplayTarget.textContent = plusCode;
    }

    let enriched = {
      placeName,
      formattedAddress,
      vicinity,
      components,
      placeTypes,
      placeUrl,
    };
    if (placeId) {
      const details = await this._fetchPlaceDetails(placeId);
      if (details) enriched = this._mergeWithDetails(enriched, details);
    }

    const driverAddress = this._buildDriverAddress(enriched);
    const richReference = this._buildRichReference(enriched);

    if (this.hasAddressNameTarget) this.addressNameTarget.value = driverAddress;
    if (this.hasAddressDisplayTarget)
      this.addressDisplayTarget.textContent = driverAddress;

    this._updateDatasetMetadata({
      placeId,
      formattedAddress,
      placeName,
      source: "autocomplete",
    });
    this._showGeoDetails(enriched);
    this._setDescription(richReference);
    this.validateStatus();
  }

  // ─── PLACE DETAILS ────────────────────────────────────────────────────────────

  async _fetchPlaceDetails(placeId) {
    if (!placeId) return null;

    return new Promise((resolve) => {
      const service = new google.maps.places.PlacesService(this.mapTarget);
      service.getDetails(
        {
          placeId,
          fields: [
            "name",
            "formatted_address",
            "address_components",
            "vicinity",
            "url",
            "plus_code",
            "types",
            "adr_address",
          ],
          language: "es",
        },
        (result, status) => {
          if (status === google.maps.places.PlacesServiceStatus.OK && result) {
            resolve(result);
          } else {
            console.warn("⚠️ Place Details no disponible:", status);
            resolve(null);
          }
        },
      );
    });
  }

  _mergeWithDetails(base, details) {
    const detailComponents = this._extractComponents(
      details.address_components || [],
    );
    const mergedComponents = { ...base.components };
    Object.entries(detailComponents).forEach(([key, value]) => {
      if (value && !mergedComponents[key]) mergedComponents[key] = value;
    });

    return {
      placeName: details.name || base.placeName,
      formattedAddress: details.formatted_address || base.formattedAddress,
      vicinity: details.vicinity || base.vicinity,
      placeUrl: details.url || base.placeUrl,
      placeTypes: details.types || base.placeTypes,
      plusCode:
        details.plus_code?.global_code ||
        details.plus_code?.compound_code ||
        "",
      adrAddress: details.adr_address || "",
      components: mergedComponents,
    };
  }

  // ─── ENTRADA MANUAL ───────────────────────────────────────────────────────────

  async handleSmartInput(event) {
    const rawText = event.target.value.trim();
    if (!rawText) return;

    const normalized = rawText.replace(/\s+/g, " ").trim();
    const coordMatch = normalized.match(
      /^(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)$/,
    );

    if (coordMatch) {
      const lat = parseFloat(coordMatch[1]);
      const lng = parseFloat(coordMatch[3]);
      if (this._coordsLookLikeCostaRica(lat, lng)) {
        this._lastInputSource = "coordinates";
        this.updateFromCoords(lat, lng);
        await this.reverseGeocode({ lat, lng });
        event.target.value = "";
      } else {
        alert(
          `Las coordenadas ${lat}, ${lng} están fuera del rango esperado para Costa Rica.`,
        );
      }
      return;
    }

    if (this._looksLikePlusCode(normalized)) {
      this._lastInputSource = "plus_code";
      await this._resolvePlusCode(normalized);
      event.target.value = "";
    }
  }

  async _resolvePlusCode(plusCode) {
    if (!this.geocoder) return;

    try {
      const response = await this.geocoder.geocode({
        address: plusCode,
        componentRestrictions: { country: "CR" },
      });

      if (!response.results?.length) {
        alert(`No se pudo encontrar el Plus Code: ${plusCode}`);
        return;
      }

      const result = response.results[0];
      const lat = result.geometry.location.lat();
      const lng = result.geometry.location.lng();

      this.updateFromCoords(lat, lng);

      if (this.hasPlusTarget) {
        this.plusTarget.value = plusCode;
        if (this.hasPlusDisplayTarget)
          this.plusDisplayTarget.textContent = plusCode;
      }

      await this.reverseGeocode({ lat, lng, originalPlusCode: plusCode });
    } catch (error) {
      console.error("❌ Error resolviendo Plus Code:", error);
      alert(`No se pudo resolver el Plus Code: ${plusCode}`);
    }
  }

  // ─── REVERSE GEOCODE ──────────────────────────────────────────────────────────

  async reverseGeocode(position) {
    if (!this.geocoder) return;

    try {
      const response = await this.geocoder.geocode({
        location: { lat: position.lat, lng: position.lng },
      });

      if (!response.results?.length) return;

      const results = response.results;
      const primary = results[0];
      const formattedAddress = primary.formatted_address || "";
      const components = this._mergeGeocoderComponents(results);
      const placeName = this._extractBestPlaceNameFromGeocoderResults(results);
      const vicinity = this._extractVicinityFromResults(results);
      const plusCode =
        primary.plus_code?.global_code ||
        primary.plus_code?.compound_code ||
        position.originalPlusCode ||
        "";
      const placeTypes = primary.types || [];

      if (plusCode && this.hasPlusTarget) {
        this.plusTarget.value = plusCode;
        if (this.hasPlusDisplayTarget)
          this.plusDisplayTarget.textContent = plusCode;
      }

      const enriched = {
        placeName,
        formattedAddress,
        vicinity,
        components,
        placeTypes,
        placeUrl: "",
      };

      const driverAddress = this._buildDriverAddress(enriched);
      const richReference = this._buildRichReference(enriched);

      if (this.hasAddressNameTarget)
        this.addressNameTarget.value = driverAddress;
      if (this.hasAddressDisplayTarget)
        this.addressDisplayTarget.textContent = driverAddress;

      this._updateDatasetMetadata({
        placeId: "",
        formattedAddress,
        placeName,
        source: this._lastInputSource || "reverse_geocode",
      });

      this._showGeoDetails(enriched);
      this._setDescription(richReference);
      this.validateStatus();
    } catch (error) {
      console.error("❌ Error en reverse geocoding:", error);
    }
  }

  _mergeGeocoderComponents(results) {
    const merged = {};
    results.forEach((result) => {
      const extracted = this._extractComponents(
        result.address_components || [],
      );
      Object.entries(extracted).forEach(([key, value]) => {
        if (!merged[key] && value) merged[key] = value;
      });
    });
    return merged;
  }

  _extractBestPlaceNameFromGeocoderResults(results) {
    const preferredTypes = [
      "premise",
      "subpremise",
      "point_of_interest",
      "establishment",
      "street_address",
      "route",
    ];

    for (const type of preferredTypes) {
      for (const result of results) {
        if (!result.types?.includes(type)) continue;
        const first = (result.formatted_address || "").split(",")[0]?.trim();
        if (
          first &&
          !this._looksLikePlusCode(first) &&
          first.length > 2 &&
          first.length < 100
        )
          return first;
      }
    }

    for (const result of results) {
      const first = (result.formatted_address || "").split(",")[0]?.trim();
      if (
        first &&
        !this._looksLikePlusCode(first) &&
        first.length > 2 &&
        first.length < 100
      )
        return first;
    }

    return "";
  }

  _extractVicinityFromResults(results) {
    for (const result of results) {
      if (result.vicinity) return result.vicinity;
    }
    return "";
  }

  // ─── CONSTRUCCIÓN DE DIRECCIÓN ────────────────────────────────────────────────

  _buildDriverAddress({ placeName, formattedAddress, vicinity, components }) {
    const parts = [];
    const name = this._cleanPlaceName(placeName);
    if (name && !this._isAdministrativeOnly(name, components)) parts.push(name);

    if (vicinity) {
      const vicinityFirst = vicinity.split(",")[0]?.trim();
      if (
        vicinityFirst &&
        !this._isAdministrativeOnly(vicinityFirst, components)
      )
        this._pushUniquePart(parts, vicinityFirst);
    }

    this._appendAdministrativeHierarchy(parts, components);
    if (parts.length > 0) return parts.join(", ").trim();
    return this._cleanFormattedAddress(formattedAddress);
  }

  _buildRichReference({
    placeName,
    formattedAddress,
    vicinity,
    components,
    placeTypes,
    adrAddress,
  }) {
    const parts = [];
    const name = this._cleanPlaceName(placeName);
    if (name && !this._isAdministrativeOnly(name, components)) parts.push(name);

    if (vicinity) {
      vicinity.split(",").forEach((seg) => {
        const s = seg.trim();
        if (s && !this._looksLikePlusCode(s) && !/^costa rica$/i.test(s))
          this._pushUniquePart(parts, s);
      });
    }

    if (formattedAddress) {
      const adminCandidates = this._buildAdminCandidates(components);
      formattedAddress.split(",").forEach((seg) => {
        const s = seg.trim();
        if (!s) return;
        if (this._looksLikePlusCode(s)) return;
        if (/^costa rica$/i.test(s)) return;
        if (/^provincia\s+de\s+/i.test(s)) return;
        if (name && this._isSimilar(s, name)) return;
        if (adminCandidates.includes(s.toLowerCase())) return;
        this._pushUniquePart(parts, s);
      });
    }

    if (components.premise) this._pushUniquePart(parts, components.premise);
    if (components.subpremise)
      this._pushUniquePart(parts, components.subpremise);

    if (components.route) {
      const routeStr = components.street_number
        ? `${components.route} ${components.street_number}`
        : components.route;
      this._pushUniquePart(parts, routeStr);
    }

    this._appendAdministrativeHierarchy(parts, components);
    if (components.postal_code)
      this._pushUniquePart(parts, components.postal_code);

    return parts.join(", ").trim();
  }

  _appendAdministrativeHierarchy(parts, components) {
    const district =
      components.sublocality_5 ||
      components.sublocality_4 ||
      components.sublocality_3 ||
      components.sublocality_2 ||
      components.sublocality_1 ||
      components.sublocality ||
      components.neighborhood ||
      components.admin_level_3 ||
      null;

    const locality = components.locality || components.postal_town || null;
    const canton = components.admin_level_2 || null;
    const province = this._cleanProvince(components.admin_level_1);

    if (district) this._pushUniquePart(parts, district);
    if (locality) this._pushUniquePart(parts, locality);
    if (canton) this._pushUniquePart(parts, canton);
    if (province) this._pushUniquePart(parts, province);
  }

  _buildAdminCandidates(components) {
    return [
      components.neighborhood,
      components.sublocality,
      components.sublocality_1,
      components.sublocality_2,
      components.sublocality_3,
      components.sublocality_4,
      components.sublocality_5,
      components.locality,
      components.postal_town,
      components.admin_level_3,
      components.admin_level_2,
      this._cleanProvince(components.admin_level_1),
      components.admin_level_1,
      components.country,
      components.postal_code,
    ]
      .filter(Boolean)
      .map((v) => v.toLowerCase().trim());
  }

  // ─── CARGA DE DIRECCIÓN EXISTENTE ────────────────────────────────────────────

  loadExistingAddress(event) {
    const id = event.target.value;
    if (!id) return;

    fetch(`/delivery_addresses/${id}.json`)
      .then((r) => r.json())
      .then(async (data) => {
        const lat = parseFloat(data.latitude);
        const lng = parseFloat(data.longitude);

        if (!Number.isNaN(lat) && !Number.isNaN(lng)) {
          this.updateFromCoords(lat, lng);

          if (this.hasDescriptionTarget && data.description) {
            this.descriptionTarget.value = data.description;
            this._descriptionWasManuallyEdited = true;
          }
          if (data.plus_code && this.hasPlusTarget) {
            this.plusTarget.value = data.plus_code;
            if (this.hasPlusDisplayTarget)
              this.plusDisplayTarget.textContent = data.plus_code;
          }
          if (data.address && this.hasAddressNameTarget) {
            this.addressNameTarget.value = data.address;
            if (this.hasAddressDisplayTarget)
              this.addressDisplayTarget.textContent = data.address;
          }

          this._lastInputSource = "existing_record";
          await this.reverseGeocode({ lat, lng });
        }
      })
      .catch((error) =>
        console.error("❌ Error cargando dirección existente:", error),
      );
  }

  // ─── MAPA / COORDS ────────────────────────────────────────────────────────────

  updateFromCoords(lat, lng) {
    const pos = { lat, lng };
    if (this.map) {
      this.map.setCenter(pos);
      this.map.setZoom(17);
    }
    if (this.marker) this.marker.position = pos;
    this.updateFields(lat, lng);
    this.updateDisplays(lat, lng);
    this.validateStatus();
  }

  updateFields(lat, lng) {
    if (this.hasLatTarget) this.latTarget.value = Number(lat).toFixed(7);
    if (this.hasLngTarget) this.lngTarget.value = Number(lng).toFixed(7);
  }

  updateDisplays(lat, lng) {
    if (this.hasLatDisplayTarget)
      this.latDisplayTarget.textContent = Number(lat).toFixed(5);
    if (this.hasLngDisplayTarget)
      this.lngDisplayTarget.textContent = Number(lng).toFixed(5);
  }

  resizeMap() {
    if (!this.map) return;
    google.maps.event.trigger(this.map, "resize");
    const lat = parseFloat(this.latTarget?.value);
    const lng = parseFloat(this.lngTarget?.value);
    if (!Number.isNaN(lat) && !Number.isNaN(lng))
      this.map.setCenter({ lat, lng });
  }

  // ─── UI ───────────────────────────────────────────────────────────────────────

  _showGeoDetails({
    placeName,
    formattedAddress,
    vicinity,
    components,
    placeTypes,
    placeUrl,
  }) {
    if (!this.hasGeoDetailsTarget) return;

    const district =
      components.sublocality_5 ||
      components.sublocality_4 ||
      components.sublocality_3 ||
      components.sublocality_2 ||
      components.sublocality_1 ||
      components.sublocality ||
      components.neighborhood ||
      components.admin_level_3 ||
      null;

    const locality = components.locality || components.postal_town || null;
    const province = this._cleanProvince(components.admin_level_1);

    const rows = [
      placeName ? `<li><strong>Lugar:</strong> ${placeName}</li>` : null,
      components.premise
        ? `<li><strong>Edificio / Complejo:</strong> ${components.premise}</li>`
        : null,
      components.subpremise
        ? `<li><strong>Unidad / Apto:</strong> ${components.subpremise}</li>`
        : null,
      components.route
        ? `<li><strong>Calle / Ruta:</strong> ${components.route}${components.street_number ? " " + components.street_number : ""}</li>`
        : null,
      vicinity
        ? `<li><strong>Referencia vial:</strong> ${vicinity}</li>`
        : null,
      district
        ? `<li><strong>Distrito / Barrio:</strong> ${district}</li>`
        : null,
      locality
        ? `<li><strong>Ciudad / Pueblo:</strong> ${locality}</li>`
        : null,
      components.admin_level_2
        ? `<li><strong>Cantón:</strong> ${components.admin_level_2}</li>`
        : null,
      province ? `<li><strong>Provincia:</strong> ${province}</li>` : null,
      components.postal_code
        ? `<li><strong>Código postal:</strong> ${components.postal_code}</li>`
        : null,
      placeTypes?.length
        ? `<li><strong>Tipo de lugar:</strong> ${placeTypes.slice(0, 3).join(", ")}</li>`
        : null,
      placeUrl
        ? `<li><strong>Google Maps:</strong> <a href="${placeUrl}" target="_blank" rel="noopener">Ver en Maps</a></li>`
        : null,
      formattedAddress
        ? `<li><strong>Dirección Google:</strong> ${formattedAddress}</li>`
        : null,
    ].filter(Boolean);

    if (rows.length === 0) {
      this.geoDetailsTarget.style.display = "none";
      return;
    }

    this.geoDetailsTarget.innerHTML = `
      <div class="small">
        <div class="fw-bold text-success mb-2">Detalles detectados</div>
        <ul class="mb-0 ps-3">${rows.join("")}</ul>
      </div>
    `;
    this.geoDetailsTarget.style.removeProperty("display");
    this.geoDetailsTarget.classList.remove("d-none");
  }

  _setDescription(richReference) {
    if (!this.hasDescriptionTarget) return;
    if (this._descriptionWasManuallyEdited) return;
    if (richReference) this.descriptionTarget.value = richReference;
  }

  _updateDatasetMetadata({ placeId, formattedAddress, placeName, source }) {
    if (this.hasAddressNameTarget) {
      this.addressNameTarget.dataset.googlePlaceId = placeId || "";
      this.addressNameTarget.dataset.googleFormattedAddress =
        formattedAddress || "";
      this.addressNameTarget.dataset.googlePlaceName = placeName || "";
      this.addressNameTarget.dataset.inputSource = source || "";
    }
  }

  validateStatus() {
    const hasCoords =
      this.hasLatTarget &&
      this.hasLngTarget &&
      this.latTarget.value &&
      this.lngTarget.value &&
      parseFloat(this.latTarget.value) !== 0 &&
      parseFloat(this.lngTarget.value) !== 0;

    const hasDescription =
      this.hasDescriptionTarget &&
      this.descriptionTarget.value.trim().length >= 10;

    if (this.hasCoordsStatusTarget) {
      this.coordsStatusTarget.className = hasCoords
        ? "badge bg-success"
        : "badge bg-warning text-dark";
      this.coordsStatusTarget.innerHTML = hasCoords
        ? "Coordenadas: OK"
        : "Coordenadas: pendiente";
    }
    if (this.hasDescStatusTarget) {
      this.descStatusTarget.className = hasDescription
        ? "badge bg-success"
        : "badge bg-warning text-dark";
      this.descStatusTarget.innerHTML = hasDescription
        ? "Descripción: OK"
        : "Descripción: pendiente";
    }
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.className =
        hasCoords && hasDescription
          ? "badge bg-success"
          : "badge bg-warning text-dark";
      this.statusBadgeTarget.textContent =
        hasCoords && hasDescription ? "✓ Completo" : "⚠ Incompleto";
    }
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────────

  _extractComponents(components) {
    const find = (type) =>
      components.find((c) => (c.types || []).includes(type))?.long_name || null;
    const findShort = (type) =>
      components.find((c) => (c.types || []).includes(type))?.short_name ||
      null;

    return {
      street_number: find("street_number"),
      route: find("route"),
      intersection: find("intersection"),
      neighborhood: find("neighborhood"),
      sublocality: find("sublocality"),
      sublocality_1: find("sublocality_level_1"),
      sublocality_2: find("sublocality_level_2"),
      sublocality_3: find("sublocality_level_3"),
      sublocality_4: find("sublocality_level_4"),
      sublocality_5: find("sublocality_level_5"),
      premise: find("premise"),
      subpremise: find("subpremise"),
      locality: find("locality"),
      postal_town: find("postal_town"),
      admin_level_3: find("administrative_area_level_3"),
      admin_level_2: find("administrative_area_level_2"),
      admin_level_1: find("administrative_area_level_1"),
      admin_level_1_short: findShort("administrative_area_level_1"),
      country: find("country"),
      country_short: findShort("country"),
      postal_code: find("postal_code"),
      postal_suffix: find("postal_code_suffix"),
      point_of_interest: find("point_of_interest"),
      establishment: find("establishment"),
      plus_code: find("plus_code"),
    };
  }

  _cleanPlaceName(name) {
    if (!name) return "";
    return name
      .replace(/^\s+|\s+$/g, "")
      .replace(/\s+/g, " ")
      .trim();
  }

  _cleanProvince(value) {
    if (!value) return null;
    return value.replace(/^Provincia\s+de\s+/i, "").trim();
  }

  _cleanFormattedAddress(address) {
    if (!address) return "";
    return address
      .split(",")
      .map((p) => p.trim())
      .filter(
        (p) => p && !this._looksLikePlusCode(p) && !/^costa rica$/i.test(p),
      )
      .join(", ")
      .replace(/\s+/g, " ")
      .trim();
  }

  _pushUniquePart(parts, candidate) {
    if (!candidate) return;
    if (this._looksLikePlusCode(candidate)) return;
    const normalized = candidate.trim();
    if (!normalized) return;
    if (!parts.some((p) => this._isSimilar(p, normalized)))
      parts.push(normalized);
  }

  _isSimilar(a, b) {
    if (!a || !b) return false;
    const n = (v) =>
      v
        .toString()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toLowerCase()
        .replace(/\s+/g, " ")
        .trim();
    const na = n(a);
    const nb = n(b);
    return na === nb || na.includes(nb) || nb.includes(na);
  }

  _looksLikePlusCode(value) {
    if (!value) return false;
    return /[23456789CFGHJMPQRVWX]{2,}\+[23456789CFGHJMPQRVWX]{2,}/i.test(
      value.trim(),
    );
  }

  _coordsLookLikeCostaRica(lat, lng) {
    return lat >= 8.0 && lat <= 11.5 && lng >= -86.5 && lng <= -82.0;
  }

  _isAdministrativeOnly(value, components) {
    if (!value) return false;
    const adminValues = [
      components.neighborhood,
      components.sublocality,
      components.sublocality_1,
      components.sublocality_2,
      components.sublocality_3,
      components.sublocality_4,
      components.sublocality_5,
      components.locality,
      components.postal_town,
      components.admin_level_3,
      components.admin_level_2,
      components.admin_level_1,
      this._cleanProvince(components.admin_level_1),
    ].filter(Boolean);
    return adminValues.some((item) => this._isSimilar(value, item));
  }
}
