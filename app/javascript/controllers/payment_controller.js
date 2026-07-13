import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["form", "cardElement", "stripeToken", "cardErrors", "submitButton"];
  static values = { stripePublishableKey: String };

  async connect() {
    if (!this.stripePublishableKeyValue) return;

    // Dynamically load Stripe if not already loaded
    if (typeof Stripe === "undefined") {
      await this.loadStripe();
    }

    // Initialize Stripe
    this.stripe = Stripe(this.stripePublishableKeyValue);
    this.elements = this.stripe.elements();
    this.card = this.elements.create("card");
    this.card.mount(this.cardElementTarget);
  }

  async loadStripe() {
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = "https://js.stripe.com/v3/";
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }

  async submit(event) {
    event.preventDefault();

    if (!this.stripe) {
      this.cardErrorsTarget.textContent = this.cardErrorsTarget.textContent.trim();
      return;
    }

    this.submitButtonTarget.disabled = true;

    // Create Stripe token
    const { token, error } = await this.stripe.createToken(this.card);
    if (error) {
      this.cardErrorsTarget.textContent = error.message;
      this.submitButtonTarget.disabled = false;
      return;
    }

    // Pass token to the form and submit
    this.stripeTokenTarget.value = token.id;
    this.formTarget.submit();
  }
}
