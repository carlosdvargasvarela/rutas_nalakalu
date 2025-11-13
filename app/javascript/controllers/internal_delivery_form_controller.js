import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "deliveryDetailsBadge",
    "responsibleBadge",
    "addressBadge",
    "taskDetailsBadge",
  ];

  connect() {
    console.log("InternalDeliveryFormController connected");
    this.validateAllSections();
  }

  validateDeliveryDetails() {
    const deliveryDateField = document.querySelector(
      "input[name='delivery[delivery_date]']"
    );
    const timePreferenceField = document.querySelector(
      "select[name='delivery[delivery_time_preference]']"
    );

    const hasDeliveryDate = deliveryDateField && deliveryDateField.value !== "";
    const hasTimePreference =
      timePreferenceField && timePreferenceField.value !== "";

    const isValid = hasDeliveryDate && hasTimePreference;

    this.updateBadge(this.deliveryDetailsBadgeTarget, isValid);
  }

  validateResponsible() {
    const contactNameField = document.querySelector(
      "input[name='delivery[contact_name]']"
    );
    const contactPhoneField = document.querySelector(
      "input[name='delivery[contact_phone]']"
    );

    const hasContactName =
      contactNameField && contactNameField.value.trim() !== "";
    const hasContactPhone =
      contactPhoneField && contactPhoneField.value.trim() !== "";

    const isValid = hasContactName && hasContactPhone;

    this.updateBadge(this.responsibleBadgeTarget, isValid);
  }

  validateAddress() {
    const addressField = document.querySelector(
      "input[name='delivery_address[address]']"
    );
    const hasAddress = addressField && addressField.value.trim() !== "";

    this.updateBadge(this.addressBadgeTarget, hasAddress);
  }

  validateTaskDetails() {
    const taskField = document.querySelector("textarea[name*='[product]']");
    const hasTask = taskField && taskField.value.trim() !== "";

    this.updateBadge(this.taskDetailsBadgeTarget, hasTask);
  }

  validateAllSections() {
    this.validateDeliveryDetails();
    this.validateResponsible();
    this.validateAddress();
    this.validateTaskDetails();
  }

  updateBadge(badge, isValid) {
    if (!badge) return;

    if (isValid) {
      badge.classList.remove("bg-warning");
      badge.classList.add("bg-success");
      badge.textContent = "✓";
    } else {
      badge.classList.remove("bg-success");
      badge.classList.add("bg-warning");
      badge.textContent = "!";
    }
  }
}
