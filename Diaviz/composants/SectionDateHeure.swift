//
//  SectionDateHeure.swift
//  diaviz
//

import SwiftUI

/// Section de formulaire **réutilisable** pour saisir une date + heure —
/// deux lignes séparées (Date / Heure), chacune son propre `DatePicker`
/// mono-composant, liés au même `Date`. Zones de tap plus larges qu'un
/// unique `DatePicker` combiné (deux puces serrées sur une ligne).
///
/// Remplace les variantes hétérogènes des sheets d'injection (lente, la
/// correction n'avait même pas de date), de sport (locale forcée en plus)
/// et de repas (pas de header) — même header, mêmes icônes, même borne
/// partout.
///
/// Jamais de date future (`in: ...Date()`) : on saisit ce qui s'est passé,
/// jamais une prévision.
struct SectionDateHeure: View {

    @Binding var date: Date

    var body: some View {
        Section("Date et heure") {
            DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) {
                Label("Date", systemImage: "calendar")
            }
            DatePicker(selection: $date, in: ...Date(), displayedComponents: .hourAndMinute) {
                Label("Heure", systemImage: "clock")
            }
        }
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview {
    @Previewable @State var date = Date()
    Form {
        SectionDateHeure(date: $date)
    }
    .formStyle(.grouped)
}
#endif
