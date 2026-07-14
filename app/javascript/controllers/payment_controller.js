import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["form", "cardElement", "stripeToken", "cardErrors", "submitButton"];
  static values = { stripePublishableKey: String, processingText: String, loadErrorText: String };

  async connect() {
    if (!this.stripePublishableKeyValue) return;

    this.defaultButtonText = this.submitButtonTarget.textContent;
    this.submitButtonTarget.disabled = true;

    try {
      if (typeof Stripe === "undefined") await this.loadStripe();

      this.stripe = Stripe(this.stripePublishableKeyValue);
      this.elements = this.stripe.elements({ locale: document.documentElement.lang || "auto" });
      this.card = this.elements.create("card", {
        style: {
          base: {
            color: "#201f1f",
            fontFamily: "Montserrat, system-ui, sans-serif",
            fontSize: "16px",
            "::placeholder": { color: "#98a2b3" }
          },
          invalid: { color: "#b42318" }
        }
      });
      this.card.mount(this.cardElementTarget);
      this.card.on("change", ({ complete, error }) => {
        this.cardErrorsTarget.textContent = error ? error.message : "";
        this.submitButtonTarget.disabled = !complete;
      });
    } catch (_error) {
      this.cardErrorsTarget.textContent = this.loadErrorTextValue;
    }
  }

  disconnect() {
    if (this.card) this.card.unmount();
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
      this.cardErrorsTarget.textContent = this.cardErrorsTarget.textContent.trim() ||
        this.loadErrorTextValue;
      return;
    }

    this.submitButtonTarget.disabled = true;
    this.submitButtonTarget.setAttribute("aria-busy", "true");
    this.submitButtonTarget.textContent = this.processingTextValue;

    const { token, error } = await this.stripe.createToken(this.card);
    if (error) {
      this.cardErrorsTarget.textContent = error.message;
      this.submitButtonTarget.disabled = false;
      this.submitButtonTarget.removeAttribute("aria-busy");
      this.submitButtonTarget.textContent = this.defaultButtonText;
      return;
    }

    this.stripeTokenTarget.value = token.id;
    this.formTarget.submit();
  }
}
