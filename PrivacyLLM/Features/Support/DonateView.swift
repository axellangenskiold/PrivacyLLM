import PrivacyUI
import StoreKit
import SwiftUI

/// Voluntary support page (OD-12: the app is completely free). Donations
/// unlock nothing — these buttons exist only for people who want to give.
struct DonateView: View {
    @State private var store = DonationStore()
    @Environment(\.purchase) private var purchase

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: PVSpacing.xl) {
                hero
                amountButtons
                Text("Donations are processed by the App Store and support development. They don't unlock anything — every feature is already yours.")
                    .font(.footnote)
                    .foregroundStyle(Color.pvTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PVSpacing.s)
            }
            .padding(PVSpacing.l)
        }
        .pvScreen()
        .navigationTitle("Donate")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.start() }
        .alert("Thank you ❤️", isPresented: $store.showThanks) {
            Button("OK") {}
        } message: {
            Text("Your support keeps PrivacyLLM free for everyone.")
        }
        .alert("Donations unavailable", isPresented: noticePresented) {
            Button("OK") { store.notice = nil }
        } message: {
            if let notice = store.notice {
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

    /// Labels come from the App Store once products load; the placeholders
    /// keep the page legible (and tappable, with an explanation) before then.
    private static let placeholderPrices = ["$1", "$3", "$5"]

    private var amountButtons: some View {
        HStack(spacing: PVSpacing.m) {
            ForEach(0..<3) { index in
                tierButton(index)
            }
        }
        .disabled(store.purchaseInFlight)
    }

    private func tierButton(_ index: Int) -> some View {
        let product = store.tiers.indices.contains(index) ? store.tiers[index] : nil
        return Button {
            if let product {
                donate(product)
            } else {
                store.productsMissing()
            }
        } label: {
            Text(product?.displayPrice ?? Self.placeholderPrices[index])
                .font(PVFont.title)
                .foregroundStyle(Color.pvAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PVSpacing.l)
        }
        .buttonStyle(.plain)
        .pvCard()
        .accessibilityLabel("Donate \(product?.displayPrice ?? Self.placeholderPrices[index])")
        .accessibilityIdentifier("donate-tier-\(index)")
    }

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )
    }

    private func donate(_ product: Product) {
        guard !store.purchaseInFlight else { return }
        store.purchaseInFlight = true
        Task {
            defer { store.purchaseInFlight = false }
            do {
                let result = try await purchase(product)
                await store.handle(result)
            } catch {
                store.purchaseFailed()
            }
        }
    }
}

/// The donation tiers are StoreKit consumables — the mechanism Apple requires
/// for developer tips (guideline 3.1.1) — so the page reads "donation" while
/// the rails are ordinary in-app purchases. Nothing is delivered or unlocked;
/// a finished transaction just earns a thank-you.
///
/// The product IDs below must exist as consumables in App Store Connect at flat
/// price points $1 / $3 / $5. For local testing without App Store Connect,
/// select PrivacyLLM.storekit in the scheme (Run → Options → StoreKit
/// Configuration).
@Observable
final class DonationStore {
    static let tierIDs = [
        "com.axellangenskiold.PrivacyLLM.tip.small",
        "com.axellangenskiold.PrivacyLLM.tip.medium",
        "com.axellangenskiold.PrivacyLLM.tip.big",
    ]

    private(set) var tiers: [Product] = []
    var showThanks = false
    var notice: String?
    var purchaseInFlight = false

    /// Loads products, settles anything left unfinished (Ask to Buy approved
    /// later, crash mid-thanks), then follows transaction updates for as long
    /// as the page is on screen — the hosting `.task` cancels us on pop.
    func start() async {
        await loadProducts()
        for await unfinished in StoreKit.Transaction.unfinished {
            await settle(unfinished)
        }
        for await update in StoreKit.Transaction.updates {
            if Task.isCancelled { break }
            await settle(update)
        }
    }

    private func loadProducts() async {
        guard tiers.isEmpty else { return }
        do {
            tiers = try await Product.products(for: Self.tierIDs)
                .sorted { $0.price < $1.price }
        } catch {
            // Buttons keep their placeholder labels; tapping one explains.
        }
    }

    func handle(_ result: Product.PurchaseResult) async {
        switch result {
        case .success(let verification):
            await settle(verification)
        case .pending:
            notice = String(localized: "The donation is waiting for approval — thank you!")
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    func purchaseFailed() {
        notice = String(localized: "The App Store couldn't complete the donation. Please try again later.")
    }

    func productsMissing() {
        notice = String(localized: "Donations aren't available right now. The app stays completely free either way.")
    }

    private func settle(_ verification: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        await transaction.finish()
        if transaction.productType == .consumable, transaction.revocationDate == nil {
            showThanks = true
            Haptics.success()
        }
    }
}

#Preview {
    NavigationStack {
        DonateView()
    }
}
