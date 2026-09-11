//
//  ContentView.swift
//  Planification
//
//  Interface inspirée du panneau « Planification » d'OnyX.
//

import SwiftUI

struct ContentView: View {
    // Démarrage / réveil
    @State private var wakeDays: Set<Weekday> = Set(Weekday.allCases)
    @State private var wakeHour = 7
    @State private var wakeMinute = 0

    // Arrêt / veille
    @State private var shutdownDays: Set<Weekday> = Set(Weekday.allCases)
    @State private var shutdownHour = 23
    @State private var shutdownMinute = 0
    @State private var action: ShutdownAction = .shutdown

    // Retour utilisateur
    @State private var alert: AlertItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 20) {
                // Colonne gauche : démarrage / réveil
                DayScheduleColumn(
                    title: "Démarrage ou réveil",
                    days: $wakeDays,
                    hour: $wakeHour,
                    minute: $wakeMinute
                )

                // Colonne droite : extinction / veille
                DayScheduleColumn(
                    titleView: AnyView(
                        Picker("", selection: $action) {
                            ForEach(ShutdownAction.allCases) { action in
                                Text(action.localizedName).tag(action)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    ),
                    days: $shutdownDays,
                    hour: $shutdownHour,
                    minute: $shutdownMinute
                )
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 640)
        .onAppear(perform: loadExistingSchedule)
        .alert(item: $alert) { item in
            Alert(title: Text(item.title),
                  message: Text(item.message),
                  dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Sous-vues

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title2)
            Text("Ce panneau vous permet de configurer des horaires pour le démarrage, "
                 + "la suspension d'activité ou l'arrêt de votre Mac. Ces réglages "
                 + "utilisent la commande système « pmset » et demandent votre mot de passe.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Voir la planification actuelle") {
                showCurrentSchedule()
            }
            Spacer()
            Button("Annuler la planification") {
                cancelSchedule()
            }
            Button("Appliquer") {
                applySchedule()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    /// Préremplit l'interface avec la planification déjà active sur le Mac.
    /// Si aucune n'existe, les valeurs par défaut (tous les jours, 7h / 23h)
    /// restent en place.
    private func loadExistingSchedule() {
        let schedule = PowerScheduler.loadCurrentSchedule()

        if let wake = schedule.wake {
            wakeDays = wake.days
            wakeHour = wake.hour
            wakeMinute = wake.minute
        } else {
            wakeDays = []
        }

        if let end = schedule.end {
            shutdownDays = end.days
            shutdownHour = end.hour
            shutdownMinute = end.minute
            action = schedule.action ?? .shutdown
        } else {
            shutdownDays = []
        }
    }

    private func applySchedule() {
        do {
            try PowerScheduler.apply(
                wakeDays: wakeDays,
                wakeHour: wakeHour,
                wakeMinute: wakeMinute,
                shutdownDays: shutdownDays,
                shutdownHour: shutdownHour,
                shutdownMinute: shutdownMinute,
                action: action
            )
            alert = AlertItem(title: "Planification appliquée",
                              message: PowerScheduler.currentSchedule())
        } catch {
            alert = AlertItem(title: "Erreur",
                              message: error.localizedDescription)
        }
    }

    private func cancelSchedule() {
        do {
            try PowerScheduler.cancel()
            alert = AlertItem(title: "Planification annulée",
                              message: "Toutes les planifications répétitives ont été supprimées.")
        } catch {
            alert = AlertItem(title: "Erreur",
                              message: error.localizedDescription)
        }
    }

    private func showCurrentSchedule() {
        let schedule = PowerScheduler.currentSchedule()
        alert = AlertItem(title: "Planification actuelle",
                          message: schedule.isEmpty ? "Aucune planification." : schedule)
    }
}

/// Une colonne : liste de jours avec interrupteurs + sélecteur d'heure.
private struct DayScheduleColumn: View {
    var title: String? = nil
    var titleView: AnyView? = nil
    @Binding var days: Set<Weekday>
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let titleView {
                    titleView
                } else if let title {
                    Text(title)
                        .font(.headline)
                }
            }
            // Hauteur d'en-tête identique dans les deux colonnes pour que
            // les lignes de jours et les sélecteurs restent alignés, quelle
            // que soit la nature de l'en-tête (texte simple ou menu déroulant).
            .frame(height: 24, alignment: .bottomLeading)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Weekday.allCases) { day in
                    HStack {
                        Text(day.localizedName)
                        Spacer() // pousse l'interrupteur vers la droite, comme OnyX
                        Toggle("", isOn: binding(for: day))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    if day != Weekday.allCases.last {
                        Divider()
                    }
                }

                Divider()

                // Sélecteurs heure / minute
                HStack(spacing: 6) {
                    Spacer()
                    Picker("", selection: $hour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 64)
                    Text("heure(s)")

                    Picker("", selection: $minute) {
                        ForEach(0..<60, id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 64)
                    Text("minute(s)")
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(for day: Weekday) -> Binding<Bool> {
        Binding(
            get: { days.contains(day) },
            set: { isOn in
                if isOn { days.insert(day) } else { days.remove(day) }
            }
        )
    }
}

/// Petit modèle pour piloter les alertes.
private struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    ContentView()
}
