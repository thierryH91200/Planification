//
//  PowerScheduler.swift
//  Planification
//
//  Interface Swift au-dessus de la commande macOS `pmset repeat`.
//  Permet de planifier le démarrage/réveil et l'arrêt/veille du Mac.
//

import Foundation

/// Les 7 jours de la semaine, avec le code d'une lettre utilisé par `pmset`.
enum Weekday: Int, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    /// Code d'une lettre attendu par `pmset` (M T W R F S U).
    var code: String {
        switch self {
        case .monday:    return "M"
        case .tuesday:   return "T"
        case .wednesday: return "W"
        case .thursday:  return "R"
        case .friday:    return "F"
        case .saturday:  return "S"
        case .sunday:    return "U"
        }
    }

    var localizedName: String {
        switch self {
        case .monday:    return String(localized: "Monday")
        case .tuesday:   return String(localized: "Tuesday")
        case .wednesday: return String(localized: "Wednesday")
        case .thursday:  return String(localized: "Thursday")
        case .friday:    return String(localized: "Friday")
        case .saturday:  return String(localized: "Saturday")
        case .sunday:    return String(localized: "Sunday")
        }
    }
}

/// Le type d'événement de fin de journée que l'on planifie.
enum ShutdownAction: String, CaseIterable, Identifiable {
    case shutdown
    case sleep
    case restart

    var id: String { rawValue }

    /// Mot-clé attendu par `pmset`.
    var pmsetKeyword: String { rawValue }

    var localizedName: String {
        switch self {
        case .shutdown: return String(localized: "Shut Down")
        case .sleep:    return String(localized: "Sleep")
        case .restart:  return String(localized: "Restart")
        }
    }
}

/// Erreurs possibles lors de l'application d'une planification.
enum SchedulerError: LocalizedError {
    case noDaySelected
    case commandFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDaySelected:
            return String(localized: "No day selected. Enable at least one day in each column.")
        case .commandFailed(let message):
            return message
        case .cancelled:
            return String(localized: "Operation cancelled (no password provided).")
        }
    }
}

/// Un événement de planification lu depuis `pmset -g sched`.
struct ParsedEvent {
    var hour: Int
    var minute: Int
    var days: Set<Weekday>
}

/// La planification répétitive actuellement configurée sur le Mac.
struct ParsedSchedule {
    var wake: ParsedEvent?
    var end: ParsedEvent?
    var action: ShutdownAction?
}

/// Construit et exécute les commandes `pmset repeat`.
struct PowerScheduler {

    // MARK: - Construction de la commande

    /// Formate un jeu de jours en chaîne de codes (ex. "MTWRF").
    /// L'ordre lundi→dimanche est conservé.
    static func dayCodes(for days: Set<Weekday>) -> String {
        Weekday.allCases
            .filter { days.contains($0) }
            .map(\.code)
            .joined()
    }

    /// Construit la commande `pmset repeat` complète (sans le `sudo`).
    ///
    /// Exemple de résultat :
    /// `pmset repeat wakeorpoweron MTWRFSU 07:00:00 shutdown MTWRFSU 23:00:00`
    static func buildCommand(wakeDays: Set<Weekday>,
                             wakeHour: Int,
                             wakeMinute: Int,
                             shutdownDays: Set<Weekday>,
                             shutdownHour: Int,
                             shutdownMinute: Int,
                             action: ShutdownAction) -> String {
        var parts = ["pmset", "repeat"]

        if !wakeDays.isEmpty {
            let time = String(format: "%02d:%02d:00", wakeHour, wakeMinute)
            parts += ["wakeorpoweron", dayCodes(for: wakeDays), time]
        }

        if !shutdownDays.isEmpty {
            let time = String(format: "%02d:%02d:00", shutdownHour, shutdownMinute)
            parts += [action.pmsetKeyword, dayCodes(for: shutdownDays), time]
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Exécution

    /// Applique la planification. Demande le mot de passe administrateur
    /// via le dialogue système standard.
    static func apply(wakeDays: Set<Weekday>,
                      wakeHour: Int,
                      wakeMinute: Int,
                      shutdownDays: Set<Weekday>,
                      shutdownHour: Int,
                      shutdownMinute: Int,
                      action: ShutdownAction) throws {
        guard !wakeDays.isEmpty || !shutdownDays.isEmpty else {
            throw SchedulerError.noDaySelected
        }

        let command = buildCommand(wakeDays: wakeDays,
                                   wakeHour: wakeHour,
                                   wakeMinute: wakeMinute,
                                   shutdownDays: shutdownDays,
                                   shutdownHour: shutdownHour,
                                   shutdownMinute: shutdownMinute,
                                   action: action)
        try runWithAdminPrivileges(command)
    }

    /// Annule toute planification répétitive existante.
    static func cancel() throws {
        try runWithAdminPrivileges("pmset repeat cancel")
    }

    /// Lit la planification actuelle (`pmset -g sched`). Ne nécessite pas d'admin.
    static func currentSchedule() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "sched"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return String(localized: "Unable to read the schedule: \(error.localizedDescription)")
        }
    }

    // MARK: - Lecture / analyse de la planification existante

    /// Lit et analyse la planification répétitive actuelle pour préremplir
    /// l'interface. Ne nécessite pas de privilèges administrateur.
    static func loadCurrentSchedule() -> ParsedSchedule {
        parseSchedule(currentSchedule())
    }

    /// Analyse le texte brut renvoyé par `pmset -g sched`.
    /// Seule la section « Repeating power events » est prise en compte.
    static func parseSchedule(_ text: String) -> ParsedSchedule {
        var schedule = ParsedSchedule()
        var inRepeatingSection = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("Repeating power events") {
                inRepeatingSection = true
                continue
            }
            if line.hasPrefix("Scheduled power events") {
                inRepeatingSection = false
                continue
            }
            guard inRepeatingSection, !line.isEmpty else { continue }

            // Format attendu : « <type> at <H:MM><AM|PM> <jours...> »
            guard let (type, event) = parseEventLine(line) else { continue }

            switch type {
            case "wake", "poweron", "wakepoweron", "wakeorpoweron":
                schedule.wake = event
            case "shutdown":
                schedule.end = event
                schedule.action = .shutdown
            case "sleep":
                schedule.end = event
                schedule.action = .sleep
            case "restart":
                schedule.end = event
                schedule.action = .restart
            default:
                break
            }
        }
        return schedule
    }

    /// Analyse une ligne unique. Renvoie le type d'événement et ses détails.
    private static func parseEventLine(_ line: String) -> (type: String, event: ParsedEvent)? {
        let tokens = line.split(separator: " ").map(String.init)
        // Minimum : ["<type>", "at", "<heure>", "<jours...>"]
        guard tokens.count >= 4, tokens[1] == "at" else { return nil }

        let type = tokens[0].lowercased()
        guard let (hour, minute) = parseTime(tokens[2]) else { return nil }

        let dayTokens = Array(tokens[3...])
        let days = parseDays(dayTokens)
        guard !days.isEmpty else { return nil }

        return (type, ParsedEvent(hour: hour, minute: minute, days: days))
    }

    /// Convertit « 7:00AM » ou « 11:00PM » en heure sur 24h.
    private static func parseTime(_ token: String) -> (hour: Int, minute: Int)? {
        let upper = token.uppercased()
        let isPM = upper.hasSuffix("PM")
        let isAM = upper.hasSuffix("AM")
        guard isPM || isAM else { return nil }

        let timePart = String(upper.dropLast(2)) // retire AM/PM
        let comps = timePart.split(separator: ":")
        guard comps.count == 2,
              var hour = Int(comps[0]),
              let minute = Int(comps[1]) else { return nil }

        // Passage en 24h.
        if isPM && hour != 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        return (hour, minute)
    }

    /// Interprète la description des jours (« every day », « weekdays »,
    /// « weekends » ou une liste de noms de jours en anglais).
    private static func parseDays(_ tokens: [String]) -> Set<Weekday> {
        let joined = tokens.joined(separator: " ").lowercased()

        switch joined {
        case "every day":
            return Set(Weekday.allCases)
        case "weekdays":
            return [.monday, .tuesday, .wednesday, .thursday, .friday]
        case "weekends":
            return [.saturday, .sunday]
        default:
            break
        }

        let mapping: [String: Weekday] = [
            "monday": .monday, "tuesday": .tuesday, "wednesday": .wednesday,
            "thursday": .thursday, "friday": .friday,
            "saturday": .saturday, "sunday": .sunday
        ]
        var days: Set<Weekday> = []
        for token in tokens {
            if let day = mapping[token.lowercased()] {
                days.insert(day)
            }
        }
        return days
    }

    // MARK: - Privilèges administrateur

    /// Exécute une commande shell avec les privilèges administrateur via
    /// AppleScript (`do shell script … with administrator privileges`),
    /// ce qui déclenche le dialogue de mot de passe standard de macOS.
    private static func runWithAdminPrivileges(_ command: String) throws {
        // Échappe les guillemets doubles pour l'insertion dans l'AppleScript.
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw SchedulerError.commandFailed(String(localized: "Unable to create the script."))
        }

        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            // -128 = l'utilisateur a annulé le dialogue de mot de passe.
            if let code = errorInfo[NSAppleScript.errorNumber] as? Int, code == -128 {
                throw SchedulerError.cancelled
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? String(localized: "Unknown error")
            throw SchedulerError.commandFailed(message)
        }
    }
}
