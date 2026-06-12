import PassKit
import PrivacyUI
import SwiftUI

/// Voluntary support page (OD-12: the app is completely free). Donations
/// unlock nothing — these buttons exist only for people who want to give.
struct DonateView: View {
    @State private var coordinator = ApplePayDonationCoordinator()
    @State private var showCustomAmount = false
    @State private var customAmountText = ""

    var body: some View {
        @Bindable var coordinator = coordinator
        ScrollView {
            VStack(spacing: PVSpacing.xl) {
                hero
                amountButtons
                Text("Donations go through Apple Pay and support development. They don't unlock anything — every feature is already yours.")
                    .font(.footnote)
                    .foregroundStyle(Color.pvTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PVSpacing.s)
            }
            .padding(PVSpacing.l)
        }
        .pvScreen()
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Choose an amount", isPresented: $showCustomAmount) {
            TextField("Amount in US dollars", text: $customAmountText)
                .keyboardType(.decimalPad)
            Button("Continue") { donateCustomAmount() }
            Button("Cancel", role: .cancel) { customAmountText = "" }
        } message: {
            Text("Any amount helps — thank you.")
        }
        .alert("Thank you ❤️", isPresented: $coordinator.showThanks) {
            Button("OK") {}
        } message: {
            Text("Your support keeps PrivacyLLM free for everyone.")
        }
        .alert("Apple Pay isn't available", isPresented: noticePresented) {
            Button("OK") { coordinator.notice = nil }
        } message: {
            if let notice = coordinator.notice {
                Text(notice)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: PVSpacing.m) {
            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.pvAccent)
                .frame(width: 96, height: 96)
                .background(Color.pvAccentWash, in: Circle())
                .pvGlow()
                .padding(.top, PVSpacing.xl)
                .accessibilityHidden(true)
            Text("PrivacyLLM is free")
                .font(PVFont.display)
                .foregroundStyle(Color.pvTextPrimary)
            Text("No subscriptions, no locked features, no ads — and it stays that way. If the app is useful to you, you can leave a voluntary donation.")
                .font(.subheadline)
                .foregroundStyle(Color.pvTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var amountButtons: some View {
        VStack(spacing: PVSpacing.m) {
            HStack(spacing: PVSpacing.m) {
                amountButton("$1") { coordinator.donate(1) }
                amountButton("$2") { coordinator.donate(2) }
                amountButton("$3") { coordinator.donate(3) }
            }
            Button {
                showCustomAmount = true
            } label: {
                Text("Other amount…")
                    .font(PVFont.headline)
                    .foregroundStyle(Color.pvAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PVSpacing.l)
            }
            .buttonStyle(.plain)
            .pvCard()
            .accessibilityHint("Lets you type an amount, then opens Apple Pay")
        }
    }

    private func amountButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(PVFont.title)
                .foregroundStyle(Color.pvAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PVSpacing.l)
        }
        .buttonStyle(.plain)
        .pvCard()
        .accessibilityLabel("Donate \(label)")
        .accessibilityHint("Opens Apple Pay")
    }

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { coordinator.notice != nil },
            set: { if !$0 { coordinator.notice = nil } }
        )
    }

    private func donateCustomAmount() {
        // Swedish (and most European) keyboards produce a decimal comma.
        let normalized = customAmountText.replacingOccurrences(of: ",", with: ".")
        customAmountText = ""
        guard let amount = Decimal(string: normalized), amount > 0 else { return }
        coordinator.donate(amount)
    }
}

/// Presents the Apple Pay sheet for a donation and reports the outcome.
///
/// Shipping checklist (none of this blocks local builds — until done, the
/// sheet simply won't present and the user sees the "isn't available" notice):
/// 1. Create `merchantIdentifier` in the Apple Developer portal and add the
///    Apple Pay capability with it under Signing & Capabilities.
/// 2. Wire a payment processor into `didAuthorizePayment` — the PKPayment
///    token on its own charges nobody.
/// 3. App Review: Apple Pay donations are normally reserved for approved
///    nonprofits (guideline 3.2.1); tips to a developer are expected to be
///    consumable in-app purchases (3.1.1). Be ready to swap this file's
///    PassKit flow for StoreKit consumables if review pushes back.
@Observable
final class ApplePayDonationCoordinator: NSObject {
    static let merchantIdentifier = "merchant.com.axellangenskiold.PrivacyLLM"

    var showThanks = false
    var notice: String?

    private var controller: PKPaymentAuthorizationController?
    private var didAuthorize = false

    func donate(_ amount: Decimal) {
        guard controller == nil else { return }
        guard PKPaymentAuthorizationController.canMakePayments() else {
            notice = String(localized: "This device can't use Apple Pay. The app stays completely free either way.")
            return
        }

        var exact = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 2, .bankers)

        let request = PKPaymentRequest()
        request.merchantIdentifier = Self.merchantIdentifier
        request.merchantCapabilities = .threeDSecure
        request.countryCode = "SE"
        request.currencyCode = "USD"
        request.supportedNetworks = [.visa, .masterCard, .amex]
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: String(localized: "Donation to PrivacyLLM"),
                amount: NSDecimalNumber(decimal: rounded)
            ),
        ]

        didAuthorize = false
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        self.controller = controller
        controller.present { [weak self] presented in
            guard !presented, let self else { return }
            Task { @MainActor in
                self.controller = nil
                self.notice = String(localized: "Apple Pay couldn't be opened. Check that a card is set up in the Wallet app.")
            }
        }
    }
}

extension ApplePayDonationCoordinator: PKPaymentAuthorizationControllerDelegate {
    // PassKit calls these on a private queue.
    nonisolated func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        // A payment processor must consume `payment.token` here before this
        // ships; accepting the token without one moves no money.
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
        Task { @MainActor in self.didAuthorize = true }
    }

    nonisolated func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
        Task { @MainActor in
            self.controller = nil
            if self.didAuthorize {
                self.didAuthorize = false
                self.showThanks = true
                Haptics.success()
            }
        }
    }
}

#Preview {
    NavigationStack {
        DonateView()
    }
}
