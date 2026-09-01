import AppFoundation
import EventKit
import Foundation
import ShotCore

/// `ActionPerforming` portunun EventKit gerçeklemesi.
///
/// **İzin stratejisi (07 §2):** izinler açılışta değil, kullanıcı "Hatırlatıcı kur"a
/// bastığında istenir. Hatırlatıcılar için tam erişim gerekir (EventKit yazma-yalnız
/// hatırlatıcı erişimi sunmaz), takvim için **yazma-yalnız** yeterlidir — daha az izin
/// istemek hem doğru hem de App Review'da açıklaması kolay.
///
/// `actor`: `EKEventStore` `Sendable` değildir ve tek bir örneğin paylaşılması gerekir
/// (her aksiyon için yeni store açmak izin durumunu yeniden sorgular ve yavaştır).
public actor EventKitActionPerformer: ActionPerforming {
    private let store = EKEventStore()

    public init() {}

    // MARK: - Hatırlatıcı

    public func createReminder(_ draft: ReminderDraft) async throws {
        try await requestRemindersAccess()

        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw AppError(.notFound, "Varsayılan hatırlatıcı listesi yok")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.calendar = calendar
        if let dueDate = draft.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate
            )
            // Bileşen tabanlı son tarih tek başına bildirim üretmez; alarm açıkça eklenir.
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        do {
            try store.save(reminder, commit: true)
            Log.info(.action, "Hatırlatıcı oluşturuldu")
        } catch {
            throw AppError(.unknown, "Hatırlatıcı kaydedilemedi", underlying: error)
        }
    }

    // MARK: - Takvim

    public func createCalendarEvent(_ draft: CalendarEventDraft) async throws {
        try await requestCalendarAccess()

        guard let calendar = store.defaultCalendarForNewEvents else {
            throw AppError(.notFound, "Varsayılan takvim yok")
        }

        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.notes = draft.notes
        event.startDate = draft.startDate
        event.endDate = draft.startDate.addingTimeInterval(draft.duration)
        event.calendar = calendar

        do {
            try store.save(event, span: .thisEvent, commit: true)
            Log.info(.action, "Takvim etkinliği oluşturuldu")
        } catch {
            throw AppError(.unknown, "Etkinlik kaydedilemedi", underlying: error)
        }
    }

    // MARK: - İzinler

    private func requestRemindersAccess() async throws {
        switch EventKitAccessPolicy.remindersDecision(
            for: EKEventStore.authorizationStatus(for: .reminder)
        ) {
        case .proceed:
            return
        case .request:
            let granted = await (try? store.requestFullAccessToReminders()) ?? false
            guard granted else { throw AppError(.permissionDenied, "Hatırlatıcı izni yok") }
        case .denied:
            throw AppError(.permissionDenied, "Hatırlatıcı izni yok")
        }
    }

    private func requestCalendarAccess() async throws {
        switch EventKitAccessPolicy.calendarDecision(
            for: EKEventStore.authorizationStatus(for: .event)
        ) {
        case .proceed:
            return
        case .request:
            let granted = await (try? store.requestWriteOnlyAccessToEvents()) ?? false
            guard granted else { throw AppError(.permissionDenied, "Takvim izni yok") }
        case .denied:
            throw AppError(.permissionDenied, "Takvim izni yok")
        }
    }
}
