import AppFoundation
import Foundation
import ShotCore
import ShotCoreTestSupport
import Testing
@testable import LibraryKit

@MainActor
@Suite("ShotDetailViewModel")
struct ShotDetailViewModelTests {
    private func dateEntity(_ iso: String, raw: String, grounded: Bool = true) -> ExtractedEntity {
        ExtractedEntity(
            kind: .date, rawValue: raw, normalizedValue: iso, confidence: 0.9, isGrounded: grounded
        )
    }

    @Test("Yalnız temellendirilmiş varlıklar gösterilir")
    func onlyGroundedEntitiesAreShown() {
        // KANON §6: uydurulmuş bir değer arayüze asla ulaşmaz.
        let shot = TestDependencies.shot(entities: [
            dateEntity("2026-02-14T00:00:00Z", raw: "14 Şubat 2026", grounded: true),
            dateEntity("2030-01-01T00:00:00Z", raw: "uydurma", grounded: false),
        ])
        let model = ShotDetailViewModel(
            shot: shot,
            dependencies: TestDependencies.make(index: FakeIndex()),
            paywall: PaywallPresenter()
        )

        #expect(model.entities.count == 1)
        #expect(model.entities.first?.rawValue == "14 Şubat 2026")
    }

    @Test("Aksiyon tarihi en erken tarihtir")
    func actionableDateIsEarliest() {
        let shot = TestDependencies.shot(entities: [
            dateEntity("2026-03-01T00:00:00Z", raw: "1 Mart"),
            dateEntity("2026-02-14T00:00:00Z", raw: "14 Şubat"),
        ])
        let model = ShotDetailViewModel(
            shot: shot,
            dependencies: TestDependencies.make(index: FakeIndex()),
            paywall: PaywallPresenter()
        )

        #expect(model.actionableDate == ISO8601.parse("2026-02-14T00:00:00Z"))
    }

    @Test("Hatırlatıcı çıkarılan tarihle oluşturulur")
    func reminderUsesExtractedDate() async {
        let actions = FakeActionPerformer()
        let shot = TestDependencies.shot(entities: [dateEntity("2026-02-14T00:00:00Z", raw: "14 Şubat")])
        let model = ShotDetailViewModel(
            shot: shot,
            dependencies: TestDependencies.make(index: FakeIndex(), actions: actions),
            paywall: PaywallPresenter()
        )

        await model.createReminder()

        let reminders = await actions.reminders
        #expect(reminders.count == 1)
        #expect(reminders.first?.dueDate != nil)
        #expect(model.toast == "Hatırlatıcı oluşturuldu")
    }

    @Test("Tarih yoksa takvim etkinliği oluşturulmaz")
    func calendarRequiresDate() async {
        let actions = FakeActionPerformer()
        let model = ShotDetailViewModel(
            shot: TestDependencies.shot(),
            dependencies: TestDependencies.make(index: FakeIndex(), actions: actions),
            paywall: PaywallPresenter()
        )

        await model.createCalendarEvent()

        #expect(await actions.events.isEmpty)
        #expect(model.errorMessage != nil)
    }

    @Test("Kota bitince aksiyon yapılmaz, paywall açılır")
    func exhaustedActionQuotaPresentsPaywall() async {
        let actions = FakeActionPerformer()
        let quota = FakeQuotaMeter(remaining: [.action: 0])
        let paywall = PaywallPresenter()
        let model = ShotDetailViewModel(
            shot: TestDependencies.shot(entities: [dateEntity("2026-02-14T00:00:00Z", raw: "14 Şubat")]),
            dependencies: TestDependencies.make(index: FakeIndex(), actions: actions, quota: quota),
            paywall: paywall
        )

        await model.createReminder()

        #expect(await actions.reminders.isEmpty)
        #expect(paywall.trigger == .actionQuotaExhausted)
    }

    @Test("İzin reddi genel hata değil, yönlendirici mesaj gösterir")
    func permissionDeniedShowsActionableMessage() async {
        let actions = FakeActionPerformer()
        await actions.setError(AppError(.permissionDenied, "izin yok"))
        let model = ShotDetailViewModel(
            shot: TestDependencies.shot(entities: [dateEntity("2026-02-14T00:00:00Z", raw: "14 Şubat")]),
            dependencies: TestDependencies.make(index: FakeIndex(), actions: actions),
            paywall: PaywallPresenter()
        )

        await model.createReminder()

        #expect(model.errorMessage?.contains("Ayarlar") == true)
    }

    @Test("Kategori düzeltmesi kaydı işaretler ve saklar")
    func categoryCorrectionIsPersisted() async {
        let index = FakeIndex()
        let model = ShotDetailViewModel(
            shot: TestDependencies.shot(),
            dependencies: TestDependencies.make(index: index),
            paywall: PaywallPresenter()
        )

        await model.correctCategory(to: .ticket)

        #expect(model.shot.analysis.category == .ticket)
        #expect(model.shot.userCorrected)
        #expect(await index.storage["asset-0"]?.analysis.category == .ticket)
    }

    @Test("Kitaplıktan kaldırma indeksten siler")
    func removalDeletesFromIndex() async {
        let index = FakeIndex(shots: [TestDependencies.shot()])
        let model = ShotDetailViewModel(
            shot: TestDependencies.shot(),
            dependencies: TestDependencies.make(index: index),
            paywall: PaywallPresenter()
        )

        await model.removeFromLibrary()

        #expect(await index.storage.isEmpty)
    }
}
